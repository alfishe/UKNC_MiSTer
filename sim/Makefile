# Model of the core for Verilator: make, then obj_dir/Vsim_top [frames] [every]

RTL = ../rtl
SRC = sim_top.sv monitor.sv hps_io_sim.sv pll_sim.v ../UKNC.sv \
      $(RTL)/uknc_mem.sv $(RTL)/uknc_rom.sv $(RTL)/cpu.v $(RTL)/ppu.v \
      $(RTL)/wmrst.v $(RTL)/xm2-01.v $(RTL)/vp1_120.v $(RTL)/vp65.v \
      $(RTL)/mkcolorreg.v $(RTL)/aberrant.v $(RTL)/covox.v $(RTL)/kakave.v $(RTL)/ide.v $(RTL)/mixer.v \
      $(RTL)/vp1-128fdd.v $(RTL)/fdd/fdd4.v $(RTL)/ay/ym2149.sv $(RTL)/uart/uart_rx.v \
      $(RTL)/uart/uart_tx.v $(RTL)/uart/uartfifo.v $(RTL)/vm2/vm2_wb.v \
      $(RTL)/vm2/vm2_plm.v $(RTL)/keyboard.sv

VFLAGS = --cc --exe --build -O3 -j 0 --top-module sim_top -I. -I.. \
         -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-PINMISSING -Wno-PINCONNECTEMPTY \
         -Wno-DECLFILENAME -Wno-UNDRIVEN -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN \
         -Wno-TIMESCALEMOD -Wno-COMBDLY -Wno-CASEX -Wno-UNOPTFLAT \
         -CFLAGS -O2

obj_dir/Vsim_top: $(SRC) sim_main.cpp
	verilator $(VFLAGS) $(SRC) sim_main.cpp

clean:
	rm -rf obj_dir *.ppm

.PHONY: clean
