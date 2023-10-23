import sys
import decimal
import math

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python number.py <in> <out>")
        sys.exit(1)

    bits = []
    with open(sys.argv[1], "rb") as f:
        data = f.read()
        for b in data:
            for i in range(8):
                bits.append((b >> (7 - i)) & 1)

    required_bits = len(bits)
    digits = math.ceil(required_bits * math.log10(2))
    actual_bits = math.log2(10) * digits

    # This ensures that no actual information is lost
    assert actual_bits >= required_bits
    decimal.getcontext().prec = digits

    accumulator = decimal.Decimal(0)
    pow2 = decimal.Decimal(1)
    for bit in bits:
        pow2 /= 2
        if bit == 1:
            accumulator += pow2

    number = str(accumulator)
    number = [number[i : i + 120] for i in range(0, len(number), 120)]

    with open(sys.argv[2], "w") as f:
        for n in number:
            f.write(n)
            f.write("\n")
