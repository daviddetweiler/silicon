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
    data = bytes(i for i in range(256))
    span = lambda pair : data[pair[0] : pair[0] + pair[1]]
    table = [(0, 0)] * 4096
    seen = set()
    for i in range(256):
        table[i] = (i, 1)
        seen.add(span(table[i]))

    next_code = 256
    prev = 256, 0
    for code in codes:
        if code < next_code:
            value = table[code]
            decoded = span(value)
            data += decoded
            candidate = prev[0], prev[1] + 1            
            if span(candidate) not in seen:
                table[next_code] = candidate
                seen.add(span(candidate))
                next_code += 1

            prev = prev[0] + prev[1], value[1]
        else:
            data += span(prev) + span(prev)[:1]
            decoded = prev[0] + prev[1], prev[1] + 1
            table[next_code] = decoded
            next_code += 1
            prev = decoded

    return data[256:]


def to_triplets(codes):
    data = b""
    if len(codes) % 2 == 1:
        codes.append(0)

    for i in range(0, len(codes), 2):
        l = codes[i]
        r = codes[i + 1]
        assert l < 4096
        assert r < 4096
        triplet = (r << 12) | l
        data += triplet.to_bytes(3, "little")

    return data


def from_triplets(data):
    codes = []
    for i in range(0, len(data), 3):
        triplet = int.from_bytes(data[i : i + 3], "little")
        r = (triplet >> 12) & 0xFFF
        l = triplet & 0xFFF
        codes.append(l)
        codes.append(r)

    return codes

def dump(filename, data):
    with open(filename, "w") as f:
        for byte in data:
            f.write(repr(byte) + "\n")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python .\lzw.py <filename> <compressed>")
        sys.exit(1)

    filename = sys.argv[1]
    with open(filename, "rb") as f:
        data = f.read()

    result = encode(data)
    round_trip = decode(result)
    dump("a.log", data)
    dump("b.log", round_trip)
    if round_trip != data:
        print("Round trip failed")
        sys.exit(1)

    print(len(data), "bytes uncompressed")
    n_codes = len(result)
    print(n_codes, "codes")

    compressed = to_triplets(result)
    if from_triplets(compressed)[:len(result)] != result:
        print("Triplet round trip failed")
        sys.exit(1)

    print(len(compressed), "bytes compressed")
    print(len(compressed) / len(data), "compression ratio")
    with open(sys.argv[2], "wb") as f:
        f.write(len(data).to_bytes(4, "little"))
        f.write(n_codes.to_bytes(4, "little"))
        f.write(compressed)
