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

## Install

Add this package (`SapientKit/` in the SapientChat repo) to your app, then:

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
// What the device offers, and what's downloaded, loaded, and fits in memory.
let catalog = try await sapient.catalog()

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
| `GET /v1/health` | Engine version, loaded models, memory, thermal state |
| `GET /v1/models` | Downloaded models |
| `GET /v1/catalog` | Every model offered, with download/load/fit state |
| `POST /v1/models/download` | `{"model", "stream"?}` — progress as server-sent events with `stream` |
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

## Limits (set by SAPIENT's iOS engine)

- Only catalog models sized for phones load; memory is checked against what iOS
  allows before each load.
- `temperature` and `tools` aren't applied per request; a reply is capped at 512
  tokens. `usage.prompt_tokens` is 0; `completion_tokens` counts streamed pieces.
- `/v1/completions` runs the prompt through the model's chat template.
