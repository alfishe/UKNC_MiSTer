//
// uartfifo.v
//
// Stand-in for the Gowin FIFO IP of the same name used by vp65.v in
// tang-uknc: 4 entries of 8 bits, independent clocks, Q registered on RdEn.
// Gray-coded pointers, two-flop synchronisers.
//
module uartfifo
(
   input  [7:0] Data,
   input        WrClk,
   input        WrEn,
   input        RdClk,
   input        RdEn,
   output reg [7:0] Q,
   output       Empty,
   output       Full
);

localparam AW = 2;

reg  [7:0]  mem[0:(1<<AW)-1];

reg  [AW:0] wbin = 0, wgray = 0;
reg  [AW:0] rbin = 0, rgray = 0;
reg  [AW:0] rgray_w1 = 0, rgray_w2 = 0;   // read pointer in the write domain
reg  [AW:0] wgray_r1 = 0, wgray_r2 = 0;   // write pointer in the read domain

wire [AW:0] wbin_next  = wbin + 1'd1;
wire [AW:0] rbin_next  = rbin + 1'd1;

assign Full  = wgray == {~rgray_w2[AW:AW-1], rgray_w2[AW-2:0]};
assign Empty = rgray == wgray_r2;

always @(posedge WrClk) begin
   {rgray_w2, rgray_w1} <= {rgray_w1, rgray};
   if(WrEn && !Full) begin
      mem[wbin[AW-1:0]] <= Data;
      wbin  <= wbin_next;
      wgray <= wbin_next ^ (wbin_next >> 1);
   end
end

always @(posedge RdClk) begin
   {wgray_r2, wgray_r1} <= {wgray_r1, wgray};
   if(RdEn && !Empty) begin
      Q     <= mem[rbin[AW-1:0]];
      rbin  <= rbin_next;
      rgray <= rbin_next ^ (rbin_next >> 1);
   end
end

endmodule
