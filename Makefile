all: build debug-build zip Makefile

build: silicon.exe Makefile

debug-build: silicon-debug.exe Makefile

silicon.bin: silicon.asm Makefile
    pwsh -c "nasm -fbin silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o silicon.bin"

silicon.obj: silicon.asm Makefile
    pwsh -c "nasm -fwin64 silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o silicon.obj -g -Dstandalone"

lzss.bin: silicon.bin lzss.py Makefile
    python .\lzss.py silicon.bin lzss.bin

lzss.inc: lzss.bin textify.py Makefile
    python .\textify.py lzss.bin lzss.inc

load-lzss.bin: load-lzss.asm lzss.inc Makefile
    nasm -fbin load-lzss.asm -o load-lzss.bin

lzss-huff.bin: load-lzss.bin huffman.py Makefile
    python .\huffman.py load-lzss.bin lzss-huff.bin

lzss-huff.inc: lzss-huff.bin textify.py Makefile
    python .\textify.py lzss-huff.bin lzss-huff.inc

load-lzss-huff.obj: load-lzss-huff.asm lzss-huff.inc Makefile
    nasm -fwin64 load-lzss-huff.asm

silicon.exe: load-lzss-huff.obj Makefile
    link load-lzss-huff.obj kernel32.lib \
        /out:silicon.exe \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /ignore:4254 \
        /section:kernel,RE \
        /merge:.rdata=kernel \
        /merge:.text=kernel

silicon-debug.exe: silicon.obj Makefile
    link silicon.obj kernel32.lib \
        /out:silicon-debug.exe \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /ignore:4254 \
        /section:kernel,RE \
        /section:data,RW \
        /merge:.rdata=kernel \
        /merge:.text=kernel \
        /merge:.bss=data \
        /debug

clean: Makefile
    del *.obj *.exe *.pdb *.ilk *.zip *.bin *.log *.inc README.txt

zip: silicon.zip Makefile

silicon.zip: silicon.exe Makefile
    echo Verify the hash of silicon.exe using this powershell command > README.txt
    echo Get-FileHash -Algorithm SHA256 silicon.exe >> README.txt
    echo. >> README.txt
    pwsh -c "(Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "Compress-Archive -Force -Path silicon.exe,README.txt,init.si -DestinationPath silicon.zip"
