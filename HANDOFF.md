# Implementation handoff — 16 October 2026

> Historical handoff. For the current macOS build and verification status, see [Documentation/VALIDATION.md](Documentation/VALIDATION.md) and [README.md](README.md). The missing lifecycle and packaging described below have since been implemented.

## Verified status

This is **unfinished source**, not an installable or end-to-end-tested macOS application.

Development occurred in a Linux session at `/mnt/data/LocalDictation`, not in the folder selected on the user's Mac. The user requested a portable handoff so development can continue in their actual project folder.

Git was initialised before implementation. The initial commit is `43d7234` (`Initialise LocalDictation repository`). The source and this handoff are committed in the supplied archive. The archive includes `.git`; it excludes build caches and model weights.

There are 2,268 lines across the Swift source and tests at this handoff. Treat this as source written, not working-product verification.

## What exists

| Component | Files | Verification |
| --- | --- | --- |
| Domain models/settings | `Sources/DictationCore/Models.swift` | Compiled/tested on Linux |
| Durable session store | `Sources/DictationCore/HistoryStore.swift` | Core unit tests pass |
| Vocabulary handling | `Sources/DictationCore/Vocabulary.swift` | Core unit tests pass |
| Delivery decision policy | `Sources/DictationCore/DeliveryPolicy.swift` | Pure policy tests pass; no real Accessibility test |
| Audio utilities and recognition warnings | `AudioUtilities.swift`, `WorkerProtocol.swift` | Core unit tests pass; no model inference test |
| Native app/controller/UI | `Sources/LocalDictation/` | Written but not compiled on macOS |
| Audio capture | `AudioRecorder.swift` | Written; microphone/device handling not tested |
| Global shortcuts and insertion | `HotKeyManager.swift`, `InsertionService.swift` | Written; not tested in another application |
| Local model installer | `ModelInstaller.swift` | Written; no weights downloaded or installation validated here |
| Helper client and model worker | `WorkerClient.swift`, `Sources/DictationWorker/WorkerMain.swift` | Written; dependency APIs and local inference unverified |

## Commands actually run

Environment: Swift 6.2.1, target `x86_64-unknown-linux-gnu`.

```sh
cd /mnt/data/LocalDictation
swift test
```

The latest verification completed with **35 tests passing in four suites**. A copy of the actual output is in `Documentation/core-tests-linux.log`.

`Package.swift` conditionally includes the native application, worker, and MLX dependencies only on macOS. Therefore passing Linux tests prove **nothing about compilation of those macOS-only targets**.

No native app launch, microphone capture, model inference, or cross-application insertion has been performed here.

## Known missing pieces — start here

1. **The `LocalDictation` app executable has no entry point or app delegate.** Add the lifecycle, menu-bar item/menu, history/settings windows, overlay ownership, callback wiring, startup, and orderly shutdown. The worker has its own `@main`; that does not supply an entry point for the main application.
2. **No app packaging script exists.** `WorkerClient` refers to `Scripts/build-app.sh`, but that file has not been created. The `Scripts` and `Resources` directories were prepared only; empty directories are not part of the Git source tree.
3. **No app Info.plist or signing/resource packaging is supplied.** Add a stable bundle ID, microphone usage description, appropriate menu-bar app configuration, embedded `DictationWorker`, MLX/Metal resources, and a verified build/sign/install workflow.
4. **No resolved macOS dependency graph exists.** Resolve and compile the pinned dependencies on the user's Mac, correct API/build issues, and commit `Package.resolved`. Verify the deployment target against the resolved packages.
5. **No real model weights or recognition results exist.** Verify the installer/local-folder workflow, load Qwen, confirm vocabulary reaches its context, then test full recordings and long-output behaviour.
6. **No manual integration/safety tests have been run.** Run the acceptance checks in `SPEC.md`, especially focus changes, secure/custom fields, terminal behaviour, clipboard delivery, microphone interruptions, and crash recovery.

## Important implementation details to review

- `WorkerClient` intentionally expects `Contents/MacOS/DictationWorker` inside a packaged `.app`; a direct `swift run` is not currently a usable launch path.
- Worker stderr currently goes to the null device. Provide useful local diagnostics during native integration, without leaking recording/transcript content into logs.
- Vocabulary is sent through a Qwen-specific `context` parameter. Preserve and test that path.
- Offline batch planning and token-limit warnings exist, but have only synthetic/core coverage. They do not prove the model returns every word or joins boundaries correctly.
- The installer has manifest/revision/hash checks in source; its network paths and on-disk results are not tested here.
- Paste fallback leaves the transcript on the clipboard instead of restoring previous contents on an arbitrary timer. Explain that behaviour and verify against real target apps.
- Terminal detection currently uses a list of app bundle IDs; an integrated terminal inside a code editor needs additional review.
- Do not advertise encryption, perfect transcription, universal input compatibility, or guaranteed delivery. Those are not established by the source or current tests.

## Continuing in the selected folder

Read `SPEC.md` first for the product contract. Retain this implementation as a starting point, but expect macOS compiler and integration fixes.

When importing the whole archive into a new empty project folder, include its hidden `.git` directory to preserve history. If the destination is already a repository, retain that repository's `.git` and copy the source/docs instead; do not overwrite an existing history.

When using only `SPEC.md`, initialise Git in the selected folder before implementing, unless it is already under version control.

The next concrete milestone is **a packaged app that builds and launches on the user's Mac**, followed by a recorded, locally transcribed utterance recoverable from history. Do not spend the next session polishing UI while the entry point, packaging, and recogniser remain unverified.
