import sys
import math
import ac


def encode_15bit(n):
    assert 0 <= n < 2**15
    if n < 0x80:
        return n.to_bytes(1, "little")
    else:
        hi = n >> 8
        lo = n & 0xFF
        return (0x80 | hi).to_bytes(1, "little") + lo.to_bytes(1, "little")


def bake_lzss_model(data):
    window = 2**15
    i = 0
    bits = []
    coded = [b"", b"", b""]
    while i < len(data):
        j = 3  # At least 2 bytes are needed to encode a match, so we match only 3 bytes or more.
        longest_match = None
        while True:
            window_base = max(0, i - window)
            window_data = data[window_base : i + j - 1]
            m = window_data.rfind(data[i : i + j])
            if m == -1 or i + j > len(data):
                break

            o, l = i - (window_base + m), j
            if o >= 2**15 or l >= 2**15:
                break

            longest_match = o, l
            j += 1

        if longest_match is not None:
            offset, length = longest_match
            offset_code = encode_15bit(offset)
            length_code = encode_15bit(length)
            if len(offset_code) + len(length_code) < length:
                coded[1] += offset_code
                coded[2] += length_code
                bits.append(1)
                i += length
            else:
                coded[0] += data[i].to_bytes(1, "little")
                bits.append(0)
                i += 1
        else:
            coded[0] += data[i].to_bytes(1, "little")
            bits.append(0)
            i += 1

    return bits, coded


def entropy(symbols):
    histogram = {}
    for symbol in symbols:
        histogram[symbol] = histogram.get(symbol, 0) + 1

    total = sum(histogram.values())
    p_values = [count / total for count in histogram.values()]

    return sum(-p * math.log2(p) for p in p_values)


def encode(lzss_model, allocation_size, model_type):
    commands, (literals, offsets, lengths) = lzss_model

    commands_size = len(commands)
    commands_bytes = math.ceil(commands_size / 8)
    literals_size = len(literals)
    offsets_size = len(offsets)
    lengths_size = len(lengths)
    total_bytes = literals_size + offsets_size + lengths_size + commands_bytes

    print(commands_size, "bits")
    print(literals_size, "bytes of literals")
    print(offsets_size, "bytes of offsets")
    print(lengths_size, "bytes of lengths")
    print(total_bytes, "bytes total")

    command_entropy_limit = entropy(commands) / 1  # 1 bit per command
    literal_entropy_limit = entropy(literals) / 8  # 8 bits per byte
    offset_entropy_limit = entropy(offsets) / 8  # 8 bits per byte
    length_entropy_limit = entropy(lengths) / 8  # 8 bits per byte

    min_command_bytes = command_entropy_limit * commands_bytes
    min_literal_bytes = literal_entropy_limit * literals_size
    min_offset_bytes = offset_entropy_limit * offsets_size
    min_length_bytes = length_entropy_limit * lengths_size

    minimum_bytes = (
        min_command_bytes + min_literal_bytes + min_offset_bytes + min_length_bytes
    )

    print(f"{command_entropy_limit:.4f} bits per command minimum")
    print(f"{literal_entropy_limit:.4f} bytes per literal minimum")
    print(f"{offset_entropy_limit:.4f} bytes per offset minimum")
    print(f"{length_entropy_limit:.4f} bytes per length minimum")

    encoder = ac.Encoder()
    command_model = model_type(2)
    literal_model = model_type(256)
    offset_model = model_type(256)
    length_model = model_type(256)

    a, b, c = 0, 0, 0
    encoder.encode_incremental(literal_model, allocation_size.to_bytes(4, "little"))
    encoder.encode_incremental(literal_model, len(commands).to_bytes(4, "little"))
    for bit in commands:
        encoder.encode_incremental(command_model, [bit])
        if bit == 0:
            encoder.encode_incremental(literal_model, literals[a : a + 1])
            a += 1
        else:
            if offsets[b] & 0x80 == 0:
                encoder.encode_incremental(offset_model, offsets[b : b + 1])
                b += 1
            else:
                encoder.encode_incremental(offset_model, offsets[b : b + 2])
                b += 2

            if lengths[c] & 0x80 == 0:
                encoder.encode_incremental(length_model, lengths[c : c + 1])
                c += 1
            else:
                encoder.encode_incremental(length_model, lengths[c : c + 2])
                c += 2

    assert a == len(literals)
    assert b == len(offsets)
    assert c == len(lengths)
    coded = encoder.finalize()

    print(len(coded), "bytes compressed")
    print(f"{100 * (len(coded) / minimum_bytes - 1):.2f}% adaptive coding overhead")

    return coded


def decode_15bit(data):
    leader = data[0]
    if leader < 0x80:
        return leader
    else:
        hi = leader & 0x7F
        lo = data[1]
        return (hi << 8) | lo


def decode(encoded, model_type):
    decoder = ac.Decoder(encoded)
    command_model = model_type(2)
    literal_model = model_type(256)
    offset_model = model_type(256)
    length_model = model_type(256)

    _ = int.from_bytes(bytes(decoder.decode_incremental(literal_model, 4)), "little")
    n_commands = int.from_bytes(
        bytes(decoder.decode_incremental(literal_model, 4)), "little"
    )

    decompressed = b""
    for _ in range(n_commands):
        bit = decoder.decode_incremental(command_model, 1)[0]
        if bit == 0:
            literal = bytes(decoder.decode_incremental(literal_model, 1))
            decompressed += literal
        else:
            offset = decoder.decode_incremental(offset_model, 1)
            if offset[0] & 0x80 != 0:
                offset += decoder.decode_incremental(offset_model, 1)

            length = decoder.decode_incremental(length_model, 1)
            if length[0] & 0x80 != 0:
                length += decoder.decode_incremental(length_model, 1)

            offset = decode_15bit(offset)
            length = decode_15bit(length)

            # This is necessary to do this even kind of efficiently in python, but the assembly language version can
            # just use byte-by-byte copies.
            if offset > length:
                decompressed += decompressed[-offset : -(offset - length)]
            else:
                while length > 0:
                    if offset <= length:
                        decompressed += decompressed[-offset:]
                    else:
                        decompressed += decompressed[-offset : -(offset - length)]

                    length -= offset

    return decompressed


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("pack", "unpack"):
        print("Usage: bitweaver.py <pack|unpack> <input> <output>")
        sys.exit(1)

    with open(sys.argv[2], "rb") as f:
        data = f.read()

    model_type = ac.GlobalAdaptiveModel

    if sys.argv[1] == "pack":
        lzss_model = bake_lzss_model(data)
        encoded = encode(lzss_model, len(data), model_type)
        print(
            f"Final compression ratio: {100 * len(encoded) / len(data) :.2f}% ({model_type.__name__})"
        )
        decoded = decode(encoded, model_type)
        if decoded != data:
            print("Stream corruption detected!")
            sys.exit(1)

        with open(sys.argv[3], "wb") as f:
            f.write(encoded)
    elif sys.argv[1] == "unpack":
        decoded = decode(data, model_type)
        with open(sys.argv[3], "wb") as f:
            f.write(decoded)
