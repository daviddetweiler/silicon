import enum
import json


def main():
    makes = ['make_thread', 'make_variable', 'make_constant', 'make_code_word']
    stripped = filter(lambda line: len(line), (line.split() for line in open(
        'silicon.asm').readlines()))

    filtered = list(filter(lambda line: (
        line[0] in makes or line[0] == 'make_header') and line[1] != 'macro', stripped))

    words = list(filter(lambda line: line[0] != 'make_header', filtered))

    count_map = {}
    word_map = {'count': 0, 'counts': count_map}
    for make in makes:
        word_map[make[5:]] = []
        count_map[make[5:]] = 0

    for make, word in words:
        word_map[make[5:]].append(word)
        count_map[make[5:]] += 1
        word_map['count'] += 1

    header_map = {'count': 0}
    for n, line in enumerate(filtered):
        if line[0] == 'make_header':
            header_map[line[1][1:-1]] = filtered[n + 1][1]
            header_map['count'] += 1

    source_map = {'headers': header_map, 'words': word_map}
    json.dump(source_map, open('words.json', 'w'))


if __name__ == '__main__':
    main()
