import Foundation
import Testing
@testable import SapientChat

struct ServeCommandsTests {
    @Test func everyCommandUsesTheEndpointKeyAndModel() {
        let commands = ServeCommands.all(base: "http://10.0.0.2:11435", apiKey: "k", model: "openhorizon/m")
        #expect(commands.allSatisfy { $0.command.contains("http://10.0.0.2:11435/v1/") })
        #expect(commands.allSatisfy { $0.command.contains("Authorization: Bearer k") })
        let modelCommands = ["Download", "Load into memory", "Unload from memory", "Delete download", "Chat", "Chat, streaming", "Completion"]
        for title in modelCommands {
            let command = commands.first { $0.title == title }?.command ?? ""
            #expect(command.contains(#""model":"openhorizon/m""#), "\(title)")
        }
        #expect(Set(commands.map(\.group)) == Set(ServeCommand.Group.allCases))
    }

    @Test func noKeyMeansNoAuthHeader() {
        let commands = ServeCommands.all(base: "http://127.0.0.1:1", apiKey: "", model: "m")
        #expect(!commands.contains { $0.command.contains("Authorization") })
        #expect(commands.first { $0.title == "Available to download" }?.command == "curl 'http://127.0.0.1:1/v1/catalog?status=available'")
    }
}

@MainActor
struct CatalogFilterAndPingTests {
    private func makeRouter() -> ServeRouter {
        let storage = FakeStorage(downloads: [TestModels.small.repoId: 100])
        let services = makeServices(chat: ControlledChatService(), storage: storage)
        return ServeRouter(services: services, device: DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService()))
    }

    private func ids(_ response: HTTPResponse) throws -> [String] {
        guard case .data(let data) = response.body else { return [] }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
    }

    @Test func catalogFiltersByStatus() async throws {
        let router = makeRouter()
        func get(_ query: [String: String]) async -> HTTPResponse {
            await router.handle(HTTPRequest(method: "GET", path: "/v1/catalog", query: query))
        }
        #expect(try ids(await get([:])).count == 2)
        #expect(try ids(await get(["status": "downloaded"])) == [TestModels.small.alias])
        #expect(try ids(await get(["status": "available"])) == [TestModels.big.alias])
        #expect(try ids(await get(["status": "loaded"])).isEmpty)
        #expect(await get(["status": "nope"]).status == 400)
    }

    @Test func pingAnswersWithoutTouchingModels() async throws {
        let response = await makeRouter().handle(HTTPRequest(method: "GET", path: "/v1/ping"))
        #expect(response.status == 200)
        guard case .data(let data) = response.body else { Issue.record("no body"); return }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["status"] as? String == "ok")
        #expect(json?["version"] as? String == SapientVersion.current)
    }
}

/// Records start/stop instead of playing audio.
final class FakeKeeper: BackgroundKeeping, @unchecked Sendable {
    private(set) var isRunning = false
    var fails = false
    func start() async throws {
        if fails { throw SilentAudioKeeper.KeeperError.noBuffer }
        isRunning = true
    }
    func stop() async { isRunning = false }
}

@MainActor
struct ServerBackgroundTests {
    private func makeServer(keeper: FakeKeeper, defaults: UserDefaults) -> (ServerViewModel, ControlledChatService) {
        let chat = ControlledChatService()
        let router = ServeRouter(
            services: makeServices(chat: chat),
            device: DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        )
        return (ServerViewModel(router: router, defaults: defaults, keeper: keeper), chat)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "server-\(UUID().uuidString)")!
    }

    @Test(.enabled(if: ServerViewModel.canRunInBackground))
    func backgroundModeKeepsAliveOnlyWhileServing() async {
        let keeper = FakeKeeper()
        let defaults = freshDefaults()
        let (server, chat) = makeServer(keeper: keeper, defaults: defaults)
        _ = try? await chat.load(model: TestModels.small.alias)

        server.setRunsInBackground(true)
        #expect(server.runsInBackground, "the choice is saved")
        #expect(!server.isServingInBackground, "but does nothing while the server is off")
        #expect(!EngineBackendPreference.cpuOnly(defaults), "GPU as usual")
        #expect(!keeper.isRunning, "the app closes normally")
        #expect(await chat.loadedModels() == [TestModels.small.alias])

        server.port = UInt16.random(in: 40_000...50_000)
        server.isOn = true
        await server.keeperSettled()
        #expect(server.isServingInBackground)
        #expect(keeper.isRunning)
        #expect(EngineBackendPreference.cpuOnly(defaults), "models load on the CPU")
        #expect(await eventually { await chat.loadedModels().isEmpty }, "released to reload on the CPU")

        server.isOn = false
        await server.keeperSettled()
        #expect(!keeper.isRunning)
        #expect(!EngineBackendPreference.cpuOnly(defaults), "back to the GPU")
        #expect(server.runsInBackground, "the choice is still saved for next time")
    }

    @Test(.enabled(if: ServerViewModel.canRunInBackground))
    func aKeeperThatCannotStartTurnsTheModeOff() async {
        let keeper = FakeKeeper()
        keeper.fails = true
        let (server, _) = makeServer(keeper: keeper, defaults: freshDefaults())
        server.port = UInt16.random(in: 40_000...50_000)
        server.isOn = true
        server.setRunsInBackground(true)
        await server.keeperSettled()
        await server.keeperSettled()
        #expect(!server.runsInBackground)
        #expect(server.backgroundError != nil)
        server.isOn = false
    }

    @Test func theSettingIsRemembered() {
        let defaults = freshDefaults()
        let (first, _) = makeServer(keeper: FakeKeeper(), defaults: defaults)
        first.setRunsInBackground(true)
        let (second, _) = makeServer(keeper: FakeKeeper(), defaults: defaults)
        #expect(second.runsInBackground == ServerViewModel.canRunInBackground)
    }
}

@MainActor
struct ServerLiveActivityTests {
    @Test func pingsAndRequestsUpdateTheServerActivity() {
        let service = RecordingLiveActivities()
        let clock = ManualClock()
        let server = ServerLiveActivity(service: service, minimumInterval: 0, clock: { clock.now })
        server.recorded(method: "GET", path: "/v1/ping", status: 200)
        #expect(service.started.isEmpty, "nothing until serving begins")

        server.begin(endpoint: "192.168.1.46:11435")
        #expect(service.started.map(\.title) == ["API server"])
        #expect(service.started.first?.model == "192.168.1.46:11435")

        server.recorded(method: "GET", path: "/v1/ping", status: 200)
        #expect(service.updates.last?.requests == 1)
        #expect(service.updates.last?.detail == "Last: GET /v1/ping")

        // A chat request updates the same activity instead of starting one.
        let tracker = LiveActivityTracker(service: server, title: "API request", minimumInterval: 0, clock: { clock.now })
        tracker.start(model: "SmolLM2 135M")
        tracker.generating()
        clock.advance(0.1)
        tracker.token()
        #expect(service.started.count == 1)
        #expect(service.updates.last?.phase == .generating)
        #expect(service.updates.last?.detail == "SmolLM2 135M")
        tracker.finish()
        #expect(service.ended.isEmpty, "the server activity stays")
        #expect(service.updates.last?.phase == .serving)
        #expect(service.updates.last?.detail == "Last: SmolLM2 135M · 1 tokens")

        server.finish()
        #expect(service.ended.last?.phase == .finished)
    }

    @Test func withoutServingRequestsGetTheirOwnActivity() {
        let service = RecordingLiveActivities()
        let server = ServerLiveActivity(service: service)
        let tracker = LiveActivityTracker(service: server, title: "Request from Shortcuts")
        tracker.start(model: "m")
        tracker.finish()
        #expect(service.started.map(\.title) == ["Request from Shortcuts"])
        #expect(service.ended.count == 1)
    }
}

@MainActor
struct APIDownloadsShowInModelsTabTests {
    @Test func aDownloadOverTheAPIShowsOnItsRow() async throws {
        let storage = FakeStorage()
        let chat = ControlledChatService()
        let services = makeServices(chat: chat, storage: storage, downloads: FakeDownloader(storage: storage, hangs: true))
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let router = ServeRouter(services: services, device: device)
        let manager = ModelManagerViewModel(services: services, device: device)
        router.onModelPhase = { alias, phase in manager.apiPhase(phase, for: alias) }
        await manager.refresh()

        let request = HTTPRequest(method: "POST", path: "/v1/models/download", body: Data(#"{"model":"\#(TestModels.small.alias)"}"#.utf8))
        let call = Task { await router.handle(request) }
        #expect(await eventually { manager.rows.first { $0.model == TestModels.small }?.activity != nil })
        call.cancel()
        _ = await call.value
        #expect(await eventually { manager.rows.first { $0.model == TestModels.small }?.activity == nil })
    }
}

@MainActor
struct ServerHeartbeatTests {
    @Test func theServerActivityKeepsSendingWhileIdle() async {
        let service = RecordingLiveActivities()
        let server = ServerLiveActivity(service: service, minimumInterval: 0, heartbeatInterval: .milliseconds(20))
        server.begin(endpoint: "127.0.0.1:1")
        #expect(await eventually { service.updates.count >= 3 }, "heartbeats arrive without any requests")
        server.finish()
        let count = service.updates.count
        try? await Task.sleep(for: .milliseconds(80))
        #expect(service.updates.count == count, "and stop when the server stops")
    }
}
