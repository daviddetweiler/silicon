import sys
import ac
import math
from typing import *

HV_CONFIG = {
    "control": ac.HowardVitterModel,
    "literal": ac.HowardVitterTreeModel,
    "offset": ac.HowardVitterTreeModel,
    "length": ac.HowardVitterTreeModel,
    "alt_offset": ac.HowardVitterTreeModel,
    "alt_length": ac.HowardVitterTreeModel,
}

DEFAULT_CONFIG = {
    "control": ac.AdaptiveMarkovModel,
    "literal": ac.GlobalAdaptiveModel,
    "offset": ac.GlobalAdaptiveModel,
    "length": ac.GlobalAdaptiveModel,
    "alt_offset": ac.GlobalAdaptiveModel,
    "alt_length": ac.GlobalAdaptiveModel,
}

CONFIGS = {
    "hv": HV_CONFIG,
    "default": DEFAULT_CONFIG,
}

CONFIG = CONFIGS["default"]


def encode_15bit(n: int) -> Tuple[int, int, int]:
    assert 0 <= n < 2**15
    if n < 0x80:
        return 0, n, 0
    else:
        hi = n >> 7
        lo = n & 0x7F
        return 1, lo, hi


def encode(data: bytes, allocation_size: int) -> bytes:
    encoder = ac.Encoder()
    command_model = CONFIG["control"](2)
    literal_model = CONFIG["literal"](256)
    octl_model = ac.AdaptiveMarkovModel(2)
    offset_model = CONFIG["offset"](128)
    alt_offset_model = CONFIG["alt_offset"](256)
    lctl_model = ac.AdaptiveMarkovModel(2)
    length_model = CONFIG["length"](128)
    alt_length_model = CONFIG["alt_length"](256)

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
            octl, olo, ohi = encode_15bit(offset)
            lctl, llo, lhi = encode_15bit(length)
            if (octl + 1) + (lctl + 1) < length:
                encoder.encode(command_model, [1])
                encoder.encode(octl_model, [octl])
                encoder.encode(offset_model, [olo])
                if octl == 1:
                    encoder.encode(alt_offset_model, [ohi])

                encoder.encode(lctl_model, [lctl])
                encoder.encode(length_model, [llo])
                if lctl == 1:
                    encoder.encode(alt_length_model, [lhi])

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


def decode_15bit(data: bytes) -> int:
    leader = data[0]
    if leader < 0x80:
        return leader
    else:
        hi = leader & 0x7F
        lo = data[1]
        return (hi << 8) | lo


def decode(encoded: bytes) -> bytes:
    decoder = ac.Decoder(encoded)
    command_model = CONFIG["control"](2)
    literal_model = CONFIG["literal"](256)
    octl_model = ac.AdaptiveMarkovModel(2)
    offset_model = CONFIG["offset"](128)
    alt_offset_model = CONFIG["alt_offset"](256)
    lctl_model = ac.AdaptiveMarkovModel(2)
    length_model = CONFIG["length"](128)
    alt_length_model = CONFIG["alt_length"](256)

    _ = int.from_bytes(bytes(decoder.decode(literal_model, 4)), "little")
    expected_bytes = int.from_bytes(bytes(decoder.decode(literal_model, 4)), "little")

    decompressed = b""
    while len(decompressed) < expected_bytes:
        bit = decoder.decode(command_model, 1)[0]
        if bit == 0:
            literal = bytes(decoder.decode(literal_model, 1))
            decompressed += literal
        else:
            octl = decoder.decode(octl_model, 1)[0]
            olo = decoder.decode(offset_model, 1)[0]
            if octl == 1:
                ohi = decoder.decode(alt_offset_model, 1)[0]
                olo = (ohi << 7) | olo

            lctl = decoder.decode(lctl_model, 1)[0]
            llo = decoder.decode(length_model, 1)[0]
            if lctl == 1:
                lhi = decoder.decode(alt_length_model, 1)[0]
                llo = (lhi << 7) | llo

            offset = olo
            length = llo

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


def get_size(data: bytes) -> int:
    bss_size = 0
    bss_size = int.from_bytes(data[0:8], "little")
    if bss_size > 2**32:  # We're probably dealing with a non-image
        bss_size = 0

    print(bss_size, "extra bytes of BSS", sep="\t")

    return len(data) + bss_size


def info(data: bytes) -> None:
    decoder = ac.Decoder(data)
    command_model = CONFIG["control"](2)
    literal_model = CONFIG["literal"](256)
    offset_model = CONFIG["offset"](256)
    length_model = CONFIG["length"](256)
    alt_offset_model = CONFIG["alt_offset"](256)
    alt_length_model = CONFIG["alt_length"](256)

    allocation_size = int.from_bytes(bytes(decoder.decode(literal_model, 4)), "little")

    expected_bytes = int.from_bytes(bytes(decoder.decode(literal_model, 4)), "little")

    print(allocation_size, "bytes allocated", sep="\t")
    print(expected_bytes, "bytes expected", sep="\t")

    bytes_counted = 0
    control_bit_count = 0
    literal_byte_count = 0
    offset_byte_count = 0
    length_byte_count = 0
    pair_count = 0
    extended_offset_count = 0
    extended_length_count = 0
    while bytes_counted < expected_bytes:
        bit = decoder.decode(command_model, 1)[0]
        control_bit_count += 1
        if bit == 0:
            decoder.decode(literal_model, 1)
            literal_byte_count += 1
            bytes_counted += 1
        else:
            pair_count += 1
            b = decoder.decode(offset_model, 1)
            offset_byte_count += 1
            if b[0] & 0x80 != 0:
                decoder.decode(alt_offset_model, 1)
                offset_byte_count += 1
                extended_offset_count += 1

            b = decoder.decode(length_model, 1)
            length_byte_count += 1
            if b[0] & 0x80 != 0:
                b += decoder.decode(alt_length_model, 1)
                length_byte_count += 1
                extended_length_count += 1

            bytes_counted += decode_15bit(b)

    print(control_bit_count, "control bits", sep="\t")
    print(literal_byte_count, "literal bytes", sep="\t")
    print(offset_byte_count, "offset bytes", sep="\t")
    print(extended_offset_count, "extended offsets", sep="\t")
    print(length_byte_count, "length bytes", sep="\t")
    print(extended_length_count, "extended lengths", sep="\t")
    print(pair_count, "offset-length pairs", sep="\t")

    uncoded_length = (
        math.ceil(control_bit_count / 8)
        + literal_byte_count
        + offset_byte_count
        + length_byte_count
        + extended_offset_count
        + extended_length_count
    )

    print(uncoded_length, "bytes uncoded", sep="\t")
    print(f"{100 * len(data) / uncoded_length :.2f}%\tcoding ratio")
    print(f"{100 * uncoded_length / expected_bytes :.2f}%\tuncoded compression ratio")
    print(f"{100 * len(data) / expected_bytes :.2f}%\ttotal compression ratio")


if __name__ == "__main__":
    if sys.argv[1] not in ("pack", "unpack", "info"):
        print("Usage: bitweaver.py <pack|unpack|info> [...]")
        sys.exit(1)

    command = sys.argv[1]
    if command in ("pack", "unpack") and len(sys.argv) != 4:
        print("Usage: bitweaver.py <pack|unpack> <input> <output>")
        sys.exit(1)
    elif command == "info" and len(sys.argv) != 3:
        print("Usage: bitweaver.py info <input>")
        sys.exit(1)

    with open(sys.argv[2], "rb") as rf:
        data = rf.read()

    if command == "pack":
        full_size = get_size(data)
        encoded = encode(data, full_size)
        print(f"{100 * len(encoded) / len(data) :.2f}%\tcompression ratio")
        decoded = decode(encoded)
        if decoded != data:
            print("Stream corruption detected!")
            sys.exit(1)

        with open(sys.argv[3], "wb") as wf:
            wf.write(encoded)
    elif command == "unpack":
        decoded = decode(data)
        with open(sys.argv[3], "wb") as wf:
            wf.write(decoded)
    elif command == "info":
        info(data)
