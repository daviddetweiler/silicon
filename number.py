import sys
import decimal
import math

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python number.py <in> <out>")
        sys.exit(1)

    bits = []
    with open(sys.argv[1], 'rb') as f:
        data = f.read()
        for b in data:
            for i in range(8):
                bits.append((b >> (7 - i)) & 1)

    decimal.getcontext().prec = math.ceil(math.log10(2**len(bits)))
    accumulator = decimal.Decimal(0)
    pow2 = decimal.Decimal(1)
    for bit in bits:
        pow2 /= 2
        if bit == 1:
            accumulator += pow2

    number = str(accumulator)
    number = [number[i:i+120] for i in range(0, len(number), 120)]

    with open(sys.argv[2], 'w') as f:
        for n in number:
            f.write(n)
            f.write('\n')
