derive_pll_clocks

# core specific constraints

# uknc_mem divides clk_sys (PLL output 0, 50 MHz) in fabric: the PPU clock
# by 16, the 25 MHz peripheral clock by 2 and the CPU clock by 12, all off
# counters that leave reset on the same clk_sys edge.  Counting that edge
# as the first, clk_25 rises on odd edges, the PPU clock on edges 8 + 16n
# and the CPU clock on edges 1 + 12n.  Clock edge k of clk_sys is master
# edge 2k - 1 here, so the PPU clock rises on clk_25's FALLING edges.
set clk_sys_pin {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}

create_generated_clock -name clk_ppu -source [get_pins $clk_sys_pin] \
	-edges {15 31 47} [get_registers {emu:emu|uknc_mem:ram1|clk312_q}]
create_generated_clock -name clk_25 -source [get_pins $clk_sys_pin] \
	-edges {1 3 5} [get_registers {emu:emu|uknc_mem:ram1|clk25_q}]
create_generated_clock -name clk_cpu -source [get_pins $clk_sys_pin] \
	-edges {1 13 25} [get_registers {emu:emu|uknc_mem:ram1|clkcpu_q}]

derive_clock_uncertainty
