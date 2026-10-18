# macOS validation — 19 October 2026

## Current state

The project builds a signed, launchable Apple Silicon menu-bar app. First-use model installation and OS permissions are still required. Full speech recognition and delivery acceptance are not yet verified.

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
