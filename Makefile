SRCS := ../BBCZ80/DIST.asm  ../BBCZ80/MAIN.asm ../BBCZ80/EXEC.asm ../BBCZ80/EVAL.asm ../BBCZ80/ASMB.asm  ../BBCZ80/MATH.asm ../BBCZ80/HOOK.asm MSXBIOS.asm MSXOS.asm  ../BBCZ80/DATA.asm
EXCLUDE	:= "BASICRAM BASICVAR BBX80VAR BBX80RAM"
 
# system agnostic commands
ifdef ComSpec
	RMF	:= del /f /q
	SEARCH	:= find
	CP	:= copy /b
	MODE := MOVE
	/	:= $(strip \)
else
	RMF	:= rm -f 
	SEARCH	:= grep
	CP	:= cp
	/	:= /
endif 

bbcbasic.com: $(SRCS)
	@echo Assembling MSX edition..
	z88dk-z80asm -DMSXBIOS -Oobj -oBBX80.bin -b -d -l -m $(SRCS)
	z88dk-appmake +glue -b obj$/BBX80 --filler 0x00 --clean --exclude-sections $(EXCLUDE)
	$(CP) obj$/BBX80__.bin  bin$/BBCBASIC.com
#	$(RMF) obj$/bbcbasic.com
	@echo done

clean:
	$(RMF) obj$/*
	$(RMF) BBCZ80$/*
	@echo Cleanup done