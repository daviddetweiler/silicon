import sys
import json
from typing import *


def get_words(lines: List[List[str]], kind: str, numbers=False) -> List[str]:
    return sorted(
        [
            line[1].strip(",") if not numbers else (n, line[1].strip(","))
            for n, line in enumerate(lines)
            if len(line) and line[0] == kind and line[1][0] != "%"
        ]
    )


def get_docs():
    with open("./docs/words.md") as f:
        return [line.strip() for line in f.readlines() if line.startswith("    ")]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: analyzer.py <source>")
        sys.exit(1)

    with open(sys.argv[1]) as f:
        data = f.read()

    lines = [line.strip().split() for line in data.splitlines()]

    code_words = get_words(lines, "code")
    thread_words = get_words(lines, "thread")
    variables = get_words(lines, "variable")
    constants = get_words(lines, "constant")
    strings = get_words(lines, "string")
    aliases = [
        (n, line.strip('"')) for n, line in get_words(lines, "declare", numbers=True)
    ]

    dictionary = {}
    for n, alias in aliases:
        word = lines[n + 1]
        if len(word) < 2:
            continue
        elif word[0] not in ["code", "thread", "variable", "constant", "string"]:
            continue

        dictionary[alias] = word[1].strip(",")

    words = {
        "code_words": code_words,
        "thread_words": thread_words,
        "variables": variables,
        "constants": constants,
        "strings": strings,
    }

    words["all"] = sorted(sum(words.values(), []))
    a, b = set(words["all"]), set(get_docs())
    undocumented = a - b
    nonexistent = b - a
    words["undocumented"] = sorted(undocumented)
    words["nonexistent"] = sorted(nonexistent)

    unnamed = sorted([word for word in words["all"] if word not in dictionary.values()])
    words["unnamed"] = unnamed

    statistics = {
        "primitives": len(code_words),
        "threads": len(thread_words),
        "variables": len(variables),
        "constants": len(constants),
        "strings": len(strings),
    }

    statistics["total"] = sum(statistics.values())
    json.dump(
        {"vocabulary": words, "stats": statistics, "dictionary": dictionary},
        sys.stdout,
        indent=4,
        sort_keys=True,
    )
