//
// hps_io_sim.sv
//
// Simulation stand-in for sys/hps_io.sv: no OSD (the status bits come
// from +status=).  Downloads, keys, the gamepad and the disk side of the
// sector interface are sim_top's ports, driven by the testbench.
//
module hps_io #(parameter CONF_STR = "", parameter WIDE = 0, parameter VDNUM = 1)
(
   input         clk_sys,
   inout  [45:0] HPS_BUS,
   inout  [35:0] EXT_BUS,
   inout  [21:0] gamma_bus,

   output [  1:0] buttons,
   output         forced_scandoubler,
   output [127:0] status,
   input  [ 15:0] status_menumask,

   output        ioctl_download,
   output [ 7:0] ioctl_index,
   output        ioctl_wr,
   output [26:0] ioctl_addr,
   output [15:0] ioctl_dout,

   output [VDNUM-1:0] img_mounted,
   output             img_readonly,
   output      [63:0] img_size,

   input       [31:0] sd_lba[VDNUM],
   input       [ 5:0] sd_blk_cnt[VDNUM],
   input  [VDNUM-1:0] sd_rd,
   input  [VDNUM-1:0] sd_wr,
   output [VDNUM-1:0] sd_ack,
   output      [12:0] sd_buff_addr,
   output      [15:0] sd_buff_dout,
   input       [15:0] sd_buff_din[VDNUM],
   output             sd_buff_wr,

   output [31:0] joystick_0,

   output [10:0] ps2_key,
   output [24:0] ps2_mouse,
   output [64:0] RTC
);

assign buttons        = 0;
assign forced_scandoubler = 0;
assign gamma_bus[20:0] = 0;
// the OSD's settings: +status=HEX on the command line, all zero without
reg [127:0] status_arg = 0;
initial if(!$value$plusargs("status=%h", status_arg)) status_arg = 0;
assign status         = status_arg;
assign ioctl_download = sim_top.ioctl_download;
assign ioctl_index    = sim_top.ioctl_index;
assign ioctl_wr       = sim_top.ioctl_wr;
assign ioctl_addr     = sim_top.ioctl_addr;
assign ioctl_dout     = sim_top.ioctl_dout;
assign ps2_key        = sim_top.ps2_key;
assign joystick_0     = sim_top.joystick;
assign ps2_mouse      = 0;
assign RTC            = 0;

assign img_mounted    = sim_top.img_mounted;
assign img_readonly   = 1'b0;
assign img_size       = {32'd0, sim_top.img_size};
assign sd_ack         = sim_top.sd_ack;
assign sd_buff_addr   = {5'd0, sim_top.sd_buff_addr};
assign sd_buff_dout   = sim_top.sd_buff_dout;
assign sd_buff_wr     = sim_top.sd_buff_wr;

endmodule
