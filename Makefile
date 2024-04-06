BW=.\tools\bitweaver.py
AC=.\tools\ac.py
INC=.\tools\inc.py
VERSION=.\tools\version.py
ANALYZER=.\tools\analyzer.py
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
    pwsh -c "nasm \
        -I $(OUT) \
        -fwin64 \
        $(SRC)\kernel.asm \
        -Dgit_version=""$$(git describe --dirty --tags)"" \
        -Dstandalone \
        -o $(OUT)\kernel.obj

$(OUT)\kernel.bin.bw: $(OUT)\kernel.bin $(BW) Makefile
    python $(BW) pack $(OUT)\kernel.bin $(OUT)\kernel.bin.bw

$(OUT)\kernel.bin.bw.inc: $(OUT)\kernel.bin.bw $(INC) Makefile
    python $(INC) $(OUT)\kernel.bin.bw $(OUT)\kernel.bin.bw.inc

$(OUT)\core.inc: $(SRC)\core.si $(INC) Makefile
    python $(INC) $(SRC)\core.si $(OUT)\core.inc

$(OUT)\loader.obj: $(OUT)\kernel.bin.bw.inc $(SRC)\loader.asm Makefile
    nasm -I $(OUT) -fwin64 $(SRC)\loader.asm -o $(OUT)\loader.obj

$(BW): $(AC) Makefile

$(OUT)\silicon.exe: $(OUT)\loader.obj Makefile
    link $(OUT)\loader.obj kernel32.lib \
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
        /merge:.bss=data

clean: Makefile
    del report.json *.log log.si
    cd .\out\ && del *.obj *.exe *.pdb *.ilk *.zip *.bin *.log *.inc README.txt *.bw *.version

zip: build $(OUT)\silicon.zip Makefile

$(OUT)\silicon.zip: Makefile
    echo Verify the hash of silicon.exe using this powershell command > $(OUT)\README.txt
    echo Get-FileHash -Algorithm SHA256 silicon.exe >> $(OUT)\README.txt
    echo. >> $(OUT)\README.txt
    pwsh -c "cd $(OUT); (Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "cd $(OUT); Compress-Archive -Force -Path silicon.exe,README.txt,..\scripts\ -DestinationPath silicon.zip"

run: build Makefile
    $(OUT)\silicon.exe

run-term: build Makefile
    pwsh -c "wt -F $$(Resolve-Path $(OUT)\silicon.exe)"

report: report.json Makefile

report.json: $(ANALYZER) $(SRC)\kernel.asm .\docs\words.md Makefile
    python $(ANALYZER) $(SRC)\kernel.asm > report.json

image-info:
    python $(BW) info $(OUT)\kernel.bin.bw
