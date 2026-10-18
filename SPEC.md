# Brief — product and implementation specification

## Purpose and authority

Build a standalone, native macOS dictation utility for Torben and coders who work similarly. The primary use is speaking high-level specifications, requirements, explanations, and documentation to coding agents. The intended experience is like speaking with another coder who knows the terminology and the names of your projects.

**Output quality is the main priority.** The product should require less correction than default macOS dictation on this workflow, especially for recurring project names such as **Blint** and ambiguous coding terms such as **JSON**, which might otherwise be transcribed as “Jason.” Better-than-macOS quality is an acceptance goal to demonstrate, not an existing claim.

The app must be usable across applications, including **Blint, the user's coding tool**, as well as other coding-agent interfaces, editors, browsers, and native text fields. It must run independently of Blint. “Usable anywhere” means system-wide access with safe insertion where supported and a retained transcript/manual copy fallback elsewhere; it does not authorize unsafe insertion or imply universal compatibility has been proven.

`LocalDictation` is a working name, not a final branding decision.

### Product intent governs feature decisions

Preserve both parts of the recognition context: **all project names plus a small, curated vocabulary for coding disambiguation**. Neither a project-name-only dictionary nor a dependency/codebase index satisfies this requirement. Repository scanning should provide broad context, not detailed knowledge of classes, symbols, dependencies, or implementation internals.

Evaluate proposed features against the primary workflow: will this reduce corrections, preserve the intended specification, or make dictation safer and easier to use in the destination app? More collected terms, deeper indexing, smaller models, faster inference, and real-time UI are not goals in themselves. Explain how a proposed behavior serves this intent before implementing it. Do not replace the agreed product intent with whichever narrow implementation is easiest to build.

This clarification supersedes the earlier project-name-only and broad dependency-vocabulary directions. Historical validation notes describe past implementations, not current requirements.

This document describes the required product, **not a claim that every feature is implemented**. Read `Documentation/VALIDATION.md` for the current verified implementation status; `HANDOFF.md` preserves the original handoff. Continue existing source where useful; do not throw it away and start again without a concrete technical reason.

Work in the folder selected by the user in the coding session. Initialise Git before writing implementation files when that folder is not already a repository. Preserve an existing repository, its history, and unrelated files. Never claim to have written to the user's Mac when work actually happened in a separate container.

## 1. Priorities and constraints

Priority order:

1. Faithful, complete output for spoken specifications and documentation, including project names and coding terminology.
2. Preservation and recovery of recordings and transcripts.
3. Safe, convenient system-wide delivery.
4. Responsive native controls and clear recording/processing feedback.
5. Model size, memory efficiency, transcription speed, and real-time feedback are secondary to output quality. Accept larger models and slower completed-recording processing when measured quality improves.

Target hardware is the user's Apple Silicon MacBook Pro, M4 Max with 128 GB unified memory. There is no requirement to accommodate low-memory consumer machines. Prefer full-precision/BF16 model weights initially; assess quality before introducing aggressive quantisation.

All recording, recognition, vocabulary handling, and history storage must work locally. No recurring API fees, accounts, subscriptions, cloud transcription fallback, analytics, or upload of audio/transcripts. An explicitly initiated initial model download is acceptable. Once dependencies and model files are installed, normal use must work without internet access. Importing an existing local model folder must also be supported.

The desired experience is ChatGPT-style record-then-transcribe, not conversational voice chat. Perfect recognition is an aspiration to evaluate, not a guarantee to advertise.

### Explicit non-goals

No mandatory live transcript, partial-text insertion, rolling transcript corrections, automatic stopping on silence, general voice-command framework, code generation, mandatory LLM rewriting, mobile app, Blint dependency, or App Store distribution work for the first version. Do not silently rewrite meaning to make prose more elegant.

## 2. Primary interaction

1. A configurable global shortcut starts recording from any normal application. Default to hold-to-dictate: key press starts capture and release ends it. Also offer a toggle mode (press once to start, again to stop) in Settings → Shortcuts.
2. Capture the intended destination before displaying app UI, if a destination can be identified.
3. Create a durable history entry and begin saving microphone audio immediately.
4. Display a small non-activating waveform/level overlay with duration and recording status. It must not take focus from the target application. The waveform indicates microphone activity, not live interpretation.
5. Pauses do not stop recording. Release ends hold-mode recording; a second press ends toggle-mode recording. Repeated key-down events must not toggle repeatedly. A release during microphone preparation must prevent delayed recording after the key is no longer held. Menu Record/Stop remains available in either mode.
6. Finalise the saved recording and transcribe it locally. Show processing status, not provisional transcript text.
7. Save the completed recognition result before attempting insertion.
8. Insert only when the captured destination is still suitable and the delivery policy permits it. Otherwise keep the result pending.
9. A separate configurable shortcut inserts the latest pending result into a field the user deliberately selected.
10. Show the completed text in a small, non-activating floating card with a quick copy action and explicit delivery outcome, even after successful insertion. Hide it automatically 30 seconds after completion; allow manual reopening for another 30 seconds. Do not automatically display old text at launch. Keep the delivery explanation after copying and in Recent. Recent dictation remains recoverable regardless of delivery outcome, within the selected retention limit.

The floating panel defaults to the top centre of the screen. A visible drag handle lets the user reposition it without taking focus from the destination. Remember its position across recordings and app launches; recover to a visible screen if the saved display is disconnected.

The menu-bar menu should expose Record/Stop, Insert Pending, History, Settings, model status, and Quit. A model load or inference job must not block the main thread.

For the first version, one recording/transcription job at a time is acceptable. Repeated shortcut presses during loading or recognition must not create duplicate jobs. Make the busy state explicit.

Cancellation must distinguish stopping a recording while keeping its audio, cancelling inference while preserving its input, and explicitly deleting an entry. Escape/cancel must not silently discard a multi-minute recording.

## 3. Recognition engine

### Initial choice

Use Qwen3-ASR-1.7B via an Apple Silicon-native Swift/MLX execution path. Existing source uses MLX Audio Swift. This is a starting choice, subject to evaluation on the user's recordings—not a declaration that it outperforms every alternative.

The current manifest pins MLX Audio Swift 0.1.5 and MLX Swift 0.32.3, with a resolved dependency graph. Native compilation and the packaged Metal smoke check have been verified; model inference and speech accuracy remain separate acceptance checks. See `Documentation/VALIDATION.md` for evidence. Keep dependency APIs, local-only loading, licensing, and packaged resources verified when changing the engine.

Keep the model loaded between requests when practical. Provide explicit load/unload controls and visible state. Loading failure must not delete a recording or prevent access to history.

Put inference behind a replaceable engine boundary. Prefer a long-lived helper process so recogniser crashes can be recovered from without losing the recording app. Do not build multi-engine transcript merging or a mandatory second model into the first version. Future engines should fit the boundary without changing persistence or delivery rules.

### Whole-recording processing and completeness

Ordinary several-minute dictations should be transcribed as completed recordings with as much context as the verified runtime supports. Do not implement live streaming merely because a library offers it.

Internal offline batching is permitted only where a verified model/runtime limit requires it. It must be invisible to the normal recording interaction. Account for every sample, choose boundaries carefully, and test omissions/duplication around joins. A sample-coverage test alone does not demonstrate word-level completeness.

Never silently truncate input to a duration cap or output to a fixed short token budget. Detect and surface known token-budget exhaustion, empty output, malformed output, processing failures, and incomplete batch execution. Retain audio and allow retry. A warning must prevent automatic insertion until reviewed. Absence of a warning does not prove the recogniser captured every word.

Use deterministic/conservative decoding initially. Record the actual model identity/revision, vocabulary context, language, processing duration, warnings, and inference settings relevant to reproducibility.

Do not fabricate confidence scores. If calibrated confidence is unavailable, display observable processing warnings instead.

## 4. Broad project context and coding disambiguation

### Required recognition context

Use two complementary sources of context for every recording:

1. **Personal project names.** Automatically discover the names of all the user's projects from a configurable repositories folder, defaulting to `~/repos`. Use root manifests such as `package.json`, concise project titles, and folder names to identify human-facing names. Preserve intended spelling and capitalization, such as Blint and BuildIQ. Combine duplicate worktrees and avoid version/branch/internal-target aliases overwhelming the useful names. All projects are available together; do not require switching profiles or manually listing each project.
2. **A small curated coding vocabulary.** Maintain a shared list of ambiguous or commonly misrecognized coding terms, plus focused language/project-type lists where useful. For example, JSON should be available as the intended technical term when the user discusses a JSON document, rather than repeatedly becoming “Jason.” Detect broad project types such as TypeScript and Swift from lightweight metadata and enable relevant curated terms across the user's projects. The term lists may be manually curated in the app's source; users should not have to author a glossary of coding concepts.

A term earns its place by helping recognition of the user's high-level speech, not simply by appearing in a repository. Choose the initial lists conservatively and revise them from observed errors and comparative recordings. Project-type detection is a way to select useful disambiguation hints, not a reason to collect all dependencies or language APIs.

### Boundaries and behavior

Do not index classes, functions, internal package/target names, source symbols, or dependency inventories to construct a rich codebase knowledge system. This app primarily captures specifications and documentation for coding agents, not line-by-line code dictation. Broad project names and coding context are sufficient for the intended workflow.

Supply context to the recognizer during recognition. It is analogous to personal names informing spellcheck, not a deterministic find-and-replace dictionary. Do not universally replace “blink” with “Blint” or “Jason” with “JSON”; ordinary language and real people's names must remain possible. Do not claim context guarantees correct output or constitutes model training.

Keep the settings simple: repositories folder, scan status, the recognized project names, a concise explanation of coding disambiguation, and optional corrections/extra spellings. Scanning and useful coding defaults should work without mandatory per-project setup. Do not expose a sprawling inventory of technical concepts as a required configuration task.

Refresh locally, cache results, and never execute repository code. Retain the last usable context on scan failure, make material scan problems visible, and never silently drop terms to satisfy a context limit. Preserve the exact context used for each recording; using updated context for a retry is explicit.

### Recognition examples to validate

- “In Blint, let the agent save the specification as a JSON document.” Preserve **Blint** and **JSON**.
- “This project uses TypeScript; the companion Mac app uses Swift.” Preserve the language names without requiring the user to configure them manually.
- “Ask Jason to review the document.” Preserve the person's name; coding hints must not force JSON.
- “Do not delete the existing file; add the new behavior only after confirmation.” Preserve negation, sequencing, and constraints faithfully.

These are evaluation examples, not replacement rules or a promise of perfect transcription.

## 5. Recent dictation: a small recovery buffer

The purpose is to recover the last piece of dictated content when focus was wrong, insertion failed, or the user needs to copy it again. It is **not** a permanent chronological record of everything spoken. This supersedes the previous indefinite-history requirement.

Default to keeping the latest entry. At the top of Recent, provide a simple count-or-time control: keep the last N entries or keep entries for N minutes (five minutes is the initial value when switching to time mode). Expiry deletes audio and transcript metadata together, including delivered and pending results. Clearly disclose automatic deletion. Count mode may keep the previous usable transcript alongside a newer failed attempt, so a failure cannot displace the last recoverable text. Protect active recording/inference; apply cleanup at launch, after operations, after retention changes, and periodically while idle. Time retention starts when the result becomes available, so long dictations still have a recovery window. Copying must not restart that window.

Persist recovery metadata before capture and write audio incrementally on a bounded writer queue. Keep recognition and delivery states separate. Save completed text before insertion. Recover interrupted work on launch; isolate unreadable metadata and report it rather than blindly deleting unknown files. Retain audio for retry within the recovery policy. A process crash must not turn a failed paste into lost content.

The floating card belongs in a screen corner, remains available while the result is retained, and offers Copy and Recent without taking focus from the destination. Users may dismiss and reopen it. A persistent latest result does not require a live transcript. Show waveform/duration while recording and a processing state while analyzing the completed recording. Real-time text is optional future work only if it can be added without sacrificing quality or distracting from the main workflow.

Recent should open on the latest usable result and support copying, explicit staging for insertion, editing, replay/export, retry, and deletion. Older recordings are not needed as an archive. Keep the context and raw recognition attempt with each retained entry for reproducibility, without collecting unrelated target-field content.

Store recovery data in local Application Support with restrictive permissions, outside Git. Cleanup removes app-managed files, not copies already placed on the clipboard, pasted elsewhere, exported, or captured in OS backups. Do not promise encryption beyond actual OS/app protections.

## 6. Destination and insertion safety

Use macOS Accessibility to inspect the focused element when available. Keep the captured element identity/window/application and enough transient information to detect a changed destination or selection. Do not log or persist the contents of unrelated target fields.

For automatic insertion, require a suitable editable destination and a conservative focus check. If focus changed during recording/processing, the target disappeared, the selection moved, or identification is uncertain, leave the transcript pending. Switching away and back should not silently reset the caution state.

Recheck immediately before delivery. Insert at the selection/caret where supported; do not replace the whole field merely because its value is writable.

Where direct selected-text insertion is not reliable, permit an explicitly enabled paste fallback. Explain that it uses the system clipboard. Avoid time-based clipboard restoration that can race a delayed paste. Distinguish a dispatched paste request from confirmed insertion. Do not automatically retry a mutation with a different delivery method when the first could have partially succeeded.

Never automatically deliver into a future field merely because it becomes focused. Pending text requires a deliberate insertion action. Unknown or incompatible targets should not prevent recording or transcription; manual copy is the fallback.

Exclude recognised secure/password fields. Treat uncertain focus conservatively; Accessibility cannot be assumed to identify every custom secure surface. Terminal-style destinations are disabled by default and require explicit opt-in. Never synthesise Return/Enter to submit a message or execute a command. Include embedded editor terminals in the manual safety review rather than relying only on application bundle IDs.

Compatibility must be tested in the user's applications, particularly Blint, code editors, browser text areas, and native macOS text fields. Do not advertise universal compatibility without evidence.

## 7. Native architecture and packaging

Use SwiftUI for settings/history and AppKit for application lifecycle, menu-bar integration, window behaviour, and a non-activating overlay. Use AVFoundation audio capture and appropriate resampling for the recogniser.

Suggested boundaries, matching the existing source:

- `DictationCore`: models, durable storage, vocabulary, audio utilities, delivery policy, and worker protocol; platform-independent tests.
- `LocalDictation`: native UI, controller, microphone capture, shortcuts, permissions, model installation, Accessibility/paste delivery, and helper client.
- `DictationWorker`: local model loading, decoding, and structured responses.

A worker failure/cancellation must resolve pending requests and leave the application usable. Prevent stale worker responses from modifying a newer job. Capture actionable worker diagnostics without logging private transcript/audio content. Keep machine-readable IPC separate from model/library diagnostic output.

Build a real `.app` with a stable bundle identifier, microphone usage description, the worker executable, and required MLX/Metal resources. Do not assume `swift run` represents the installed application environment. Provide a documented local build/install workflow without requiring a paid distribution account; validate the signing approach and permissions on the actual Mac.

The exact minimum macOS/toolchain version must follow verified dependency requirements, not an untested manifest assertion. Request microphone and Accessibility permissions with clear explanations. Missing Accessibility should still permit recording, recognition, and manual copy. Never request permissions unrelated to the implemented features.

## 8. Validation and acceptance

### Automated tests

Cover vocabulary merging/limits, durable settings/history, recovery after interrupted jobs, original-transcript preservation, retry history, safe deletion/export, count/time retention, active-work protection, recent-card copy/reopen, sample coverage, token-budget warnings, cancellation behaviour, focus changes, unknown/secure fields, terminal policy, and shortcut validation. Add macOS-specific integration coverage where practical.

Existing Linux tests only exercise `DictationCore`; they are not evidence that AppKit, audio hardware, MLX inference, or paste delivery works.

### Required end-to-end checks on macOS

1. Build and launch the packaged Apple Silicon app and its worker.
2. Grant permissions and record using the global shortcut without activating the overlay.
3. Transcribe a short recording and a several-minute recording, verifying the final sentence is present.
4. Compare the same representative speech with and without project-name and curated coding context. Include Blint, JSON/Jason, TypeScript, Swift, ordinary language, and names that must not be forced into coding terms.
5. Change focus or remove the destination during capture/processing; confirm no unintended insertion and full recovery from history.
6. Run with no active input field; explicitly insert the retained result later.
7. Force-quit during recording, terminate the worker during inference, restart, and recover/retry the available audio.
8. Deny/revoke permissions; disconnect the microphone; simulate disk-full and model-load failures.
9. Test native fields, browser fields, Blint, editors, clipboard fallback, secure inputs, and terminal restrictions.
10. Disable networking after model installation and verify recording, transcription, history, and insertion still work.

### Accuracy evaluation

Build a personal set of approximately 30–50 recordings containing normal explanations, pauses, corrections, acronyms, project names, filenames, numbers, negations, and longer utterances. Use separate held-out examples when tuning vocabulary. Keep private recordings out of source control.

Use high-level specifications and documentation as the main evaluation material, rather than dependency lists or source-code symbol recitation. Compare against default macOS dictation using the same speech and input conditions where feasible, with the same reference text and scoring criteria. Record any differences in capture conditions.

Measure correction effort, recurring project-name errors (especially Blint), coding-term disambiguation, omissions/additions, punctuation, and preservation of numbers, negations, constraints, and the final sentence. Include ordinary-word/person-name examples to detect over-biasing. Evaluate project-name hints and curated coding hints separately and together.

The quality target is lower correction effort and fewer important meaning/name errors than default macOS dictation on this workload, without introducing systematic replacements. Report actual results and failure cases; passing unit tests or loading a model does not establish this. Latency and memory are secondary observations, not substitutes for quality. Do not select solely from model size or published aggregate benchmarks. A comparison engine can be added later if real results justify it.

## 9. Delivery order and definition of done

Continue in this order: inspect the handoff; resolve/build on macOS; complete application lifecycle and packaging; prove recording/recovery; verify local inference and context forwarding; verify UI/hotkeys; exercise safe delivery; run the accuracy and failure tests; document actual results and commit.

A usable first version is a locally buildable and launchable app that records by shortcut, processes the complete saved recording locally, uses project names and targeted coding disambiguation, preserves recent recoverable content, and safely inserts or retains the result. A collection of uncompiled native source files does not meet this definition.

The product quality goal is not complete until representative speech demonstrates an improvement over default macOS dictation for the intended workflow, and delivery in Blint has been exercised. A runnable app is an engineering milestone, not evidence of that quality.

Document remaining limitations and failed checks plainly. Report actual file locations and actual commands/tests run. Do not claim successful model inference, application compilation, microphone capture, or system-wide insertion without having performed and checked them.
