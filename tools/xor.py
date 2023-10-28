import sys

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print('Usage: python xor.py <a> <b> <c>')
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        a = f.read()

    with open(sys.argv[2], "rb") as f:
        b = f.read()

    shared = min(len(a), len(b))
    if len(a) != len(b):
        print('Warning: files are not the same length')

    c = bytearray(shared)
    for i in range(shared):
        c[i] = a[i] ^ b[i]

    with open(sys.argv[3], "wb") as f:
        f.write(c)
