silicon.exe: silicon.obj
	link silicon.obj kernel32.lib /fixed /nologo /entry:start /subsystem:console /Brepro

silicon.obj: silicon.asm
	nasm -fwin64 .\silicon.asm

run: silicon.exe
	wt -d . .\silicon.exe
