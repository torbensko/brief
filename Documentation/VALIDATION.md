# macOS validation — 19 October 2026

## Current state

The project builds a signed, launchable Apple Silicon menu-bar app. The model is now installed and native loading plus offline synthetic recognition are verified. OS permissions, real microphone speech, and end-to-end delivery acceptance remain open. The entries below preserve earlier checks chronologically; see the latest recognition evaluation at the end.

Verified on this Mac with Apple Swift 6.4 and Xcode's macOS 27.0 SDK:

- Native app and Qwen/MLX worker compile.
- All 35 core tests pass in four suites: recognition context, safe delivery, durable history, and audio completeness.
- `Scripts/build-app.sh` packages both executables, resource bundles, and Metal shaders. Ad-hoc signature verification passes.
- The packaged worker's `--self-test` performs an MLX GPU computation successfully.
- The packaged worker returns a structured failure with the matching request ID for a missing model directory, without crashing.
- The app launches and opens Settings on first use. General, Model, and Shortcuts controls were inspected in the running UI; History opens from the Window menu and displays its empty state correctly.

## Repairs made

- Added application entry point, menu-bar controls, history/settings window ownership, non-activating overlay, standard editing menus, and orderly asynchronous shutdown.
- Fixed shutdown during microphone preparation so a recording that starts while quitting is finalized and retained.
- Corrected the incompatible MLX pin from 0.30.6 to 0.32.3 to satisfy MLX Audio 0.1.5's resolved MLX LM dependency. Added `Package.resolved`.
- Added Info.plist, microphone usage description, repeatable app packaging/signing and check scripts, and an explicit bundled Metal library lookup.
- Installed Xcode's missing Metal Toolchain on this Mac.
- Initialized Git because the imported folder contained no `.git` directory. Ignored build output and kept private app data outside the repository.

## Remaining acceptance checks

No model weights were installed and no microphone recording was made during this check. Microphone and Accessibility permissions remain for the user to grant. In particular, these checks remain open:

- Download/import model weights, load Qwen, and recognize a real short and long recording, including vocabulary and final-sentence accuracy.
- Confirm physical global recording/history shortcuts; the automated synthetic history chord did not open the window and is not evidence of successful global-hotkey operation.
- Verify audio capture and crash recovery on the actual microphone.
- Verify focus changes, secure inputs, terminal restrictions, clipboard fallback, and insertion in the intended applications.
- Confirm inference works with networking disabled after model setup.
- Exercise permission denial, microphone disconnect, disk-full conditions, and worker cancellation during real inference.

The deployment target is macOS 14, but execution on older macOS versions has not been tested. Upstream build warnings remain (Metal C++ extension diagnostics and a Swift build resource-bundle warning); they did not prevent compilation or the packaged GPU check. The older Linux results and historical handoff are retained separately.

## Automatic coding vocabulary update — 19 October 2026

Replaced the manual active-profile workflow with shared vocabulary from all repositories. The app scans `~/repos` at startup, caches results, adds built-in coding terms and detected technology terms, and offers a simplified Coding settings tab with optional extra spellings.

Verified 41 tests across five suites, including nested package discovery, stack detection, ignored dependency/hidden/symlink folders, malformed metadata, legacy settings compatibility, cache persistence, and an opt-in scan of this Mac's repos folder. That scan found 38 repository folders and 168 distinct names in about six seconds, with no scan notes. Combined recognition context was 4,404 bytes, below the existing 16 KB limit. Private scan contents remain in Application Support, outside Git.

The rebuilt app's Coding screen was visually inspected and showed 38 repositories, 168 names, and 35 technology terms. The saved catalog was verified on disk. App signature verification and the packaged Metal worker self-test passed again. Speech accuracy with the expanded context still requires a model and real recording, as noted above.

## Project-name-only correction — 19 October 2026

Supersedes the broad vocabulary update above. Removed built-in coding concepts, dependency/framework extraction, recursive package indexing, and technology UI. The scanner now extracts one main name per root project and deduplicates Git worktrees and names. Earlier broad caches are excluded pending refresh; explicit custom spellings remain supported.

Verified 43 tests, including dependency/internal-package exclusion, worktree deduplication, version suffix cleanup, old-cache exclusion, and the actual repos scan. The result is 17 project names and 230 bytes of context, including the exact spelling Blint. The signed app was rebuilt, restarted, and its Project names tab verified to show the saved dictionary. Recognition accuracy still requires an installed model and actual speech testing.

## Coding context and recent recovery — 19 October 2026

Implemented the combined product intent: project-name hints plus small, manually curated coding-disambiguation lists selected by broad project types. Detection inspects shallow filenames/manifests and skips generated/dependency folders; it does not import dependency or symbol inventories. The actual repos scan still yields 17 distinct project names; combined context is 506 bytes.

Replaced indefinite retention with a recent recovery policy. Default: latest entry; count and minutes (initially five) controls are at the top of Recent. Expiry removes both audio and metadata. Active processing suspends cleanup. Count mode additionally protects the last usable transcript when a newer attempt fails. Time expiry is measured from the result's availability, and copying does not renew it. Cleanup runs at startup, after idle updates, on policy changes, and every ten seconds while idle.

The bottom-left non-activating card shows microphone levels while recording, processing status after stopping, and the latest retained transcript with Copy last text and Recent after recognition. Successful insertion does not dismiss the result. The user can dismiss it and reopen it from the menu bar.

Verification:

- 51 tests pass in seven suites, including removal of audio and metadata, count/time expiry, active protection, long recordings receiving a recovery window, failed-attempt protection, settings compatibility, and focused coding context/type detection.
- Packaged app builds, signature verification passes, and packaged MLX Metal self-test passes.
- Isolated UI preview verified Recent layout, count-to-five-minute selection, opening Recent from the floating card, and one-click copying with visible confirmation. The preview uses a temporary store and a clearly identified sample transcript, not actual speech recognition; its files are removed on exit.
- UI preview can be repeated with `open build/LocalDictation.app --args --preview-recovery` after quitting the normal app. `--preview-card` opens just the recovery card. Do not grant permissions or record in the preview; it is for layout checks.

Still outstanding: model installation and real inference, microphone waveform/capture on physical hardware, comparison with macOS dictation, and focus/insertion tests in Blint. Model download approval was requested for an inference test; no model weights were downloaded during these checks. Passing these tests does not establish speech accuracy.

## Installed model and offline recognition — 19 October 2026

Following explicit user authorization, downloaded the approximately 4.08 GB Qwen3-ASR-1.7B BF16 weights through the native installer and verified successful model loading. This supersedes the missing-model/inference status in earlier entries.

The packaged worker completed 42 synthetic transcriptions with networking denied by the macOS process sandbox. With complete app context, all 14 samples matched their reference words after case/punctuation normalization; no key terms were missing. Without context, three samples missed project names. Both approximately 100-second specifications retained their final sentence, and all 42 responses had no warnings. See [RECOGNITION-EVALUATION.md](RECOGNITION-EVALUATION.md) for the comparison, method, limitations, and repeatable command.

Added a synthetic evaluation script and a headless option to read the app's exact saved recognition context. Rebuilt/signed the app and checked Python syntax. No recognition-engine changes were needed. The existing 51-test core result remains applicable. Real user speech, macOS comparison, permissions, physical microphone/shortcut checks, and focus/insertion in Blint remain open.

## Hold-to-dictate and movable panel — 19 October 2026

Added hold-to-dictate as the default, with toggle mode selectable in Shortcuts. Global hotkeys now handle press and release, suppress repeat presses, and track ownership so releases from ignored/busy presses cannot affect another recording. Releasing during permission/storage preparation cancels the pending start. Menu Record/Stop remains available.

The panel defaults to top centre, has a visible drag handle, remembers its frame across launches, and returns to a visible screen when its saved display is unavailable. The drag handle leaves action buttons independently clickable and the panel remains non-activating.

Verification: 57 tests pass across eight suites, including hold/release, preparation cancellation, ignored busy presses, menu-stop-before-release, toggle repeat suppression, and legacy settings/default persistence. App packaging/signing and the Metal self-test pass. Inspected the updated card and Shortcuts UI in isolated preview; dragged the handle and confirmed a saved window frame. Physical held-key capture and end-to-end insertion still require a live session. The insertion path remains automatic by default, gated on Accessibility access and the original field remaining suitable/unchanged; it does not submit the text.

## Diagnosed missing insertion access — 19 October 2026

Investigated the user's failed GPT-field delivery. The running app showed Microphone enabled but Accessibility permission needed for insertion. Automatic insertion and clipboard fallback were both enabled. The latest successful recognition had no warnings and no captured target application, consistent with the permission gate preventing target capture. No evidence yet establishes an editor-specific insertion failure.

Added a persistent Accessibility-blocked notice and Enable insertion action to the result panel and General settings. It remains visible after Copy updates the transient status, and checks permission changes every two seconds. Visually verified the notice on the user's actual retained result and navigation to setup.

The previous ad-hoc signing changed the app identity across rebuilds, causing microphone permission to become unavailable after the rebuild as well. The build now uses a unique installed Apple Development identity when available, with explicit SIGNING_IDENTITY override and an announced ad-hoc fallback. This Mac's signed build passed verification and has a certificate-based designated requirement rather than a binary hash. Permission grants for this new identity still require user authorization.

The 10 safe-delivery tests pass, including the missing-Accessibility gate. App build and signature verification pass. End-to-end GPT-field insertion remains pending the Accessibility grant; do not present compilation or the permission diagnosis as a successful live paste.

## Accessibility grant repaired — 19 October 2026

With explicit user authorization, refreshed the macOS permission. The system toggle was on while the app still reported no access. Toggling alone did not resolve the mismatch. Removed the stale LocalDictation entry and re-added the current signed build from build/LocalDictation.app. The running app then visibly reported both Accessibility enabled and Microphone enabled, and the blocked-insertion notice disappeared.

An attempted unsent insertion check in the GPT composer was blocked because Computer Use disallows controlling com.openai.codex. No message was sent and no automated GPT-field insertion result is claimed. The user can now retry with permissions actually recognized by the app.

## Editor delivery and temporary result panel — 19 October 2026

The user's latest failed delivery had ChatGPT recorded as its target, a ready transcript, and automatic insertion/paste enabled. The old transient failure message had been replaced by Copy, so its precise rejection reason was not recoverable. Do not claim a proven root cause beyond these observations.

Removed the requirement that a recognized, enabled, non-secure text editor expose AXSelectedTextRange; several web editors omit this attribute. Known focus/selection/value changes still prevent automatic delivery, and unknown/read-only/secure fields remain blocked. Standard paste is now chosen first when enabled; direct Accessibility insertion is available when paste is disabled. There is no retry after a mutation, preventing duplicate insertion.

Persist a separate delivery explanation on the session, displayed on the result card and in Recent. Copy no longer erases it. Messages distinguish blocked delivery from a paste request, without claiming the receiving app actually accepted the paste.

The result panel now dismisses after 30 seconds even when a transcript exists; reopening starts a fresh timeout. Old text is not shown automatically at launch. Recording and processing remain visible. The isolated preview was visible initially and no window could be inspected after the timeout (the UI inspector timed out); this is consistent with hiding, but not a precise timing measurement. Normal app reopened afterwards.

60 tests pass in nine suites, including recognized text editors, blocked unsafe targets, and delivery-explanation persistence after copying. Packaging/signature checks and the MLX self-test pass. Actual insertion into GPT remains unverified because computer-use access to that app is prohibited; the next user attempt now supplies a durable delivery explanation.

## Brief v1 publishing preparation — 19 October 2026

Renamed the displayed app and executable to Brief while retaining the existing bundle identifier and Application Support location. Added a full-bleed blue icon master and derived ICNS sizes, with no border or outer corner mask. VERSION is 1.0.0.

Added GitHub CI and a signing/notarisation release workflow based on Safari Profile Studio. The five signing secrets use the same names. Distribution is Apple Silicon only. Public signed releases remain gated until the owner configures signing and either dispatches the workflow or enables VERSION-triggered releases.

Local verification: 60 tests pass; release build completes; DMG checksum verification and ZIP integrity checks pass; the release worker passes the MLX Metal self-test. The renamed executable reads the existing saved context successfully. Restored the local development signature after producing the explicitly unsigned preview archives. GitHub's first clean-runner test step also passed; packaging was still running when this note was written.

Published source at https://github.com/torbensko/brief and the website entry at https://torbensko.com/software/brief/. Both the website build and visual review passed. The live page was verified after deployment. It links to source and Releases without advertising an unavailable DMG.
