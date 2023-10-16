import sys
import math
from collections import defaultdict


def print_tree(tree, level=0):
    if tree[0] is None:
        print(f'{"  " * level}0')
        print_tree(tree[2][0], level + 1)
        print(f'{"  " * level}1')
        print_tree(tree[2][1], level + 1)
    else:
        print(f'{"  " * level}byte: {tree[0]:02x} ({tree[1]})')


def find(tree, byte):
    if tree[0] is not None:
        if tree[0] == byte:
            return []
        else:
            return None
    else:
        bits = find(tree[2][0], byte)
        if bits is not None:
            bits.insert(0, 0)
            return bits

        bits = find(tree[2][1], byte)
        if bits is not None:
            bits.insert(0, 1)
            return bits


def find_memoized(memo, tree, byte):
    if byte not in memo:
        bits = find(tree, byte)
        memo[byte] = bits
        return bits
    else:
        return memo[byte]


def encode(tree, data):
    bits = []
    memo = {}
    for byte in data:
        bits.extend(find_memoized(memo, tree, byte))

    return bits


def non_leaf_nodes(tree):
    if tree[0] is None:
        return 1 + non_leaf_nodes(tree[2][0]) + non_leaf_nodes(tree[2][1])
    else:
        return 0


def decode(tree, bits):
    data = []
    i = 0
    while i < len(bits):
        node = tree
        while node[0] is None:
            node = node[2][bits[i]]
            i += 1

        data.append(node[0])

    return bytes(data)


def entropy(histogram):
    total = sum(histogram.values())
    entropy = 0
    for count in histogram.values():
        p = count / total
        entropy += p * math.log2(p)

    return -entropy


def to_byte(bits):
    byte = 0
    for i in range(len(bits)):
        byte |= bits[i] << i

    return byte.to_bytes(1, "little")


def tape_out(destination, uncompressed_size, encoding, leaf_mask, bit_string):
    with open(destination, "wb") as file:
        valid_size = len(bit_string)
        file.write(uncompressed_size.to_bytes(4, "little"))
        file.write(valid_size.to_bytes(4, "little"))

        bit_alignment = (8 - (len(bit_string) % 8)) % 8
        bit_string += [0] * bit_alignment
        byte_string = b"".join(
            to_byte(bit_string[i : i + 8]) for i in range(0, len(bit_string), 8)
        )

        file.write(byte_string)
        after_bit_string = file.tell()
        padding = (8 - (after_bit_string % 8)) % 8
        bitfield_bytes = math.ceil(len(encoding) * 2 / 8)
        file.write(bitfield_bytes.to_bytes(1, "little"))
        file.write(leaf_mask.to_bytes(bitfield_bytes, "little"))
        file.write(b"".join(node.to_bytes(2, "little") for node in encoding))
        if file.tell() - after_bit_string < padding:
            padding = (8 - (after_bit_string % 8)) % 8
            file.write(b"\0" * padding)


# New encoding format:
# 512-bit bitfield, an array of bit pairs (left, right), with a set bit indicating a leaf
# An array of byte pairs (left, right), each representing either an index or a literal byte

# So 4-byte uncompressed length, 4-byte bitstream length, 8-byte-aligned bitstream, one byte for the tree size, a byte
# stream of the leaf bitfield, and a byte stream of the tree itself (left-right alternating). We should also nuke the
# "header" in silicon.bin (just patch address(x) and make sure we only compress after the header). Do we bring back
# xorfuscation?


def encode_tree(tree):
    size = non_leaf_nodes(tree)
    encoding = [None] * size
    leaf_mask_ref = [0]
    encode_tree_recurse(tree, leaf_mask_ref, encoding, 0)
    return encoding, leaf_mask_ref[0]


# Returns (node, free)
def encode_tree_recurse(tree, leaf_mask_ref, encoding, i):
    s = i
    i += 1
    l_node = tree[2][0]
    r_node = tree[2][1]
    l_leaf = l_node[0] is not None
    r_leaf = r_node[0] is not None
    node_mask = l_leaf << 1 | r_leaf
    if not l_leaf:
        l, i = encode_tree_recurse(l_node, leaf_mask_ref, encoding, i)
    else:
        l = l_node[0]

    if not r_leaf:
        r, i = encode_tree_recurse(r_node, leaf_mask_ref, encoding, i)
    else:
        r = r_node[0]

    leaf_mask_ref[0] |= node_mask << (s * 2)
    encoding[s] = l << 8 | r

    return s, i


def decode_with_encoded_tree(encoding, leaf_mask_ref, bits):
    data = []
    i = 0
    j = 0
    while i < len(bits):
        node_mask = (leaf_mask_ref >> (j * 2)) & 3
        node = encoding[j]
        bit = bits[i]
        if not bit:
            node_mask >>= 1
            node >>= 8

        if node_mask & 1:
            data.append(node & 0xFF)
            node = 0

        j = node & 0xFF
        i += 1

    return bytes(data)


def get_size(data):
    bss_size = 0
    bss_size = int.from_bytes(data[0:8], "little")
    print("BSS size:", bss_size)
    return len(data) + bss_size


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python huffman.py <filename> <destination>")
        sys.exit(1)

    filename = sys.argv[1]
    destination = sys.argv[2]
    with open(filename, "rb") as file:
        data = file.read()

    histogram = defaultdict(lambda: 0)
    for byte in data:
        histogram[byte] += 1

    nodes = []
    for byte, count in histogram.items():
        nodes.append((byte, count, (None, None)))

    while len(nodes) > 1:
        nodes = sorted(nodes, key=lambda x: -x[1])
        left = nodes.pop()
        right = nodes.pop()
        nodes.append((None, left[1] + right[1], (left, right)))

    tree = nodes[0]
    bit_string = encode(tree, data)
    print("Compressed size:", len(bit_string) / 8, "bytes")
    print("Tree contains:", non_leaf_nodes(tree), "non-leaf nodes")
    print("Entropy:", entropy(histogram), "bits per byte")
    good_round_trip = decode(tree, bit_string) == data
    print("Successful round-trip:", good_round_trip)
    if not good_round_trip:
        sys.exit(1)

    encoded_tree, leaf_mask = encode_tree(tree)
    good_round_trip = (
        decode_with_encoded_tree(encoded_tree, leaf_mask, bit_string) == data
    )

    print("Successful second round-trip:", good_round_trip)
    if not good_round_trip:
        sys.exit(1)

    tape_out(destination, get_size(data), encoded_tree, leaf_mask, bit_string)
