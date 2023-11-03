BW=.\tools\bitweaver.py
AC=.\tools\ac.py
INC=.\tools\inc.py
VERSION=.\tools\version.py
ANALYZER=.\tools\analyzer.py
XSH32=.\tools\xsh32.py
OUT=.\out
SRC=.\src

all: build uncompressed-build zip Makefile

build: version $(OUT)\silicon.exe Makefile

uncompressed-build: version $(OUT)\silicon-uncompressed.exe Makefile

version: $(VERSION) Makefile
    pwsh -c "git describe --dirty --tags > $(OUT)\actual.version"
    python $(VERSION) $(OUT)\actual.version $(OUT)\expected.version

$(OUT)\kernel.bin: $(SRC)\kernel.asm $(OUT)\core.inc $(OUT)\expected.version Makefile
    pwsh -c "nasm \
        -I $(OUT) \
        -fbin $(SRC)\kernel.asm \
        -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o $(OUT)\kernel.bin"

$(OUT)\kernel.obj: $(SRC)\kernel.asm $(OUT)\core.inc $(OUT)\expected.version Makefile
    echo "" > $(OUT)\kernel.obj
    pwsh -c "nasm \
        -I $(OUT) \
        -fwin64 \
        $$(Resolve-Path $(SRC)\kernel.asm) \
        -Dgit_version=""$$(git describe --dirty --tags)"" \
        -Dstandalone -g \
        -o $$(Resolve-Path $(OUT)\kernel.obj)"

$(OUT)\kernel.bin.bw: $(OUT)\kernel.bin $(BW) Makefile
    python $(BW) pack $(OUT)\kernel.bin $(OUT)\kernel.bin.bw

$(OUT)\compressed.inc: $(OUT)\kernel.bin.bw $(INC) Makefile
    python $(INC) $(OUT)\kernel.bin.bw $(OUT)\compressed.inc

$(OUT)\core.inc: scripts\core.si $(INC) Makefile
    python $(INC) scripts\core.si $(OUT)\core.inc

$(OUT)\loader.bin: $(OUT)\compressed.inc $(SRC)\loader.asm $(OUT)\core.inc Makefile
    nasm -I $(OUT) -fbin $(SRC)\loader.asm -o $(OUT)\loader.bin

$(OUT)\loader.bin.xsh32 $(OUT)\seed.inc: $(OUT)\loader.bin $(XSH32) Makefile
    python $(XSH32) $(OUT)\loader.bin $(OUT)\loader.bin.xsh32 $(OUT)\seed.inc

$(OUT)\xsh32.obj: $(SRC)\xsh32.asm $(OUT)\xsh32.inc $(OUT)\seed.inc Makefile
    nasm -I $(OUT) -fwin64 $(SRC)\xsh32.asm -o $(OUT)\xsh32.obj

$(OUT)\xsh32.inc: $(OUT)\loader.bin.xsh32 $(INC) Makefile
    python $(INC) $(OUT)\loader.bin.xsh32 $(OUT)\xsh32.inc

$(BW): $(AC) Makefile

$(OUT)\silicon.exe: $(OUT)\xsh32.obj Makefile
    link $(OUT)\xsh32.obj kernel32.lib \
        /out:$(OUT)\silicon.exe \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /ignore:4254 \
        /section:kernel,RWE \
        /merge:.rdata=kernel \
        /merge:.text=kernel

$(OUT)\silicon-uncompressed.exe: $(OUT)\kernel.obj Makefile
    link $(OUT)\kernel.obj kernel32.lib \
        /out:$(OUT)\silicon-uncompressed.exe \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /ignore:4254 \
        /section:kernel,RWE \
        /section:data,RWE \
        /merge:.rdata=kernel \
        /merge:.text=kernel \
        /merge:.bss=data /debug

clean: Makefile
    del report.json *.log log.si
    cd .\out\ && del *.obj *.exe *.pdb *.ilk *.zip *.bin *.log *.inc README.txt *.bw *.version *.xsh32

zip: build $(OUT)\silicon.zip Makefile

$(OUT)\silicon.zip: Makefile
    echo Verify the hash of silicon.exe using this powershell command > $(OUT)\README.txt
    echo Get-FileHash -Algorithm SHA256 silicon.exe >> $(OUT)\README.txt
    echo. >> $(OUT)\README.txt
    pwsh -c "cd $(OUT); (Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "cd $(OUT); Compress-Archive -Force -Path silicon.exe,README.txt -DestinationPath silicon.zip"

run: build Makefile
    $(OUT)\silicon.exe

run-term: build Makefile
    pwsh -c "wt -F $$(Resolve-Path $(OUT)\silicon.exe)"

report: report.json Makefile

report.json: $(ANALYZER) $(SRC)\kernel.asm Makefile
    python $(ANALYZER) $(SRC)\kernel.asm > report.json

image-info:
    python $(BW) info $(OUT)\kernel.bin.bw
