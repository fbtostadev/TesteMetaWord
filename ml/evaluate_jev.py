#!/usr/bin/env python3
"""Compares Jev (TypeSafe, hosted decision model) with the local engine on a dataset split.

Jev answers typed questions and does not write text, so it is scored only on decisions:
- fusao: one yes/no (Noul) per pair, "these two can be fused"; scored as valid/invalid.
- atmosfera: one Noul per pair among the focus and the words, all in one request; the zones are
  then computed in code with the app's rule (1 fuses with the focus, 2 fuses with another word,
  3 none), as TypeSafe recommends instead of asking for the multi-step judgment directly.

Two variants: "regras" puts this project's grammar in the state; "livre" only asks whether the
pair forms natural Brazilian Portuguese (which shows where the grammar may be too strict).
Instructions are in English, as TypeSafe advises; the words stay in Portuguese.

The raw probabilities are saved (results/jev-<variant>-<split>-raw.jsonl), so thresholds are
scored offline. With --tune-split, each task's threshold is chosen on that split (for example
valid) and only then applied to --split, as TypeSafe advises calibrating on labeled data.

Reads TYPESAFE_API_KEY from the environment or from the repository's .env; never prints it.
Example: python3 evaluate_jev.py --variant regras --tune-split valid --name jev-regras
"""
import argparse
import itertools
import json
import os
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).parent
URL = "https://api.typesafe.ai/v1/systemone"
PRICE_PER_MILLION_INPUT = 0.042


def api_key():
    if os.environ.get("TYPESAFE_API_KEY"):
        return os.environ["TYPESAFE_API_KEY"]
    env = HERE.parent / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            name, _, value = line.partition("=")
            if name.strip() in ("TYPESAFE_API_KEY", "JEV_API_KEY"):
                return value.strip().strip('"').strip("'")
    raise SystemExit("Defina TYPESAFE_API_KEY no ambiente ou em .env na raiz do projeto.")


def grammar_text():
    v = json.loads((HERE / "vocabulary.json").read_text())
    verbs = "; ".join(f"{verb} ({', '.join(spec['complements']) or 'no complement'}"
                      f"{'; also ' + ', '.join(v['quantities']) if spec.get('quantity') else ''})"
                      for verb, spec in v["verbs"].items())
    return (
        "Two items fuse into one phrase shaped [subject] [não] modal verb [complement or quantity] [time]. "
        f"Subjects: {', '.join(v['subjects'])}. Modal verbs, conjugated for the subject (first person when there "
        f"is no subject): {', '.join(v['modals'])}. Verbs and the only complements each accepts: {verbs}. "
        f"Times: {', '.join(v['times'])}. Every phrase needs a modal verb; a complement, quantity or time needs a "
        "verb; each slot appears at most once; at least one of the two items is a single word. "
        f"Any other word ({', '.join(v['extra_words'])}) never fuses."
    )


def pair_question(a, b, variant):
    if variant == "regras":
        text = f'Following the composition rules in `rules`, the items "{a}" and "{b}" can be fused into one valid phrase.'
    else:
        text = (f'Joining "{a}" and "{b}" in either order, adjusting only conjugation and adding no other words, '
                "gives a natural, grammatical Brazilian Portuguese phrase.")
    return {"type": "noul", "instructions": text}


def state(variant):
    if variant == "regras":
        return {"app": "Augmentative and alternative communication in Brazilian Portuguese", "rules": grammar_text()}
    return {"app": "Augmentative and alternative communication: the user joins word chips into sentences",
            "language": "Brazilian Portuguese"}


def ask(key, body):
    data = json.dumps(body, ensure_ascii=False).encode()
    for attempt in range(6):
        request = urllib.request.Request(URL, data=data, method="POST", headers={
            "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response), time.perf_counter() - started
        except urllib.error.HTTPError as error:
            if error.code in (429, 529) and attempt < 5:
                time.sleep(2 ** attempt)
                continue
            raise SystemExit(f"TypeSafe respondeu {error.code}: {error.read().decode()[:300]}")
    raise SystemExit("TypeSafe indisponível após várias tentativas.")


def parse_user(content):
    if content.startswith("fusao: "):
        a, b = content[len("fusao: "):].split(" + ")
        return "fusao", (a.strip('"'), b.strip('"'))
    focus_part, words_part = content[len("atmosfera: foco "):].split("; palavras: ")
    return "atmosfera", (focus_part.strip('"'), json.loads(words_part))


def collect(row, key, variant, model):
    """Asks Jev every pair the row needs and keeps the raw yes-probabilities."""
    task, data = parse_user(row["messages"][1]["content"])
    pairs = [data] if task == "fusao" else list(itertools.combinations([data[0], *data[1]], 2))
    questions = {f"q{i}": pair_question(a, b, variant) for i, (a, b) in enumerate(pairs)}
    answer, seconds = ask(key, {"model": model, "state": state(variant), "questions": questions})
    return {"task": task, "data": data, "expected": json.loads(row["messages"][-1]["content"]),
            "pairs": [[a, b, answer["answers"][f"q{i}"]["noul"]] for i, (a, b) in enumerate(pairs)],
            "seconds": seconds, "model": answer.get("model"), "tokens": answer.get("usage", {}).get("input_tokens", 0)}


def raw_rows(split, variant, model, limit, workers):
    path = HERE / "results" / f"jev-{variant}-{split}-raw.jsonl"
    if path.exists():
        return [json.loads(line) for line in open(path)]
    key = api_key()
    rows = [json.loads(line) for line in open(HERE / "data" / f"{split}.jsonl")][:limit]
    with ThreadPoolExecutor(workers) as pool:
        collected = list(pool.map(lambda row: collect(row, key, variant, model), rows))
    path.parent.mkdir(exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in collected))
    return collected


def share(a, b):
    return round(a / b, 3) if b else None


def score_fusions(rows, threshold):
    fusions = [r for r in rows if r["task"] == "fusao"]
    right = [(r["pairs"][0][2] >= threshold) == (r["expected"]["resultado"] is not None) for r in fusions]
    valid = [ok for r, ok in zip(fusions, right) if r["expected"]["resultado"] is not None]
    invalid = [ok for r, ok in zip(fusions, right) if r["expected"]["resultado"] is None]
    return {"n": len(fusions), "threshold": threshold, "valid_invalid_right": share(sum(right), len(right)),
            "valid_pairs_right": share(sum(valid), len(valid)), "invalid_pairs_rejected": share(sum(invalid), len(invalid)),
            "brier": round(sum((r["pairs"][0][2] - (r["expected"]["resultado"] is not None)) ** 2 for r in fusions) / max(1, len(fusions)), 4)}


def score_atmospheres(rows, threshold):
    atmospheres = [r for r in rows if r["task"] == "atmosfera"]
    words_ok = words = exact = 0
    for r in atmospheres:
        focus, listed = r["data"]
        fuses = {frozenset((a, b)) for a, b, p in r["pairs"] if p >= threshold}
        truth = {w: z for z, ws in r["expected"].items() for w in ws}
        guess = {w: "1" if frozenset((w, focus)) in fuses else
                 "2" if any(frozenset((w, o)) in fuses for o in listed if o != w) else "3" for w in listed}
        words += len(truth)
        words_ok += sum(guess[w] == z for w, z in truth.items())
        exact += all(guess[w] == z for w, z in truth.items())
    return {"n": len(atmospheres), "threshold": threshold, "words_in_right_zone": share(words_ok, words),
            "exact": share(exact, len(atmospheres))}


def best_threshold(rows, scorer, metric):
    candidates = [round(0.05 * k, 2) for k in range(1, 20)]
    return max(candidates, key=lambda t: (scorer(rows, t)[metric] or 0, -abs(t - 0.5)))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--split", default="test")
    parser.add_argument("--tune-split", default=None, help="choose thresholds on this split first")
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--variant", choices=["regras", "livre"], default="regras")
    parser.add_argument("--model", default="jev-latest")
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--name", default=None, help="results/<name>.json")
    args = parser.parse_args()

    fusion_threshold = atmosphere_threshold = 0.5
    if args.tune_split:
        tuning = raw_rows(args.tune_split, args.variant, args.model, args.limit, args.workers)
        fusion_threshold = best_threshold(tuning, score_fusions, "valid_invalid_right")
        atmosphere_threshold = best_threshold(tuning, score_atmospheres, "words_in_right_zone")
    rows = raw_rows(args.split, args.variant, args.model, args.limit, args.workers)
    tokens = sum(r["tokens"] for r in rows)
    summary = {
        "model": sorted({r["model"] for r in rows if r["model"]}), "variant": args.variant,
        "split": args.split, "tuned_on": args.tune_split, "examples": len(rows),
        "fusao": score_fusions(rows, fusion_threshold), "fusao_at_0.5": score_fusions(rows, 0.5),
        "atmosfera": score_atmospheres(rows, atmosphere_threshold), "atmosfera_at_0.5": score_atmospheres(rows, 0.5),
        "latency_ms_per_request": round(1000 * sum(r["seconds"] for r in rows) / max(1, len(rows))),
        "input_tokens": tokens, "cost_usd": round(tokens / 1e6 * PRICE_PER_MILLION_INPUT, 4),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if args.name:
        (HERE / "results" / f"{args.name}.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
