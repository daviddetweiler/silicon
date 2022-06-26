silicon.exe: silicon.obj
	link silicon.obj kernel32.lib /fixed /nologo /entry:start /subsystem:console /Brepro

silicon.obj: silicon.asm
	nasm -fwin64 .\silicon.asm

silicon-debug.exe: silicon-debug.obj
	link silicon-debug.obj kernel32.lib /fixed /nologo /entry:start /subsystem:console /Brepro /debug

silicon-debug.obj: silicon.asm
	nasm -fwin64 -g .\silicon.asm -o silicon-debug.obj

run: silicon.exe
	wt -d . .\silicon.exe

debug: silicon-debug.exe
	devenv /debugexe silicon-debug.exe

clean:
	del *.obj *.pdb *.ilk *.exe *.zip

silicon.zip: silicon.exe
	tar -a -c -f silicon.zip silicon.exe
