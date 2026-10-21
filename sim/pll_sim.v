//
// pll_sim.v
//
// Simulation stand-in for rtl/pll.v: outclk_0 is the reference itself and
// outclk_1 divides it by 12, the 50 MHz -> 4.1667 MHz of the real PLL.
//
module pll
(
   input      refclk,
   input      rst,
   output     outclk_0,
   output reg outclk_1 = 1'b0,
   output     locked
);

localparam CPU_DIVIDER = 12;
localparam HALF_PERIOD = CPU_DIVIDER / 2;

reg [3:0] cnt = 0;

always @(posedge refclk) begin
   if(cnt == HALF_PERIOD - 1) begin
      cnt      <= 0;
      outclk_1 <= ~outclk_1;
   end
   else cnt <= cnt + 1'd1;
end

assign outclk_0 = refclk;
assign locked   = ~rst;

endmodule
