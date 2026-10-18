# LocalDictation

Native macOS menu-bar dictation with local Qwen3-ASR recognition, automatic coding vocabulary, recoverable recordings, and conservative text insertion.

## Build and open

Use an Apple Silicon Mac with full Xcode and Swift 6.4 (the toolchain verified here). Install Xcode's Metal compiler once if it is missing:

```sh
xcodebuild -downloadComponent MetalToolchain
Scripts/build-app.sh
open build/LocalDictation.app
```

The first build downloads Swift dependencies. The script creates a locally ad-hoc-signed app containing both executables and the MLX Metal shaders. A paid developer account is not required. `SIGNING_IDENTITY` can optionally select an installed signing identity. Keep the app at a consistent location when granting permissions; rebuilding an ad-hoc-signed app can require granting permissions again.

The waveform icon in the menu bar opens Record, Insert Pending, History, Settings, and Quit. Settings opens automatically until a model folder is configured. Use the packaged app rather than `swift run`, since transcription requires the embedded worker and resources.

## First use

1. In Settings → Model, explicitly download the Qwen3-ASR BF16 model, or choose an existing local model folder and save settings. Weights are several gigabytes and are not included in the project.
2. Grant Microphone access in Settings → General. Accessibility is needed only for insertion into other apps; recording and manual copy remain available without it.
3. Review the shortcuts in Settings → Shortcuts. Start and stop a recording using the same shortcut.
4. Review the result in History. If the destination changed or recognition raised a warning, the transcript remains saved for review or manual insertion.

Audio, transcripts, settings, and downloaded weights live in `~/Library/Application Support/LocalDictation`, outside this project. Model downloading is explicit; recognition uses local files. Audio is retained until explicitly deleted.

## Automatic coding vocabulary

Settings → Coding scans `~/repos` automatically at launch. Choose another repositories folder or use **Scan repositories** to refresh it. All discovered names are included together in every new recording; no profile switching is required.

The scanner collects folder names, manifest names (including nested packages), product names, and project README titles. It recognizes source languages and common dependency stacks, adding appropriate coding terms. General coding vocabulary is built in. Optional extra spellings and terms from older saved profiles are preserved.

Scans run locally in the background, skip dependencies/build output/hidden folders/symlinks, and never execute project files. Results are cached in Application Support. Failed scans retain the previous vocabulary; warnings are visible, and oversized combined context is rejected rather than silently truncated. Existing recordings retain their original vocabulary snapshot unless explicitly retranscribed with current vocabulary.

## Checks

```sh
Scripts/check.sh
```

This runs the core tests, builds/signs the app, and exercises MLX computation using the packaged worker and Metal shaders. It does not substitute for a real microphone, recognition, and cross-application insertion test. See [Documentation/VALIDATION.md](Documentation/VALIDATION.md) for the latest verified status and remaining manual checks.

## Source

- `Sources/DictationCore`: persistence, models, audio utilities, vocabulary, delivery policy.
- `Sources/LocalDictation`: lifecycle/menu bar, native UI, audio capture, shortcuts, insertion, installer, worker client.
- `Sources/DictationWorker`: offline Qwen3-ASR model worker.
- `Tests/DictationCoreTests`: core regression tests.
- [SPEC.md](SPEC.md): product requirements, including acceptance checks.
- [HANDOFF.md](HANDOFF.md): historical Linux handoff; its missing-entry-point and build-status notes describe the source before the macOS integration work.

The imported folder had no Git history. A new repository has been initialized here; the original archive's commit history was not present.
