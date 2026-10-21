//============================================================================
//
//  UKNC (Elektronika MS 0511) for MiSTer
//
//  The machine is tang-uknc's (github.com/lordamot/tang-uknc, MIT, Alexey
//  Gurov, Sergei Lemeshev and contributors), with the K1801VM2 cores by
//  1801BM1 (github.com/1801BM1/cpu11, CC BY 3.0).  This file is the glue to
//  the MiSTer framework; uknc_mem.sv stands in for tang-uknc's SDRAM
//  controller and keyboard.sv for its BL616 firmware's key translation.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign BUTTONS = 0;
// LED_DISK: the floppy motor, under FLOPPY DISKS

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"UKNC;;",
	"-;",
	"S0,DSK,Drive 0;",
	"S1,DSK,Drive 1;",
	"S2,DSK,Drive 2;",
	"S3,DSK,Drive 3;",
	"O[11],Floppy write protect,Off,On;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"O[3:2],Volume,Full,1/2,1/4,Mute;",
	"O[4],AY stereo,ABC,Mono;",
	"O[5],Low-pass filter,On,Off;",
	"O[6],Old freaks,Off,On;",
	"-;",
	"O[7],Aberrant AY,On,Off;",
	"O[9:8],Covox,177372,Off,LPT,Both;",
	"O[10],Beeper,On,Off;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"V,v",`BUILD_DATE
};

wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;

localparam DRIVES = 4;

wire [DRIVES-1:0] img_mounted;
wire              img_readonly;
wire [63:0]       img_size;
wire [31:0]       sd_lba[DRIVES];
wire [DRIVES-1:0] sd_rd;
wire [DRIVES-1:0] sd_wr;
wire [DRIVES-1:0] sd_ack;
wire [12:0]       sd_buff_addr;
wire [15:0]       sd_buff_dout;
wire [15:0]       sd_buff_din[DRIVES];
wire              sd_buff_wr;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1), .VDNUM(DRIVES)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.sd_lba(sd_lba),
	.sd_blk_cnt('{DRIVES{6'd0}}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////
//
// clk_sys  50 MHz       memory, video, and the counter the PPU clock and
//                       the 25 MHz peripheral clock are made from (uknc_mem)
// clk_cpu  4.17 MHz     the CPU (tang-uknc: 4.18 MHz)
// clk_ppu  3.125 MHz    the PPU, clk_sys / 16
//

wire clk_sys;
wire clk_cpu;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_cpu),
	.locked(pll_locked)
);

wire clk_25;
wire clk_50;
wire clk_ppu;
wire mem_init;

wire cpuclk_p = clk_cpu;
wire cpuclk_n = ~clk_cpu;
wire ppuclk_p = clk_ppu;
wire ppuclk_n = ~clk_ppu;

///////////////////////   ROM LOADING   //////////////////////////

localparam ROM_INDEX = 8'd0;          // boot.rom
localparam ROM_BYTES = 32768;

wire rom_loading = ioctl_download && ioctl_index == ROM_INDEX;
wire rom_wr_en   = rom_loading && ioctl_wr && ioctl_addr < ROM_BYTES;

wire reset = RESET | status[0] | buttons[1] | rom_loading;

///////////////////////   MEMORY AND VIDEO   /////////////////////

wire [15:0] addr_cpu_o;
wire [31:0] data_cpu_i;
wire [31:0] data_cpu_o;
wire        read_cpu_o;
wire        wrte_cpu_o;
wire [ 3:0] mask_cpu_o;
wire        askn_cpu_i;

wire [15:0] addr_ppu_o;
wire [31:0] data_ppu_i;
wire [31:0] data_ppu_o;
wire        read_ppu_o;
wire        wrte_ppu_o;
wire [ 3:0] mask_ppu_o;
wire        askn_ppu_i;

wire        hsync;
wire        vsync;
wire        visible;
wire        ce_pix;
wire [ 7:0] red;
wire [ 7:0] green;
wire [ 7:0] blue;

uknc_mem ram1
(
	.clkram   (clk_sys),
	.lockclk  (pll_locked),
	.init     (mem_init),

	.hsync    (hsync),
	.vsync    (vsync),
	.visible  (visible),
	.ce_pix   (ce_pix),
	.red      (red),
	.green    (green),
	.blue     (blue),

	.clk_25   (clk_25),
	.clk_50   (clk_50),

	.cpu_addr ({3'd0,addr_cpu_o}),
	.cpu_dout (data_cpu_i),
	.cpu_din  (data_cpu_o),
	.cpu_dqm  (mask_cpu_o),
	.cpu_read (read_cpu_o),
	.cpu_wrte (wrte_cpu_o),
	.cpu_busy (),
	.cpu_asck (askn_cpu_i),

	.ppu_clk  (clk_ppu),
	.ppu_addr ({3'd0,addr_ppu_o}),
	.ppu_dout (data_ppu_i),
	.ppu_din  (data_ppu_o),
	.ppu_dqm  (mask_ppu_o),
	.ppu_read (read_ppu_o),
	.ppu_wrte (wrte_ppu_o),
	.ppu_busy (),
	.ppu_asck (askn_ppu_i)
);

reg  [7:0] vga_r, vga_g, vga_b;
reg        vga_hs, vga_vs, vga_de;

always @(posedge clk_sys) if(ce_pix) begin
	vga_r  <= red;
	vga_g  <= green;
	vga_b  <= blue;
	vga_hs <= hsync;
	vga_vs <= vsync;
	vga_de <= visible;
end

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;
assign VGA_R  = vga_r;
assign VGA_G  = vga_g;
assign VGA_B  = vga_b;
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;
assign VGA_DE = vga_de;

///////////////////////   KEYBOARD   /////////////////////////////

wire [7:0] keycode;

keyboard kbd
(
	.clk(clk_sys),
	.reset(reset),
	.ps2_key(ps2_key),
	.key_byte(keycode)
);

///////////////////////   PPU BUS   //////////////////////////////

wire       ppu_vm_init_o;
wire       ppu_vm_virq_i;

wire [16:0]ppu_wbm_adr_o;
wire [15:0]ppu_wbm_dat_o;
wire [15:0]ppu_wbm_dat_i;
wire       ppu_wbm_cyc_o;
wire       ppu_wbm_wre_o;
wire [ 1:0]ppu_wbm_sel_o;
wire       ppu_wbm_stb_o;
wire       ppu_wbm_ack_i;
wire [15:0]ppu_wbi_dat_i;
wire       ppu_wbi_ack_i;
wire       ppu_wbi_stb_o;

wire       ppu_vm_virq_i_vp;
wire [15:0]ppu_wbm_dat_i_vp;
wire       ppu_wbm_ack_i_vp;
wire [15:0]ppu_wbi_dat_i_vp;
wire       ppu_wbi_ack_i_vp;

wire       pin_tmr_ena_o;
wire [15:0]ppu_wbm_dat_i_128;
wire       ppu_wbm_ack_i_128;
wire [15:0]ppu_wbm_dat_i_xm2;
wire       ppu_vm_virq_i_xm2;
wire       ppu_wbm_ack_i_xm2;

wire [15:0]ppu_wbi_dat_i_xm2;
wire       ppu_wbi_ack_i_xm2;
wire       ppu_wbi_stb_o_xm2;

wire [15:0]ppu_wbm_dat_i_abr;
wire       ppu_wbm_ack_i_abr;
wire [15:0]ppu_wbm_dat_i_cvx;
wire       ppu_wbm_ack_i_cvx;

assign ppu_vm_virq_i = ppu_vm_virq_i_xm2 | ppu_vm_virq_i_vp;

// Acks are ORed and the data is a priority mux, as in tang-uknc's top.v:
// two devices answering one address would be silent here.
assign ppu_wbm_dat_i = ppu_wbm_ack_i_xm2 ? ppu_wbm_dat_i_xm2 :
                       ppu_wbm_ack_i_vp  ? ppu_wbm_dat_i_vp  :
                       ppu_wbm_ack_i_128 ? ppu_wbm_dat_i_128 :
                       ppu_wbm_ack_i_abr ? ppu_wbm_dat_i_abr :
                       ppu_wbm_ack_i_cvx ? ppu_wbm_dat_i_cvx : 16'o0;

assign ppu_wbm_ack_i = ppu_wbm_ack_i_xm2 | ppu_wbm_ack_i_vp | ppu_wbm_ack_i_128 |
                       ppu_wbm_ack_i_abr | ppu_wbm_ack_i_cvx;

assign ppu_wbi_dat_i = ppu_wbi_ack_i_xm2 ? ppu_wbi_dat_i_xm2 :
                       ppu_wbi_ack_i_vp  ? ppu_wbi_dat_i_vp  : 16'o0;
assign ppu_wbi_ack_i = ppu_wbi_ack_i_xm2 | ppu_wbi_ack_i_vp;

wire pp_rst = reset | ~mem_init;

ppu_wb ppu1
(
	.clk_ppu_p    (ppuclk_p),
	.clk_ppu_n    (ppuclk_n),
	.rst          (pp_rst),
	.clk50hz      (vsync),

	.addr_ram     (addr_ppu_o),
	.duot_ram     (data_ppu_o),
	.dinp_ram     (data_ppu_i),
	.mask_ram     (mask_ppu_o),
	.read_ram     (read_ppu_o),
	.wrte_ram     (wrte_ppu_o),
	.askn_ram     (askn_ppu_i),

	.pin_vm_init_o(ppu_vm_init_o),
	.pin_vm_dclo_o(),
	.pin_vm_aclo_o(),

	.pin_vm_virq_i(ppu_vm_virq_i),

	.pin_wbm_adr_o(ppu_wbm_adr_o),
	.pin_wbm_dat_o(ppu_wbm_dat_o),
	.pin_wbm_dat_i(ppu_wbm_dat_i),
	.pin_wbm_cyc_o(ppu_wbm_cyc_o),
	.pin_wbm_wre_o(ppu_wbm_wre_o),
	.pin_wbm_sel_o(ppu_wbm_sel_o),
	.pin_wbm_stb_o(ppu_wbm_stb_o),
	.pin_wbm_ack_i(ppu_wbm_ack_i),
	.pin_wbi_dat_i(ppu_wbi_dat_i),
	.pin_wbi_ack_i(ppu_wbi_ack_i),
	.pin_wbi_stb_o(ppu_wbi_stb_o),

	.pin_tmr_ena_o(pin_tmr_ena_o),
	.pin_cart_sel_o(),
	.pin_cart_bank_o(),

	.rom_wr_clk   (clk_sys),
	.rom_wr_addr  (ioctl_addr[14:1]),
	.rom_wr_data  (ioctl_dout),
	.rom_wr_en    (rom_wr_en)
);

wire sound;
wire cpu_vm_dclo_i;
wire cpu_vm_aclo_i;
wire pin_vm_halt_i;

xm2_01 dd1
(
	.pin_vm_clk25 (clk_25),
	.pin_vm_clk_p (ppuclk_n),

	.pin_vm_init_i(ppu_vm_init_o),

	.pin_vm_virq_o(ppu_vm_virq_i_xm2),

	.pin_wbm_adr_i(ppu_wbm_adr_o),
	.pin_wbm_dat_i(ppu_wbm_dat_o),
	.pin_wbm_dat_o(ppu_wbm_dat_i_xm2),

	.pin_wbm_wre_i(ppu_wbm_wre_o),

	.pin_wbm_stb_i(ppu_wbm_stb_o),
	.pin_wbm_ack_o(ppu_wbm_ack_i_xm2),

	.pin_wbi_dat_o(ppu_wbi_dat_i_xm2),
	.pin_wbi_ack_o(ppu_wbi_ack_i_xm2),
	.pin_wbi_stb_i(ppu_wbi_stb_o),

	.pin_vm_dclo_o(cpu_vm_dclo_i),
	.pin_vm_aclo_o(cpu_vm_aclo_i),
	.pin_vm_halt_o(pin_vm_halt_i),

	.pin_wbi_stb_o(ppu_wbi_stb_o_xm2),

	.but_data     (keycode),

	.sound        (sound)
);

// The CPU's DCLO/ACLO/HALT come from the PPU's R177716; into the CPU's
// clock domain through two flops, as on the Tang.
reg [1:0] cpu_dclo_s = 2'b11;
reg [1:0] cpu_aclo_s = 2'b11;
reg [1:0] cpu_halt_s = 2'b00;
always @(posedge cpuclk_p) begin
	cpu_dclo_s <= {cpu_dclo_s[0], cpu_vm_dclo_i};
	cpu_aclo_s <= {cpu_aclo_s[0], cpu_vm_aclo_i};
	cpu_halt_s <= {cpu_halt_s[0], pin_vm_halt_i};
end

///////////////////////   FLOPPY DISKS   /////////////////////////

// A drive has a disk when a non-empty image is mounted in it; one mounted
// read-only is write protected, and the OSD can protect them all.
reg [DRIVES-1:0] mount_dsk = 0;
reg [DRIVES-1:0] img_ro    = 0;

always @(posedge clk_sys)
	for(int i = 0; i < DRIVES; i++)
		if(img_mounted[i]) begin
			mount_dsk[i] <= |img_size;
			img_ro[i]    <= img_readonly;
		end

wire [DRIVES-1:0] fdd_wprot = img_ro | {DRIVES{status[11]}};

wire [15:0] disk_data_in;     // controller -> drive
wire [15:0] disk_data_out;    // drive -> controller
wire        disk_write;
wire [ 1:0] disk_drive;
wire        disk_motor;
wire        disk_step;
wire        disk_dir;
wire        disk_head;
wire        disk_valid;
wire        disk_sync;
wire        disk_crc_ok;
wire        disk_rdy;
wire        disk_tr0;
wire        disk_ind;
wire [31:0] fdd_lba;
wire [15:0] fdd_buff_din;

fdd4 fdd
(
	.pin_25mhz_ck (clk_25),
	.ppu_vm_init_i(ppu_vm_init_o),

	.data_in      (disk_data_in),
	.data_out     (disk_data_out),
	.write        (disk_write),

	.drive        (disk_drive),
	.motor        (disk_motor),
	.step         (disk_step),
	.dir          (disk_dir),
	.head         (disk_head),
	.valid        (disk_valid),
	.sync         (disk_sync),
	.crc_ok       (disk_crc_ok),
	.rdy          (disk_rdy),
	.tr0          (disk_tr0),
	.ind          (disk_ind),

	.mount_dsk    (mount_dsk),

	.sd_clk       (clk_sys),
	.sd_lba       (fdd_lba),
	.sd_rd        (sd_rd),
	.sd_wr        (sd_wr),
	.sd_ack       (sd_ack),
	.sd_buff_addr (sd_buff_addr[7:0]),
	.sd_buff_dout (sd_buff_dout),
	.sd_buff_din  (fdd_buff_din),
	.sd_buff_wr   (sd_buff_wr)
);

// One request is up at a time, so every drive gets the same LBA and buffer.
assign sd_lba      = '{DRIVES{fdd_lba}};
assign sd_buff_din = '{DRIVES{fdd_buff_din}};

assign LED_DISK = {1'b0, disk_motor};

vp1_128fdd vp128
(
	.ppu_vm_clk_p (ppuclk_n),

	.ppu_vm_init_i(ppu_vm_init_o),

	.ppu_wbm_adr_i(ppu_wbm_adr_o),
	.ppu_wbm_dat_i(ppu_wbm_dat_o),
	.ppu_wbm_dat_o(ppu_wbm_dat_i_128),
	.ppu_wbm_cyc_i(ppu_wbm_cyc_o),
	.ppu_wbm_wre_i(ppu_wbm_wre_o),
	.ppu_wbm_stb_i(ppu_wbm_stb_o),
	.ppu_wbm_ack_o(ppu_wbm_ack_i_128),

	.data_in      (disk_data_out),
	.data_out     (disk_data_in),
	.write        (disk_write),

	.drive        (disk_drive),
	.motor        (disk_motor),
	.step         (disk_step),
	.dir          (disk_dir),
	.head         (disk_head),
	.valid        (disk_valid),
	.sync         (disk_sync),
	.crc_ok       (disk_crc_ok),
	.rdy          (disk_rdy),
	.tr0          (disk_tr0),
	.ind          (disk_ind),
	.wrprt_dsk    (fdd_wprot),
	.fdd_en       (1'b1)
);

///////////////////////   SOUND   ////////////////////////////////

wire [9:0] ay_a_channel;
wire [9:0] ay_b_channel;
wire [9:0] ay_c_channel;

wire [2:0] ay_en  = status[7] ? 3'b000 : 3'b111;
// OSD order: 177372, Off, LPT, Both -> {LPT, 177372}
wire [1:0] covox_en = (status[9:8] == 2'd0) ? 2'b01 :
                      (status[9:8] == 2'd1) ? 2'b00 :
                      (status[9:8] == 2'd2) ? 2'b10 : 2'b11;

aberrant ay1
(
	.ppu_vm_clk_p (ppuclk_n),

	.ppu_vm_init_i(ppu_vm_init_o),

	.ppu_wbm_adr_i(ppu_wbm_adr_o),
	.ppu_wbm_dat_i(ppu_wbm_dat_o),
	.ppu_wbm_dat_o(ppu_wbm_dat_i_abr),
	.ppu_wbm_cyc_i(ppu_wbm_cyc_o),
	.ppu_wbm_wre_i(ppu_wbm_wre_o),
	.ppu_wbm_sel_o(ppu_wbm_sel_o),
	.ppu_wbm_stb_i(ppu_wbm_stb_o),
	.ppu_wbm_ack_o(ppu_wbm_ack_i_abr),

	.ay_en        (ay_en),

	.a_channel    (ay_a_channel),
	.b_channel    (ay_b_channel),
	.c_channel    (ay_c_channel),
	.m_channel    ()
);

wire [7:0] covox_sample;

covox cvx1
(
	.clk   (ppuclk_n),
	.init  (ppu_vm_init_o),
	.en    (covox_en[0]),
	.adr   (ppu_wbm_adr_o),
	.dat_i (ppu_wbm_dat_o),
	.dat_o (ppu_wbm_dat_i_cvx),
	.wre   (ppu_wbm_wre_o),
	.sel   (ppu_wbm_sel_o),
	.stb   (ppu_wbm_stb_o),
	.ack   (ppu_wbm_ack_i_cvx),
	.sample(covox_sample)
);

wire [7:0] lpt_data;
reg  [7:0] lpt_sample = 8'd0;
always @(posedge ppuclk_p) lpt_sample <= covox_en[1] ? lpt_data : 8'd0;

wire [15:0] volume_data_l;
wire [15:0] volume_data_r;

mixer mix1
(
	.clk      (ppuclk_p),
	.ay_a     (ay_a_channel),
	.ay_b     (ay_b_channel),
	.ay_c     (ay_c_channel),
	.beep     (sound & ~status[10]),
	.covox    (covox_sample),
	.lpt      (lpt_sample),
	.stereo   (~status[4]),
	.lowpass  (~status[5]),
	.oldfreaks(status[6]),
	.volume   (2'd3 - status[3:2]),
	.out_l    (volume_data_l),
	.out_r    (volume_data_r)
);

// The mixer runs on the PPU clock; bring its words onto clk_sys.
reg [15:0] audio_l_s, audio_r_s, audio_l, audio_r;
always @(posedge clk_sys) begin
	audio_l_s <= volume_data_l;  audio_l <= audio_l_s;
	audio_r_s <= volume_data_r;  audio_r <= audio_r_s;
end

assign AUDIO_S = 1;
assign AUDIO_L = audio_l;
assign AUDIO_R = audio_r;

///////////////////////   CPU BUS   //////////////////////////////

wire [15:0]vp65_wbm_dat_i;
wire [15:0]vp65_wbi_dat_i;
wire       vp65_vm_virq_i;
wire       vp65_wbm_ack_i;
wire       vp65_wbi_ack_i;
wire       cpu_vm_init_o;

wire       cpu_vm_virq_i_vp;
wire [15:0]cpu_wbm_dat_i_vp;
wire       cpu_wbm_ack_i_vp;
wire [15:0]cpu_wbi_dat_i_vp;
wire       cpu_wbi_ack_i_vp;

wire       cpu_vm_virq_i = cpu_vm_virq_i_vp | vp65_vm_virq_i;

wire [16:0]cpu_wbm_adr_o;
wire [15:0]cpu_wbm_dat_o;
wire [15:0]cpu_wbm_dat_i = cpu_wbm_ack_i_vp ? cpu_wbm_dat_i_vp :
                           vp65_wbm_ack_i   ? vp65_wbm_dat_i   : 16'o0;
wire       cpu_wbm_cyc_o;
wire       cpu_wbm_wre_o;
wire [ 1:0]cpu_wbm_sel_o;
wire       cpu_wbm_stb_o;
wire       cpu_wbm_ack_i = cpu_wbm_ack_i_vp | vp65_wbm_ack_i;

wire [15:0]cpu_wbi_dat_i = cpu_wbi_ack_i_vp ? cpu_wbi_dat_i_vp :
                           vp65_wbi_ack_i   ? vp65_wbi_dat_i   : 16'o0;
wire       cpu_wbi_ack_i = cpu_wbi_ack_i_vp | vp65_wbi_ack_i;
wire       cpu_wbi_stb_o;

cpu_wb cpu1
(
	.clk_ppu_p    (cpuclk_p),
	.clk_ppu_n    (cpuclk_n),
	.clk50hz      (vsync),

	.addr_ram     (addr_cpu_o),
	.duot_ram     (data_cpu_o),
	.dinp_ram     (data_cpu_i),
	.mask_ram     (mask_cpu_o),
	.read_ram     (read_cpu_o),
	.wrte_ram     (wrte_cpu_o),
	.askn_ram     (askn_cpu_i),

	.pin_vm_init_o(cpu_vm_init_o),
	.pin_vm_dclo_i(cpu_dclo_s[1]),
	.pin_vm_aclo_i(cpu_aclo_s[1]),
	.pin_vm_halt_i(cpu_halt_s[1]),

	.pin_vm_virq_i(cpu_vm_virq_i),

	.pin_wbm_adr_o(cpu_wbm_adr_o),
	.pin_wbm_dat_o(cpu_wbm_dat_o),
	.pin_wbm_dat_i(cpu_wbm_dat_i),
	.pin_wbm_cyc_o(cpu_wbm_cyc_o),
	.pin_wbm_wre_o(cpu_wbm_wre_o),
	.pin_wbm_sel_o(cpu_wbm_sel_o),
	.pin_wbm_stb_o(cpu_wbm_stb_o),
	.pin_wbm_ack_i(cpu_wbm_ack_i),
	.pin_wbi_dat_i(cpu_wbi_dat_i),
	.pin_wbi_ack_i(cpu_wbi_ack_i),
	.pin_wbi_stb_o(cpu_wbi_stb_o),

	.pin_tmr_ena_i(pin_tmr_ena_o)
);

wire cpu_wbi_stb_o_vp1;   // the CPU's interrupt-ack chain, on to vp65

// The channels between the processors (KR1801VP1-120)
vp1_120 vp1
(
	.clk          (clk_25),

	.cpu_vm_init_i(cpu_vm_init_o),

	.cpu_vm_virq_o(cpu_vm_virq_i_vp),

	.cpu_wbm_adr_i(cpu_wbm_adr_o),
	.cpu_wbm_dat_i(cpu_wbm_dat_o),
	.cpu_wbm_dat_o(cpu_wbm_dat_i_vp),
	.cpu_wbm_cyc_i(cpu_wbm_cyc_o),
	.cpu_wbm_wre_i(cpu_wbm_wre_o),
	.cpu_wbm_sel_i(cpu_wbm_sel_o),
	.cpu_wbm_stb_i(cpu_wbm_stb_o),
	.cpu_wbm_ack_o(cpu_wbm_ack_i_vp),
	.cpu_wbi_dat_o(cpu_wbi_dat_i_vp),
	.cpu_wbi_ack_o(cpu_wbi_ack_i_vp),
	.cpu_wbi_stb_i(cpu_wbi_stb_o),

	.cpu_wbi_stb_o(cpu_wbi_stb_o_vp1),

	.ppu_vm_init_i(ppu_vm_init_o),

	.ppu_vm_virq_o(ppu_vm_virq_i_vp),

	.ppu_wbm_adr_i(ppu_wbm_adr_o),
	.ppu_wbm_dat_i(ppu_wbm_dat_o),
	.ppu_wbm_dat_o(ppu_wbm_dat_i_vp),
	.ppu_wbm_cyc_i(ppu_wbm_cyc_o),
	.ppu_wbm_wre_i(ppu_wbm_wre_o),
	.ppu_wbm_sel_i(ppu_wbm_sel_o),
	.ppu_wbm_stb_i(ppu_wbm_stb_o),
	.ppu_wbm_ack_o(ppu_wbm_ack_i_vp),
	.ppu_wbi_dat_o(ppu_wbi_dat_i_vp),
	.ppu_wbi_ack_o(ppu_wbi_ack_i_vp),
	.ppu_wbi_stb_i(ppu_wbi_stb_o_xm2),

	.ppu_wbi_stb_o(),

	.lpt_data     (lpt_data)
);

// The serial port (KR1801VP1-065), on the MiSTer UART
vp065 dd2
(
	.pin_50MHz_clk(clk_50),
	.pin_vm_clk_p (cpuclk_n),

	.pin_vm_init_i(cpu_vm_init_o),

	.pin_vm_virq_o(vp65_vm_virq_i),

	.pin_wbm_adr_i(cpu_wbm_adr_o),
	.pin_wbm_dat_i(cpu_wbm_dat_o),
	.pin_wbm_dat_o(vp65_wbm_dat_i),
	.pin_wbm_wre_i(cpu_wbm_wre_o),
	.pin_wbm_stb_i(cpu_wbm_stb_o),
	.pin_wbm_ack_o(vp65_wbm_ack_i),
	.pin_wbi_dat_o(vp65_wbi_dat_i),
	.pin_wbi_ack_o(vp65_wbi_ack_i),
	.pin_wbi_stb_i(cpu_wbi_stb_o_vp1),

	.pin_wbi_stb_o(),

	.pin_tx_o     (UART_TXD),
	.pin_rx_i     (UART_RXD),
	.pin_ac_o     ()
);

///////////////////////   LEDS   /////////////////////////////////

assign LED_USER = sound;

endmodule
