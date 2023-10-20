all: build debug-build zip Makefile

build: silicon.exe Makefile

debug-build: silicon-debug.exe Makefile

silicon.bin: silicon.asm Makefile
    pwsh -c "nasm -fbin silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o silicon.bin"

silicon.obj: silicon.asm Makefile
    pwsh -c "nasm -fwin64 silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o silicon.obj -g -Dstandalone"

silicon.bin.lzss: silicon.bin lzss.py Makefile
    python .\lzss.py silicon.bin silicon.bin.lzss

lzss.inc: silicon.bin.lzss inc.py Makefile
    python .\inc.py silicon.bin.lzss lzss.inc

lzss.bin: lzss.asm lzss.inc Makefile
    nasm -fbin lzss.asm -o lzss.bin

lzss.bin.hf: lzss.bin hf.py Makefile
    python .\hf.py lzss.bin lzss.bin.hf

hf.inc: lzss.bin.hf inc.py Makefile
    python .\inc.py lzss.bin.hf hf.inc

hf.bin: hf.asm hf.inc Makefile
    nasm -fbin hf.asm -o hf.bin

hf.bin.xsh32 seed.inc: hf.bin xsh32.py Makefile
    python .\xsh32.py hf.bin hf.bin.xsh32 seed.inc

xsh32.inc: hf.bin.xsh32 inc.py Makefile
    python .\inc.py hf.bin.xsh32 xsh32.inc

xsh32.obj: xsh32.asm xsh32.inc seed.inc Makefile
    nasm -fwin64 xsh32.asm

silicon.exe: xsh32.obj Makefile
    link xsh32.obj kernel32.lib \
        /out:silicon.exe \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /ignore:4254 \
        /section:kernel,RWE \
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
        /section:data,RWE \
        /merge:.rdata=kernel \
        /merge:.text=kernel \
        /merge:.bss=data \
        /debug

clean: Makefile
    del *.obj *.exe *.pdb *.ilk *.zip *.bin *.log *.inc README.txt *.hf *.lzss *.xsh32

zip: silicon.zip Makefile

silicon.zip: silicon.exe Makefile
    echo Verify the hash of silicon.exe using this powershell command > README.txt
    echo Get-FileHash -Algorithm SHA256 silicon.exe >> README.txt
    echo. >> README.txt
    pwsh -c "(Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "Compress-Archive -Force -Path silicon.exe,README.txt,init.si -DestinationPath silicon.zip"
