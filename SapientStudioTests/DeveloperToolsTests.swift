// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import SwiftData
import Testing
@testable import SapientStudio

struct StructuredOutputTests {
    private let toolsBody = Data("""
        {"messages":[{"role":"user","content":"Weather in Paris?"}],
         "tools":[{"type":"function","function":{"name":"get_weather","description":"Current weather",
                   "parameters":{"type":"object","properties":{"city_name":{"type":"string"}},"required":["city_name"]}}}]}
        """.utf8)

    @Test func readsToolsAndKeepsSchemaKeyNames() {
        let structured = StructuredOutput(body: toolsBody)
        #expect(structured.toolNames == ["get_weather"])
        #expect(structured.usesTools && structured.isActive)
        #expect(structured.toolsJSON.contains("city_name"), "snake_case keys inside a schema stay as sent")
        #expect(structured.instructions?.contains("<tool_call>") == true)
    }

    @Test func aRequestWithoutToolsOrFormatIsLeftAlone() {
        let structured = StructuredOutput(body: Data(#"{"messages":[{"role":"user","content":"Hi"}]}"#.utf8))
        #expect(!structured.isActive)
        #expect(structured.instructions == nil)
        let history = [ChatMessage(role: .user, text: "Hi")]
        #expect(structured.applying(to: history) == history)
    }

    @Test func toolChoiceNoneTurnsToolsOff() {
        var object = try! JSONSerialization.jsonObject(with: toolsBody) as! [String: Any]
        object["tool_choice"] = "none"
        let structured = StructuredOutput(body: try! JSONSerialization.data(withJSONObject: object))
        #expect(!structured.usesTools)
        object["tool_choice"] = ["type": "function", "function": ["name": "get_weather"]]
        let forced = StructuredOutput(body: try! JSONSerialization.data(withJSONObject: object))
        #expect(forced.toolChoice == .function("get_weather"))
        #expect(forced.instructions?.contains("You must call the tool \"get_weather\"") == true)
    }

    @Test func instructionsJoinAnExistingSystemMessage() {
        let structured = StructuredOutput(body: toolsBody)
        let history = structured.applying(to: [ChatMessage(role: .system, text: "Be brief"), ChatMessage(role: .user, text: "Hi")])
        #expect(history.count == 2)
        #expect(history[0].text.hasPrefix("Be brief\n\n"))
        let added = structured.applying(to: [ChatMessage(role: .user, text: "Hi")])
        #expect(added.map(\.role) == [.system, .user])
    }

    @Test func findsATaggedToolCall() {
        let structured = StructuredOutput(body: toolsBody)
        let reply = #"Sure. <tool_call>{"name": "get_weather", "arguments": {"city_name": "Paris"}}</tool_call>"#
        guard case .toolCalls(let calls) = structured.interpret(reply) else { Issue.record("expected a tool call"); return }
        #expect(calls.count == 1)
        #expect(calls[0].function.name == "get_weather")
        #expect(calls[0].function.arguments == #"{"city_name":"Paris"}"#)
        #expect(calls[0].id.hasPrefix("call_"))
    }

    @Test func acceptsAMissingClosingTagAndABareObject() {
        let names = ["get_weather"]
        #expect(StructuredOutput.toolCalls(in: #"<tool_call>{"name":"get_weather","arguments":{}}"#, names: names).count == 1)
        #expect(StructuredOutput.toolCalls(in: "```json\n{\"name\":\"get_weather\",\"arguments\":{\"city_name\":\"Rome\"}}\n```", names: names).count == 1)
    }

    @Test func anUnknownToolOrPlainTextIsNotACall() {
        let structured = StructuredOutput(body: toolsBody)
        #expect(StructuredOutput.toolCalls(in: #"<tool_call>{"name":"delete_all","arguments":{}}</tool_call>"#, names: ["get_weather"]).isEmpty)
        #expect(structured.interpret("It is sunny in Paris.") == .content("It is sunny in Paris.", jsonValid: nil, missingKeys: []))
    }

    @Test func extractsJSONFromFencesAndPreamble() {
        #expect(StructuredOutput.extractJSON(from: "Here you go:\n```json\n{\"a\": [1, 2]}\n```") == "{\"a\": [1, 2]}")
        #expect(StructuredOutput.extractJSON(from: #"{"text": "a } brace in a string"}"#) == #"{"text": "a } brace in a string"}"#)
        #expect(StructuredOutput.extractJSON(from: "no json here") == nil)
        #expect(StructuredOutput.extractJSON(from: "{broken") == nil)
    }

    @Test func jsonModeReportsWhetherJSONCameBack() {
        let structured = StructuredOutput(body: Data(#"{"messages":[],"response_format":{"type":"json_object"}}"#.utf8))
        #expect(structured.interpret("Sure! {\"city\": \"Tokyo\"}") == .content("{\"city\": \"Tokyo\"}", jsonValid: true, missingKeys: []))
        #expect(structured.interpret("Tokyo is in Japan.") == .content("Tokyo is in Japan.", jsonValid: false, missingKeys: []))
    }

    @Test func jsonSchemaReportsMissingRequiredKeys() {
        let body = #"{"messages":[],"response_format":{"type":"json_schema","json_schema":{"name":"place","schema":{"type":"object","required":["city","country"]}}}}"#
        let structured = StructuredOutput(body: Data(body.utf8))
        #expect(structured.instructions?.contains("JSON Schema") == true)
        #expect(structured.interpret(#"{"city":"Tokyo"}"#) == .content(#"{"city":"Tokyo"}"#, jsonValid: true, missingKeys: ["country"]))
    }

    @Test func toolMessagesBecomeTextTheEngineUnderstands() {
        let body = """
            {"messages":[{"role":"user","content":"Weather?"},
              {"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"get_weather","arguments":"{\\"city_name\\":\\"Paris\\"}"}}]},
              {"role":"tool","tool_call_id":"call_1","content":"18C, sunny"}]}
            """
        let history = StructuredOutput.history(body: Data(body.utf8))
        #expect(history?.map(\.role) == [.user, .assistant, .user])
        #expect(history?[1].text == #"<tool_call>{"arguments":{"city_name":"Paris"},"name":"get_weather"}</tool_call>"#)
        #expect(history?[2].text.contains("18C, sunny") == true)
        #expect(StructuredOutput.history(body: Data(#"{"messages":[{"role":"robot","content":"x"}]}"#.utf8)) == nil)
    }
}

@MainActor
struct StructuredAPITests {
    private func makeRouter(reply: [String]) -> (ServeRouter, ControlledChatService) {
        let chat = ControlledChatService(autoReply: reply)
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        return (ServeRouter(services: makeServices(chat: chat), device: device), chat)
    }

    private func post(_ json: String) -> HTTPRequest {
        HTTPRequest(method: "POST", path: "/v1/chat/completions", body: Data(json.utf8))
    }

    private func text(_ response: HTTPResponse) async throws -> String {
        switch response.body {
        case .data(let data): return String(decoding: data, as: UTF8.self)
        case .stream(let chunks):
            var data = Data()
            for try await chunk in chunks { data.append(chunk) }
            return String(decoding: data, as: UTF8.self)
        }
    }

    private let tools = #"[{"type":"function","function":{"name":"get_weather","parameters":{"type":"object"}}}]"#

    @Test func aToolCallComesBackInOpenAIShape() async throws {
        let (router, chat) = makeRouter(reply: ["<tool_call>", #"{"name":"get_weather","arguments":{"city":"Paris"}}"#, "</tool_call>"])
        let response = await router.handle(post(#"{"model":"smollm2-135m-q4","messages":[{"role":"user","content":"Weather?"}],"tools":\#(tools)}"#))
        #expect(response.status == 200)
        let reply = try JSONSerialization.jsonObject(with: Data(try await text(response).utf8)) as? [String: Any]
        let choice = (reply?["choices"] as? [[String: Any]])?.first
        let message = choice?["message"] as? [String: Any]
        #expect(choice?["finish_reason"] as? String == "tool_calls")
        #expect(message?["content"] is NSNull)
        let call = (message?["tool_calls"] as? [[String: Any]])?.first
        #expect(call?["type"] as? String == "function")
        #expect((call?["function"] as? [String: Any])?["name"] as? String == "get_weather")
        #expect((call?["function"] as? [String: Any])?["arguments"] as? String == #"{"city":"Paris"}"#)
        // The model was told about the tool.
        #expect(await chat.histories.first?.first?.role == .system)
        #expect(await chat.histories.first?.first?.text.contains("get_weather") == true)
    }

    @Test func withToolsAnOrdinaryAnswerIsStillAnAnswer() async throws {
        let (router, _) = makeRouter(reply: ["It is ", "sunny."])
        let response = await router.handle(post(#"{"model":"smollm2-135m-q4","messages":[{"role":"user","content":"Hi"}],"tools":\#(tools)}"#))
        let body = try await text(response)
        #expect(body.contains(#""finish_reason" : "stop""#))
        #expect(body.contains("It is sunny."))
    }

    @Test func jsonModeReturnsTheJSONAndSaysWhenThereIsNone() async throws {
        let (router, _) = makeRouter(reply: ["Sure: ", #"{"city":"Tokyo"}"#])
        let valid = try await text(await router.handle(post(#"{"model":"smollm2-135m-q4","messages":[{"role":"user","content":"Hi"}],"response_format":{"type":"json_object"}}"#)))
        let reply = try JSONSerialization.jsonObject(with: Data(valid.utf8)) as? [String: Any]
        let message = ((reply?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
        #expect(message?["content"] as? String == #"{"city":"Tokyo"}"#)
        #expect((reply?["sapient"] as? [String: Any])?["json_valid"] as? Bool == true)

        let (prose, _) = makeRouter(reply: ["Tokyo ", "is nice."])
        let invalid = try await text(await prose.handle(post(#"{"model":"smollm2-135m-q4","messages":[{"role":"user","content":"Hi"}],"response_format":{"type":"json_object"}}"#)))
        let other = try JSONSerialization.jsonObject(with: Data(invalid.utf8)) as? [String: Any]
        #expect((other?["sapient"] as? [String: Any])?["json_valid"] as? Bool == false)
    }

    @Test func aStreamedToolCallArrivesAsOneDelta() async throws {
        let (router, _) = makeRouter(reply: [#"<tool_call>{"name":"get_weather","arguments":{}}</tool_call>"#])
        let response = await router.handle(post(#"{"model":"smollm2-135m-q4","stream":true,"messages":[{"role":"user","content":"Hi"}],"tools":\#(tools)}"#))
        #expect(response.contentType == "text/event-stream")
        let events = try await text(response).components(separatedBy: "\n\n").filter { !$0.isEmpty }
        #expect(events.count == 4) // role, tool call, final, [DONE]
        #expect(events[1].contains(#""tool_calls""#) && events[1].contains(#""index":0"#))
        #expect(events[2].contains(#""finish_reason":"tool_calls""#))
        #expect(events.last == "data: [DONE]")
    }

    @Test func aReplyCutOffForRepeatingSaysSoInsteadOfLookingFinished() async throws {
        let chat = ControlledChatService()
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let router = ServeRouter(services: makeServices(chat: chat), device: device)
        async let pending = router.handle(post(#"{"model":"smollm2-135m-q4","messages":[{"role":"user","content":"Hi"}]}"#))
        #expect(await eventually { await chat.replyCount == 1 })
        await chat.send("hello hello", toReply: 0)
        await chat.failReply(0, with: ChatServiceError.stoppedRepeating)
        let response = await pending
        #expect(response.status == 200)
        let reply = try JSONSerialization.jsonObject(with: Data(try await text(response).utf8)) as? [String: Any]
        let choice = (reply?["choices"] as? [[String: Any]])?.first
        #expect((choice?["message"] as? [String: Any])?["content"] as? String == "hello hello", "what arrived is kept")
        #expect(choice?["finish_reason"] as? String == "length")
        #expect((reply?["sapient"] as? [String: Any])?["stopped_repeating"] as? Bool == true)
    }

    @Test func reachingMaxTokensIsReportedAsLength() async throws {
        let (router, _) = makeRouter(reply: ["a", "b", "c"])
        let body = try await text(await router.handle(post(#"{"model":"smollm2-135m-q4","max_tokens":2,"messages":[{"role":"user","content":"Hi"}]}"#)))
        #expect(body.contains(#""finish_reason" : "length""#))
        #expect(!body.contains("sapient"), "no note when nothing unusual happened")
    }

    @Test func theActivityEndpointSaysWhatIsRunningWithoutBeingLogged() async throws {
        let chat = ControlledChatService(autoReply: ["ok"])
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let router = ServeRouter(services: makeServices(chat: chat), device: device)
        let island = WindowIsland(lingering: .milliseconds(10))
        router.activity = { island.snapshot }
        router.apiKey = "secret"
        var logged = 0
        router.onRequest = { _ in logged += 1 }

        let idle = try JSONSerialization.jsonObject(with: Data(try await text(await router.handle(HTTPRequest(method: "GET", path: "/v1/activity"))).utf8)) as? [String: Any]
        #expect(idle?["active"] as? Bool == false)

        let id = island.start(
            SapientActivityAttributes(title: "API server", model: "10.0.0.2:11435"),
            state: .init(phase: .serving, detail: "Waiting for requests", requests: 3, startedAt: .now)
        )
        var local = HTTPRequest(method: "GET", path: "/v1/activity")
        local.remoteAddress = "127.0.0.1"
        let busy = try JSONSerialization.jsonObject(with: Data(try await text(await router.handle(local)).utf8)) as? [String: Any]
        #expect(busy?["active"] as? Bool == true)
        #expect(busy?["phase"] as? String == "serving" && busy?["requests"] as? Int == 3)
        #expect(busy?["model"] as? String == "10.0.0.2:11435")
        #expect(logged == 0, "the helper's polling isn't a request to log")

        // From another device it needs the key, like everything else.
        var remote = HTTPRequest(method: "GET", path: "/v1/activity")
        remote.remoteAddress = "192.168.1.50"
        #expect(await router.handle(remote).status == 401)

        island.end(try #require(id), state: .init(phase: .finished, startedAt: .now, endedAt: .now))
        #expect(island.snapshot.phase == "finished", "kept a moment after it ends")
        #expect(await eventually { !island.snapshot.active })
    }

    @Test func aPlainRequestStillStreamsTokenByToken() async throws {
        let (router, _) = makeRouter(reply: ["a", "b", "c"])
        let response = await router.handle(post(#"{"model":"smollm2-135m-q4","stream":true,"messages":[{"role":"user","content":"Hi"}]}"#))
        let events = try await text(response).components(separatedBy: "\n\n").filter { !$0.isEmpty }
        #expect(events.count == 6)
    }
}

struct DeveloperModelTests {
    private func entry(_ path: String, status: Int = 200, source: String? = nil, prompt: String? = nil) -> RequestLogEntry {
        var entry = RequestLogEntry(date: .now, method: "POST", path: path, status: status, source: source)
        if let prompt { entry.messages = [.init(role: "user", text: prompt)] }
        return entry
    }

    @Test func theLogFiltersByTextErrorsAndApp() {
        let entries = [
            entry("/v1/chat/completions", source: "curl", prompt: "Tell me about whales"),
            entry("/v1/models/load", status: 507, source: "Notes"),
            entry("/v1/chat/completions", status: 400, source: "curl"),
        ]
        #expect(RequestLogFilter().apply(entries).count == 3)
        #expect(RequestLogFilter(errorsOnly: true).apply(entries).count == 2)
        #expect(RequestLogFilter(source: "Notes").apply(entries).map(\.path) == ["/v1/models/load"])
        #expect(RequestLogFilter(text: "whales").apply(entries).count == 1)
        #expect(RequestLogFilter(text: "507").apply(entries).count == 1)
        #expect(RequestLogFilter.sources(in: entries) == ["Notes", "curl"])
        #expect(RequestLogFilter.export(entries).contains("\"path\" : \"/v1/models/load\""))
    }

    @Test func onlyRequestsWithABodyOrAGETCanBeReplayed() {
        var post = entry("/v1/chat/completions")
        #expect(!post.canReplay)
        post.requestBody = "{}"
        #expect(post.canReplay)
        #expect(RequestLogEntry(date: .now, method: "GET", path: "/v1/models").canReplay)
    }

    @Test func tokenEstimatesAreRoughAndLabelled() {
        #expect(TokenEstimate.tokens(in: "") == 0)
        #expect(TokenEstimate.tokens(in: "abcd") == 1)
        #expect(TokenEstimate.tokens(in: String(repeating: "a", count: 401)) == 101)
        #expect(TokenEstimate.window(for: TestModels.small, picked: nil) == 8192)
        #expect(TokenEstimate.window(for: TestModels.big, picked: nil) == 3072)
        #expect(TokenEstimate.window(for: TestModels.big, picked: 4096) == 4096)
        #expect(TokenEstimate.label(tokens: 120, window: 8192) == "About 120 of 8,192 tokens")
    }

    @Test func aLongChatKeepsTheSystemPromptAndTheNewestMessages() {
        let long = String(repeating: "word ", count: 80) // about 100 tokens
        var history = [ChatMessage(role: .system, text: "Be brief")]
        for index in 0..<10 {
            history.append(ChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant, text: "\(index) \(long)"))
        }
        history.append(ChatMessage(role: .user, text: "newest"))
        let whole = TokenEstimate.fitting(history, window: 8192)
        #expect(whole.dropped == 0 && whole.history == history)

        let cut = TokenEstimate.fitting(history, window: 600) // room for about four of them
        #expect(cut.dropped > 0 && cut.dropped == history.count - cut.history.count)
        #expect(cut.history.first?.role == .system)
        #expect(cut.history.last?.text == "newest")
        #expect(cut.history[1].role == .user, "the window opens on a user message")
        // Even one message bigger than the window is still sent.
        let huge = TokenEstimate.fitting([ChatMessage(role: .user, text: String(repeating: "x", count: 10_000))], window: 100)
        #expect(huge.history.count == 1 && huge.dropped == 0)
    }

    @Test func aReplyStuckOnRepeatIsNoticedButOrdinaryTextIsNot() {
        var loop = RepetitionGuard()
        var stoppedAt: Int?
        for index in 0..<400 where stoppedAt == nil {
            if loop.isLooping(after: ["output", " of", " the", " "][index % 4]) { stoppedAt = index }
        }
        #expect(stoppedAt != nil && stoppedAt! < 100, "a four-token loop stops within a hundred tokens")

        var single = RepetitionGuard()
        #expect((0..<80).contains { _ in single.isLooping(after: "hello ") })

        var counting = RepetitionGuard()
        #expect(!(1...600).contains { counting.isLooping(after: "\($0)") || counting.isLooping(after: "\n") })

        // A few identical lines in a row (a table, a list) are fine.
        var list = RepetitionGuard()
        #expect(!(0..<40).contains { _ in list.isLooping(after: "- item\n") })
    }

    @Test func termsAreAskedOnceAndAgainWhenTheyChange() {
        let defaults = UserDefaults(suiteName: "terms-\(UUID().uuidString)")!
        #expect(!TermsOfService.isAccepted(defaults))
        TermsOfService.accept(defaults)
        #expect(TermsOfService.isAccepted(defaults))
        // An older acceptance doesn't cover a newer version of the text.
        defaults.set(TermsOfService.version - 1, forKey: TermsOfService.acceptedVersionKey)
        #expect(!TermsOfService.isAccepted(defaults))
    }

    @Test func theTermsSayWhatTheyMustAndLinkToTheCompany() {
        let text = TermsOfService.sections.map(\.body).joined(separator: " ")
        #expect(text.contains("OpenHorizon Labs Pvt Ltd"))
        #expect(text.contains("[openhorizon.so](https://openhorizon.so)"))
        #expect(text.contains("does not collect"))
        #expect(text.contains("Hugging Face"))
        #expect(text.contains("without warranty"))
        #expect(text.contains("Nalinish Ranjan and Saidev Dhal"))
        #expect(TermsOfService.sections.allSatisfy { (try? AttributedString(markdown: $0.body)) != nil })
    }

    @Test func samplingSettingsAreClampedAndSavedPerModel() {
        let store = SamplingStore(defaults: UserDefaults(suiteName: "sampling-\(UUID().uuidString)")!)
        #expect(store.settings(for: "a").isDefault)
        store.set(SamplingSettings(topP: 5, topK: 0, repetitionPenalty: 1), for: "a")
        #expect(store.settings(for: "a") == SamplingSettings(topP: 1, topK: 1, repetitionPenalty: nil))
        #expect(store.settings(for: "b").isDefault)
        store.set(SamplingSettings(), for: "a")
        #expect(store.settings(for: "a").isDefault)
    }

    @Test func pairingCarriesBothURLFormsAndTheKeyOnlyWhenSet() {
        let open = ServerPairing(url: "http://192.168.1.20:11435", apiKey: "")
        #expect(open.json == #"{"base_url":"http://192.168.1.20:11435/v1","url":"http://192.168.1.20:11435"}"#)
        #expect(ServerPairing(url: "http://a:1", apiKey: "secret").json.contains(#""api_key":"secret""#))
        #expect(ServerPairing.qrCode(for: open.json) != nil)
    }
}

@MainActor
struct DeveloperViewModelTests {
    private func result(model: String, rate: Double, backend: String = "cpu") -> BenchmarkResult {
        BenchmarkResult(
            model: model, backend: backend, isMemoryMapped: true, contextLength: 8192, loadTimeMs: 1, promptTokens: 1,
            maxTokens: 128, warmupRuns: [],
            runs: [BenchmarkRunResult(index: 1, isWarmup: false, ttftMs: 100, elapsedMs: 1_000, tokens: 128,
                                      decodeTokensPerSecond: rate, prefillTokensPerSecond: 50, hitEndOfTurn: false,
                                      footprintBytes: nil)],
            meanTtftMs: 100, meanDecodeTokensPerSecond: rate, minDecodeTokensPerSecond: rate, maxDecodeTokensPerSecond: rate,
            meanPrefillTokensPerSecond: 50, peakFootprintBytes: nil, thermalStart: "nominal", thermalEnd: "nominal",
            cancelled: false, engineVersion: "0.6.7", method: "test", isSimulator: true
        )
    }

    @Test func historyComparesARunWithTheOneBeforeItOnTheSameModel() {
        let store = InMemoryBenchmarkHistoryStore()
        let history = BenchmarkHistory(store: store) { DeviceInfo(model: "iPhone16,2", system: "iOS 27.0", isSimulator: false) }
        let start = Date(timeIntervalSince1970: 1_000)
        history.record(result(model: "a", rate: 20), date: start)
        history.record(result(model: "b", rate: 50), date: start.addingTimeInterval(10))
        history.record(result(model: "a", rate: 22), date: start.addingTimeInterval(20))
        #expect(history.entries.map(\.result.model) == ["a", "b", "a"])
        #expect(abs((history.change(for: history.entries[0]) ?? 0) - 0.1) < 0.0001)
        #expect(history.change(for: history.entries[1]) == nil, "first run of b")
        #expect(history.change(for: history.entries[2]) == nil, "first run of a")
        #expect(BenchmarkHistory(store: store).entries.count == 3, "kept across launches")
        history.delete(history.entries[0])
        #expect(store.entries().count == 2)
    }

    @Test func aRunOnOtherComputeIsNotComparedAndCancelledRunsAreNotSaved() {
        let history = BenchmarkHistory(store: InMemoryBenchmarkHistoryStore()) { DeviceInfo(model: "x", system: "y", isSimulator: true) }
        history.record(result(model: "a", rate: 20, backend: "cpu"), date: Date(timeIntervalSince1970: 1))
        history.record(result(model: "a", rate: 60, backend: "wgpu (Metal)"), date: Date(timeIntervalSince1970: 2))
        #expect(history.change(for: history.entries[0]) == nil)
        #expect(BenchmarkHistoryRow.changeText(0.1) == "+10% vs last run")
        #expect(BenchmarkHistoryRow.isNoise(0.02) && !BenchmarkHistoryRow.isNoise(-0.05))
    }

    @Test func aPromptSetRunsEveryPromptOnEveryModelAndKeepsTheAnswers() async throws {
        let chat = ControlledChatService(autoReply: ["Par", "is"])
        let services = makeServices(chat: chat)
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let store = InMemoryPromptSetStore()
        let viewModel = PromptSetsViewModel(services: services, device: device, store: store, initialModel: TestModels.small.alias)
        #expect(viewModel.sets.map(\.name) == ["Quick Check"], "starts with the starter set")

        var set = viewModel.newSet()
        set.name = "  "
        set.systemPrompt = "Be brief"
        set.prompts = ["Capital of France?", "  ", "Capital of Italy?"]
        viewModel.save(set)
        #expect(viewModel.selected?.name == "Untitled")
        viewModel.addModel()
        #expect(viewModel.models.count == 2 && viewModel.models[0] != viewModel.models[1])

        viewModel.run()
        #expect(await eventually { !viewModel.isRunning && viewModel.selected?.runs.isEmpty == false })
        let run = try #require(viewModel.selected?.runs.first)
        #expect(run.answers.count == 4, "two prompts on two models; the blank one is skipped")
        #expect(run.answers.allSatisfy { $0.reply == "Paris" && $0.tokens == 2 && $0.error == nil })
        #expect(await chat.histories.first?.map(\.role) == [.system, .user])
        #expect(store.sets().first { $0.id == set.id }?.runs.count == 1, "saved")
        #expect(PromptSetsView.summary(of: run.models[0], in: run).hasPrefix("2 answers"))
        #expect(PromptSetsView.changes(from: run, to: run) == "All 4 answers match the run before this one.")
    }

    private func makePlayground(reply: [String]) -> (PlaygroundViewModel, ControlledChatService) {
        let chat = ControlledChatService(autoReply: reply)
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let router = ServeRouter(services: makeServices(chat: chat), device: device)
        return (PlaygroundViewModel(router: router, model: TestModels.small.alias) { "http://10.0.0.2:11435" }, chat)
    }

    @Test func thePlaygroundBuildsTheRequestItShows() throws {
        let (playground, _) = makePlayground(reply: [])
        playground.systemPrompt = "Be brief"
        playground.messages[0].text = "Hi"
        playground.maxTokens = 64
        playground.stopText = "END\nSTOP"
        playground.wantsJSON = true
        let object = try JSONSerialization.jsonObject(with: Data(playground.requestBodyText.utf8)) as? [String: Any]
        #expect((object?["messages"] as? [[String: String]])?.map { $0["role"] } == ["system", "user"])
        #expect(object?["max_tokens"] as? Int == 64)
        #expect(object?["stop"] as? [String] == ["END", "STOP"])
        #expect((object?["response_format"] as? [String: String])?["type"] == "json_object")
        #expect(playground.code(.curl).contains("http://10.0.0.2:11435/v1/chat/completions"))
        #expect(playground.code(.python).contains("requests.request("))
        #expect(playground.code(.swift).contains("URLSession.shared"))
        playground.toolsText = "{}"
        #expect(playground.toolsProblem == "Tools must be a JSON array." && !playground.canRun)
    }

    @Test func thePlaygroundRunsThroughTheRouterAndStreamsTheReply() async {
        let (playground, chat) = makePlayground(reply: ["Hel", "lo"])
        playground.messages[0].text = "Hi"
        playground.run()
        #expect(await eventually { !playground.isRunning && playground.metrics != nil })
        #expect(playground.reply == "Hello")
        #expect(playground.metrics?.status == 200)
        #expect(playground.metrics?.tokens == 2)
        #expect(playground.rawResponse.contains("data: [DONE]"))
        #expect(await chat.replyModels == [TestModels.small.alias])
    }

    @Test func aLoggedRequestOpensInTheFormOrAsRawJSON() {
        let (playground, _) = makePlayground(reply: [])
        playground.open(method: "POST", path: "/v1/chat/completions", body: #"{"model":"smollm2-135m-q4","stream":true,"messages":[{"role":"system","content":"S"},{"role":"user","content":"Hi"}]}"#)
        #expect(!playground.isRaw)
        #expect(playground.systemPrompt == "S" && playground.messages.map(\.text) == ["Hi"] && playground.streams)
        #expect(playground.model == TestModels.small.alias)
        // A field the form can't show keeps the request as sent.
        playground.open(method: "POST", path: "/v1/chat/completions", body: #"{"messages":[{"role":"user","content":"Hi"}],"user":"me"}"#)
        #expect(playground.isRaw && playground.rawBody.contains("\"user\""))
        playground.open(method: "GET", path: "/v1/models", body: nil)
        #expect(playground.isRaw && playground.method == "GET" && playground.canRun)
    }

    @Test func aChatsSystemPromptIsSentFirstAndSaved() async throws {
        let container = try makeContainer()
        let store = SwiftDataConversationStore(context: container.mainContext)
        let service = ControlledChatService(autoReply: ["ok"])
        let list = ChatListViewModel(services: makeServices(chat: service), store: store)
        list.newChat()
        let chat = try #require(list.activeChat)
        chat.systemPrompt = "  Answer in French.  "
        #expect(chat.conversation.systemPrompt == "Answer in French.")
        chat.draft = "Hello"
        chat.send()
        #expect(await eventually { await service.histories.count == 1 })
        #expect(await service.histories.first?.map(\.role) == [.system, .user])
        #expect(await service.histories.first?.first?.text == "Answer in French.")
        #expect(chat.contextEstimate.tokens > 0 && chat.contextEstimate.window != nil)
        chat.systemPrompt = ""
        #expect(chat.conversation.systemPrompt == nil)
    }
}
