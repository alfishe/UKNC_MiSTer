# [UKNC](https://en.wikipedia.org/wiki/UKNC) (Elektronika MS 0511) for MiSTer Platform

A Soviet school computer of 1987: two PDP-11 compatible K1801VM2 processors,
the CPU with 64 KB of RAM and the peripheral processor (PPU) with 32 KB of RAM
and 32 KB of ROM, a 640x288 display in three planes and eight colours out of
sixteen, and the floppy, keyboard and sound on the PPU's side.

The machine is [tang-uknc](https://github.com/lordamot/tang-uknc) moved to
MiSTer, with the K1801VM2 cores from [1801BM1/cpu11](https://github.com/1801BM1/cpu11).
[UKNCBTL](https://github.com/nzeemin/ukncbtl) was the reference for the
machine's behaviour.

## Features
* Both processors, the PPU ROM built in.
* Four floppy drives, read and write.
* PS/2 keyboard mapped to the UKNC layout.
* Beeper, "Aberrant" AY-3-8910 card, Covox.
* Serial port on the MiSTer UART.
* Kakave+ cartridge: PS/2 mouse and real-time clock (set from the MiSTer).
* IDE hard disk cartridge with the WD ROM, CHS and LBA28.
* Gamepad mapped to keys.
* 15 kHz video, 640x288; doubled to 31 kHz with `forced_scandoubler=1`
  in `MiSTer.ini` or a Scandoubler Fx (HQ2x, CRT scanlines) in the OSD.
* Colour, grey or green monitor: on a monochrome one the eight RGB codes
  are eight levels of brightness, as UKNCBTL shows them.

## Installation
Put the RBF in the root of the SD card and floppy images (`.dsk`, 800 KB:
80 tracks, 2 sides, 10 sectors of 512 bytes) in `games/UKNC`.

Hard disk images (`.img`, WD layout, plain or inverted) go in `games/UKNC`
too.

Another PPU ROM can be put in `games/UKNC/boot.rom` (32 KB); it is loaded
over the built-in one at start-up.

## Usage
Mount an image in drive 0, press `1` in the boot menu and then Enter (ВВОД).

"Floppy write protect" in the OSD protects all drives; a read-only image file
protects its own drive.

Mount a hard disk image in "Hard disk" and boot from 2 (кассета ПЗУ) in
the boot menu.  The cartridge is there while an image is mounted and "IDE
cartridge" is on; its geometry is taken from the image's first sector.
A read-only image file is write protected.  "HDD sector delay" slows the
disk down for programs that time themselves by it: the default plays
[Bad Apple](https://github.com/blairecas/badapple)'s sound at its 24 kHz.

"Kakave+ mouse" and "Kakave+ clock" in the OSD hide the cartridge's mouse
and clock from the software.

The gamepad's D-pad is the arrow keys, or keypad 8, 4, 6 and 2 ("Gamepad"
in the OSD); A is Space, B ВВОД, X УПР and Y АР2.  The keyboard's rows
apply: Space and ВВОД share a row with the Right arrow, so a game sees
only the last pressed of them.

## Keyboard

| PC              | UKNC        |
|-----------------|-------------|
| F1-F5           | К1-К5       |
| F6              | ПОМ         |
| F7              | УСТ         |
| F8              | ИСП         |
| F9              | СБРОС       |
| F10             | СТОП        |
| Esc             | АР2         |
| Backspace       | ЗБ          |
| Tab             | ТАБ         |
| Enter           | ВВОД        |
| Caps Lock       | ФИКС        |
| Ctrl            | УПР         |
| Shift           | НР          |
| Left Alt        | АЛФ         |
| Right Alt       | ГРАФ        |
| Keypad Enter    | keypad ВВОД |
| Keypad /        | keypad ,    |
| =               | Ч ^         |

## Simulation
`sim/` holds a Verilator model of the core; `make` there, then
`obj_dir/Vsim_top FRAMES EVERY [options]` writes frames as PPM files.
The options are listed in `sim/sim_main.cpp`.

## Licences
* The framework (`sys/`) and this core's own files: GPL v2 or later, see `LICENSE`.
* tang-uknc's HDL in `rtl/`: MIT, see `rtl/LICENSE.tang-uknc.md`.
* `rtl/vm2/`: K1801VM2 by 1801BM1, CC BY 3.0.
* `rtl/ay/ym2149.sv`: MikeJ and Sorgelig, see the file.
* `rtl/rom/ide_wdrom.hex`: the WD ROM of Oleg H.'s IDE controller
  (`ide_wdromv0110.bin`, taken from tang-uknc).
