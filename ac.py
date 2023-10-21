import sys
import math

UPPER8 = ((1 << 8) - 1) << (64 - 8)
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
        # At least 256 observations are required to use the model
        if self.totals[self.context] > 512:
            return divide(self.histograms[self.context][symbol], self.totals[self.context])
        else:
            return self.fallback.pvalue(symbol)

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
    if len(sys.argv) != 3:
        print("Usage: python3 ac.py <input> <output>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    encoder = Encoder()
    encoder.encode_incremental(GlobalAdaptiveModel(256), data)
    encoded = encoder.finalize()

    decoder = Decoder(encoded)
    decoded = decoder.decode_incremental(GlobalAdaptiveModel(256), len(data))
    assert decoded == list(data)

    print("Compressed size:", len(encoded))
    print("Compression ratio:", len(encoded) / len(data))
    with open(sys.argv[2], "wb") as f:
        f.write(encoded)
