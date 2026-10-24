# Brief 1.2.1

- Fixed a communication stall between the speech and cleanup helpers that could leave Brief waiting for a completed edit.
- The floating dictation panel shows edits by default with a compact Edits on/off control beside History for every new result, plus a single quiet status row with matching copy buttons.
- Wording cleanup can add at most three seconds before Brief uses the original transcription.
- **Use original now** skips cleanup immediately and continues normal delivery.
- Long dictations bypass cleanup without loading the editing model.
- Late or incomplete cleanup output never replaces text that has already been delivered.
