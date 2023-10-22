all: build debug-build zip Makefile

build: version silicon.exe Makefile

debug-build: version silicon-debug.exe Makefile

version: version.py Makefile
    pwsh -c "git describe --dirty --tags > actual.version"
    python .\version.py actual.version expected.version version.inc

silicon.bin: silicon.asm core.inc version.inc Makefile
    pwsh -c "nasm -fbin silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o silicon.bin"

silicon.obj: silicon.asm core.inc Makefile
    pwsh -c "nasm -fwin64 silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o silicon.obj -g -Dstandalone"

silicon.bin.bw: silicon.bin bitweaver.py Makefile
    python .\bitweaver.py pack silicon.bin silicon.bin.bw

bw.inc: silicon.bin.bw inc.py Makefile
    python .\inc.py silicon.bin.bw bw.inc

core.inc: core.si inc.py Makefile
    python .\inc.py core.si core.inc

bw.obj: bw.inc bw.asm core.inc Makefile
    nasm -fwin64 bw.asm -o bw.obj

bitweaver.py: ac.py Makefile

silicon.exe: bw.obj Makefile
    link bw.obj kernel32.lib \
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
        /section:data,RWE \
        /merge:.rdata=kernel \
        /merge:.text=kernel \
        /merge:.bss=data \
        /debug

clean: Makefile
    del *.obj *.exe *.pdb *.ilk *.zip *.bin *.log *.inc README.txt *.hf *.lzss *.xsh32 *.bw

zip: build silicon.zip Makefile

silicon.zip: Makefile
    echo Verify the hash of silicon.exe using this powershell command > README.txt
    echo Get-FileHash -Algorithm SHA256 silicon.exe >> README.txt
    echo. >> README.txt
    pwsh -c "(Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "Compress-Archive -Force -Path silicon.exe,README.txt -DestinationPath silicon.zip"
