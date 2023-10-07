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
        $(debug_link_flags)

silicon.obj: silicon.asm
    nasm -fwin64 silicon.asm $(debug_nasm_flags)

clean:
    del *.obj *.exe *.pdb *.ilk

zip: silicon.zip

silicon.zip: silicon.exe
    pwsh -c "Compress-Archive -Force -Path silicon.exe -DestinationPath silicon.zip"
