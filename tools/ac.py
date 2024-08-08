import sys
import math
from typing import List

UPPER1 = ((1 << 1) - 1) << (64 - 1)
TAIL1 = UPPER1 >> 1
BITS64 = (1 << 64) - 1

# Do we have any overflow issues?


def divide(a, b):
    a <<= 64
    a //= b
    return a & BITS64


def multiply(a, b):
    a *= b
    a >>= 64
    return a & BITS64


def add(a, b):
    return (a + b) & BITS64


def subtract(a, b):
    return (a - b) & BITS64


def shl(a, n):
    return (a << n) & BITS64


def shr(a, n):
    return (a >> n) & BITS64


def nlog2(n):
    return 64 - math.log2(n)


def entropy(symbols):
    histogram = {}
    for symbol in symbols:
        histogram[symbol] = histogram.get(symbol, 0) + 1

    total = sum(histogram.values())
    p_values = [count / total for count in histogram.values()]

    return sum(-p * math.log2(p) for p in p_values)


class GlobalAdaptiveModel:
    def __init__(self, n_symbols):
        assert (
            n_symbols > 0 and n_symbols <= 256
        )  # 64 bits of p-value per symbol makes larger models impractical
        self.total = n_symbols
        self.histogram = [1] * n_symbols

    def pvalue(self, symbol):
        return divide(self.histogram[symbol], self.total)

    def update(self, symbol):
        self.histogram[symbol] += 1
        self.total += 1

    def range(self):
        return len(self.histogram)


# TODO: check precision guarantees (0x4cfffff..., 0x4d01000000...) seems to me the smallest possible interval width
# (2^48 + 1)


class MarkovNode:
    def __init__(self):
        self.model = GlobalAdaptiveModel(2)
        self.children = [None, None]
        self.tag = None


class MarkovChainModel:
    def __init__(self, node: MarkovNode):
        self.node = node

    def pvalue(self, symbol):
        return self.node.model.pvalue(symbol)

    def update(self, symbol):
        self.node.model.update(symbol)
        self.node = self.node.children[symbol]

    def range(self):
        return 2


def build_markov_bitstring(end: MarkovNode, n: int) -> MarkovNode:
    if n == 0:
        return end
    else:
        node = MarkovNode()
        node.children[0] = build_markov_bitstring(end, n - 1)
        node.children[1] = build_markov_bitstring(end, n - 1)
        return node


def markov_join(node: MarkovNode, other: MarkovNode):
    joined = MarkovNode()
    joined.children[0] = node
    joined.children[1] = other
    return joined


def build_markov_chain() -> MarkovNode:
    root = MarkovNode()
    root.tag = "root"
    short_length_model = build_markov_bitstring(root, 7)
    short_length_model.tag = "short_length"
    ext_length_model = build_markov_bitstring(short_length_model, 8)
    ext_length_model.tag = "ext_length"
    length_model = markov_join(short_length_model, ext_length_model)
    length_model.tag = "length"

    short_offset_model = build_markov_bitstring(length_model, 7)
    short_offset_model.tag = "short_offset"
    ext_offset_model = build_markov_bitstring(short_offset_model, 8)
    ext_offset_model.tag = "ext_offset"
    offset_model = markov_join(short_offset_model, ext_offset_model)
    offset_model.tag = "offset"

    literal_model = build_markov_bitstring(root, 8)
    literal_model.tag = "literal"
    root.children[0] = literal_model
    root.children[1] = offset_model

    return root


def build_markov_loop(n: int) -> MarkovNode:
    root = MarkovNode()
    root.tag = "root"
    root.children[0] = build_markov_bitstring(root, n - 1)
    root.children[1] = build_markov_bitstring(root, n - 1)
    return root


class Encoder:
    def __init__(self) -> None:
        self.a = 0
        self.b = (1 << 64) - 1
        self.encoded = b""
        self.next_byte: List[int] = []
        self.pending = 0
        self.leader = 0
        self.log = open("encode.log", "w")

    def shift_out(self, bits: List[int]):
        self.next_byte += bits
        while len(self.next_byte) >= 8:
            code_bits, self.next_byte = self.next_byte[:8], self.next_byte[8:]
            code = 0
            for bit in code_bits:
                code = (code << 1) | bit

            self.encoded += code.to_bytes(1, "little")

    def encode(self, model, data):
        for byte in data:
            interval_width = subtract(self.b, self.a)
            print(self.a, self.b, file=self.log)
            for i in range(model.range()):
                p = model.pvalue(i)
                subinterval_width = multiply(interval_width, p)
                if subinterval_width == 0:
                    print("Zero-width interval")

                new_a = add(self.a, subinterval_width)
                if byte == i:
                    if new_a > self.b:
                        print("Invariant broken")
                        sys.exit(1)

                    self.b = new_a
                    break
                else:
                    self.a = new_a

            # print(f"a({self.a:064b}, {self.b:064b})", file=self.log)
            while (self.a ^ self.b) & UPPER1 == 0:
                # 1 bits have been locked in
                flush_pending = self.pending > 0
                to_code = shr(self.a, 64 - 1)
                self.shift_out([to_code])
                self.a = shl(self.a, 1)
                self.b = shl(self.b, 1)
                self.b |= (1 << 1) - 1
                # print(f"b({self.a:064b}, {self.b:064b})", file=self.log)
                if flush_pending:
                    filler = 1 if to_code == self.leader else 0
                    self.shift_out([filler] * self.pending)
                    self.pending = 0

            print(
                f"[{model.node.model.histogram[0]}, {model.node.model.histogram[1]}, {model.node.model.total}], {byte}",
                file=self.log,
            )
            model.update(byte)
            # print(f"c({byte})", file=self.log)

            a_top = shr(self.a, 64 - 1)
            b_top = shr(self.b, 64 - 1)
            if b_top - a_top == 1:
                while True:
                    a_tail = shr(self.a & TAIL1, 62)
                    b_tail = shr(self.b & TAIL1, 62)
                    if a_tail == 0b1 and b_tail == 0b0:
                        # print(f"*({self.a:064b}, {self.b:064b})", file=self.log)
                        self.leader = a_top
                        # How to understand this check:
                        # Think of the interval (0.799..., 0.8000...) in decimal.
                        # The interval may still shrink arbitrarily without ever actually locking in any digits
                        self.a = shl(self.a, 1)
                        self.b = shl(self.b, 1)
                        self.b |= (1 << 1) - 1
                        self.pending += 1
                        self.a &= ~UPPER1
                        self.b &= ~UPPER1
                        self.a |= shl(a_top, 64 - 1)
                        self.b |= shl(b_top, 64 - 1)
                    else:
                        break

    def end_stream(self):
        flush_pending = self.pending > 0
        self.a = add(self.a, 1 << (64 - 1))  # The decoder semantics use open intervals
        to_code = shr(self.a, (64 - 1))
        self.shift_out([to_code])
        if flush_pending:
            filler = 1 if to_code == self.leader else 0
            self.shift_out([filler] * self.pending)
            self.pending = 0

        n_pad = (8 - (len(self.encoded) % 8)) % 8
        self.shift_out([0] * n_pad)

        return self.encoded


class Decoder:
    def __init__(self, encoded: bytes):
        self.bitgroups = [byte for byte in encoded]
        self.a = 0
        self.b = (1 << 64) - 1
        self.window = 0
        self.i = 0
        self.next_byte: List[int] = []
        self.log = open("decode.log", "w")

    def decode(self, model, expected_length):
        decoded = []
        while self.i < 8:
            self.window = shl(self.window, 8) | (
                self.bitgroups[self.i] if self.i < len(self.bitgroups) else 0
            )

            self.i += 1

        while len(decoded) < expected_length:
            interval_width = subtract(self.b, self.a)
            print(self.a, self.b, file=self.log)
            byte = None
            for j in range(model.range()):
                subinterval_width = multiply(interval_width, model.pvalue(j))
                next_a = add(self.a, subinterval_width)
                if next_a > self.window:
                    self.b = next_a
                    byte = j
                    break

                self.a = next_a

            # print(f"a({self.a:064b}, {self.b:064b})", file=self.log)
            while (self.a ^ self.b) & UPPER1 == 0:
                # 1 bits have been locked in
                self.a = shl(self.a, 1)
                self.b = shl(self.b, 1)
                self.b |= (1 << 1) - 1
                # print(f"b({self.a:064b}, {self.b:064b})", file=self.log)
                self.shift_window()

            decoded += [byte]
            # print(f"c({byte})", file=self.log)
            print(
                f"[{model.node.model.histogram[0]}, {model.node.model.histogram[1]}, {model.node.model.total}], {byte}",
                file=self.log,
            )
            model.update(byte)

            a_top = shr(self.a, 64 - 1)
            b_top = shr(self.b, 64 - 1)
            if b_top - a_top == 1:
                while True:
                    a_tail = shr(self.a & TAIL1, 62)
                    b_tail = shr(self.b & TAIL1, 62)
                    if a_tail == 0b1 and b_tail == 0b0:
                        # print(f"*({self.a:064b}, {self.b:064b})", file=self.log)
                        # How to understand this check:
                        # Think of the interval (0.799..., 0.8000...) in decimal.
                        # The interval may still shrink arbitrarily without ever actually locking in any digits
                        self.a = shl(self.a, 1)
                        self.a &= ~UPPER1
                        self.a |= shl(a_top, 64 - 1)

                        self.b = shl(self.b, 1)
                        self.b &= ~UPPER1
                        self.b |= shl(b_top, 64 - 1)

                        self.b |= (1 << 1) - 1

                        window_top = shr(self.window, 64 - 1)
                        self.shift_window()
                        self.window &= ~UPPER1
                        self.window |= shl(window_top, 64 - 1)
                    else:
                        break

        return decoded

    def shift_window(self):
        if len(self.next_byte) == 0:
            byte = self.bitgroups[self.i] if self.i < len(self.bitgroups) else 0
            self.i += 1
            self.next_byte = [(byte >> (7 - i)) & 1 for i in range(8)]

        next_bit = self.next_byte.pop()
        self.window = shl(self.window, 1) | next_bit
