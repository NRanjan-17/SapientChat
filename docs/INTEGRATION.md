# Integrating SAPIENT into your app

There are three ways to use SAPIENT models from your own code. Pick by where the
model should run and who manages it.

| | Model runs in | You manage downloads and memory | Best for |
| --- | --- | --- | --- |
| [1. Embed the engine](#1-embed-the-engine-sapient-swift) | your app's process | yes | an app that ships its own on-device AI |
| [2. Call Sapient Chat with SapientKit](#2-call-sapient-chat-with-sapientkit) | Sapient Chat | no, Sapient Chat does | iOS/macOS apps that share one set of models |
| [3. Plain HTTP](#3-plain-http-any-language) | Sapient Chat | no | scripts, servers, other platforms, OpenAI clients |

## 1. Embed the engine (`sapient-swift`)

The engine as a Swift package: a prebuilt `SapientFFI.xcframework` (iOS device,
iOS simulator, macOS) plus Swift bindings.

### Add the package

Xcode → File → Add Package Dependencies →
`https://github.com/openhorizon-labs/sapient-swift`, rule **Up to Next Major
Version** from `0.6.6`, product **Sapient**. Or in `Package.swift`:

```swift
.package(url: "https://github.com/openhorizon-labs/sapient-swift", from: "0.6.6")
// target dependency:
.product(name: "Sapient", package: "sapient-swift")
```

Supports iOS 14+ and macOS 12+. The package links the system libraries it needs
(`c++`, `iconv`, SystemConfiguration, Metal, QuartzCore); you add nothing else.

Recommended entitlements for larger models on iOS:
`com.apple.developer.kernel.increased-memory-limit` and
`com.apple.developer.kernel.extended-virtual-addressing`.

### Load a model and chat

```swift
import Sapient

// Once, at launch: keep downloads in your app's sandbox.
setCacheDir(path: URL.cachesDirectory.appending(path: "sapient").path(percentEncoded: false))

// Optional: download first, with progress. Return false to cancel.
final class Progress: DownloadListener {
    func onProgress(downloadedBytes: UInt64, totalBytes: UInt64) -> Bool {
        print("\(downloadedBytes) of \(totalBytes)")
        return true
    }
}
try await downloadModel(model: "openhorizon/qwen2.5-0.5b-q4", listener: Progress())

// Load. Unset options use the engine's defaults.
var options = GenerationOptions(maxTokens: 512)
options.backend = "hybrid"        // "cpu", "wgpu" (GPU), "hybrid" (CPU + GPU); nil = automatic
options.contextLength = 4096      // nil = engine default (8192; 3072 for >1.5B on phones)
let session = try await loadSession(model: "openhorizon/qwen2.5-0.5b-q4", options: options)

// Stream a reply. Return false from onToken to stop generating.
final class Printer: TokenListener {
    func onToken(token: String) -> Bool {
        print(token, terminator: "")
        return true
    }
}
let reply = try await session.chatMessagesStream(
    messages: [Message(role: "system", content: "Be brief."),
               Message(role: "user", content: "What is SAPIENT?")],
    listener: Printer()
)
```

`chatMessagesStream` is stateless: send the whole history each turn (the
engine's prefix cache keeps re-sent history cheap). For a session that keeps its
own history, use `chatStreamAsync(userMessage:listener:)` / `chatAsync(userMessage:)`.

### More of the API

| Call | |
| --- | --- |
| `listModels()` | The catalog: alias, repo, family, params, category, gated |
| `modelDownloadSize(model:)` | Bytes a download will fetch |
| `session.backendLabel()`, `contextLength()`, `loadTimeMs()`, `isMmap()` | How the model was loaded |
| `session.benchmarkAsync(options:listener:)` | Decode/prefill speed, first token, memory |
| `memoryFootprintBytes()`, `availableMemoryBytes()` | Your process's memory and what iOS still allows |
| `setThermalLevel(level:)` | `.nominal`/`.fair`/`.serious`/`.critical`, mapped from `ProcessInfo.thermalState`, so the engine uses fewer CPU threads when hot |
| `version()` | Engine version |

Errors are `SapientError` (e.g. `.Cancelled`).

### Lessons from Sapient Chat

- **Memory:** check `availableMemoryBytes()` before loading; iOS ends an app that
  goes over its limit. 4/8-bit (GGUF) models are memory-mapped and cheapest.
  CPU + GPU (`"hybrid"`) costs about one copy for those, but two copies for
  full-precision models, so use the GPU alone for them on small devices.
- **Background:** iOS forbids GPU work in the background. Stop generating when
  your app leaves the foreground, or load on `"cpu"` if you must keep going.
  Downloads can continue with a `BGContinuedProcessingTask` (iOS 26+).
- **Threading:** the async calls run on the engine's own threads; don't call the
  blocking variants from the main thread.
- **Thermals:** forward `ProcessInfo.thermalStateDidChangeNotification` to
  `setThermalLevel`; prefer the GPU alone while the device is hot.

## 2. Call Sapient Chat with SapientKit

Let Sapient Chat hold the models (downloaded once, shared by every app, up to
four in memory) and ask it to run them. `SapientKit` (in this repo) wraps the
API with Swift types, over HTTP or, on the same iPhone, a URL handoff that brings
Sapient Chat to the front and returns the result to your app.

```swift
import SapientKit

let sapient = SapientClient.automatic(callbackScheme: "myapp", appName: "My App")
let up = try await sapient.ping()                  // { status, version }
let ready = try await sapient.catalog(.downloaded)
try await sapient.load("openhorizon/qwen2.5-0.5b-q4")
let reply = try await sapient.chat([.user("Hi!")], maxTokens: 200)
```

Setup (URL scheme, `onOpenURL`, API key) and the full method list:
[SapientKit/README.md](../SapientKit/README.md).

## 3. Plain HTTP (any language)

Turn on Settings → API Server in Sapient Chat. It serves `sapient serve`'s
OpenAI-compatible API on port 11435 (Endpoints & Access shows the addresses and
ready-to-copy commands for every route).

```bash
curl http://192.168.1.20:11435/v1/ping
curl 'http://192.168.1.20:11435/v1/catalog?status=downloaded'
curl http://192.168.1.20:11435/v1/models/load -H 'Content-Type: application/json' \
  -d '{"model":"openhorizon/qwen2.5-0.5b-q4"}'
curl http://192.168.1.20:11435/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"openhorizon/qwen2.5-0.5b-q4","messages":[{"role":"user","content":"Hi!"}]}'
```

Any OpenAI client works by pointing its base URL at the phone:

```python
from openai import OpenAI
client = OpenAI(base_url="http://192.168.1.20:11435/v1", api_key="unused-or-your-key")
reply = client.chat.completions.create(
    model="openhorizon/qwen2.5-0.5b-q4",
    messages=[{"role": "user", "content": "Hi!"}],
)
print(reply.choices[0].message.content)
```

Keep in mind:

- The server answers while Sapient Chat is open. With "Keep running in
  background" (Debug/sideload builds) it also answers with the app closed, on
  the CPU, at a battery cost.
- Set an API key before allowing other devices on a shared network; clients
  then send `Authorization: Bearer <key>`.
- A reply is capped at 512 tokens; `temperature` and `tools` aren't applied per
  request.
- Every request is in Sapient Chat's request log (Settings → Request Log), with
  the prompt, reply and timing.
