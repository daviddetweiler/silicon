import sys
import math


def init_table():
    table = {}
    for i in range(256):
        table[i.to_bytes(1, "little")] = i

    return table


def init_inverse_table():
    table = init_table()
    inverse_table = {}
    for k, v in table.items():
        inverse_table[v] = k

    return inverse_table


def encode(data):
    table = init_table()
    code = 256
    result = []
    b, e = 0, 1
    while b < len(data):
        subdata = data[b:e]
        if subdata not in table or e > len(data):
            result.append(table[data[b : e - 1]])
            table[subdata] = code
            code += 1
            b = e - 1
        else:
            e += 1

    return result


def decode(codes):
    table = init_inverse_table()
    next_code = 256
    data = b""
    prev = b""
    for code in codes:
        if code in table:
            decoded = table[code]
            data += decoded
            candidate = prev + decoded[:1]
            if candidate not in table.values():
                table[next_code] = candidate
                next_code += 1

            prev = decoded
        else:
            decoded = prev + prev[:1]
            data += decoded
            table[next_code] = decoded
            next_code += 1
            prev = decoded

    return data


def to_triplets(codes):
    data = b""
    if len(codes) % 2 == 1:
        codes.append(0)

    for i in range(0, len(codes), 2):
        l = codes[i]
        r = codes[i + 1]
        assert l < 4096
        assert r < 4096
        triplet = (l << 12) | r
        data += triplet.to_bytes(3, "little")

    return data


def from_triplets(data):
    codes = []
    for i in range(0, len(data), 3):
        triplet = int.from_bytes(data[i : i + 3], "little")
        l = (triplet >> 12) & 0xFFF
        r = triplet & 0xFFF
        codes.append(l)
        codes.append(r)

    return codes


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python .\lzw.py <filename> <compressed>")
        sys.exit(1)

    filename = sys.argv[1]
    with open(filename, "rb") as f:
        data = f.read()

    result = encode(data)
    round_trip = decode(result)
    if round_trip != data:
        print("Round trip failed")
        sys.exit(1)

    print(len(data), "bytes uncompressed")
    print(len(result), "codes")

    compressed = to_triplets(result)
    if from_triplets(compressed)[:len(result)] != result:
        print("Triplet round trip failed")
        sys.exit(1)

    print(len(compressed), "bytes compressed")
    print(len(compressed) / len(data), "compression ratio")
    with open(sys.argv[2], "wb") as f:
        f.write(compressed)
