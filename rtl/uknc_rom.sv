//
// uknc_rom.sv
//
// The PPU's 32 KB system ROM (tang-uknc used a Gowin pROM, rom208).
// Initialised from rom/uknc_rom.hex and overwritable from the HPS: a
// boot.rom in games/UKNC is loaded over it at start-up, so the core runs
// with the stock ROM and anyone who has another one can use it.
//
module uknc_rom
(
   input             clk,          // read side, the PPU's clock
   input      [13:0] addr,         // word address
   output reg [15:0] dout,

   input             wr_clk,
   input      [13:0] wr_addr,
   input      [15:0] wr_data,
   input             wr_en
);

// The image path is relative to the directory the tool runs in: the
// project's for Quartus; sim/ has an rtl link to the same.
localparam WORDS = 16384;

reg [15:0] mem[0:WORDS-1];

initial $readmemh("rtl/rom/uknc_rom.hex", mem);

always @(posedge clk) dout <= mem[addr];

always @(posedge wr_clk) if(wr_en) mem[wr_addr] <= wr_data;

endmodule
