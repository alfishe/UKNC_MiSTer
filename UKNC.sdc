derive_pll_clocks

# core specific constraints

# uknc_mem divides clk_sys (PLL output 0, 50 MHz) in fabric: the PPU clock
# by 16 and the 25 MHz peripheral clock by 2.
set clk_sys_pin {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}

create_generated_clock -name clk_ppu -source [get_pins $clk_sys_pin] \
	-divide_by 16 [get_registers {emu:emu|uknc_mem:ram1|clk312_q}]
create_generated_clock -name clk_25 -source [get_pins $clk_sys_pin] \
	-divide_by 2 [get_registers {emu:emu|uknc_mem:ram1|clk25_q}]

derive_clock_uncertainty
