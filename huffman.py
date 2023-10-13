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

def entropy(histogram):
    total = sum(histogram.values())
    entropy = 0
    for count in histogram.values():
        p = count / total
        entropy += p * math.log2(p)

    return -entropy

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: python huffman.py <filename>')
        sys.exit(1)

    filename = sys.argv[1]
    with open(filename, 'rb') as f:
        data = f.read()

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
    bit_string = ''.join(str(b) for b in encode(tree, data))
    print('Compressed size:', len(bit_string) / 8, 'bytes')
    print('Tree contains:', node_count(tree), 'nodes')
    print('Entropy:', entropy(histogram), 'bits per byte')
