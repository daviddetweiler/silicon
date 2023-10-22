import sys

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 version.py <actual> <expected>")
        sys.exit(1)

    with open(sys.argv[1], "r") as f:
        actual = f.read()

    expected = ""
    try:
        with open(sys.argv[2], "r") as f:
            expected = f.read()
            if expected == actual:
                sys.exit(0)
    except FileNotFoundError:
        pass

    print(f"Updating version from {expected} to {actual}...")

    with open(sys.argv[2], "w") as f:
        f.write(actual)
