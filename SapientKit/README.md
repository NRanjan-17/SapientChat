# SapientKit

Call **SapientChat** — the app that downloads, loads and runs SAPIENT models on
iPhone and iPad — from your own app. SapientChat holds the models (up to four in
memory at once); your app asks it to load one and run chats.

## Two ways to reach SapientChat

| Where your app runs | Route | Streaming |
| --- | --- | --- |
| Another device (Mac, phone, server) on the same network | HTTP to the API server | Yes |
| Beside SapientChat on iPad (Split View, Stage Manager) | HTTP to `127.0.0.1:11435` | Yes |
| Same iPhone | URL handoff: SapientChat comes to the front, runs the request, returns to your app | No — the full reply arrives at once |

iOS suspends apps in the background, so on the same iPhone SapientChat's server
can't answer while your app is in front. The handoff covers that case.
`SapientClient.automatic` tries HTTP first and falls back to the handoff.

HTTP needs the server on: in SapientChat, tap **API Server** and turn it on.
It answers while SapientChat is open; Debug/sideload builds can keep it
answering with the app closed (Endpoints & Access → Keep running in background).
Other ways to use SAPIENT, including embedding the engine in your own app:
[docs/INTEGRATION.md](../docs/INTEGRATION.md).

## Install

In Xcode: **File → Add Package Dependencies**, enter

```
https://github.com/NRanjan-17/SapientChat
```

and add the **SapientKit** product to your app target (only SapientKit builds;
the app itself isn't part of the package). Or in `Package.swift`:

```swift
.package(url: "https://github.com/NRanjan-17/SapientChat", from: "1.0.0"),
// target dependency:
.product(name: "SapientKit", package: "SapientChat"),
```

Requires iOS 18 / macOS 15. MIT-licensed. Then:

```swift
import SapientKit

// Another device or iPad side by side:
let sapient = SapientClient.http(URL(string: "http://192.168.1.20:11435")!)

// Same iPhone, or whichever works:
let sapient = SapientClient.automatic(callbackScheme: "myapp", appName: "My App")
```

For the handoff (`.handoff` or `.automatic`):

1. Register a URL scheme for your app (Target → Info → URL Types), e.g. `myapp`.
2. Forward incoming URLs to the client:
   ```swift
   WindowGroup { ContentView() }
       .onOpenURL { url in sapient.handle(url) }
   ```
3. Optional: add `sapient` to `LSApplicationQueriesSchemes` in Info.plist to check
   `HandoffTransport.isSapientInstalled` first.

If an API key is set on SapientChat's server screen, pass it as `apiKey:`.

## Use

```swift
// Is SapientChat there? No model work.
let up = try await sapient.ping()

// What the device offers, and what's downloaded, loaded, and fits in memory.
let catalog = try await sapient.catalog()
let downloaded = try await sapient.catalog(.downloaded)   // or .available, .loaded

// Download (with progress over HTTP), then load.
for try await event in sapient.downloadWithProgress("openhorizon/qwen2.5-0.5b") {
    print(event.fraction ?? 0)
}
try await sapient.load("openhorizon/qwen2.5-0.5b")

// Chat. `model` nil uses the most recently used loaded model.
let reply = try await sapient.chat([.system("Be brief."), .user("What is SAPIENT?")], maxTokens: 200)
print(reply.text)

// Stream (HTTP); over a handoff the whole reply arrives as one piece.
for try await piece in sapient.streamChat([.user("Write a haiku")]) {
    print(piece, terminator: "")
}

// Free memory, or delete files.
try await sapient.unload("openhorizon/qwen2.5-0.5b")
try await sapient.delete("openhorizon/qwen2.5-0.5b")

// Engine version, loaded models, memory and thermal state.
let health = try await sapient.health()
```

Errors are `SapientError`: `.api(status:message:)`, `.unavailable` (not installed
or not reachable), `.cancelled` (the user cancelled in SapientChat),
`.invalidResponse`.

## The API

SapientChat serves `sapient serve`'s OpenAI-compatible routes, plus model
management. Any HTTP client works; SapientKit is a convenience.

| Route | |
| --- | --- |
| `GET /v1/ping` | `{"status":"ok","version":…}`, no model work |
| `GET /v1/health` | Engine version, loaded models, memory, thermal state |
| `GET /v1/models` | Downloaded models |
| `GET /v1/catalog` | Every model offered, with download/load/fit state and sizes (`memory`, `size_on_disk`); `?status=available\|downloaded\|loaded` filters it |
| `POST /v1/models/download` | `{"model", "stream"?}` — progress as server-sent events with `stream` (`progress` "45%", `size` "412 MB of 1.1 GB") |
| `POST /v1/models/load` | `{"model"}` — downloads if needed |
| `POST /v1/models/unload` | `{"model"?}` — omit to unload all |
| `POST /v1/models/delete` | `{"model"}` |
| `POST /v1/chat/completions` | OpenAI chat: `model`, `messages`, `stream`, `max_tokens`, `stop` |
| `POST /v1/completions` | `prompt` instead of `messages` |

```bash
curl http://192.168.1.20:11435/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"openhorizon/qwen2.5-0.5b","messages":[{"role":"user","content":"Hi!"}]}'
```

### Handoff URL

```
sapient://x-callback-url/request
  ?path=/v1/chat/completions      any route above
  &method=POST                    default: POST with a body, else GET
  &body=<base64url JSON>          request body (stream is turned off)
  &key=<API key>                  if the server has one set
  &x-source=<app name>            shown in SapientChat while it runs
  &x-success=<url>                gets ?status=<code>&body=<base64url JSON>
  &x-error=<url>                  same plus error=<message>, for 4xx/5xx
  &x-cancel=<url>                 opened if the user cancels
```

Plain JSON replies are indented with sorted keys; streamed events are one line
each. Downloads and loads started over the API show in SapientChat's Models tab
and Dynamic Island, and every request is in its Request Log with the prompt,
reply and timing.

## Limits (set by SAPIENT's iOS engine)

- Only catalog models sized for phones load; memory is checked against what iOS
  allows before each load.
- `temperature` and `tools` aren't applied per request; a reply is capped at 512
  tokens. `usage.prompt_tokens` is 0; `completion_tokens` counts streamed pieces.
- `/v1/completions` runs the prompt through the model's chat template.
