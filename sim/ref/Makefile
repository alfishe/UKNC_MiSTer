# The reference: headless UKNCBTL.  make UKNCBTL=<a clone of
# github.com/nzeemin/ukncbtl-qt>; colors.inc is its screen colour table.

ifndef UKNCBTL
$(error set UKNCBTL to a clone of github.com/nzeemin/ukncbtl-qt)
endif
EMU      = $(UKNCBTL)/emulator
EMUBASE  = $(addprefix $(EMU)/emubase/,Board.cpp Floppy.cpp Hard.cpp Memory.cpp \
           Processor.cpp SoundAY.cpp Disasm.cpp)

ref: ref.cpp shim/stdafx.h colors.inc $(EMUBASE)
	c++ -std=c++17 -O2 -w -Ishim -I. -I$(EMU) -o $@ ref.cpp $(EMUBASE)

colors.inc: $(EMU)/qscreen.cpp
	sed -n '/ScreenView_StandardRGBColors\[16 \* 8\]/,/};/p' $< | grep 0x > $@

clean:
	rm -f ref colors.inc

.PHONY: clean
