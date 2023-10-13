debug=0

!if $(debug)
debug_link_flags=/debug
debug_nasm_flags=-g
!else
debug_link_flags=
debug_nasm_flags=
!endif

silicon.exe: silicon.obj Makefile
    link silicon.obj kernel32.lib \
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
        /Brepro \
        $(debug_link_flags)

silicon.bin: silicon-flat.asm Makefile
    pwsh -c "nasm -fbin silicon-flat.asm -Dgit_version=""$$(git describe --dirty --tags)"" -o silicon.bin"

compressed.bin: silicon.bin huffman.py Makefile
    python .\huffman.py silicon.bin

silicon.obj: silicon.asm Makefile
    pwsh -c "nasm -fwin64 silicon.asm -Dgit_version=""$$(git describe --dirty --tags)"" $(debug_nasm_flags)"

clean: Makefile
    del *.obj *.exe *.pdb *.ilk *.zip *.bin

zip: silicon.zip Makefile

silicon.zip: silicon.exe Makefile
    echo Verify the hash of silicon.exe using this powershell command > README.txt
    echo Get-FileHash -Algorithm SHA256 silicon.exe >> README.txt
    echo. >> README.txt
    pwsh -c "(Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "Compress-Archive -Force -Path silicon.exe,README.txt,init.si -DestinationPath silicon.zip"
