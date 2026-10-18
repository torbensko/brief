# LocalDictation

Local, coding-centric macOS dictation for speaking high-level specifications and documentation to coding agents. The intended experience is like speaking with another coder who knows your terms and projects.

## Product intent — read before changing the app

- **Quality first:** aim for less correction than default macOS dictation. Model size, speed, memory use, and real-time feedback are secondary to faithful, complete output.
- **Know the projects:** discover names across `~/repos`, including Blint, without manual project lists or profile switching.
- **Understand coding speech:** add a small curated vocabulary for disambiguation, such as JSON versus “Jason,” with relevant terms selected from broad project types such as TypeScript and Swift.
- **Keep context broad:** this is for explaining requirements to coding agents. It does not need a dependency inventory or detailed knowledge of classes, functions, and internal packages.
- **Work across apps:** support dictation into Blint and other agent tools, editors, browsers, and native fields, with saved transcripts and manual copy when safe insertion is unavailable.
- **Preserve meaning:** context should guide recognition, never blindly replace ordinary words or rewrite the user's specifications.

The authoritative requirements are in [SPEC.md](SPEC.md), especially its purpose, priorities, vocabulary scope, and quality acceptance criteria. Both project names **and** targeted coding disambiguation are required. Do not simplify this into names only or expand it into a codebase index. Explain how proposed features improve this workflow before implementing them.

**Current gap:** the app currently implements the project-name dictionary, but curated coding disambiguation and project-type selection still need implementation and evaluation. Better-than-macOS accuracy and end-to-end delivery in Blint have not yet been demonstrated. This documentation update does not claim those features are complete.

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

## Project name dictionary

Settings → Project names scans `~/repos` at launch and keeps a short list of main project names, such as Blint and BuildIQ. It reads root project metadata and short README titles, uses the folder name as a fallback, and combines duplicate Git worktrees. Names from all projects are available together.

The current scanner does not collect dependencies, internal package names, or source symbols. The planned small curated coding vocabulary and broad project-type detection complement this name dictionary; they are not a dependency index. Optional user-entered spellings are preserved. The dictionary guides recognition; it does not perform automatic word replacement or guarantee a particular transcription.

Scans stay local and results are cached in Application Support. Older broad scan caches are excluded until refreshed. Existing recordings retain their original vocabulary snapshot unless explicitly retranscribed with current vocabulary.

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
