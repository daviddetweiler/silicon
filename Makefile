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
        /merge:.text=silicon

silicon.obj: silicon.asm
    nasm -fwin64 silicon.asm
