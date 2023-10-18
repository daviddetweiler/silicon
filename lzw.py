import sys
import binascii


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
    resets = 0
    table = init_table()
    code = 256
    codes = []
    b, e = 0, 1
    while b < len(data):
        subdata = data[b:e]
        if subdata not in table or e > len(data):
            if code == 4095:
                codes.append(code)
                table = init_table()
                code = 256
                e = b + 1
                resets += 1
                continue

            codes.append(table[data[b : e - 1]])
            table[subdata] = code
            code += 1
            b = e - 1
        else:
            e += 1

    return codes, resets


def span_raw(data, s):
    return data[s[0] : s[0] + s[1]]


def contains(data, table, next_code, c):
    crc = binascii.crc32(span_raw(data, c))
    found = False
    for i in range(next_code):
        row = table[i]
        if crc != row[2]:
            continue

        if span_raw(data, row) == span_raw(data, c):
            found = True
            break

    return found


def decode(codes):
    data = bytes(i for i in range(256))
    span = lambda pair: span_raw(data, pair)
    table = [(0, 0, 0)] * 4096
    for i in range(256):
        table[i] = (i, 1, binascii.crc32(i.to_bytes(1, "little")))

    next_code = 256
    prev = 256, 0
    for code in codes:
        if code == 4095:
            next_code = 256
            prev = len(data), 0
            continue

        if code < next_code:
            value = table[code]
            decoded = span(value)
            data += decoded
            candidate = prev[0], prev[1] + 1
            if not contains(data, table, next_code, candidate):
                table[next_code] = candidate + (binascii.crc32(span(candidate)),)
                next_code += 1

            prev = prev[0] + prev[1], value[1]
        else:
            data += span(prev)
            data += span(prev)[:1]
            decoded = prev[0] + prev[1], prev[1] + 1
            prev = decoded
            table[next_code] = decoded + (binascii.crc32(span(decoded)),)
            next_code += 1

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


def get_size(data):
    bss_size = 0
    bss_size = int.from_bytes(data[0:8], "little")
    if bss_size > 2**32:  # We're probably dealing with a non-image
        bss_size = 0

    print("BSS size:", bss_size)

    return len(data) + bss_size


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python .\lzw.py <filename> <compressed>")
        sys.exit(1)

    filename = sys.argv[1]
    with open(filename, "rb") as f:
        data = f.read()

    uncompressed_size = get_size(data)
    codes, resets = encode(data)
    round_trip = decode(codes)
    if round_trip != data:
        print("Round trip failed")
        sys.exit(1)

    print(resets, "dictionary resets")
    print(uncompressed_size, "bytes uncompressed")
    n_codes = len(codes)
    print(n_codes, "codes")

    compressed = to_triplets(codes)
    if from_triplets(compressed)[: len(codes)] != codes:
        print("Triplet round trip failed")
        sys.exit(1)

    print(len(compressed), "bytes compressed")
    print(len(compressed) / len(data), "compression ratio")
    with open(sys.argv[2], "wb") as f:
        f.write(uncompressed_size.to_bytes(4, "little"))
        f.write(n_codes.to_bytes(4, "little"))
        f.write(compressed)
