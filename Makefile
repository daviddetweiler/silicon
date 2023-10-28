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

$(OUT)\silicon.bin: silicon.asm $(OUT)\core.inc $(OUT)\expected.version Makefile
    pwsh -c "nasm -I $(OUT) -fbin silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o $(OUT)\silicon.bin"

$(OUT)\silicon.obj: silicon.asm $(OUT)\core.inc $(OUT)\expected.version Makefile
    pwsh -c "nasm -I $(OUT) -fwin64 silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" \
        -o $(OUT)\silicon.obj -g -Dstandalone"

$(OUT)\silicon.bin.bw: $(OUT)\silicon.bin $(BW) Makefile
    python $(BW) pack $(OUT)\silicon.bin $(OUT)\silicon.bin.bw

$(OUT)\bw.inc: $(OUT)\silicon.bin.bw $(INC) Makefile
    python $(INC) $(OUT)\silicon.bin.bw $(OUT)\bw.inc

$(OUT)\core.inc: scripts\core.si $(INC) Makefile
    python $(INC) scripts\core.si $(OUT)\core.inc

$(OUT)\bw.obj: $(OUT)\bw.inc bw.asm $(OUT)\core.inc Makefile
    nasm -I $(OUT) -fwin64 bw.asm -o $(OUT)\bw.obj

$(BW): $(AC) Makefile

$(OUT)\silicon.exe: $(OUT)\bw.obj Makefile
    link $(OUT)\bw.obj kernel32.lib \
        /out:$(OUT)\silicon.exe \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /ignore:4254 \
        /section:kernel,RE \
        /merge:.rdata=kernel \
        /merge:.text=kernel

$(OUT)\silicon-debug.exe: $(OUT)\silicon.obj Makefile
    link $(OUT)\silicon.obj kernel32.lib \
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
    cd .\out\ && del *.obj *.exe *.pdb *.ilk *.zip *.bin *.log *.inc README.txt *.bw *.version

zip: build $(OUT)\silicon.zip Makefile

$(OUT)\silicon.zip: Makefile
    echo Verify the hash of silicon.exe using this powershell command > README.txt
    echo Get-FileHash -Algorithm SHA256 $(OUT)\silicon.exe >> $(OUT)\README.txt
    echo. >> README.txt
    pwsh -c "cd $(OUT); (Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "cd $(OUT); Compress-Archive -Force -Path silicon.exe,README.txt -DestinationPath silicon.zip"

run: build Makefile
    pwsh -c "wt -F $$(Resolve-Path $(OUT)\silicon.exe)"

report: report.json Makefile

report.json: $(ANALYZER) silicon.asm Makefile
    python $(ANALYZER) silicon.asm > report.json

image-info:
    python $(BW) info $(OUT)\silicon.bin.bw
