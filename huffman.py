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


def encode(tree, data):
    bits = []
    for byte in data:
        bits.extend(find(tree, byte))

    return bits


def node_count(tree):
    if tree[0] is None:
        return 1 + node_count(tree[2][0]) + node_count(tree[2][1])
    else:
        return 1


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


def tape_out(uncompressed_size, encoding, bit_string):
    with open("compressed.bin", "wb") as file:
        file.write(uncompressed_size.to_bytes(4, "little"))
        file.write(len(encoding).to_bytes(2, "little"))
        file.write(b"".join(node.to_bytes(3, "little") for node in encoding))

        valid_size = len(bit_string)
        align = (8 - (len(bit_string) % 8)) % 8
        bit_string += [0] * align
        file.write(valid_size.to_bytes(4, "little"))
        byte_string = b"".join(
            to_byte(bit_string[i : i + 8]) for i in range(0, len(bit_string), 8)
        )

        file.write(byte_string)

# A maximum of 512 nodes in the tree, so only 9 bits are needed to label a node
# Here's a non-leaf node:
# | 1 | 5-bit pad | 9-bit left child | 9-bit right child |
# Here's a leaf node:
# | 0 | 15-bit pad | 8-bit byte |

def encode_tree(tree):
    size = node_count(tree)
    encoding = [None] * size
    encode_tree_recurse(tree, encoding, 0)
    return encoding

# Returns (node, free)
def encode_tree_recurse(tree, encoding, i):
    if tree[0] is None:
        s = i
        l, i = encode_tree_recurse(tree[2][0], encoding, i + 1)
        r, i = encode_tree_recurse(tree[2][1], encoding, i)
        encoding[s] = (1 << 23) | (l << 9) | r
        return s, i
    else:
        encoding[i] = tree[0]
        return i, i + 1
    
def decode_with_encoded_tree(encoding, bits):
    log = open('decode.log', 'w')

    data = []
    i = 0
    j = 0
    while i < len(bits):
        print(f'i={i:02x} {encoding[j]:03x}', file=log)
        mask = ((1 << 9) - 1)
        node = encoding[j]
        if bits[i] == 0:
            node >>= 9
        
        j = node & mask
        i += 1

        if encoding[j] & (1 << 23) == 0:
            data.append(encoding[j])
            j = 0

    log.close()

    return bytes(data)

def get_size(data):
    bss_size = int.from_bytes(data[8:16], 'little')
    print('BSS size:', bss_size)

    return len(data) + bss_size

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python huffman.py <filename>")
        sys.exit(1)

    filename = sys.argv[1]
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
    print("Tree contains:", node_count(tree), "nodes")
    print("Entropy:", entropy(histogram), "bits per byte")
    good_round_trip = decode(tree, bit_string) == data
    print("Successful round-trip:", good_round_trip)
    if not good_round_trip:
        sys.exit(1)

    encoded_tree = encode_tree(tree)
    good_round_trip = decode_with_encoded_tree(encoded_tree, bit_string) == data
    print("Successful second round-trip:", good_round_trip)
    if not good_round_trip:
        sys.exit(1)

    tape_out(get_size(data), encoded_tree, bit_string)

    with open('bits.log', 'w') as file:
        for bit in bit_string:
            print('1' if bit else '0', file=file)

    with open('raw-compressed.bin', 'wb') as file:
        byte_string = b"".join(
            to_byte(bit_string[i : i + 8]) for i in range(0, len(bit_string), 8)
        )

        file.write(byte_string)
