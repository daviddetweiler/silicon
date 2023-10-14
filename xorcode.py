import sys
import binascii

def xorshift32(x):
    x ^= (x << 13) & 0xffffffff
    x ^= (x >> 17) & 0xffffffff
    x ^= (x << 5) & 0xffffffff
    return x

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python xorcode.py <filename> <destination> <chksum>")
        sys.exit(1)

    filename = sys.argv[1]
    with open(filename, "rb") as file:
        data = file.read()

    chksum = binascii.crc32(data)
    state = chksum
    words = [int.from_bytes(data[i:i+4], 'little') for i in range(0, len(data), 4)]
    for i in range(len(words)):
        words[i] ^= state
        state = xorshift32(state)

    data = b''.join([word.to_bytes(4, 'little') for word in words])

    with open(sys.argv[2], 'wb') as file:
        file.write(data)

    with open(sys.argv[3], 'w') as file:
        file.write(f'%define seed 0x{chksum:08x}')
