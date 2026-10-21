//
// uknc_mem.sv
//
// UKNC main memory, the CPU/PPU memory arbiter and the display generator.
//
// Derived from tang-uknc sdram2.v (MIT, Alexey Gurov, Sergei Lemeshev and
// contributors): the same 16-phase cycle on horz[3:0], the same slots for
// the display and the two processors, the same video generator.  The SDRAM
// is replaced by block RAM, which the DE10-Nano has room for: the whole
// machine is 192 KB.
//
//   plane 0     32K x 16  the "PPU zone": PPU RAM, video plane 0 (blue)
//   planes 1,2  64K x 16  the "CPU zone": CPU RAM, low byte plane 1 (green),
//                         high byte plane 2 (red)
//
// Ports are the sdram2 ones: 32-bit data, bits 15:0 the PPU zone and bits
// 31:16 the CPU zone, dqm active high (1 = byte lane not written).  The PPU
// zone is addressed by addr[15:1] (a byte address), the CPU zone by
// addr[15:0] (a plane offset).
//
// Timing.  The SDRAM controller issued a READ on phase N and sampled the
// data on phase N+2.  A block RAM registers its address on one edge and has
// the data after it, so here the address for a sample taken on phase N+2 is
// presented on phase N+1 - same sampling phases, same values.  A processor
// therefore sees exactly the latency it saw on the Tang, which matters:
// the machine's speed was tuned against it.
//
module uknc_mem(
   input             clkram,      // 50 MHz
   input             lockclk,     // PLL locked
   output            init,        // high once memory and video are running

   output            hsync,
   output            vsync,
   output            visible,
   output            ce_pix,      // one clkram in two: the 25 MHz pixel rate
   output     [ 7:0] red,
   output     [ 7:0] green,
   output     [ 7:0] blue,

   output            clk_25,
   output            clk_50,

   input      [18:0] cpu_addr,
   output reg [31:0] cpu_dout,
   input      [31:0] cpu_din,
   input      [ 3:0] cpu_dqm,
   input             cpu_read,
   input             cpu_wrte,
   output reg        cpu_busy,
   output reg        cpu_asck,

   output            ppu_clk,     // 3.125 MHz
   output            cpu_clk,     // 4.1667 MHz
   input      [18:0] ppu_addr,
   output reg [31:0] ppu_dout,
   input      [31:0] ppu_din,
   input      [ 3:0] ppu_dqm,
   input             ppu_read,
   input             ppu_wrte,
   output reg        ppu_busy,
   output reg        ppu_asck
);

// ---------------------------------------------------------------------
// Start-up.  Nothing to initialise in a block RAM; the counter only holds
// init low for a moment after lock so that every clock derived below is
// running before the processors leave reset.
// ---------------------------------------------------------------------
localparam INIT_DELAY_BITS = 16;   // 65536 clkram cycles, 1.3 ms

// The PLL's lock is asynchronous: every counter below takes it through
// the same two flops, so they all leave reset on the same edge.
reg  [1:0] lock_s = 2'b00;
always @(posedge clkram) lock_s <= {lock_s[0], lockclk};
wire locked = lock_s[1];

reg  [INIT_DELAY_BITS-1:0] settle = 0;
always @(posedge clkram)
   if(!locked) settle <= 0;
   else if(~&settle) settle <= settle + 1'd1;

assign init = &settle;

// ---------------------------------------------------------------------
// Display timing.  horz counts clkram cycles of a line; vert counts lines.
// ---------------------------------------------------------------------
localparam HSYNC = 64;
localparam HBP   = 80;
localparam HACTV = 640;
localparam HFP   = 16;
localparam HSTR  = 800;

localparam VSYNC = 3;
localparam VBP   = 14;
localparam VACTV = 600;
localparam VFP   = 1;
localparam VSTR  = 618;

localparam HORZ_LAST = HSTR*2 - 1;
localparam VERT_LAST = VSTR - 1;

// The first 20 and the last 6 of the 600 active lines are blanked, as on
// the Tang: the machine's 288 lines doubled are 576.
localparam VSHOW_FIRST = 20;
localparam VSHOW_END   = VACTV - 6;

// The line table starts here on every frame (PPU RAM, 0270).
localparam LINE_TABLE = 16'o270;

reg  [10:0] horz = 0;
reg  [ 9:0] vert = 0;
reg  [15:0] vga_adst = 0;        // address of the line's data
reg  [15:0] vga_adnx = LINE_TABLE;  // address of the next control word
reg  qutro_reg = 0;
reg  types_reg = 0;
reg  vga_curs  = 0;
reg  ppu_ll = 0;
reg  ppu_hl = 0;
reg  cpu_vl = 0;
reg  curs_set = 1'b0;
reg [31:0] vga_regi = 0;         // line attributes
reg [31:0] vga_regc = 0;         // line palette

reg  curs_set_d = 1'b0;
always @(posedge clkram)begin
    curs_set_d <= curs_set;
    if(new_scr)                       vga_curs <= 1'b0;
    else if(curs_set && !curs_set_d)  vga_curs <= ~vga_curs;
end

wire [6:0] xx = horz[10:4];
wire refresh  = xx == 83;        // the SDRAM's refresh slot, kept idle
wire get_regs = xx == 80;

wire [15:0]addr_reg = qutro_reg ?  {vga_adnx[15:3],3'b000} : {vga_adnx[15:2],2'b00};
wire [15:0]addr_scr = vga_adst + adtx;

wire [ 3:0] q = horz[3:0];
wire cpu_select = &ppu_dqm_new[3:2];

// End of frame: the line table pointer is reset here.
localparam NEW_SCR_HORZ = 1279;
wire new_scr = vert==VERT_LAST && horz==NEW_SCR_HORZ;
wire get_regs_new = ~(vert>19 && vert[0]);

reg  [18:0] cpu_addr_new = 0;
reg  [31:0] cpu_din_new  = 0;
reg  [ 3:0] cpu_dqm_new  = 0;
reg  cpu_read_new = 0;
reg  cpu_wrte_new = 0;

reg  [18:0] ppu_addr_new = 0;
reg  [31:0] ppu_din_new  = 0;
reg  [ 3:0] ppu_dqm_new  = 0;
reg  ppu_read_new = 0;
reg  ppu_wrte_new = 0;

// The PPU gets one memory slot in four (sdram2's ppu_emul).
reg  [ 3:0] ppu_emul = 4'b0001;

reg  [15:0] pr_blue_data  = 0;
reg  [ 7:0] pr_green_data = 0;
reg  [ 7:0] pr_red_data   = 0;

reg  [ 7:0] blue_data  = 0;
reg  [ 7:0] green_data = 0;
reg  [ 7:0] red_data   = 0;

// ---------------------------------------------------------------------
// The two memories.  Address and write enable are functions of the phase;
// see the timing note at the top.
// ---------------------------------------------------------------------
localparam PLANE0_AW  = 15;
localparam PLANE12_AW = 16;

reg  [PLANE0_AW-1:0]  p0_addr;
reg  [15:0]           p0_wdata;
reg  [ 1:0]           p0_we;
wire [15:0]           p0_q;

reg  [PLANE12_AW-1:0] p12_addr;
reg  [15:0]           p12_wdata;
reg  [ 1:0]           p12_we;
wire [15:0]           p12_q;

uknc_bram #(.AW(PLANE0_AW)) plane0 (
   .clk(clkram), .addr(p0_addr), .wdata(p0_wdata), .we(p0_we), .q(p0_q)
);

uknc_bram #(.AW(PLANE12_AW)) plane12 (
   .clk(clkram), .addr(p12_addr), .wdata(p12_wdata), .we(p12_we), .q(p12_q)
);

wire run = init && !refresh;

always @(*) begin
   p0_addr   = addr_scr[15:1];
   p0_wdata  = ppu_din_new[15:0];
   p0_we     = 2'b00;
   p12_addr  = addr_scr[15:0];
   p12_wdata = ppu_din_new[31:16];
   p12_we    = 2'b00;

   case(q)
   // display: control words sampled on 4..7, plane 0 data on 4
   4'd3:  p0_addr = get_regs ? addr_reg[15:1]           : addr_scr[15:1];
   4'd4:  p0_addr = addr_reg[15:1] + 15'd1;
   4'd5:  p0_addr = addr_reg[15:1] + 15'd2;
   4'd6:  p0_addr = addr_reg[15:1] + 15'd3;
   // PPU zone for the PPU: written on 10, read sampled on 12
   4'd10: if(run && ppu_wrte_new) begin
             p0_addr = ppu_addr_new[15:1];
             p0_we   = ~ppu_dqm_new[1:0];
          end
   4'd11: p0_addr = ppu_addr_new[15:1];
   default: ;
   endcase

   case(q)
   // display: planes 1 and 2 sampled on 7
   4'd6:  p12_addr = addr_scr[15:0];
   // CPU zone for the CPU or the PPU: written on 13, read sampled on 15
   4'd13: if(run) begin
             p12_addr = cpu_select ? cpu_addr_new[15:0] : ppu_addr_new[15:0];
             if(cpu_select ? cpu_wrte_new : ppu_wrte_new) begin
                p12_wdata = cpu_select ? cpu_din_new[31:16] : ppu_din_new[31:16];
                p12_we    = cpu_select ? ~cpu_dqm_new[3:2]  : ~ppu_dqm_new[3:2];
             end
          end
   4'd14: p12_addr = cpu_select ? cpu_addr_new[15:0] : ppu_addr_new[15:0];
   default: ;
   endcase
end

always @(posedge clkram)begin
   ppu_ll <= 1'b0;
   ppu_hl <= 1'b0;
   cpu_vl <= 1'b0;

   if(!tx && !horz[0])begin
      case(vga_regi[21:20])
      2'b00  : blue_data  <= !addr_scr[0] ? pr_blue_data[15:8] : pr_blue_data[7:0];
      default: blue_data  <=  addr_scr[0] ? pr_blue_data[15:8] : pr_blue_data[7:0];
      endcase
      green_data <= pr_green_data;
      red_data   <= pr_red_data;
   end

   if(new_scr)begin
      vga_adnx  <= LINE_TABLE;
      types_reg <= 0;
      qutro_reg <= 0;
      curs_set  <= 0;
   end

   if(horz==HORZ_LAST)begin
      if(vert == VERT_LAST) vert <= 10'd0;
      else vert <= vert + 1'b1;
      horz <= 11'd0;
   end else horz <= horz + 1'b1;

   if(!locked)begin
      horz <= 0;
      vert <= 0;
   end

   if(init && !refresh) begin
      case (q)
      4'd4 : if(get_regs) begin
                if(get_regs_new)begin
                   if(qutro_reg)begin
                      if(types_reg) vga_regc[15: 0] <= p0_q;
                      else          vga_regi[15: 0] <= p0_q;
                   end else         vga_adst        <= p0_q;
                end
             end else begin
                pr_blue_data <= p0_q;
             end
      4'd5 : if(get_regs) begin
                if(get_regs_new)begin
                   if(qutro_reg) begin
                      if(types_reg) vga_regc[31:16] <= p0_q;
                      else          vga_regi[31:16] <= p0_q;
                   end else         vga_adnx        <= p0_q;
                end
             end
      4'd6 : if(get_regs) begin
                if(get_regs_new)begin
                   if(qutro_reg) vga_adst  <= p0_q;
                   else          types_reg <= vga_adnx[2];
                end
             end
      4'd7 : begin
                if(get_regs)begin
                   if(get_regs_new)begin
                      if(qutro_reg)begin
                         vga_adnx  <= p0_q;
                         curs_set  <= p0_q[0];
                         qutro_reg <= p0_q[1];
                         types_reg <= p0_q[2];
                      end else begin
                         qutro_reg <= vga_adnx[1];
                         curs_set  <= vga_adnx[0];
                      end
                   end
                end else begin
                   pr_green_data <= p12_q[ 7:0];
                   pr_red_data   <= p12_q[15:8];
                end

                cpu_addr_new <= cpu_addr;
                cpu_din_new  <= cpu_din;
                cpu_dqm_new  <= cpu_dqm;
                cpu_read_new <= cpu_read;
                cpu_wrte_new <= cpu_wrte;

                ppu_addr_new <= ppu_addr;
                ppu_din_new  <= ppu_din;
                ppu_dqm_new  <= ppu_dqm;
                ppu_read_new <= ppu_read & ppu_emul[0];
                ppu_wrte_new <= ppu_wrte & ppu_emul[0];

                ppu_emul <= {ppu_emul[2:0],ppu_emul[3]};
             end
      4'd10: if(ppu_wrte_new) ppu_ll <= cpu_select;
      4'd12: if(ppu_read_new)begin
                ppu_dout[15: 0] <= p0_q;
                ppu_ll          <= cpu_select;
             end
      4'd13: if(cpu_select) begin
                if(cpu_wrte_new) cpu_vl <= 1'b1;
             end else begin
                if(ppu_wrte_new) ppu_hl <= 1'b1;
             end
      4'd15: if(cpu_select)begin
                cpu_vl <= cpu_read_new;
                cpu_dout[31:16] <= p12_q;
             end else begin
                ppu_hl <= ppu_read_new;
                ppu_dout[31:16] <= p12_q;
             end
      default: ;
      endcase
   end
end

// ---------------------------------------------------------------------
// busy/asck towards the processors
// ---------------------------------------------------------------------
always @(posedge clkram)begin
   if(init)begin
      if(ppu_read|ppu_wrte && !ppu_asck) ppu_busy <= 1'b1;
      else ppu_busy <= 1'b0;
      if(!(ppu_read|ppu_wrte)) ppu_asck <= 1'b0;
      if(ppu_hl||ppu_ll) ppu_asck <= 1'b1;

      if(cpu_read|cpu_wrte && !cpu_asck) cpu_busy <= 1'b1;
      else cpu_busy <= 1'b0;
      if(!(cpu_read|cpu_wrte)) cpu_asck <= 1'b0;
      if(cpu_vl) cpu_asck <= 1'b1;
   end else begin
      ppu_busy <= 1'b0;
      ppu_asck <= 1'b0;
      cpu_busy <= 1'b1;
      cpu_asck <= 1'b0;
   end
end

// ---------------------------------------------------------------------
// Clocks off counters of clkram, from flops of their own (sdram2).
// clk25_q is horz[0]; clk312_q toggles where horz[3] does.  The CPU's
// clock comes off a counter of its own here rather than off the PLL, so
// that its phase against the other two is the same at every start: all
// three counters leave reset on the same clkram edge.  Counting that edge
// as the first, clk_25 rises on odd edges, the PPU clock on edges 8 + 16n
// and the CPU clock on edges 1 + 12n; UKNC.sdc gives the tool exactly
// these edges.
// ---------------------------------------------------------------------
localparam CPU_DIV  = 12;              // 50 MHz / 12 = 4.1667 MHz
localparam CPU_HIGH = CPU_DIV / 2;

reg clk25_q  = 1'b0;
reg clk312_q = 1'b0;
reg clkcpu_q = 1'b0;
reg [3:0] cpu_phase = 4'd0;            // edges since reset, mod CPU_DIV
wire [3:0] cpu_phase_n = cpu_phase == CPU_DIV - 1 ? 4'd0 : cpu_phase + 4'd1;

always @(posedge clkram)
   if(!locked)begin
      clk25_q   <= 1'b0;
      clk312_q  <= 1'b0;
      clkcpu_q  <= 1'b0;
      cpu_phase <= 4'd0;
   end else begin
      clk25_q   <= ~horz[0];
      clk312_q  <= horz[3] ^ (&horz[2:0]);
      cpu_phase <= cpu_phase_n;
      clkcpu_q  <= cpu_phase_n >= 4'd1 && cpu_phase_n <= CPU_HIGH;
   end

assign clk_50  = clkram;
assign clk_25  = clk25_q;
assign ppu_clk = clk312_q;
assign cpu_clk = clkcpu_q;
assign ce_pix  = horz[0];

// ---------------------------------------------------------------------
// Video generator
// ---------------------------------------------------------------------
wire [ 9:0]x  = horz[10:1];
wire [ 9:0]xs = visible_x ? horz[10:1] - 10'd8 : 10'd0;

// visible_x starts 8 pixels late: the first byte of a line is fetched
// eight pixels ahead of its display.
wire  visible_y = vert < VACTV;
wire  visible_x = horz >= 16 && horz < (HACTV + 8)*2;
wire  visible_z = vert > (VSHOW_FIRST-1) && vert < VSHOW_END;

wire   visiblez  = visible_x && visible_z;
assign visible   = visible_x && visible_y;

assign hsync     = horz >= (HACTV + HFP)*2 && horz < (HACTV + HFP + HSYNC)*2;
assign vsync     = vert >= (VACTV + VFP)   && vert < (VACTV + VFP + VSYNC);

// adtx: byte of the line, from x = 0; indx: from the visible start; tx: the
// bit within the byte.
wire [ 9:0]adtx= vga_regi[21:20] == 0 ?  x[9:3] :
                 vga_regi[21:20] == 1 ?  x[9:4] :
                 vga_regi[21:20] == 2 ?  x[9:5] :  x[9:6];

wire [ 9:0]indx= vga_regi[21:20] == 0 ? xs[9:3] :
                 vga_regi[21:20] == 1 ? xs[9:4] :
                 vga_regi[21:20] == 2 ? xs[9:5] : xs[9:6];

wire [ 2:0]tx  = vga_regi[21:20] == 0 ? xs[2:0] :
                 vga_regi[21:20] == 1 ? xs[3:1] :
                 vga_regi[21:20] == 2 ? xs[4:2] : xs[5:3];

reg  [ 2:0]tripl = 0;

always @(posedge clkram)
    if(horz[0])begin
        tripl[0] <= blue_data [tx];
        tripl[1] <= green_data[tx];
        tripl[2] <= red_data  [tx];
    end

reg  [ 3:0]cvt;

always @(*)
    case(tripl)
    3'b000: cvt = vga_regc[ 3: 0];
    3'b001: cvt = vga_regc[ 7: 4];
    3'b010: cvt = vga_regc[11: 8];
    3'b011: cvt = vga_regc[15:12];
    3'b100: cvt = vga_regc[19:16];
    3'b101: cvt = vga_regc[23:20];
    3'b110: cvt = vga_regc[27:24];
    3'b111: cvt = vga_regc[31:28];
    endcase

reg  [ 6:0] xcursor;
always @(*)
   case(vga_regi[21:20])
   2'b00: xcursor = vga_regi[14: 8];
   2'b01: xcursor = {1'b0, vga_regi[14: 9]};
   2'b10: xcursor = {2'b0, vga_regi[14:10]};
   2'b11: xcursor = {3'b0, vga_regi[14:11]};
   endcase

wire        cursor_pos = {3'd0, xcursor} == indx;
wire        cursor_pos_byte = tx==vga_regi[7:5] || !vga_regi[4];
wire        iscursor   = cursor_pos & vga_curs & cursor_pos_byte;

// A colour channel's level comes from the palette's Y bit and the line's
// intensity bit for that channel (vga_regi[16] blue, [17] green, [18] red),
// as in UKNCBTL's colour table.  The cursor takes the place of the pixel
// at full intensity.
localparam [7:0] LEVEL_DIM        = 8'h60;   // Y = 0, intensity off
localparam [7:0] LEVEL_NORMAL     = 8'h80;   // Y = 0, intensity on
localparam [7:0] LEVEL_BRIGHT_DIM = 8'hDF;   // Y = 1, intensity off
localparam [7:0] LEVEL_BRIGHT     = 8'hFF;   // Y = 1, intensity on

localparam CH_BLUE = 0, CH_GREEN = 1, CH_RED = 2;
localparam YRGB_Y  = 3;
localparam INTENSITY_LSB = 16;

function [7:0] level(input on, input y, input intensity);
   level = !on ? 8'd0 :
           y   ? (intensity ? LEVEL_BRIGHT : LEVEL_BRIGHT_DIM) :
                 (intensity ? LEVEL_NORMAL : LEVEL_DIM);
endfunction

wire [ 3:0] yrgb   = iscursor ? vga_regi[3:0] : cvt;
wire [ 2:0] intens = iscursor ? 3'b111 : vga_regi[INTENSITY_LSB +: 3];

assign red   = visiblez ? level(yrgb[CH_RED],   yrgb[YRGB_Y], intens[CH_RED])   : 8'd0;
assign green = visiblez ? level(yrgb[CH_GREEN], yrgb[YRGB_Y], intens[CH_GREEN]) : 8'd0;
assign blue  = visiblez ? level(yrgb[CH_BLUE],  yrgb[YRGB_Y], intens[CH_BLUE])  : 8'd0;

endmodule

// ---------------------------------------------------------------------
// 16-bit single-port RAM with byte enables, inferred as M10K.
// ---------------------------------------------------------------------
module uknc_bram #(parameter AW = 15)
(
   input              clk,
   input  [AW-1:0]    addr,
   input  [15:0]      wdata,
   input  [ 1:0]      we,
   output reg [15:0]  q
);

reg [1:0][7:0] mem[0:(1<<AW)-1];

always @(posedge clk) begin
   if(we[0]) mem[addr][0] <= wdata[ 7:0];
   if(we[1]) mem[addr][1] <= wdata[15:8];
   q <= mem[addr];
end

endmodule
