import sys
import json
from typing import *


def get_words(lines: List[List[str]], kind: str) -> List[str]:
    return [
        line[1].strip(",")
        for line in lines
        if len(line) and line[0] == kind and line[1][0] != "%"
    ]


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

    words = {
        "code_words": code_words,
        "thread_words": thread_words,
        "variables": variables,
        "constants": constants,
        "strings": strings,
    }

    statistics = {
        "code_words": len(code_words),
        "thread_words": len(thread_words),
        "variables": len(variables),
        "constants": len(constants),
        "strings": len(strings),
    }

    statistics["total"] = sum(statistics.values())
    json.dump({"vocabulary": words, "stats": statistics}, sys.stdout, indent=4)
