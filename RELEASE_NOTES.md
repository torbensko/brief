# Brief 1.2.1

- Fixed a communication stall between the speech and cleanup helpers that could leave Brief waiting for a completed edit.
- The floating dictation panel labels tidied wording and shows edits by default for every new result.
- Wording cleanup can add at most three seconds before Brief uses the original transcription.
- **Use original now** skips cleanup immediately and continues normal delivery.
- Long dictations bypass cleanup without loading the editing model.
- Late or incomplete cleanup output never replaces text that has already been delivered.
