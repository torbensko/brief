# Local recognition evaluation — 19 October 2026

The installed model successfully recognized synthetic specifications using the packaged app worker with all worker networking denied by the macOS process sandbox. This checks the actual local inference path and vocabulary hints; it does not establish superiority over macOS dictation or accuracy on the user's voice.

## Setup

- Downloaded and checksum-verified through the app: `mlx-community/Qwen3-ASR-1.7B-bf16`, revision `e1f6c266914abc5a46e8756e02580f834a6cf8a7` (approximately 4.08 GB of weights).
- Confirmed successful model loading in the native app.
- Two macOS synthetic voices: Karen (Australian English) and Samantha (US English), at 155 words per minute.
- Seven passages per voice: project names, JSON/person-name contrast, languages, negative constraints, ordinary words, and a 276-word specification lasting approximately 99–102 seconds.
- Each of the 14 samples was recognized with no context, project names alone, and the app's complete 506-byte context: 42 transcriptions total. The complete context includes 17 project names and a small curated coding vocabulary selected by detected project types.
- Used production worker decoding settings and complete recordings, without microphone capture. Temporary synthetic audio was deleted after the run and never entered the app's recovery buffer.

## Results

Word error rate below is total word edits divided by the 734 reference words per condition, ignoring case and punctuation. Key-term checks additionally require the expected spelling/case.

| Recognition context | Word errors | Word error rate | Samples missing a key term |
| --- | ---: | ---: | ---: |
| None | 12 / 734 | 1.63% | 3 / 14 |
| Project names only | 2 / 734 | 0.27% | 0 / 14 |
| Complete app context | 0 / 734 | 0% | 0 / 14 |

Concrete observations:

- Samantha's “In Blint…” became “In Blend…” without context and “In Blint…” with either vocabulary condition.
- Both voices' “BuildIQ and Locum Motion” became “build IQ and locomotion” without context. Both vocabulary conditions preserved the project names.
- JSON, TypeScript, and Swift were already recognized correctly without hints in these samples. Jason and the ordinary verb “blink” remained intact with hints; no blind word replacement occurred.
- In Karen's long specification, no context and project names alone produced “re-change the result” for “retain the result.” The full context preserved the reference words. This small result does not isolate a general benefit from any individual coding term.
- Both long specifications preserved the final recovery-check sentence. All 42 responses completed without worker warnings. There were punctuation differences, which the word score does not assess.

The evidence supports using project-name hints. The coding vocabulary remains part of the product intent, but its benefit needs broader human-speech testing, especially genuinely ambiguous technical utterances. Perfect normalized scores on these clear synthetic samples are not a general accuracy claim.

## Repeat the check

After downloading a model and scanning repositories in the app, quit the app to avoid loading two model workers, then run:

```sh
Scripts/build-app.sh
python3 Scripts/evaluate-recognition.py --include-long --deny-network --output .build/synthetic-recognition-offline.json
```

The script reads the configured model and exact saved recognition context through the app's headless `--recognition-context` option. `--voice` and `--mode` can restrict a run. Expected project spellings in the sample passages are specific to this workflow; other users should adapt them to names in their dictionary.

Raw reports stay under ignored `.build/`: they contain local paths and the complete private project dictionary. The script writes incremental results and fails on worker errors; accuracy differences are reported rather than treated as execution failures.

## Still to verify

Real microphone speech, pauses/noise/accents, longer recordings beyond this approximately 100-second sample, and a matched comparison against macOS dictation remain untested. Physical shortcuts, permission handling, waveform activity, and delivery/focus recovery in Blint also require an actual end-to-end session. No microphone or Accessibility permission was granted by this evaluation.
