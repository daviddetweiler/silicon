import sys

# It may be possible to measurably beat huffman coding by using arithmetic coding
# It allows "fractional bit-packing," allowing a closer approach to the entropy limit, while also being adaptive,
# allowing us to remove the 256-byte codebook from the header.

# Binary fractions in finite-bit representations: For the sake of the example, suppose we are using 64-bit repetitions.
# The bits are represented "in reverse order:" the 64th bit is the 2^-1 bit, the 63rd bit is the 2^-2 bit, and so on.
# This allows for proper carry propagation, so addition is already defined. Multiplication is more complex. I think that
# by multiplying two 64-bit numbers, we get a 128-bit number, and then we take the 64 most significant bits of that
# ("left" bits) and shift right by one bit.

UPPER32 = ((1 << 32) - 1) << 32
BITS64 = (1 << 64) - 1


def divide(a, b):
    a <<= 64
    a //= b
    return a & BITS64


def multiply(a, b):
    a *= b
    a >>= 64
    return (a >> 1) & BITS64


def add(a, b):
    return (a + b) & BITS64


def subtract(a, b):
    return (a - b) & BITS64


def shl(a, n):
    return (a << n) & BITS64


def shr(a, n):
    return (a >> n) & BITS64


def encode(model, data):
    total, histogram = model
    a, b = 0, (1 << 64) - 1
    encoded = b""
    debug = []
    print(len(data))
    for byte in data:
        probabilities = [divide(histogram[i], total) for i in range(256)]
        interval_width = subtract(b, a)
        for i in range(256):
            subinterval_width = multiply(interval_width, probabilities[i])
            if byte == i:
                b = add(a, subinterval_width)
                break
            else:
                a = add(a, subinterval_width)

        debug.append((a, b))

        if (a ^ b) & UPPER32 == 0:
            # 32 bits have been locked in
            to_code = shr(a, 32)
            encoded += to_code.to_bytes(4, "little")
            a = shl(a, 32)
            b = shl(b, 32)

        histogram[byte] += 1
        total += 1

    a = add(a, 1 << 32) # The decoder semantics use open intervals
    to_code = shr(a, 32)
    encoded += to_code.to_bytes(4, "little")

    return encoded


def decode(model, data, expected_length):
    total, histogram = model
    a, b = 0, (1 << 64) - 1
    decoded = b""
    bitgroups = [
        int.from_bytes(data[i : i + 4], "little") for i in range(0, len(data), 4)
    ]

    i = 2
    window = shl(bitgroups[0], 32) | bitgroups[1]
    while len(decoded) < expected_length:
        probabilities = [divide(histogram[i], total) for i in range(256)]
        interval_width = subtract(b, a)
        byte = None
        for j in range(256):
            subinterval_width = multiply(interval_width, probabilities[j])
            next_a = add(a, subinterval_width)
            if next_a > window:
                b = next_a
                byte = j
                break

            a = next_a

        if (a ^ b) & UPPER32 == 0:
            # 32 bits have been locked in
            a = shl(a, 32)
            b = shl(b, 32)
            window = shl(window, 32) | (bitgroups[i] if i < len(bitgroups) else 0)
            i += 1

        decoded += bytes([byte])
        histogram[byte] += 1
        total += 1

    return decoded


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 ac.py <input> <output>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    model = (256, [1] * 256)
    ac = encode(model, data)
    model = (256, [1] * 256)
    round_trip = decode(model, ac, len(data))
    assert round_trip == data
    print("Compressed size:", len(ac))
    print("Compression ratio:", len(ac) / len(data))
    with open(sys.argv[2], "wb") as f:
        f.write(ac)
