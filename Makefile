silicon.exe: silicon.obj
    link silicon.obj kernel32.lib /subsystem:console /entry:start /nologo

silicon.obj: silicon.asm
    nasm -fwin64 silicon.asm
