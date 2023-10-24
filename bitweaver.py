import sys
import ac


def encode_15bit(n):
    assert 0 <= n < 2**15
    if n < 0x80:
        return n.to_bytes(1, "little")
    else:
        hi = n >> 8
        lo = n & 0xFF
        return (0x80 | hi).to_bytes(1, "little") + lo.to_bytes(1, "little")


def encode(data, allocation_size):
    encoder = ac.Encoder()
    command_model = ac.HowardVitterModel(2)
    literal_model = ac.HowardVitterTreeModel(256)
    offset_model = ac.GlobalAdaptiveModel(256)
    length_model = ac.GlobalAdaptiveModel(256)
    alt_offset_model = ac.GlobalAdaptiveModel(256)
    alt_length_model = ac.GlobalAdaptiveModel(256)

    expected_bytes = len(data)
    encoder.encode(literal_model, allocation_size.to_bytes(4, "little"))
    encoder.encode(literal_model, expected_bytes.to_bytes(4, "little"))

    window = 2**15 - 1
    i = 0
    while i < len(data):
        # At least 2 bytes are needed to encode a match, so we match only 3 bytes or more.
        j = 3
        longest_match = None
        while True:
            if i + j > len(data):
                break

            window_base = max(0, i - window)
            window_data = data[window_base : i + j - 1]
            m = window_data.rfind(data[i : i + j])
            if m == -1:
                break

            o, l = i - (window_base + m), j
            longest_match = o, l
            j += 1

        if longest_match is not None:
            offset, length = longest_match
            offset_code = encode_15bit(offset)
            length_code = encode_15bit(length)
            if len(offset_code) + len(length_code) < length:
                encoder.encode(command_model, [1])
                encoder.encode(offset_model, offset_code[:1])
                if len(offset_code) > 1:
                    encoder.encode(alt_offset_model, offset_code[1:])

                encoder.encode(length_model, length_code[:1])
                if len(length_code) > 1:
                    encoder.encode(alt_length_model, length_code[1:])

                i += length
            else:
                encoder.encode(command_model, [0])
                encoder.encode(literal_model, data[i : i + 1])
                i += 1
        else:
            encoder.encode(command_model, [0])
            encoder.encode(literal_model, data[i : i + 1])
            i += 1

    coded = encoder.end_stream()
    print(len(coded), "bytes compressed", sep="\t")

    return coded


def decode_15bit(data):
    leader = data[0]
    if leader < 0x80:
        return leader
    else:
        hi = leader & 0x7F
        lo = data[1]
        return (hi << 8) | lo


def decode(encoded):
    decoder = ac.Decoder(encoded)
    command_model = ac.HowardVitterModel(2)
    literal_model = ac.HowardVitterTreeModel(256)
    offset_model = ac.GlobalAdaptiveModel(256)
    length_model = ac.GlobalAdaptiveModel(256)
    alt_offset_model = ac.GlobalAdaptiveModel(256)
    alt_length_model = ac.GlobalAdaptiveModel(256)

    _ = int.from_bytes(bytes(decoder.decode(literal_model, 4)), "little")
    expected_bytes = int.from_bytes(
        bytes(decoder.decode(literal_model, 4)), "little"
    )

    decompressed = b""
    while len(decompressed) < expected_bytes:
        bit = decoder.decode(command_model, 1)[0]
        if bit == 0:
            literal = bytes(decoder.decode(literal_model, 1))
            decompressed += literal
        else:
            offset = decoder.decode(offset_model, 1)
            if offset[0] & 0x80 != 0:
                offset += decoder.decode(alt_offset_model, 1)

            length = decoder.decode(length_model, 1)
            if length[0] & 0x80 != 0:
                length += decoder.decode(alt_length_model, 1)

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


def get_size(data):
    bss_size = 0
    bss_size = int.from_bytes(data[0:8], "little")
    if bss_size > 2**32:  # We're probably dealing with a non-image
        bss_size = 0

    print(bss_size, "extra bytes of BSS", sep="\t")

    return len(data) + bss_size


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("pack", "unpack"):
        print("Usage: bitweaver.py <pack|unpack> <input> <output>")
        sys.exit(1)

    with open(sys.argv[2], "rb") as f:
        data = f.read()

    if sys.argv[1] == "pack":
        full_size = get_size(data)
        encoded = encode(data, full_size)
        print(f"{100 * len(encoded) / len(data) :.2f}%\tcompression ratio")
        decoded = decode(encoded)
        if decoded != data:
            print("Stream corruption detected!")
            sys.exit(1)

        with open(sys.argv[3], "wb") as f:
            f.write(encoded)
    elif sys.argv[1] == "unpack":
        decoded = decode(data)
        with open(sys.argv[3], "wb") as f:
            f.write(decoded)
