#!/usr/bin/env python3
"""Synthetic speech integration check, not a human accuracy benchmark.
Uses macOS say, local model weights, and the packaged worker; no audio is uploaded.
"""
import argparse
import array
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import wave

ROOT = Path(__file__).resolve().parent.parent
CASES = [
    ("project_and_json", "In Blint, let the agent save the specification as a JSON document. Do not delete the existing file.", ["Blint", "JSON", "Do not delete"]),
    ("person_name", "Ask Jason to review the document before we send it to the client.", ["Jason"]),
    ("languages", "The main project uses TypeScript. The companion Mac app uses Swift. Keep the user interface simple.", ["TypeScript", "Swift"]),
    ("project_names", "For BuildIQ and Locum Motion, document the requirements before starting implementation.", ["BuildIQ", "Locum Motion"]),
    ("constraints", "Do not remove the existing records. Keep the last five entries for recovery. Only save changes after confirmation.", ["Do not remove", "five", "after confirmation"]),
    ("ordinary_words", "The cursor should blink while the user types. Jason will review the final document tomorrow.", ["blink", "Jason"]),
]
LONG = " ".join([
    "I want to describe the new recovery workflow for Blint. The goal is to make specifications easier to dictate without losing the user's original meaning.",
    "Start by saving the complete recording locally. Do not insert partial text while the person is still speaking. Pauses must not finish the recording automatically.",
    "When the recording ends, process it as a whole. Keep the project name and the coding vocabulary available as recognition hints. A JSON document is a technical document, while Jason is a person who might review it.",
    "The main application uses TypeScript and the native companion uses Swift. We are discussing the behavior of these projects, not the names of every function inside them.",
    "If the selected text field changes, retain the result instead of pasting into an unexpected place. Show the last completed message in a small card with a copy button.",
    "Keep only a small recovery buffer. The user can choose the last few entries or a short time limit. Do not create an indefinite archive of everything spoken.",
    "The settings screen should be easy to understand. Explain what each choice changes, preserve the user's existing preferences, and avoid unnecessary controls.",
    "Please document the acceptance criteria before implementation. Quality matters more than speed, memory usage, or live feedback. It is acceptable to wait a little longer for an accurate complete result.",
    "We should test mistakes involving project names and ordinary words. Ask Jason to review the result. A cursor may blink, and that should not be replaced with a project name.",
    "Finally, preserve this last instruction exactly in meaning: do not delete the existing file. The final sentence is the recovery check is complete."
])


def words(text):
    return re.findall(r"[\w']+", text.lower())


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        new = [i]
        for j, y in enumerate(b, 1):
            new.append(min(new[-1] + 1, row[j] + 1, row[j - 1] + (x != y)))
        row = new
    return row[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--voice", action="append", default=[])
    parser.add_argument("--include-long", action="store_true")
    parser.add_argument("--deny-network", action="store_true", help="Deny all worker networking with the macOS process sandbox")
    parser.add_argument("--mode", action="append", choices=["without_context", "project_names_only", "app_context"])
    args = parser.parse_args()
    settings = json.loads((Path.home() / "Library/Application Support/LocalDictation/settings.json").read_text())
    model = args.model or Path(settings.get("modelDirectory", ""))
    if not (model / "config.json").exists():
        parser.error("Download or select the model in the app first.")
    app = ROOT / "build/Brief.app/Contents/MacOS"
    context = subprocess.check_output([str(app / "Brief"), "--recognition-context"], text=True).strip()
    report = {"kind": "synthetic integration check", "model_directory": str(model), "context": context,
              "voices": args.voice or ["Karen", "Samantha"], "worker_network_denied": args.deny_network, "results": [],
              "limitations": "Synthetic TTS only. Not a macOS dictation comparison, microphone test, or measure of the user's voice."}
    names = []
    seen = set()
    for project in settings.get("repositoryVocabulary", {}).get("projects", []):
        for name in project["names"]:
            if name.lower() not in seen:
                seen.add(name.lower()); names.append(name)
    contexts = {"without_context": "", "project_names_only": ", ".join(names), "app_context": context}
    cases = CASES + ([("long_specification", LONG, ["Blint", "JSON", "Jason", "TypeScript", "Swift", "recovery check is complete"])] if args.include_long else [])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    def save():
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    with tempfile.TemporaryDirectory(prefix="dictation-synthetic-") as temp:
        diagnostic = open(Path(temp) / "worker.stderr", "w+")
        command = [str(app / "DictationWorker")]
        if args.deny_network:
            command = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)"] + command
        proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=diagnostic, text=True, bufsize=1,
                                env={**os.environ, "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1"})
        lines = queue.Queue()
        def reader():
            for line in proc.stdout:
                if line.startswith("LOCALDICTATION:"):
                    lines.put(json.loads(line.removeprefix("LOCALDICTATION:")))
            lines.put(None)
        threading.Thread(target=reader, daemon=True).start()
        try:
            for voice in report["voices"]:
                for name, reference, expected in cases:
                    wav = Path(temp) / "speech.wav"
                    pcm = Path(temp) / "speech.f32le"
                    subprocess.run(["say", "-v", voice, "-r", "155", "-o", str(wav), "--file-format=WAVE", "--data-format=LEI16@22050", reference], check=True)
                    with wave.open(str(wav)) as audio:
                        assert audio.getnchannels() == 1 and audio.getsampwidth() == 2
                        rate = audio.getframerate()
                        samples = array.array("h", audio.readframes(audio.getnframes()))
                    floats = array.array("f", (x / 32768.0 for x in samples))
                    pcm.write_bytes(floats.tobytes())
                    for label in args.mode or ["without_context", "project_names_only", "app_context"]:
                        hint = contexts[label]
                        req_id = str(uuid.uuid4()).upper()
                        request = dict(id=req_id, operation="transcribe", modelDirectory=str(model), audioPath=str(pcm),
                                       sampleRate=rate, context=hint, language="English", tokenBudgetMultiplier=1)
                        start = time.monotonic()
                        proc.stdin.write(json.dumps(request) + "\n"); proc.stdin.flush()
                        response = lines.get(timeout=900)
                        if response is None:
                            diagnostic.seek(0)
                            raise RuntimeError("Worker exited: " + diagnostic.read()[-4000:])
                        assert response["id"].upper() == req_id
                        if not response["success"]:
                            raise RuntimeError(response.get("message", "Inference failed"))
                        attempt = response["attempt"]
                        text = attempt["text"]
                        result = dict(case=name, voice=voice, mode=label, reference=reference, transcript=text,
                                      expected_terms={term: term in text for term in expected},
                                      word_error_rate=distance(words(reference), words(text)) / max(1, len(words(reference))),
                                      elapsed_seconds=time.monotonic() - start, attempt=attempt)
                        report["results"].append(result); save()
                        print(json.dumps({k: result[k] for k in ["case", "voice", "mode", "transcript", "expected_terms", "word_error_rate", "elapsed_seconds"]}), flush=True)
        finally:
            proc.terminate()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait()
            diagnostic.close()
    save()

if __name__ == "__main__":
    main()
