import sys
import math


def compute_codebook(bitfield, nodes):
    codebook = {}
    compute_codebook_recursive(codebook, bitfield, nodes, 0, [])
    return codebook


def compute_codebook_recursive(codebook, bitfield, nodes, i, bits):
    node = nodes[i]
    flags = (bitfield >> (i * 2)) & 0b11
    left = (node >> 8) & 0xFF
    right = node & 0xFF
    if flags & 0b10:
        codebook[left] = bits + [0]
    else:
        compute_codebook_recursive(codebook, bitfield, nodes, left, bits + [0])

    if flags & 0b01:
        codebook[right] = bits + [1]
    else:
        compute_codebook_recursive(codebook, bitfield, nodes, right, bits + [1])


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python blob-dump.py <filename>")
        sys.exit(1)

    filename = sys.argv[1]
    with open(filename, "rb") as file:
        data = file.read()

    uncompressed_size = int.from_bytes(data[0:4], "little")
    bit_count = int.from_bytes(data[4:8], "little")
    print("Uncompressed size:", uncompressed_size)
    print("Bit count:", bit_count)
    tree_offset = 8 + math.ceil(bit_count / 8)
    bitfield_length = int.from_bytes(data[tree_offset : tree_offset + 1], "little")
    bitfield_offset = tree_offset + 1
    nodes_offset = bitfield_offset + bitfield_length
    nodes_data = data[nodes_offset:]
    node_count = len(nodes_data) / 2
    nodes = [
        int.from_bytes(nodes_data[i : i + 2], "little")
        for i in range(0, len(nodes_data), 2)
    ]

    print("Node count:", node_count)
    bitfield = int.from_bytes(
        data[bitfield_offset : bitfield_offset + bitfield_length], "little"
    )
    codebook = compute_codebook(bitfield, nodes)
    codebook = sorted(codebook.items(), key=lambda x: x[0])

    i = 0
    print("Codebook:")
    for byte, code in codebook:
        if i % 4 == 0:
            print()

        column = f'0x{byte:02x}: {"".join(str(b) for b in code)}'
        align = (32 - (len(column) % 32)) % 32
        print(column + " " * align, end="")
        i += 1
