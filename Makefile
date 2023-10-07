debug=0

!if $(debug)
debug_link_flags=/debug
debug_nasm_flags=-g
!else
debug_link_flags=
debug_nasm_flags=
!endif

silicon.exe: silicon.obj
    link silicon.obj kernel32.lib \
        /subsystem:console \
        /entry:start \
        /nologo \
        /fixed \
        /ignore:4254 \
        /section:silicon,RWE \
        /merge:.rdata=silicon \
        /merge:.bss=silicon \
        /merge:.text=silicon \
        /Brepro \
        $(debug_link_flags)

silicon.obj: silicon.asm
    pwsh -c "nasm -fwin64 silicon.asm -Dgit_version=""$$(git describe)"" $(debug_nasm_flags)"

clean:
    del *.obj *.exe *.pdb *.ilk *.zip

zip: silicon.zip

silicon.zip: silicon.exe
    echo Verify the hash of silicon.exe using this powershell command > README.txt
    echo Get-FileHash -Algorithm SHA256 silicon.exe >> README.txt
    echo. >> README.txt
    pwsh -c "(Get-FileHash -Algorithm SHA256 silicon.exe).Hash >> README.txt"
    pwsh -c "Compress-Archive -Force -Path silicon.exe,README.txt -DestinationPath silicon.zip"
