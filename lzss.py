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

def encode_15bit(n):
    assert 0 <= n < 2**15
    if n < 0x80:
        return n.to_bytes(1, "little")
    else:
        hi = n >> 8
        lo = n & 0xFF
        return (0x80 | hi).to_bytes(1, "little") + lo.to_bytes(1, "little")
    
def decode_15bit(data):
    leader = data[0]
    if leader < 0x80:
        return leader, data[1:]
    else:
        hi = leader & 0x7F
        lo = data[1]
        return (hi << 8) | lo, data[2:]

def encode(data):
    window = 2**15
    i = 0
    bits = []
    coded = b""
    while i < len(data):
        j = 3  # At least 4 bytes are needed to encode a match, so we match only 5 bytes or more.
        longest_match = None
        while True:
            window_base = max(0, i - window)
            window_data = data[window_base : i + j - 1]
            m = window_data.rfind(data[i : i + j])
            if m == -1 or i + j > len(data):
                break
            else:
                longest_match = i - (window_base + m), j
                j += 1

        if longest_match is not None:
            offset, length = longest_match
            pair_code = encode_15bit(offset) + encode_15bit(length)
            if len(pair_code) < length:
                coded += pair_code
                bits.append(1)
                i += length
            else:
                coded += data[i].to_bytes(1, "little")
                bits.append(0)
                i += 1
        else:
            coded += data[i].to_bytes(1, "little")
            bits.append(0)
            i += 1

    print(len(bits), "bits")
    return (
        len(data).to_bytes(2, "little")
        + math.ceil(len(bits) / 8).to_bytes(2, "little")
        + to_bytes(bits)
        + coded
    )


def decode(data):
    uncompressed_size = int.from_bytes(data[:2], "little")
    data = data[2:]
    bitvector_length = int.from_bytes(data[:2], "little")
    data = data[2:]

    bits = []
    for byte in data[:bitvector_length]:
        for i in range(8):
            bits.append(byte >> i & 1)

    coded = data[bitvector_length:]

    data = b""
    for bit in bits:
        if len(data) == uncompressed_size:
            break

        if bit == 0:
            data += coded[:1]
            coded = coded[1:]
        else:
            offset, coded = decode_15bit(coded)
            length, coded = decode_15bit(coded)
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
