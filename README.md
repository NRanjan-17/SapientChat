# Sapient Chat

Run large language models on iPhone and iPad, entirely on the device, with
[SAPIENT](https://github.com/SkidGod4444/sapient), a pure-Rust edge inference
engine. Chat with them, benchmark them, and serve them to other apps and
devices through an OpenAI-compatible API.

Nothing you type leaves the device. Models download once from Hugging Face and
then run offline.

## What it does

- **Chats** with any model from SAPIENT's phone-sized catalog (SmolLM2, Qwen2.5,
  Llama 3.2, DeepSeek-R1, Phi, Gemma, …). Replies stream with live speed stats;
  Model Stats shows the backend, context window, memory and per-chat averages.
- **Models tab**: download, load (up to four in memory), unload and delete.
  Downloaded models are listed first; sort by size. Each model shows its maker's
  logo, size, format and memory need.
- **Benchmark**: decode speed, first-token time, prefill and memory for one model,
  or two models side by side (Compare), exportable as PDF or JSON.
- **API server**: SAPIENT's OpenAI-compatible routes plus model management,
  served from the phone to apps on the device (URL handoff) and devices on the
  network (HTTP). See [SapientKit](SapientKit/README.md) and
  [Integrating SAPIENT](docs/INTEGRATION.md).
- **Dynamic Island**: downloads, API requests and benchmarks show live progress;
  a running server shows its request count.

## Requirements

- Xcode 27, iOS/iPadOS 27.
- An iPhone or iPad. Apple chips with 6 GB of RAM or more get CPU + GPU by
  default; smaller devices use the GPU. The simulator works for development
  (its numbers measure the Mac, not a phone).

## Build and run

1. Open `SapientChat.xcodeproj`.
2. Select the **SapientChat** scheme, set your team under Signing & Capabilities
   (app and `SapientActivity` targets).
3. Run on a device or simulator.

The engine comes from the Swift package
[`openhorizon-labs/sapient-swift`](https://github.com/openhorizon-labs/sapient-swift),
which Xcode resolves on first build.

Tests:

```bash
xcodebuild test -project SapientChat.xcodeproj -scheme SapientChat \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:SapientChatTests
swift test    # SapientKit, from the repository root
```

Debug builds accept `-SapientTab chats|models|benchmark|settings` (Edit Scheme →
Arguments) to open a tab, handy for screenshots.

## Settings worth knowing

| Setting | Where | What it does |
| --- | --- | --- |
| Compute | Settings → Engine | **Automatic** (default): CPU + GPU, the GPU reads the prompt and the CPU writes the reply; the GPU alone when the device is hot, in Low Power Mode, has under 6 GB of RAM, or the model is full precision. Or force CPU + GPU, GPU or CPU. Changing it reloads models. |
| Context window | A model's ⋯ menu, or the model menu in a chat | 1K–8K tokens or the engine default, for models of 1.4B and up. |
| API server | Settings → API Server | On/off, port, network access, API key, request log. |
| Keep running in background | Settings → Endpoints & Access | Debug/sideload builds only: keeps the server answering with the app closed (silent audio, models on the CPU). Uses more battery; Apple doesn't allow it in App Store builds. |
| Save prompts and replies | Endpoints & Access | Whether the request log keeps prompts, replies and bodies or only timing and status. |

## How it behaves in the background

- **Downloads finish in the background**, with the server on or off. Each one
  asks iOS for a continued processing task, so iOS shows its progress and keeps
  the app running. If iOS stops one anyway, it resumes from where it stopped when
  the app runs again.
- **Replies and benchmarks stop** when you leave the app: iOS doesn't allow GPU
  work in the background. A prompt sent while the model was still downloading or
  loading is answered when you come back.
- **The API server** pauses in the background (after letting running requests
  use iOS's ~30 s of extra time), unless "Keep running in background" is on.

## Project layout

```
SapientChat/          the app
  App/                entry point, menu commands
  Models/             value types (PhoneModel, ComputePreference, …)
  Services/           engine, downloads, Live Activities, background work
  Server/             HTTP server, router, request log capture
  ViewModels/         one per screen
  Views/              SwiftUI
SapientActivity/      Live Activity widget extension
Shared/               types used by both (activity attributes)
SapientKit/           Swift package for other apps to call Sapient Chat
SapientChatTests/     unit tests (Swift Testing)
docs/                 integration guide
```

## Privacy

Chats, the request log and downloaded models stay on the device. The app talks
to the network only to download models (Hugging Face) and, when you turn it on,
to answer API requests on your network.

## License

Sapient Chat is **dual-licensed** by Nalinish Ranjan: the
[GNU AGPL-3.0-only](LICENSE) **or** a [commercial license](COMMERCIAL-LICENSE.md)
for uses that aren't compatible with the AGPL (closed source, rebranding).
[SapientKit](SapientKit/) is [MIT](SapientKit/LICENSE), so any app can use it to
talk to Sapient Chat. Every source file carries an SPDX header.

Third-party parts (details in [NOTICE](NOTICE)):

- The **SAPIENT engine** is AGPL-3.0-only or commercial from OpenHorizon Labs Pvt
  Ltd. Using Sapient Chat outside the AGPL also needs the engine's commercial
  license. "SAPIENT" and its logo are OpenHorizon Labs trademarks.
- Model maker logos come from [LobeHub Icons](https://github.com/lobehub/lobe-icons)
  (MIT) and are trademarks of their owners.
- Downloaded models carry their own licenses, set by their authors.

The licenses are also in the app: Settings → About → Acknowledgements.
