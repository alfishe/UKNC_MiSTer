//
// sim_top.sv
//
// Simulation top: emu with the framework stubbed, the video and audio out.
//
module sim_top
(
   input         CLK_50M,
   input         RESET,
   input  [10:0] ps2_key /*verilator public*/,

   // the HPS side of the sector interface (see hps_io_sim.sv): slots 0-3
   // are the floppies, which share an LBA and a buffer, 4 the hard disk
   input  [ 4:0] img_mounted,
   input  [31:0] img_size,
   output [31:0] sd_lba,
   output [31:0] sd_lba_hdd,
   output [ 4:0] sd_rd,
   output [ 4:0] sd_wr,
   input  [ 4:0] sd_ack,
   input  [ 7:0] sd_buff_addr,
   input  [15:0] sd_buff_dout,
   output [15:0] sd_buff_din,
   output [15:0] sd_buff_din_hdd,
   input         sd_buff_wr,

   output        CE_PIXEL,
   output [ 7:0] VGA_R,
   output [ 7:0] VGA_G,
   output [ 7:0] VGA_B,
   output        VGA_HS,
   output        VGA_VS,
   output        VGA_DE,
   output [15:0] AUDIO_L,
   output [15:0] AUDIO_R,
   output        LED_USER
);

wire [45:0] HPS_BUS;

emu emu
(
   .CLK_50M (CLK_50M),
   .RESET   (RESET),
   .HPS_BUS (HPS_BUS),
   .CE_PIXEL(CE_PIXEL),
   .VGA_R   (VGA_R),
   .VGA_G   (VGA_G),
   .VGA_B   (VGA_B),
   .VGA_HS  (VGA_HS),
   .VGA_VS  (VGA_VS),
   .VGA_DE  (VGA_DE),
   .AUDIO_L (AUDIO_L),
   .AUDIO_R (AUDIO_R),
   .LED_USER(LED_USER)
);

// one floppy request is up at a time: drive 0's LBA and buffer are
// every floppy's
assign sd_lba          = emu.hps_io.sd_lba[0];
assign sd_lba_hdd      = emu.hps_io.sd_lba[4];
assign sd_rd           = emu.hps_io.sd_rd;
assign sd_wr           = emu.hps_io.sd_wr;
assign sd_buff_din     = emu.hps_io.sd_buff_din[0];
assign sd_buff_din_hdd = emu.hps_io.sd_buff_din[4];

monitor mon();

endmodule
