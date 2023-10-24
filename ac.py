import sys
import math

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


class AdaptiveMarkovModel:
    def __init__(self, n_symbols):
        assert n_symbols > 0 and n_symbols <= 256
        self.totals = [n_symbols] * n_symbols
        self.histograms = [[1] * n_symbols for _ in range(n_symbols)]
        self.context = 0
        self.fallback = GlobalAdaptiveModel(n_symbols)

    def pvalue(self, symbol):
        return divide(self.histograms[self.context][symbol], self.totals[self.context])

    def update(self, symbol):
        self.histograms[self.context][symbol] += 1
        self.totals[self.context] += 1
        self.context = symbol
        self.fallback.update(symbol)

    def range(self):
        return len(self.histograms[self.context])


class Encoder:
    def __init__(self) -> None:
        self.a = 0
        self.b = (1 << 64) - 1
        self.encoded = b""

    def encode_incremental(self, model, data):
        for byte in data:
            interval_width = subtract(self.b, self.a)
            for i in range(model.range()):
                subinterval_width = multiply(interval_width, model.pvalue(i))
                if byte == i:
                    self.b = add(self.a, subinterval_width)
                    break
                else:
                    self.a = add(self.a, subinterval_width)

            while (self.a ^ self.b) & UPPER8 == 0:
                # 8 bits have been locked in
                to_code = shr(self.a, 64 - 8)
                self.encoded += to_code.to_bytes(1, "little")
                self.a = shl(self.a, 8)
                self.b = shl(self.b, 8)
                self.b |= (1 << 8) - 1

            a_top = shr(self.a, 64 - 8)
            b_top = shr(self.b, 64 - 8)
            if b_top - a_top == 1:
                a_tail = shr(self.a & TAIL8, 48)
                b_tail = shr(self.b & TAIL8, 48)
                if a_tail == 0xFF and b_tail == 0x00:
                    # How to understand this check:
                    # Think of the interval (0.799..., 0.8000...) in decimal.
                    # The interval may still shrink arbitrarily without ever actually locking in any digits
                    print("Near-convergence detected!", subtract(self.b, self.a))

            model.update(byte)

    def finalize(self):
        self.a = add(self.a, 1 << (64 - 8))  # The decoder semantics use open intervals
        to_code = shr(self.a, (64 - 8))
        self.encoded += to_code.to_bytes(1, "little")
        return self.encoded


class Decoder:
    def __init__(self, encoded):
        self.bitgroups = [byte for byte in encoded]
        self.a = 0
        self.b = (1 << 64) - 1
        self.window = 0
        self.i = 0

    def decode_incremental(self, model, expected_length):
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
                self.window = shl(self.window, 8) | (
                    self.bitgroups[self.i] if self.i < len(self.bitgroups) else 0
                )
                self.i += 1

            decoded += [byte]
            model.update(byte)

        return decoded


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("pack", "unpack"):
        print("Usage: ac.py <pack|unpack> <input> <output>")
        sys.exit(1)

    with open(sys.argv[2], "rb") as f:
        data = f.read()

    if sys.argv[1] == "pack":
        e = entropy(data)
        print(f"{e:.2f}\tbits of entropy per byte")
        print(f"{100 * e / 8 :.2f}%\toptimal compression ratio")
        min_size = math.ceil((e / 8) * len(data))

        encoder = Encoder()
        encoder.encode_incremental(GlobalAdaptiveModel(256), data)
        encoded = encoder.finalize()

        decoder = Decoder(encoded)
        decoded = decoder.decode_incremental(GlobalAdaptiveModel(256), len(data))
        if decoded != list(data):
            print("Stream corruption detected!")
            sys.exit(1)

        print(len(encoded), "compressed size", sep="\t")
        print(f"{100 * len(encoded) / len(data):.2f}%\tcompression ratio")
        print(
            f"{100 * (len(encoded) - min_size) / min_size:.2f}%\tadaptive coding overhead"
        )
        with open(sys.argv[3], "wb") as f:
            f.write(encoded)
    elif sys.argv[1] == "unpack":
        decoder = Decoder(data)
        decoded = decoder.decode_incremental(GlobalAdaptiveModel(256), len(data))
        with open(sys.argv[3], "wb") as f:
            f.write(decoded)
