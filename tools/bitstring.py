import sys
import math

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python bitstring.py <filename> <output>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    string = " ".join(bin(byte)[2:].zfill(8) for byte in data)
    lines = [string[i : i + 72] for i in range(0, len(string), 72)]

    with open(sys.argv[2], "w") as f:
        for line in lines:
            f.write(line + "\n")
