from lzss import to_bytes
import operator
import sys
import math

def encode_huffman(data):
    histogram = {}
    for byte in data:
        histogram[byte] = histogram.get(byte, 0) + 1

    entropy = 0
    for count in histogram.values():
        p = count / len(data)
        entropy += p * math.log2(p)

    print(f"{-entropy * 100 / 8:.2f}% theoretical limit")

    nodes = [(count, byte, None) for byte, count in histogram.items()]
    while len(nodes) > 1:
        nodes.sort(key=lambda x: x[0])
        left = nodes.pop(0)
        right = nodes.pop(0)
        nodes.append((left[0] + right[0], None, (left, right)))

    tree = nodes[0]
    code_lengths = {}

    def traverse(node, length):
        if node[1] is not None:
            code_lengths[node[1]] = length
        else:
            traverse(node[2][0], length + 1)
            traverse(node[2][1], length + 1)

    traverse(tree, 0)

    pairs = sorted(code_lengths.items(), key=operator.itemgetter(1, 0))
    current_code = 0
    current_length = 1
    codebook = {}
    for byte, length in pairs:
        if length > current_length:
            current_code <<= length - current_length
            current_length = length

        bitstring = []
        for i in range(length):
            bitstring.append(current_code >> i & 1)

        bitstring.reverse()
        codebook[byte] = bitstring
        current_code += 1

    bits = sum((codebook[byte] for byte in data), [])
    coded = to_bytes(bits)
    codebook_packed = b""
    for b in range(256):
        if b in code_lengths:
            codebook_packed += code_lengths[b].to_bytes(1, "little")
        else:
            codebook_packed += b"\x00"

    with open("bits.log", "w") as f:
        for bit in bits:
            f.write(str(bit) + "\n")

    return (
        len(data).to_bytes(2, "little")
        + codebook_packed
        + coded
    )

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python huffman.py <input> <output>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    compressed = encode_huffman(data)
    ratio = len(compressed) / len(data)
    print(f"{ratio * 100:.2f}%", "compression ratio")
    print(len(compressed), "bytes compressed")
    with open(sys.argv[2], "wb") as f:
        f.write(compressed)
