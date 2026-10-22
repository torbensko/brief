# Wording cleanup evaluation

Checked on 23 October 2026, on the development Apple Silicon Mac. These are synthetic text checks, not a claim of perfect meaning preservation or a substitute for real messaging use.

## Configuration

- Local `mlx-community/Qwen3-4B-Instruct-2507-4bit`, revision `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`.
- Temperature zero; independent editor and meaning-review contexts.
- Structural checks reject changed quantities, coding literals, recognition terms, qualifiers, excessive edits and meaningful emphasis/politeness.
- Intensifier removal is deliberately narrow: conversational forms such as “really good to”. This sacrifices some tidying to avoid weakening urgency.
- Original recognition is persisted before cleanup. The 60-second timeout/failure path keeps it; explicit cancellation prevents delivery.

## Results

All 14 synthetic cases in `Tests/Fixtures/cleanup.json` passed the final checks. Clear stutters were removed; uncertain claims, project terms, numbers and unclear content were retained. Some cases pass by rejecting a model proposal and returning the entire original, including any filler. Short cases took approximately 1.4–2.8 seconds including model loading on this Mac; longer text and other hardware will differ.

During development, model-only editing weakened emphasis (“I really mean it”) and changed a legitimate repetition (“that that file”). A second model review did not catch every emphasis loss. The additional deterministic emphasis checks are therefore necessary, and neither layer proves semantic equivalence. Several fixtures informed those refinements; these are regression checks, not an independent quality benchmark.

71 core tests passed, including persistence, retry clearing old cleanup, defaults, text selection precedence, rejection rules, and reconstruction of both original and revised strings from the displayed diff. UI checks verified struck-through removals, switching to clean text, and restoring the original into the Recent editor using an isolated synthetic preview.

## Repeat

```sh
Scripts/build-app.sh
python3 Scripts/evaluate-cleanup.py --model /path/to/installed/cleanup-model
swift test
```

The evaluation uses the packaged worker and local weights, never a microphone or saved personal transcripts. Real-world usage should particularly assess missed qualifiers, deliberate repetitions, regional phrasing, ambiguous content, and unnecessary edits. Non-English cleanup has not been evaluated.
