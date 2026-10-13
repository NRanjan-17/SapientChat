// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Testing
@testable import SapientStudio

struct ClientIdentityTests {
    @Test(arguments: [
        ("Notes%20Helper/12 CFNetwork/1568.100.1 Darwin/25.0.0", "Notes Helper"),
        ("curl/8.7.1", "curl"),
        ("python-requests/2.32.3", "Python (requests)"),
        ("OpenAI/Python 1.51.0", "OpenAI Python SDK"),
        ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", "Safari"),
        ("Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36", "Chrome"),
        ("PostmanRuntime/7.42.0", "Postman"),
    ])
    func namesTheAppFromItsUserAgent(_ agent: String, _ app: String) {
        #expect(ClientIdentity.appName(fromUserAgent: agent) == app)
    }

    @Test func theHeaderBeatsTheUserAgentAndHandoffsAreThisDevice() {
        var request = HTTPRequest(method: "GET", path: "/v1/health", headers: [
            "x-sapient-client": "Caf%C3%A9 Notes", "user-agent": "curl/8.7.1",
        ])
        request.remoteAddress = "192.168.1.42"
        let named = ClientIdentity.of(request)
        #expect(named.app == "Café Notes")
        #expect(named.device == "192.168.1.42")
        #expect(named.userAgent == "curl/8.7.1")

        let handoff = ClientIdentity.of(HTTPRequest(method: "GET", path: "/v1/health"), handoffSource: "My App")
        #expect(handoff.app == "My App" && handoff.device == ClientIdentity.thisDevice)
        #expect(ClientIdentity.deviceName("::1") == ClientIdentity.thisDevice)
        #expect(ClientIdentity.deviceName("fe80::1%en0") == "fe80::1")
    }
}

@MainActor
struct ModelSettingsAPITests {
    private func makeRouter() -> (ServeRouter, ControlledChatService, TemperatureStore, ContextWindowStore) {
        let chat = ControlledChatService(autoReply: ["ok"])
        let temperatures = makeTemperatureStore()
        let windows = makeContextWindowStore()
        let memory = FixedMemory(memory: MemoryStatus(footprintBytes: 0, availableBytes: 10_000_000_000))
        let services = makeServices(chat: chat, memory: memory, contextWindows: windows, temperatures: temperatures)
        let device = DeviceStatus(memoryService: memory, thermalService: SilentThermalService())
        return (ServeRouter(services: services, device: device), chat, temperatures, windows)
    }

    private func json(_ response: HTTPResponse) throws -> [String: Any] {
        guard case .data(let data) = response.body else { Issue.record("expected data"); return [:] }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func post(_ body: String) -> HTTPRequest {
        HTTPRequest(method: "POST", path: "/v1/models/settings", body: Data(body.utf8))
    }

    @Test func readsDefaultsAsNull() async throws {
        let (router, _, _, _) = makeRouter()
        let response = await router.handle(HTTPRequest(method: "GET", path: "/v1/models/settings", query: ["model": TestModels.big.alias]))
        let settings = try json(response)
        #expect(response.status == 200)
        #expect(settings["temperature"] is NSNull && settings["context_window"] is NSNull, "defaults are explicit nulls")
        #expect(settings["context_window_adjustable"] as? Bool == true)
        #expect(settings["temperature_range"] as? [Double] == [0, 1.5])
    }

    @Test func updatesOnlyWhatsSentAndReloadsALoadedModelOnce() async throws {
        let (router, chat, temperatures, windows) = makeRouter()
        _ = try await chat.load(model: TestModels.big.alias)
        windows.set(2048, for: TestModels.big.alias)

        let response = await router.handle(post(#"{"model":"\#(TestModels.big.alias)","temperature":0.7}"#))
        let settings = try json(response)
        #expect(response.status == 200)
        #expect(temperatures.temperature(for: TestModels.big.alias) == 0.7)
        #expect(windows.tokens(for: TestModels.big.alias) == 2048, "context_window wasn't sent, so it's kept")
        #expect(settings["updated"] as? Bool == true && settings["reloaded"] as? Bool == true)
        #expect(await chat.unloadCount == 1)

        let reset = try json(await router.handle(post(#"{"model":"\#(TestModels.big.alias)","temperature":null,"context_window":null}"#)))
        #expect(reset["temperature"] is NSNull && reset["context_window"] is NSNull)
        #expect(temperatures.temperature(for: TestModels.big.alias) == nil)

        let same = try json(await router.handle(post(#"{"model":"\#(TestModels.big.alias)","temperature":null}"#)))
        #expect(same["updated"] as? Bool == false && same["reloaded"] as? Bool == false)
        #expect(await chat.unloadCount == 2, "nothing changed, nothing reloaded")
    }

    @Test func rejectsValuesTheAppDoesntOffer() async throws {
        let (router, _, _, _) = makeRouter()
        #expect(await router.handle(post(#"{"model":"\#(TestModels.big.alias)","temperature":3}"#)).status == 400)
        #expect(await router.handle(post(#"{"model":"\#(TestModels.big.alias)","temperature":"hot"}"#)).status == 400)
        #expect(await router.handle(post(#"{"model":"\#(TestModels.big.alias)","context_window":5000}"#)).status == 400)
        #expect(await router.handle(post(#"{"model":"\#(TestModels.small.alias)","context_window":4096}"#)).status == 400,
                "small models use the default window")
        #expect(await router.handle(post(#"{"model":"nope","temperature":0.5}"#)).status == 400)
        #expect(await router.handle(post("not json")).status == 422)
    }

    @Test func theLogNamesTheCallingAppAndDevice() async throws {
        let (router, _, _, _) = makeRouter()
        var logged: [RequestLogEntry] = []
        router.onRequest = { logged.append($0) }
        var request = HTTPRequest(method: "GET", path: "/v1/ping", headers: ["user-agent": "Notes%20Helper/3 CFNetwork/1568 Darwin/25.0.0"])
        request.remoteAddress = "127.0.0.1"
        _ = await router.handle(request)
        #expect(logged.last?.source == "Notes Helper")
        #expect(logged.last?.device == ClientIdentity.thisDevice)
    }
}
