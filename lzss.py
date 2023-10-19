import sys
import math
import operator

# There is some anecdotal evidence that the LZSS algorithm outperforms LZW in terms of compression ratio.


def to_bytes(bits):
    align = (8 - len(bits) % 8) % 8
    bits += [0] * align
    coded = b""
    for i in range(0, len(bits), 8):
        byte = 0
        for j in range(8):
            byte |= bits[i + j] << j

        coded += byte.to_bytes(1, "little")

    return coded


def encode(data):
    window = 2**16
    i = 0
    bits = []
    coded = b""
    while i < len(data):
        j = 3  # At least 4 bytes are needed to encode a match, so we match only 5 bytes or more.
        longest_match = None
        while True:
            window_base = max(0, i - window)
            window_data = data[i - window : i + j - 1]
            m = window_data.rfind(data[i : i + j])
            if m == -1 or i + j > len(data):
                break
            else:
                longest_match = i - (window_base + m), j
                j += 1

        if longest_match is not None:
            offset, length = longest_match
            coded += offset.to_bytes(2, "little")
            coded += length.to_bytes(2, "little")
            bits.append(1)
            i += length
        else:
            coded += data[i].to_bytes(1, "little")
            bits.append(0)
            i += 1

    return (
        len(data).to_bytes(2, "little")
        + len(bits).to_bytes(2, "little")
        + to_bytes(bits)
        + coded
    )


def decode(data):
    _ = int.from_bytes(data[:2], "little")
    data = data[2:]
    length = int.from_bytes(data[:2], "little")
    data = data[2:]

    bits = []
    bitvector_length = math.ceil(length / 8)
    for byte in data[:bitvector_length]:
        for i in range(8):
            if i < length:
                bits.append(byte >> i & 1)

    coded = data[bitvector_length:]

    data = b""
    for bit in bits:
        if bit == 0:
            data += coded[:1]
            coded = coded[1:]
        else:
            offset = int.from_bytes(coded[:2], "little")
            length = int.from_bytes(coded[2:4], "little")
            coded = coded[4:]
            if offset > length:
                data += data[-offset : -(offset - length)]
            else:
                while length > 0:
                    data += data[-offset:]
                    length -= offset

    return data


def entropy_limit(data):
    histogram = {}
    for byte in data:
        histogram[byte] = histogram.get(byte, 0) + 1

    entropy = 0
    for byte, count in histogram.items():
        p = count / len(data)
        entropy += p * math.log2(p)

    entropy = -entropy

    print(f"{entropy:.2f} bits per byte")

    ratio = entropy / 8
    print(f"{ratio * 100:.2f}%", "entropy limit")

    return ratio


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: lzss.py <input> <output>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    lzss = encode(data)
    ratio = len(lzss) / len(data)
    print(f"{ratio * 100:.2f}%", "compression ratio")

    final_ratio = entropy_limit(lzss) * ratio
    print(f"{final_ratio * 100:.2f}%", "theoretical final compression ratio")

    round_trip = decode(lzss)
    assert round_trip == data

    #coded = encode_huffman(lzss)
    coded = lzss
    ratio = len(coded) / len(data)
    #print(f"{ratio * 100:.2f}%", "compression ratio")
    print(len(coded), "bytes compressed")

    with open(sys.argv[2], "wb") as f:
        f.write(coded)
