#!/usr/bin/env python3
"""Builds the composition-engine dataset from vocabulary.json.

Two tasks, both as mlx-lm chat JSONL (system, user, assistant):
- fusao: two words or phrases -> {"resultado": phrase, "sugestoes": [a, b]} or {"resultado": null}
- atmosfera: a focus and the present words -> {"1": [...], "2": [...], "3": [...]}
  (1 combines with the focus, 2 combines with another present word, 3 has no combination),
  the same rule the app's RuleEngine uses.

Writes data/train.jsonl, data/valid.jsonl, data/test.jsonl and data/parity.jsonl (the app's
current rules, which the grammar must reproduce).
"""
import argparse
import itertools
import json
import random
from pathlib import Path

HERE = Path(__file__).parent
SYSTEM = (
    "Você é o motor de composição de um app de comunicação alternativa em português do Brasil. "
    "Responda apenas com JSON compacto."
)

# Frase = (sujeito, negação, modal, verbo, complemento ou quantidade, tempo).
SLOTS = ("subject", "negation", "modal", "verb", "tail", "time")


class Grammar:
    def __init__(self, vocabulary):
        self.v = vocabulary
        self.kind_of = {}
        for subject in vocabulary["subjects"]:
            self.kind_of[subject] = ("subject", subject)
        self.kind_of[vocabulary["negation"]] = ("negation", True)
        for modal in vocabulary["modals"]:
            self.kind_of[modal] = ("modal", modal)
        for verb in vocabulary["verbs"]:
            self.kind_of[verb] = ("verb", verb)
        for verb in vocabulary["verbs"].values():
            for complement in verb["complements"]:
                self.kind_of[complement] = ("tail", complement)
        for quantity in vocabulary["quantities"]:
            self.kind_of[quantity] = ("tail", quantity)
        for time in vocabulary["times"]:
            self.kind_of[time] = ("time", time)
        self.atoms = sorted(set(self.kind_of) | set(vocabulary["extra_words"]))
        self.phrases = {}
        for state in self.states():
            self.phrases[self.render(state)] = state

    def states(self):
        subjects = [None, *self.v["subjects"]]
        for subject, negation, modal in itertools.product(subjects, [None, True], self.v["modals"]):
            yield (subject, negation, modal, None, None, None)
            for verb, spec in self.v["verbs"].items():
                tails = [None, *spec["complements"], *(self.v["quantities"] if spec.get("quantity") else [])]
                for tail, time in itertools.product(tails, [None, *self.v["times"]]):
                    yield (subject, negation, modal, verb, tail, time)

    @staticmethod
    def parts(state):
        return sum(value is not None for value in state)

    def valid(self, state):
        subject, negation, modal, verb, tail, time = state
        if modal is None or self.parts(state) < 2:
            return False
        if (tail or time) and verb is None:
            return False
        if tail and tail not in self.v["verbs"][verb]["complements"] and not (
            tail in self.v["quantities"] and self.v["verbs"][verb].get("quantity")
        ):
            return False
        return True

    def render(self, state):
        subject, negation, modal, verb, tail, time = state
        person = self.v["subjects"][subject or self.v["default_subject"]]
        words = [person["label"]] if subject else []
        if negation:
            words.append(self.v["negation"])
        words.append(person[modal])
        words += [w for w in (verb, tail, time) if w]
        text = " ".join(words)
        return text[0].upper() + text[1:]

    def state_of(self, text):
        """Phrase state for a phrase or an atom (atoms become one-slot states)."""
        if text in self.phrases:
            return self.phrases[text]
        if text in self.kind_of:
            slot, value = self.kind_of[text]
            state = [None] * len(SLOTS)
            state[SLOTS.index(slot)] = value
            return tuple(state)
        return None

    def suggestions(self, state):
        subject, negation, modal, verb, tail, time = state
        if time:
            by_verb = self.v["after_time_suggest"].get(verb, {})
            return by_verb.get(time, self.v["after_time_suggest"]["default"])
        if tail:
            return self.v["after_complement_suggest"]
        if verb:
            return self.v["verbs"][verb]["suggest"]
        if negation:
            return self.v["negated_modal_suggest"]
        return self.v["subject_modal_suggest"]

    def fuse(self, a, b):
        """Fusion of two texts, at least one of them a single word, or None."""
        if a == b or (a not in self.atoms and b not in self.atoms):
            return None
        first, second = self.state_of(a), self.state_of(b)
        if first is None or second is None:
            return None
        if any(x is not None and y is not None for x, y in zip(first, second)):
            return None
        merged = tuple(x if x is not None else y for x, y in zip(first, second))
        if not self.valid(merged):
            return None
        return {"resultado": self.render(merged), "sugestoes": list(self.suggestions(merged))}

    def zone(self, word, focus, words):
        if self.fuse(word, focus):
            return 1
        if any(other != focus and other != word and self.fuse(word, other) for other in words):
            return 2
        return 3


def message(user, answer):
    return {"messages": [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": user},
        {"role": "assistant", "content": json.dumps(answer, ensure_ascii=False, separators=(",", ":"))},
    ]}


def fusion_example(grammar, a, b):
    return message(f'fusao: "{a}" + "{b}"', grammar.fuse(a, b) or {"resultado": None})


def atmosphere_example(grammar, focus, words):
    zones = {"1": [], "2": [], "3": []}
    for word in words:
        zones[str(grammar.zone(word, focus, [focus, *words]))].append(word)
    listed = ", ".join(f'"{w}"' for w in words)
    return message(f'atmosfera: foco "{focus}"; palavras: [{listed}]', zones)


# The app's current rules (TesteMetaWord/Vocabulary.swift, SPEC.md) that the grammar must keep.
PARITY = [
    ("querer", "ir", "Quero ir", ["agora", "depois"]),
    ("querer", "comer", "Quero comer", ["mais", "menos"]),
    ("querer", "beber", "Quero beber", ["água", "suco"]),
    ("Quero ir", "agora", "Quero ir agora", ["perto", "longe"]),
    ("Quero ir", "depois", "Quero ir depois", ["hoje", "amanhã"]),
    ("eu", "querer", "Eu quero", ["ir", "brincar"]),
    ("querer", "brincar", "Quero brincar", ["agora", "depois"]),
    ("eu", "Quero ir", "Eu quero ir", ["agora", "depois"]),
    ("Eu quero", "beber", "Eu quero beber", ["água", "suco"]),
    ("Quero beber", "água", "Quero beber água", ["agora", "depois"]),
    ("Quero comer", "agora", "Quero comer agora", ["aqui", "ali"]),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fusions", type=int, default=6000, help="fusion examples before the split")
    parser.add_argument("--atmospheres", type=int, default=2000, help="atmosphere examples before the split")
    parser.add_argument("--negative-share", type=float, default=0.25)
    parser.add_argument("--core-repeat", type=int, default=6, help="copies of each valid word + word pair in train")
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--out", type=Path, default=HERE / "data")
    args = parser.parse_args()

    grammar = Grammar(json.loads((HERE / "vocabulary.json").read_text()))
    for a, b, result, suggestions in PARITY:
        fused = grammar.fuse(a, b)
        assert fused == {"resultado": result, "sugestoes": suggestions}, (a, b, fused)
    assert grammar.fuse("eu", "brincar") is None

    rng = random.Random(args.seed)
    texts = grammar.atoms + sorted(grammar.phrases)
    # Core: every pair of single words. Few, finite and the first step of every phrase, so all
    # of them go to training, repeated, and never to the held-out splits.
    core_valid, core_invalid = [], []
    for a, b in itertools.combinations(grammar.atoms, 2):
        (core_valid if grammar.fuse(a, b) else core_invalid).append((a, b))
    positives, negatives = set(), set()
    for phrase in sorted(grammar.phrases):
        for atom in grammar.atoms:
            if grammar.fuse(phrase, atom):
                positives.add(frozenset((phrase, atom)))
    phrases = sorted(grammar.phrases)
    while len(negatives) < len(positives):
        pair = frozenset((rng.choice(phrases), rng.choice(grammar.atoms)))
        if not grammar.fuse(*pair):
            negatives.add(pair)
    negative_count = int(args.fusions * args.negative_share)
    pairs = rng.sample(sorted(map(sorted, positives)), min(len(positives), args.fusions - negative_count))
    pairs += rng.sample(sorted(map(sorted, negatives)), min(len(negatives), negative_count))
    examples = []
    for a, b in pairs:
        examples.append(fusion_example(grammar, *rng.sample([a, b], 2)))

    focuses = [t for t in texts if any(grammar.fuse(t, atom) for atom in grammar.atoms)]
    for _ in range(args.atmospheres):
        focus = rng.choice(focuses)
        partners = [a for a in grammar.atoms if grammar.fuse(focus, a)]
        others = [t for t in grammar.atoms if t != focus and t not in partners]
        words = rng.sample(partners, min(len(partners), rng.randint(1, 4))) + rng.sample(others, rng.randint(2, 5))
        rng.shuffle(words)
        examples.append(atmosphere_example(grammar, focus, words))

    rng.shuffle(examples)
    held = max(1, len(examples) // 20)
    core = [fusion_example(grammar, *rng.sample(pair, 2)) for pair in core_valid for _ in range(args.core_repeat)]
    core += [fusion_example(grammar, *rng.sample(pair, 2)) for pair in rng.sample(core_invalid, min(len(core_invalid), len(core) // 3))]
    core += [fusion_example(grammar, a, b) for a, b, _, _ in PARITY for _ in range(args.core_repeat)]
    train = examples[2 * held:] + core
    rng.shuffle(train)
    splits = {"test": examples[:held], "valid": examples[held:2 * held], "train": train}
    splits["parity"] = [fusion_example(grammar, a, b) for a, b, _, _ in PARITY]
    args.out.mkdir(parents=True, exist_ok=True)
    for name, rows in splits.items():
        with open(args.out / f"{name}.jsonl", "w") as file:
            for row in rows:
                file.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"{len(grammar.atoms)} palavras, {len(grammar.phrases)} frases, "
          f"{len(positives)} fusões frase + palavra, {len(core_valid)} palavra + palavra válidas; " + ", ".join(f"{k}: {len(v)}" for k, v in splits.items()))


if __name__ == "__main__":
    main()
