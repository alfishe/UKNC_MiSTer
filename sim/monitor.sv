//
// monitor.sv
//
// Debug prints from inside the core, enabled with +monitor (PPU bus) and
// +fddmon (the floppy controller and drives).
//
module monitor;

localparam MAX_LINES = 400;

integer lines = 0;
integer fdd_lines = 0;
integer cycles = 0;
reg     on = 0;
reg     fdd_on = 0;
reg     fdd_wr_on = 0;   // every controller write, unlimited: +fddwr
initial begin
   on     = $test$plusargs("monitor");
   fdd_wr_on = $test$plusargs("fddwr");
   fdd_on    = $test$plusargs("fddmon") || fdd_wr_on;
end

always @(posedge sim_top.emu.ppuclk_p) begin
   cycles = cycles + 1;
   if(on && lines < MAX_LINES && sim_top.emu.ppu1.wbm_stb_o && sim_top.emu.ppu1.wbm_ack_i) begin
      $display("%0d PPU %s %o = %o", cycles,
               sim_top.emu.ppu1.wbm_we_o ? "W" : "R", sim_top.emu.ppu1.wbm_adr_o,
               sim_top.emu.ppu1.wbm_we_o ? sim_top.emu.ppu1.wbm_dat_o : sim_top.emu.ppu1.wbm_dat_i);
      lines = lines + 1;
   end
end

reg old_ask = 0;
always @(posedge sim_top.emu.ppuclk_n) if(fdd_on) begin
   old_ask <= sim_top.emu.vp128.ask;
   // the controller samples the bus on this edge; values are the pre-edge ones
   if(sim_top.emu.ppu_wbm_stb_o && sim_top.emu.vp128.r17713x && !sim_top.emu.vp128.ask &&
      (sim_top.emu.ppu_wbm_wre_o ? (fdd_wr_on || sim_top.emu.ppu_wbm_adr_o[1] == 0 && fdd_lines < MAX_LINES)
                                 : fdd_lines < MAX_LINES && !sim_top.emu.ppu_wbm_adr_o[1])) begin
      $display("%0d FDD %s %o = %o trk=%0d sec=%0d", cycles, sim_top.emu.ppu_wbm_wre_o ? "W" : "R",
               sim_top.emu.ppu_wbm_adr_o[15:0],
               sim_top.emu.ppu_wbm_wre_o ? sim_top.emu.ppu_wbm_dat_o :
               {sim_top.emu.disk_ind, sim_top.emu.disk_crc_ok, 6'd0, sim_top.emu.vp128.tr, 4'd0,
                sim_top.emu.vp128.wpr, sim_top.emu.disk_rdy, sim_top.emu.disk_tr0},
               sim_top.emu.fdd.no_trk, sim_top.emu.fdd.no_sec);
      fdd_lines = fdd_lines + 1;
   end
end

reg old_rd = 0, old_wr = 0;
always @(posedge sim_top.emu.clk_25) if(fdd_on) begin
   old_rd <= sim_top.emu.fdd.read_sd;
   old_wr <= sim_top.emu.fdd.wr_go;
   if(sim_top.emu.fdd.read_sd && !old_rd) $display("%0d FDD read  lba %0d", cycles, sim_top.emu.fdd_lba);
   if(sim_top.emu.fdd.wr_go   && !old_wr) $display("%0d FDD write lba %0d", cycles, sim_top.emu.fdd_lba);
end

endmodule
