all: build debug-build zip Makefile

build: si.exe Makefile

debug-build: silicon-debug.exe Makefile

silicon.bin: silicon.asm Makefile
    pwsh -c "nasm -fbin silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o silicon.bin"

silicon.obj: silicon.asm Makefile
    pwsh -c "nasm -fwin64 silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o silicon.obj -g -Dstandalone"

compressed.bin: silicon.bin huffman.py Makefile
    python .\huffman.py silicon.bin compressed.bin

blob.inc: compressed.bin textify.py Makefile
    python .\textify.py compressed.bin

stub.obj: stub.asm blob.inc Makefile
    nasm -fwin64 stub.asm

si.exe: stub.obj Makefile
    link stub.obj kernel32.lib \
        /out:si.exe \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /Brepro \
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
        /Brepro \
        /ignore:4254 \
        /section:kernel,RE \
        /section:data,RWE \
        /merge:.rdata=kernel \
        /merge:.text=kernel \
        /merge:.bss=data \
        /debug

clean: Makefile
    del *.obj *.exe *.pdb *.ilk *.zip *.bin *.log blob.inc README.txt

zip: silicon.zip Makefile

silicon.zip: si.exe Makefile
    echo Verify the hash of si.exe using this powershell command > README.txt
    echo Get-FileHash -Algorithm SHA256 si.exe >> README.txt
    echo. >> README.txt
    pwsh -c "(Get-FileHash -Algorithm SHA256 si.exe).Hash >> README.txt"
    pwsh -c "Compress-Archive -Force -Path si.exe,README.txt,init.si -DestinationPath silicon.zip"
