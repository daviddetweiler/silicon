BW=.\tools\bitweaver.py
AC=.\tools\ac.py
INC=.\tools\inc.py
VERSION=.\tools\version.py
ANALYZER=.\tools\analyzer.py
OUT=.\out

all: build debug-build zip Makefile

build: version $(OUT)\silicon.exe Makefile

debug-build: version $(OUT)\silicon-debug.exe Makefile

version: $(VERSION) Makefile
    pwsh -c "git describe --dirty --tags > $(OUT)\actual.version"
    python $(VERSION) $(OUT)\actual.version $(OUT)\expected.version

$(OUT)\kernel.bin: kernel.asm $(OUT)\core.inc $(OUT)\expected.version Makefile
    pwsh -c "nasm -I $(OUT) -fbin kernel.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o $(OUT)\kernel.bin"

$(OUT)\kernel.obj: kernel.asm $(OUT)\core.inc $(OUT)\expected.version Makefile
    pwsh -c "nasm -I $(OUT) -fwin64 kernel.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o $(OUT)\kernel.obj -g -Dstandalone"

$(OUT)\kernel.bin.bw: $(OUT)\kernel.bin $(BW) Makefile
    python $(BW) pack $(OUT)\kernel.bin $(OUT)\kernel.bin.bw

$(OUT)\compressed.inc: $(OUT)\kernel.bin.bw $(INC) Makefile
    python $(INC) $(OUT)\kernel.bin.bw $(OUT)\compressed.inc

$(OUT)\core.inc: scripts\core.si $(INC) Makefile
    python $(INC) scripts\core.si $(OUT)\core.inc

$(OUT)\loader.obj: $(OUT)\compressed.inc loader.asm $(OUT)\core.inc Makefile
    nasm -I $(OUT) -fwin64 loader.asm -o $(OUT)\loader.obj

$(BW): $(AC) Makefile

$(OUT)\silicon.exe: $(OUT)\loader.obj Makefile
    link $(OUT)\loader.obj kernel32.lib \
        /out:$(OUT)\silicon.exe \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /ignore:4254 \
        /section:kernel,RE \
        /merge:.rdata=kernel \
        /merge:.text=kernel

$(OUT)\silicon-debug.exe: $(OUT)\kernel.obj Makefile
    link $(OUT)\kernel.obj kernel32.lib \
        /out:$(OUT)\silicon-debug.exe \
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
    del report.json
    cd .\out\ && del *.obj *.exe *.pdb *.ilk *.zip *.bin *.log *.inc README.txt *.bw *.version

zip: build $(OUT)\silicon.zip Makefile

$(OUT)\silicon.zip: Makefile
    echo Verify the hash of silicon.exe using this powershell command > README.txt
    echo Get-FileHash -Algorithm SHA256 $(OUT)\silicon.exe >> $(OUT)\README.txt
    echo. >> $(OUT)\README.txt
    pwsh -c "cd $(OUT); (Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "cd $(OUT); Compress-Archive -Force -Path silicon.exe,README.txt -DestinationPath silicon.zip"

run: build Makefile
    pwsh -c "wt -F $$(Resolve-Path $(OUT)\silicon.exe)"

report: report.json Makefile

report.json: $(ANALYZER) kernel.asm Makefile
    python $(ANALYZER) kernel.asm > report.json

image-info:
    python $(BW) info $(OUT)\kernel.bin.bw
