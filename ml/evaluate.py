#!/usr/bin/env python3
"""Scores a model (optionally with a LoRA adapter) on a dataset split.

Fusion: valid JSON, exact result (including null for invalid pairs), exact suggestions.
Atmosphere: share of words placed in the right zone, and fully exact answers.
Also reports latency per call and generation speed on this Mac.

Example: python3 evaluate.py --split test --limit 200 --adapter adapters/qwen3-0.6b
"""
import argparse
import json
import time
from pathlib import Path

from mlx_lm import generate, load

HERE = Path(__file__).parent


def parse(text):
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end < start:
        return None
    try:
        return json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", default="Qwen/Qwen3-0.6B")
    parser.add_argument("--adapter", default=None)
    parser.add_argument("--split", default="test")
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--name", default=None, help="results/<name>.json")
    args = parser.parse_args()

    model, tokenizer = load(args.model, adapter_path=args.adapter)
    rows = [json.loads(line) for line in open(HERE / "data" / f"{args.split}.jsonl")][: args.limit]
    stats = {"fusao": {"n": 0, "json": 0, "result": 0, "suggestions": 0, "positives": 0, "positives_ok": 0, "negatives": 0, "negatives_ok": 0},
             "atmosfera": {"n": 0, "json": 0, "words": 0, "words_ok": 0, "exact": 0}}
    seconds, tokens, failures = 0.0, 0, []
    for row in rows:
        messages = row["messages"]
        expected = json.loads(messages[-1]["content"])
        prompt = tokenizer.apply_chat_template(messages[:-1], add_generation_prompt=True, enable_thinking=False)
        started = time.perf_counter()
        output = generate(model, tokenizer, prompt=prompt, max_tokens=160)
        seconds += time.perf_counter() - started
        tokens += len(tokenizer.encode(output))
        answer = parse(output)
        task = "fusao" if messages[1]["content"].startswith("fusao") else "atmosfera"
        s = stats[task]
        s["n"] += 1
        s["json"] += answer is not None
        answer = answer or {}
        if task == "fusao":
            positive = expected["resultado"] is not None
            right = "resultado" in answer and answer["resultado"] == expected["resultado"]
            s["result"] += right
            s["suggestions"] += right and (not positive or answer.get("sugestoes") == expected["sugestoes"])
            s["positives" if positive else "negatives"] += 1
            s["positives_ok" if positive else "negatives_ok"] += right
            ok = right
        else:
            truth = {w: z for z, ws in expected.items() for w in ws}
            guess = {w: z for z, ws in answer.items() if isinstance(ws, list) for w in ws}
            s["words"] += len(truth)
            s["words_ok"] += sum(guess.get(w) == z for w, z in truth.items())
            ok = all(guess.get(w) == z for w, z in truth.items()) and len(guess) == len(truth)
            s["exact"] += ok
        if not ok and len(failures) < 8:
            failures.append({"prompt": messages[1]["content"], "expected": expected, "got": output.strip()})

    def share(a, b):
        return round(a / b, 3) if b else None

    f, a = stats["fusao"], stats["atmosfera"]
    summary = {
        "model": args.model, "adapter": args.adapter, "split": args.split, "examples": len(rows),
        "fusao": {"n": f["n"], "json": share(f["json"], f["n"]), "result_exact": share(f["result"], f["n"]),
                  "with_suggestions": share(f["suggestions"], f["n"]),
                  "valid_pairs_right": share(f["positives_ok"], f["positives"]),
                  "invalid_pairs_rejected": share(f["negatives_ok"], f["negatives"])},
        "atmosfera": {"n": a["n"], "json": share(a["json"], a["n"]), "words_in_right_zone": share(a["words_ok"], a["words"]),
                      "exact": share(a["exact"], a["n"])},
        "latency_ms_per_call": round(1000 * seconds / max(1, len(rows))),
        "tokens_per_second": round(tokens / seconds, 1) if seconds else None,
        "failures": failures,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if args.name:
        (HERE / "results").mkdir(exist_ok=True)
        (HERE / "results" / f"{args.name}.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
