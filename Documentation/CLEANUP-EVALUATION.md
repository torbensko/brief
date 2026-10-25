# Wording cleanup evaluation

Checked on 23 October 2026, on the development Apple Silicon Mac. These are synthetic text checks, not a claim of perfect meaning preservation or a substitute for real messaging use.

## Configuration

- Local `mlx-community/Qwen3-4B-Instruct-2507-4bit`, revision `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`.
- Temperature zero; independent editor and meaning-review contexts.
- Structural checks reject changed quantities, coding literals, recognition terms, qualifiers, excessive edits and meaningful emphasis/politeness.
- Intensifier removal is deliberately narrow: conversational forms such as “really good to”. This sacrifices some tidying to avoid weakening urgency.
- Original recognition is persisted before cleanup. The recording-length-based timeout/failure path keeps it; explicit cancellation prevents delivery.

## Results

The installed signed 1.2.0 build met 13 of the 14 exact output/preservation expectations in `Tests/Fixtures/cleanup.json`; one additional case safely fell back to its unchanged original. The evaluator explicitly accepts and reports that conservative fallback. Clear stutters were removed; uncertain claims, project terms, numbers and unclear content were retained. Some cases pass by rejecting a model proposal and returning the entire original, including any filler. Short cases took approximately 1.4–2.8 seconds in the development build and about 0.8–1.9 seconds in the signed release, including model loading on this Mac; longer text and other hardware will differ.

The final qualifier-count check deliberately leaves “Could we, could we…” unchanged, even though it is likely a stutter. This is a known missed cleanup opportunity, not a claim that every repeat is removed. Revisit it after real-world feedback without weakening negation protection.

During development, model-only editing weakened emphasis (“I really mean it”) and changed a legitimate repetition (“that that file”). A second model review did not catch every emphasis loss. The additional deterministic emphasis checks are therefore necessary, and neither layer proves semantic equivalence. Several fixtures informed those refinements; these are regression checks, not an independent quality benchmark.

73 core tests passed, including persistence, retry clearing old cleanup, defaults, text selection precedence, rejection rules, and reconstruction of both original and revised strings from the displayed diff. UI checks verified struck-through removals, switching to clean text, and restoring the original into the Recent editor using an isolated synthetic preview.

## Repeat

```sh
Scripts/build-app.sh
python3 Scripts/evaluate-cleanup.py --model /path/to/installed/cleanup-model
build/Brief.app/Contents/MacOS/Brief --check-cleanup-latency
swift test
```

The evaluation uses the packaged worker and local weights, never a microphone or saved personal transcripts. Real-world usage should particularly assess missed qualifiers, deliberate repetitions, regional phrasing, ambiguous content, and unnecessary edits. Non-English cleanup has not been evaluated.

## Real-use latency correction (1.2.1)

A real 637-character dictation took about 3.5 seconds to recognize but then spent about 64 seconds waiting for cleanup to time out. The short synthetic cases did not establish acceptable real-use latency. Cleanup now has a three-second delivery budget, bypasses inputs over 1,200 characters, and offers Use original now. Both timeout and skip stop the isolated cleanup worker and deliver the saved original, never partial output. The earlier 1.2.0 timings above describe the model's short-case results, not a latency guarantee.

The app-level integration check reproduced the stall with the recogniser loaded: the old shared async pipe reading timed out after ten seconds even though direct-worker cleanup took 1.55 seconds for 736 characters. Independent per-pipe readiness handlers resolve this contention. The initial development build then returned 184 characters in 2.16 seconds and 736 in 3.13 seconds with the recogniser still loaded. These are measured completions, including conservative unchanged fallbacks, not promises that every input will be edited. The three-second delivery budget still applies. The integration check also covers repeated helper launches, skipping an in-flight edit, restarting cleanup, and a subsequent recogniser request.

A subsequent development-build run restarting the cleanup helper between every request took 3.33, 5.10 and 3.48 seconds for 184, 736 and 184 characters respectively; skip/restart and subsequent speech requests passed. This demonstrates that the transport stall is resolved, while also showing why the delivery deadline remains necessary. The floating panel was visually checked with synthetic removed words: Wording tidied, highlighted strikethroughs, Show edits enabled and Copy original were all present.

The optimized 1.2.1 candidate completed the same cold-helper integration sequence in 1.25, 1.59 and 1.19 seconds. Skip/restart also produced the expected real edit (removing the duplicate “the”), and the subsequent speech request succeeded. The final panel design places Edits on/off beside History and matches Copy text / Copy original in a single footer beside subdued delivery feedback.


## Proportional cleanup budget (1.2.2, 25 October 2026)

Real use showed the 1.2.1 fallback was too aggressive. The actual IPC stall was already fixed, so neither a universal three-second deadline nor a 1,200-character bypass was justified for ordinary longer dictations. Cleanup now receives 10% of the persisted recording duration, with a five-second floor and twenty-second ceiling. Retries use that same saved duration. The input safety limit is restored to 8,000 characters; it is an application resource guard, not the model's advertised context capacity. Use original now and the late-result rejection remain unchanged.

74 core tests pass, including one- and two-minute budgets, the upper cap, malformed durations, and inputs beyond the old short cutoff. The app transport diagnostic now runs 184-, 1,314- and 2,680-character synthetic transcripts (the longer cases contain varied specification paragraphs) with the speech recogniser loaded and a fresh editing helper for each clip. It also checks cancellation and restart. The optimized candidate returned these cases in 1.18, 3.03 and 5.34 seconds respectively, within their 5-, 12- and 20-second budgets. These synthetic cases test latency and transport; they do not establish meaning-preservation accuracy for all long dictations.
