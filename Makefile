debug=0

!if $(debug)
debug_link_flags=/debug
debug_nasm_flags=-g
!else
debug_link_flags=
debug_nasm_flags=
!endif

build: silicon.exe Makefile

silicon.bin: silicon.asm Makefile
    pwsh -c "nasm -fbin silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" -o silicon.bin"

compressed.bin: silicon.bin huffman.py Makefile
    python .\huffman.py silicon.bin

blob.inc: compressed.bin textify.py Makefile
    python .\textify.py compressed.bin

stub.obj: stub.asm blob.inc Makefile
    nasm -fwin64 stub.asm

silicon.exe: stub.obj Makefile
    link stub.obj kernel32.lib \
        /out:silicon.exe \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /Brepro \
        /ignore:4254 \
        /section:kernel,RE \
        /merge:.rdata=kernel \
        /merge:.text=kernel \
        $(debug_link_flags)

silicon.obj: silicon.asm Makefile
    pwsh -c "nasm -fwin64 silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" $(debug_nasm_flags)"

clean: Makefile
    del *.obj *.exe *.pdb *.ilk *.zip *.bin *.log

zip: silicon.zip Makefile

silicon.zip: silicon.exe Makefile
    echo Verify the hash of silicon.exe using this powershell command > README.txt
    echo Get-FileHash -Algorithm SHA256 silicon.exe >> README.txt
    echo. >> README.txt
    pwsh -c "(Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "Compress-Archive -Force -Path silicon.exe,README.txt,init.si -DestinationPath silicon.zip"
