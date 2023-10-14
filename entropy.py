import sys
from math import log2
from collections import defaultdict

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: python entropy.py <filename>')
        sys.exit(1)

    filename = sys.argv[1]
    with open(filename, 'rb') as file:
        data = file.read()
    
    histogram = defaultdict(lambda: 0)
    for i in range(0, len(data)):
        symbol = int.from_bytes(data[i:i + 1], 'little')
        histogram[symbol] += 1

    total = sum(histogram.values())
    entropy = 0
    for symbol, count in histogram.items():
        p = count / total
        entropy -= p * log2(p)

    print('Entropy:', entropy, f'bits per symbol')
