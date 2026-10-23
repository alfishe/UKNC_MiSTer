//
// cartridge.sv
//
// The PPU's two ROM cartridge slots.  A cartridge is 24 KB, three banks
// of 8 KB, seen in window block 0 (0100000-0117777) when R177054 puts the
// window in cartridge mode: bits 2:1 the bank (1..3), bit 3 the slot
// (UKNCBTL's Memory.cpp, CMotherboard::LoadROMCartridge).
//
// The images come from the HPS: games/UKNC/boot1.rom and boot2.rom when
// the core starts, or the OSD's "Cartridge 1/2".  A slot without one is
// empty and the window times out, as on the machine.
//
// Slot 1 is also where the IDE cartridge (ide.v) sits.  While it is there
// its registers take the upper 4 KB of every bank and its ROM is the lower
// 4 KB: this module's slot 1 image, the built-in WD ROM until a file is
// loaded over it.  ide.v answers the bus then, with rom_dout from here.
//
// Clocked on clk_25 with the PPU's bus sampled on strobe edges, as ide.v.
//
module cartridge
(
   input             clk,          // clk_25
   input             rst,          // PPU INIT, active high

   // the PPU's bus
   input      [16:0] wbm_adr_i,
   input             wbm_wre_i,
   input             wbm_stb_i,
   output reg [15:0] wbm_dat_o,
   output reg        wbm_ack_o,

   // the window, from ppu.v
   input             cart_sel,     // block 0 is in cartridge mode
   input             cart_slot2,   // R177054[3]: slot 2
   input      [ 1:0] cart_bank,    // R177054[2:1], 1..3

   input             ide_present,  // the IDE cartridge holds slot 1
   output reg [15:0] rom_dout,     // slot 1's ROM to ide.v, one clock after the address

   // loading from the HPS, on clk_sys
   input             load_clk,
   input             load_slot1,
   input             load_slot2,
   input      [26:0] load_addr,    // bytes
   input      [15:0] load_data,
   input             load_wr
);

localparam BANK_WORDS = 4096;                 // 8 KB
localparam CART_WORDS = 3 * BANK_WORDS;       // 24 KB
localparam CART_BYTES = 2 * CART_WORDS;

reg [15:0] slot1[0:CART_WORDS-1];
reg [15:0] slot2[0:CART_WORDS-1];

// the built-in WD ROM; the path is relative to the directory the tool runs in
initial $readmemh("rtl/rom/ide_wdrom.hex", slot1);

// loading, and a slot holds a cartridge once something was loaded into it
wire       in_image = load_wr && load_addr < CART_BYTES;
wire [13:0] load_word = load_addr[14:1];

always @(posedge load_clk) begin
   if(in_image && load_slot1) slot1[load_word] <= load_data;
   if(in_image && load_slot2) slot2[load_word] <= load_data;
end

reg loaded1 = 1'b0, loaded2 = 1'b0;           // on load_clk
always @(posedge load_clk) begin
   if(load_slot1) loaded1 <= 1'b1;
   if(load_slot2) loaded2 <= 1'b1;
end

// reading: bank 1..3 is image bank 0..2
wire [ 1:0] bank_m1 = cart_bank - 2'd1;
wire [13:0] word    = {bank_m1, wbm_adr_i[12:1]};
reg  [15:0] slot2_dout;

always @(posedge clk) begin
   rom_dout   <= slot1[word];
   slot2_dout <= slot2[word];
end

// the bus, when no IDE cartridge answers for slot 1
wire in_window = wbm_adr_i[15:13] == 3'b100;  // 0100000-0117777
wire ce = wbm_stb_i && in_window && cart_sel &&
          (cart_slot2 ? loaded2 : loaded1 && !ide_present);
reg  ce_old = 1'b0;

// ack rises on the second clock of a strobe and stays until it drops;
// writes are acked and dropped
always @(posedge clk) begin
   ce_old <= ce;
   if(rst || !wbm_stb_i) wbm_ack_o <= 1'b0;
   else if(ce && ce_old && !wbm_ack_o) begin
      wbm_ack_o <= 1'b1;
      wbm_dat_o <= cart_slot2 ? slot2_dout : rom_dout;
   end
end

endmodule
