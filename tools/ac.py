import sys
import math
from collections import defaultdict
from typing import *

UPPER8 = ((1 << 8) - 1) << (64 - 8)
TAIL8 = UPPER8 >> 8
BITS64 = (1 << 64) - 1


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


class MarkovNode:
    def __init__(self):
        self.histogram = [1] * 2
        self.total = 2
        self.children = [None, None]
        self.tag = None
        self.mispredictions = 0


class MarkovChainModel:
    def __init__(self, node: MarkovNode):
        self.node = node
        self.named_parent = node
        self.already_missed = False

    def pvalue(self, symbol):
        return divide(self.node.histogram[symbol], self.node.total)

    def update(self, symbol):
        self.node.histogram[symbol] += 1
        self.node.total += 1
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
        self.pending = 0
        self.leader = 0
        self.input_count = 0

    def encode(self, model, data):
        assert model.range() == 2
        self.input_count += len(data)

        for byte in data:
            interval_width = subtract(self.b, self.a)
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

            while (self.a ^ self.b) & UPPER8 == 0:
                # 8 bits have been locked in
                flush_pending = self.pending > 0
                to_code = shr(self.a, 64 - 8)
                self.encoded += to_code.to_bytes(1, "little")
                self.a = shl(self.a, 8)
                self.b = shl(self.b, 8)
                self.b |= (1 << 8) - 1
                if flush_pending:
                    filler = 0xFF if to_code == self.leader else 0x00
                    self.encoded += filler.to_bytes(1, "little") * self.pending
                    self.pending = 0

            model.update(byte)

            a_top = shr(self.a, 64 - 8)
            b_top = shr(self.b, 64 - 8)
            if b_top - a_top == 1:
                while True:
                    a_tail = shr(self.a & TAIL8, 48)
                    b_tail = shr(self.b & TAIL8, 48)
                    if a_tail == 0xFF and b_tail == 0x00:
                        self.leader = a_top
                        # How to understand this check:
                        # Think of the interval (0.799..., 0.8000...) in decimal.
                        # The interval may still shrink arbitrarily without ever actually locking in any digits
                        self.a = shl(self.a, 8)
                        self.b = shl(self.b, 8)
                        self.b |= (1 << 8) - 1
                        self.pending += 1
                        self.a &= ~UPPER8
                        self.b &= ~UPPER8
                        self.a |= shl(a_top, 64 - 8)
                        self.b |= shl(b_top, 64 - 8)
                    else:
                        break

    def end_stream(self):
        flush_pending = self.pending > 0
        self.a = add(self.a, 1 << (64 - 8))  # The decoder semantics use open intervals
        to_code = shr(self.a, (64 - 8))
        self.encoded += to_code.to_bytes(1, "little")
        if flush_pending:
            filler = 0xFF if to_code == self.leader else 0x00
            self.encoded += filler.to_bytes(1, "little") * self.pending
            self.pending = 0

        return self.encoded


class Decoder:
    def __init__(self, encoded):
        self.bitgroups = [byte for byte in encoded]
        self.a = 0
        self.b = (1 << 64) - 1
        self.window = 0
        self.i = 0

    def decode(self, model, expected_length):
        decoded = []
        while self.i < 8:
            self.window = shl(self.window, 8) | (
                self.bitgroups[self.i] if self.i < len(self.bitgroups) else 0
            )

            self.i += 1

        while len(decoded) < expected_length:
            interval_width = subtract(self.b, self.a)
            byte = None
            for j in range(model.range()):
                subinterval_width = multiply(interval_width, model.pvalue(j))
                next_a = add(self.a, subinterval_width)
                if next_a > self.window:
                    self.b = next_a
                    byte = j
                    break

                self.a = next_a

            while (self.a ^ self.b) & UPPER8 == 0:
                # 8 bits have been locked in
                self.a = shl(self.a, 8)
                self.b = shl(self.b, 8)
                self.b |= (1 << 8) - 1
                self.shift_window()

            decoded += [byte]
            model.update(byte)

            a_top = shr(self.a, 64 - 8)
            b_top = shr(self.b, 64 - 8)
            if b_top - a_top == 1:
                while True:
                    a_tail = shr(self.a & TAIL8, 48)
                    b_tail = shr(self.b & TAIL8, 48)
                    if a_tail == 0xFF and b_tail == 0x00:
                        # How to understand this check:
                        # Think of the interval (0.799..., 0.8000...) in decimal.
                        # The interval may still shrink arbitrarily without ever actually locking in any digits
                        self.a = shl(self.a, 8)
                        self.a &= ~UPPER8
                        self.a |= shl(a_top, 64 - 8)

                        self.b = shl(self.b, 8)
                        self.b &= ~UPPER8
                        self.b |= shl(b_top, 64 - 8)

                        self.b |= (1 << 8) - 1

                        window_top = shr(self.window, 64 - 8)
                        self.shift_window()
                        self.window &= ~UPPER8
                        self.window |= shl(window_top, 64 - 8)
                    else:
                        break

        return decoded

    def shift_window(self):
        self.window = shl(self.window, 8) | (
            self.bitgroups[self.i] if self.i < len(self.bitgroups) else 0
        )

        self.i += 1
