//
// video_mixer_sim.sv
//
// Simulation stand-in for sys/video_mixer.sv, which Verilator reads
// differently from Quartus (its colour inputs are declared in unnamed
// generate blocks).  No scan doubler, no gamma: the core's 15 kHz video
// passes through, registered on its pixel enable as the real one does.
//
module video_mixer #(parameter LINE_LENGTH = 768, parameter HALF_DEPTH = 0, parameter GAMMA = 0)
(
   input            CLK_VIDEO,
   output reg       CE_PIXEL,
   input            ce_pix,

   input            scandoubler,
   input            hq2x,
   inout     [21:0] gamma_bus,

   input      [7:0] R,
   input      [7:0] G,
   input      [7:0] B,
   input            HSync,
   input            VSync,
   input            HBlank,
   input            VBlank,

   input            HDMI_FREEZE,
   output           freeze_sync,

   output reg [7:0] VGA_R,
   output reg [7:0] VGA_G,
   output reg [7:0] VGA_B,
   output reg       VGA_VS,
   output reg       VGA_HS,
   output reg       VGA_DE
);

assign freeze_sync = 1'b0;

always @(posedge CLK_VIDEO) begin
   CE_PIXEL <= ce_pix;
   if(ce_pix) begin
      VGA_R  <= R;
      VGA_G  <= G;
      VGA_B  <= B;
      VGA_HS <= HSync;
      VGA_VS <= VSync;
      VGA_DE <= ~(HBlank | VBlank);
   end
end

endmodule
