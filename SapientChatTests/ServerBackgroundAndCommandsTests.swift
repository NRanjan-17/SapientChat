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
final class FakeKeeper: BackgroundKeeping {
    private(set) var isRunning = false
    var fails = false
    func start() throws {
        if fails { throw SilentAudioKeeper.KeeperError.noBuffer }
        isRunning = true
    }
    func stop() { isRunning = false }
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
        #expect(server.runsInBackground)
        #expect(EngineBackendPreference.cpuOnly(defaults), "models load on the CPU")
        #expect(!keeper.isRunning, "nothing to keep alive while the server is off")
        #expect(await eventually { await chat.loadedModels().isEmpty }, "released to reload on the CPU")

        server.port = UInt16.random(in: 40_000...50_000)
        server.isOn = true
        #expect(keeper.isRunning)
        server.isOn = false
        #expect(!keeper.isRunning)

        server.setRunsInBackground(false)
        #expect(!EngineBackendPreference.cpuOnly(defaults))
    }

    @Test(.enabled(if: ServerViewModel.canRunInBackground))
    func aKeeperThatCannotStartTurnsTheModeOff() {
        let keeper = FakeKeeper()
        keeper.fails = true
        let (server, _) = makeServer(keeper: keeper, defaults: freshDefaults())
        server.port = UInt16.random(in: 40_000...50_000)
        server.isOn = true
        server.setRunsInBackground(true)
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
