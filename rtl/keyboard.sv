//
// keyboard.sv
//
// PS/2 (set 2, as hps_io reports it) to the UKNC keyboard byte stream.
//
// The PPU's keyboard register (xm2-01.v) takes bytes on a change of its
// input: a press is the key's matrix code {column[6:4], row[3:0]}, a release
// is 0x80 | row - the keyboard controller reports rows, one press per row
// until the row is let go.  This is what tang-uknc's BL616 firmware does in
// kbd_tx_uknc() (mnano/usb_host.c), and the table is its mnano/uknc.h moved
// from USB HID usages to PS/2 scan codes:
//
//  - keys meant to be chorded must not share a row (both Shifts are 0105);
//  - a second key in a row that is already held is sent as a release of the
//    row and a new press, and the older keys of the row are forgotten;
//  - a key held twice under one code (the two Shifts) is one press, released
//    when the last of them goes up.
//
// Bytes are paced, so that each one is seen as a change by xm2-01.v.
//
module keyboard
#(parameter CLK_HZ = 50_000_000)
(
   input             clk,
   input             reset,
   input      [10:0] ps2_key,      // hps_io: [10] toggle, [9] pressed, [8] extended, [7:0] code
   output reg [ 7:0] key_byte      // to xm2_01's but_data
);

// The firmware keeps consecutive bytes 2 ms apart.
localparam PACE_US     = 2000;
localparam PACE_CYCLES = CLK_HZ / 1_000_000 * PACE_US;

localparam KEY_RELEASE = 8'h80;
localparam KEY_IDLE    = 8'hff;    // what hid.v holds after reset

// ---------------------------------------------------------------------
// PS/2 set 2 to UKNC matrix code; 0 is a key the machine does not have.
// ---------------------------------------------------------------------
function [6:0] uknc_code(input ext, input [7:0] code);
   if(!ext)
      case(code)
      // letters
      8'h1C: uknc_code = 7'o072;  // A
      8'h32: uknc_code = 7'o076;  // B
      8'h21: uknc_code = 7'o050;  // C
      8'h23: uknc_code = 7'o057;  // D
      8'h24: uknc_code = 7'o033;  // E
      8'h2B: uknc_code = 7'o047;  // F
      8'h34: uknc_code = 7'o055;  // G
      8'h33: uknc_code = 7'o156;  // H
      8'h43: uknc_code = 7'o073;  // I
      8'h3B: uknc_code = 7'o027;  // J
      8'h42: uknc_code = 7'o052;  // K
      8'h4B: uknc_code = 7'o056;  // L
      8'h3A: uknc_code = 7'o112;  // M
      8'h31: uknc_code = 7'o054;  // N
      8'h44: uknc_code = 7'o075;  // O
      8'h4D: uknc_code = 7'o053;  // P
      8'h15: uknc_code = 7'o067;  // Q
      8'h2D: uknc_code = 7'o074;  // R
      8'h1B: uknc_code = 7'o111;  // S
      8'h2C: uknc_code = 7'o114;  // T
      8'h3C: uknc_code = 7'o051;  // U
      8'h2A: uknc_code = 7'o137;  // V
      8'h1D: uknc_code = 7'o071;  // W
      8'h22: uknc_code = 7'o115;  // X
      8'h35: uknc_code = 7'o070;  // Y
      8'h1A: uknc_code = 7'o157;  // Z
      // top row digits
      8'h16: uknc_code = 7'o030;  // 1
      8'h1E: uknc_code = 7'o031;  // 2
      8'h26: uknc_code = 7'o032;  // 3
      8'h25: uknc_code = 7'o013;  // 4
      8'h2E: uknc_code = 7'o034;  // 5
      8'h36: uknc_code = 7'o035;  // 6
      8'h3D: uknc_code = 7'o016;  // 7
      8'h3E: uknc_code = 7'o017;  // 8
      8'h46: uknc_code = 7'o177;  // 9
      8'h45: uknc_code = 7'o176;  // 0
      // other keys
      8'h5A: uknc_code = 7'o153;  // Enter      - ВВОД
      8'h76: uknc_code = 7'o006;  // Esc        - АР2
      8'h66: uknc_code = 7'o132;  // Backspace  - ЗБ
      8'h0D: uknc_code = 7'o026;  // Tab        - ТАБ
      8'h29: uknc_code = 7'o113;  // Space
      8'h4E: uknc_code = 7'o175;  // -          - the '- =' key
      8'h55: uknc_code = 7'o110;  // =          - Ч ^ ('- =' is on '-')
      8'h54: uknc_code = 7'o036;  // [
      8'h5B: uknc_code = 7'o037;  // ]
      8'h5D: uknc_code = 7'o136;  // backslash  - the key with Э
      8'h4C: uknc_code = 7'o007;  // ;
      8'h52: uknc_code = 7'o155;  // '          - the key with Ъ
      8'h0E: uknc_code = 7'o077;  // `
      8'h41: uknc_code = 7'o117;  // ,
      8'h49: uknc_code = 7'o135;  // .
      8'h4A: uknc_code = 7'o173;  // /
      8'h58: uknc_code = 7'o107;  // Caps Lock  - ФИКС
      // function keys
      8'h05: uknc_code = 7'o010;  // F1  - К1
      8'h06: uknc_code = 7'o011;  // F2  - К2
      8'h04: uknc_code = 7'o012;  // F3  - К3
      8'h0C: uknc_code = 7'o014;  // F4  - К4
      8'h03: uknc_code = 7'o015;  // F5  - К5
      8'h0B: uknc_code = 7'o172;  // F6  - ПОМ
      8'h83: uknc_code = 7'o152;  // F7  - УСТ
      8'h0A: uknc_code = 7'o151;  // F8  - ИСП
      8'h01: uknc_code = 7'o171;  // F9  - СБРОС
      8'h09: uknc_code = 7'o004;  // F10 - СТОП
      // keypad
      8'h7C: uknc_code = 7'o174;  // KP *
      8'h7B: uknc_code = 7'o025;  // KP -
      8'h79: uknc_code = 7'o131;  // KP +
      8'h69: uknc_code = 7'o127;  // KP 1
      8'h72: uknc_code = 7'o147;  // KP 2
      8'h7A: uknc_code = 7'o167;  // KP 3
      8'h6B: uknc_code = 7'o130;  // KP 4
      8'h73: uknc_code = 7'o150;  // KP 5
      8'h74: uknc_code = 7'o170;  // KP 6
      8'h6C: uknc_code = 7'o125;  // KP 7
      8'h75: uknc_code = 7'o145;  // KP 8
      8'h7D: uknc_code = 7'o165;  // KP 9
      8'h70: uknc_code = 7'o126;  // KP 0
      8'h71: uknc_code = 7'o146;  // KP .
      // modifiers
      8'h14: uknc_code = 7'o046;  // Left Ctrl  - УПР
      8'h12: uknc_code = 7'o105;  // Left Shift - НР
      8'h59: uknc_code = 7'o105;  // Right Shift
      8'h11: uknc_code = 7'o106;  // Left Alt   - АЛФ
      default: uknc_code = 7'o000;
      endcase
   else
      case(code)
      8'h74: uknc_code = 7'o133;  // Right
      8'h6B: uknc_code = 7'o116;  // Left
      8'h72: uknc_code = 7'o134;  // Down
      8'h75: uknc_code = 7'o154;  // Up
      8'h4A: uknc_code = 7'o005;  // KP /       - keypad ','
      8'h5A: uknc_code = 7'o166;  // KP Enter
      8'h14: uknc_code = 7'o046;  // Right Ctrl - УПР
      8'h11: uknc_code = 7'o066;  // Right Alt  - ГРАФ
      default: uknc_code = 7'o000;
      endcase
endfunction

// ---------------------------------------------------------------------
// Row tracking
// ---------------------------------------------------------------------
localparam ROWS = 16;

reg  [511:0] held = 0;            // PS/2 keys forwarded as pressed, {ext, code}
reg  [  2:0] rows[0:ROWS-1];      // keys the machine believes down, per row
reg  [  6:0] code_of[0:ROWS-1];   // the code it believes the row is held by

// Output queue: an event may produce two bytes.
localparam QAW = 4;
reg  [7:0]     q[0:(1<<QAW)-1];
reg  [QAW-1:0] q_wr = 0, q_rd = 0;
wire           q_empty = q_wr == q_rd;

reg            old_toggle = 0;
wire [8:0]     key     = ps2_key[8:0];
wire [6:0]     code    = uknc_code(ps2_key[8], ps2_key[7:0]);
wire [3:0]     row     = code[3:0];

integer i;
initial for(i = 0; i < ROWS; i = i + 1) begin rows[i] = 0; code_of[i] = 0; end

always @(posedge clk) begin
   old_toggle <= ps2_key[10];

   if(reset) begin
      held <= 0;
      for(i = 0; i < ROWS; i = i + 1) rows[i] <= 0;
      q_wr <= q_rd;
   end
   else if(old_toggle != ps2_key[10] && code != 0) begin
      if(ps2_key[9]) begin
         if(!held[key]) begin
            held[key] <= 1'b1;
            if(rows[row] != 0 && code != code_of[row]) begin
               // rollover inside the row: release it, then the new press
               q[q_wr]        <= KEY_RELEASE | row;
               q[q_wr + 1'd1] <= {1'b0, code};
               q_wr           <= q_wr + 2'd2;
               code_of[row]   <= code;
               rows[row]      <= 3'd1;
            end
            else if(rows[row] == 0) begin
               q[q_wr]        <= {1'b0, code};
               q_wr           <= q_wr + 1'd1;
               code_of[row]   <= code;
               rows[row]      <= 3'd1;
            end
            else rows[row] <= rows[row] + 1'd1;   // the same code held twice
         end
      end
      else if(held[key]) begin
         held[key] <= 1'b0;
         // a key forgotten in a rollover releases nothing
         if(code == code_of[row] && rows[row] != 0) begin
            rows[row] <= rows[row] - 1'd1;
            if(rows[row] == 1) begin
               q[q_wr] <= KEY_RELEASE | row;
               q_wr    <= q_wr + 1'd1;
            end
         end
      end
   end
end

// ---------------------------------------------------------------------
// Pacing
// ---------------------------------------------------------------------
reg [$clog2(PACE_CYCLES+1)-1:0] pace = 0;

initial key_byte = KEY_IDLE;

always @(posedge clk) begin
   if(pace != 0) pace <= pace - 1'd1;
   else if(!q_empty) begin
      key_byte <= q[q_rd];
      q_rd     <= q_rd + 1'd1;
      pace     <= PACE_CYCLES[$clog2(PACE_CYCLES+1)-1:0];
   end
end

endmodule
