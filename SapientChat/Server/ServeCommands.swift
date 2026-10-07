/// Ready-to-paste `curl` commands for the Server screen's Try It section,
/// one per thing the API does, for a chosen endpoint and model.
nonisolated struct ServeCommand: Identifiable, Equatable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case server = "Server"
        case models = "Models"
        case generate = "Generate"
    }

    let group: Group
    let title: String
    let command: String

    var id: String { title }
}

nonisolated enum ServeCommands {
    /// - Parameters:
    ///   - base: e.g. `http://192.168.1.20:11435`.
    ///   - apiKey: sent as `Authorization: Bearer` when not empty.
    ///   - model: the catalog alias the model commands use.
    static func all(base: String, apiKey: String, model: String) -> [ServeCommand] {
        let auth = apiKey.isEmpty ? "" : " -H 'Authorization: Bearer \(apiKey)'"
        func get(_ path: String) -> String {
            "curl '\(base)\(path)'\(auth)"
        }
        func post(_ path: String, _ body: String, streaming: Bool = false) -> String {
            "curl\(streaming ? " -N" : "") \(base)\(path)\(auth) -H 'Content-Type: application/json' -d '\(body)'"
        }
        let name = #""model":"\#(model)""#
        return [
            ServeCommand(group: .server, title: "Ping", command: get("/v1/ping")),
            ServeCommand(group: .server, title: "Health", command: get("/v1/health")),
            ServeCommand(group: .models, title: "All models", command: get("/v1/catalog")),
            ServeCommand(group: .models, title: "Available to download", command: get("/v1/catalog?status=available")),
            ServeCommand(group: .models, title: "Downloaded", command: get("/v1/catalog?status=downloaded")),
            ServeCommand(group: .models, title: "In memory", command: get("/v1/catalog?status=loaded")),
            ServeCommand(group: .models, title: "Download", command: post("/v1/models/download", "{\(name),\"stream\":true}", streaming: true)),
            ServeCommand(group: .models, title: "Load into memory", command: post("/v1/models/load", "{\(name)}")),
            ServeCommand(group: .models, title: "Unload from memory", command: post("/v1/models/unload", "{\(name)}")),
            ServeCommand(group: .models, title: "Delete download", command: post("/v1/models/delete", "{\(name)}")),
            ServeCommand(group: .generate, title: "Chat", command: post(
                "/v1/chat/completions", #"{\#(name),"messages":[{"role":"user","content":"Hi!"}]}"#
            )),
            ServeCommand(group: .generate, title: "Chat, streaming", command: post(
                "/v1/chat/completions", #"{\#(name),"stream":true,"messages":[{"role":"user","content":"Hi!"}]}"#,
                streaming: true
            )),
            ServeCommand(group: .generate, title: "Completion", command: post(
                "/v1/completions", #"{\#(name),"prompt":"Once upon a time","max_tokens":64}"#
            )),
        ]
    }
}
