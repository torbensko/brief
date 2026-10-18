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

**Current verification gap:** project-name hints, curated coding disambiguation, broad project-type detection, and a short recovery buffer are implemented. The Qwen model has been downloaded and verified on this Mac; 42 offline synthetic recognition checks completed, with project-name hints correcting “Blend” to “Blint.” Better-than-macOS recognition quality and end-to-end delivery in Blint still require real speech evaluation. See the [recognition evaluation](Documentation/RECOGNITION-EVALUATION.md) for results and a repeatable check.

## Build and open

Use an Apple Silicon Mac with full Xcode and Swift 6.4 (the toolchain verified here). Install Xcode's Metal compiler once if it is missing:

```sh
xcodebuild -downloadComponent MetalToolchain
Scripts/build-app.sh
open build/LocalDictation.app
```

The first build downloads Swift dependencies. The script packages both executables and the MLX Metal shaders. It uses the installed Apple Development signing identity when exactly one is available, so macOS can retain permissions across rebuilds. Otherwise it falls back to ad-hoc signing; a paid developer account is not required. `SIGNING_IDENTITY` selects a specific installed identity (or `-` for ad-hoc). Keep the app at a consistent location. Moving from ad-hoc to development signing requires granting permissions once for the new identity; ad-hoc rebuilds can require granting them repeatedly.

The waveform icon in the menu bar opens Record, Insert Pending, Recent dictation, Settings, and Quit. Settings opens automatically until a model folder is configured. Use the packaged app rather than `swift run`, since transcription requires the embedded worker and resources.

## First use

1. In Settings → Model, explicitly download the Qwen3-ASR BF16 model, or choose an existing local model folder and save settings. Weights are several gigabytes and are not included in the project.
2. Grant Microphone access in Settings → General. Accessibility is needed only for insertion into other apps; recording and manual copy remain available without it.
3. Review the shortcuts in Settings → Shortcuts. By default, hold ⌃⌥Space while speaking and release to finish. You can change the shortcut or choose press-to-start / press-to-stop mode.
4. The completed text inserts automatically into the field where dictation started, if it is still active and unchanged and Accessibility access is granted. Standard clipboard paste is the default delivery method, including for web editors. The app never presses Return. Review the result in Recent. If the destination changed or recognition raised a warning, the transcript remains saved for review or manual insertion.

Audio, transcripts, settings, and downloaded weights live in `~/Library/Application Support/LocalDictation`, outside this project. Model downloading is explicit; recognition uses local files. The default keeps the latest recovery entry. Set a count or minute limit at the top of Recent; older audio and text are automatically deleted.

## Project name dictionary

Settings → Recognition scans `~/repos` at launch and keeps a short list of main project names, such as Blint and BuildIQ. It reads root project metadata and short README titles, uses the folder name as a fallback, and combines duplicate Git worktrees. Names from all projects are available together.

The current scanner does not collect dependencies, internal package names, or source symbols. A small curated coding vocabulary and broad project-type detection complement this name dictionary; they are not a dependency index. Optional user-entered spellings are preserved. The dictionary guides recognition; it does not perform automatic word replacement or guarantee a particular transcription.

Scans stay local and results are cached in Application Support. Older broad scan caches are excluded until refreshed. Existing recordings retain their original vocabulary snapshot unless explicitly retranscribed with current vocabulary.

## Recover the last dictation

The floating panel starts at the top centre. Drag its small horizontal handle to move it; the position is remembered across recordings and launches. While recording, its waveform shows microphone activity and duration. Recognition runs on the completed recording. Afterwards, the card displays the last text, delivery status, **Copy last text**, and **Recent** for 30 seconds, then disappears. Dismiss it sooner with × or reopen it for another 30 seconds from the menu bar's **Show last text** action. Copying does not erase the saved delivery explanation. Opening the app does not automatically reopen an old result.

Recent is a recovery buffer, not a permanent archive. It defaults to the latest entry, with **Keep last entries** or **Keep for minutes** controls at the top. Switching to minutes starts at five minutes. Both audio and transcript expire. Active work is protected, and count mode retains the previous usable transcript if a new attempt fails. Time mode removes expired results even if pending. Export anything you want to keep longer.

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
