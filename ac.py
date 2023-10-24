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
        self.context_models = [GlobalAdaptiveModel(n_symbols) for _ in range(n_symbols)]
        self.context = 0

    def pvalue(self, symbol):
        return self.context_models[self.context].pvalue(symbol)

    def update(self, symbol):
        self.context_models[self.context].update(symbol)
        self.context = symbol

    def range(self):
        return self.context_models[self.context].range()


class HowardVitterModel:
    def __init__(self, n_symbols):
        assert n_symbols == 2  # For debugging atm
        self.p_for_1 = divide(1, n_symbols)
        self.f = subtract(0, divide(1, 32))

    def pvalue(self, symbol):
        return self.p_for_1 if symbol == 1 else subtract(0, self.p_for_1)

    def update(self, symbol):
        if symbol == 0:
            self.p_for_1 = multiply(self.p_for_1, self.f)
        else:
            self.p_for_1 = add(multiply(self.p_for_1, self.f), subtract(0, self.f))

    def range(self):
        return 2


class Encoder:
    def __init__(self) -> None:
        self.a = 0
        self.b = (1 << 64) - 1
        self.encoded = b""

    def encode(self, model, data):
        for symbol in data:
            interval_width = subtract(self.b, self.a)
            for i in range(model.range()):
                subinterval_width = multiply(interval_width, model.pvalue(i))
                if symbol == i:
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

            model.update(symbol)

    def end_stream(self):
        self.a = add(self.a, 1 << (64 - 8))  # The decoder semantics use open intervals
        to_code = shr(self.a, (64 - 8))
        self.encoded += to_code.to_bytes(1, "little")
        return self.encoded


class Decoder:
    def __init__(self, encoded):
        self.bitgroups = [symbol for symbol in encoded]
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
            symbol = None
            for j in range(model.range()):
                subinterval_width = multiply(interval_width, model.pvalue(j))
                next_a = add(self.a, subinterval_width)
                if next_a > self.window:
                    self.b = next_a
                    symbol = j
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

            decoded += [symbol]
            model.update(symbol)

        return decoded


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("pack", "unpack"):
        print("Usage: ac.py <pack|unpack> <input> <output>")
        sys.exit(1)

    with open(sys.argv[2], "rb") as f:
        data = f.read()

    if sys.argv[1] == "pack":
        e = entropy(data)
        print(f"{e:.2f}\tbits of entropy per symbol")
        print(f"{100 * e / 8 :.2f}%\toptimal compression ratio")
        min_size = math.ceil((e / 8) * len(data))

        encoder = Encoder()
        encoder.encode(GlobalAdaptiveModel(256), data)
        encoded = encoder.end_stream()

        decoder = Decoder(encoded)
        decoded = decoder.decode(GlobalAdaptiveModel(256), len(data))
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
        decoded = decoder.decode(GlobalAdaptiveModel(256), len(data))
        with open(sys.argv[3], "wb") as f:
            f.write(decoded)
