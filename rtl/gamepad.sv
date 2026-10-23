//
// gamepad.sv
//
// The MiSTer gamepad as keys: its buttons become PS/2 key events, merged
// into hps_io's ps2_key stream on the way to keyboard.sv, so a button is
// handled exactly as the key it stands for, row rules included.
//
//   D-pad      the arrow keys, or keypad 8 4 6 2 (OSD "Gamepad")
//   A          Space
//   B          ВВОД (Enter)
//   X          УПР (Ctrl)
//   Y          АР2 (Esc)
//
// Space and ВВОД are in the keyboard row of the Right arrow: as on the
// real keyboard, of two keys held in one row only the later is seen.
//
// An event from the keyboard goes through at once; a button change waits
// for a cycle without one.  The D-pad's keys follow the OSD setting only
// while no button is held, so a change of the setting leaves no key down.
//
module gamepad
(
   input             clk,
   input             reset,
   input      [ 1:0] mode,         // GP_ARROWS, GP_KEYPAD, GP_OFF
   input      [31:0] joystick,     // hps_io joystick_0
   input      [10:0] ps2_in,       // hps_io: [10] toggle, [9] pressed, [8] extended, [7:0] code
   output reg [10:0] ps2_out = 0   // the same, both sources merged
);

localparam [1:0] GP_ARROWS = 2'd0, GP_KEYPAD = 2'd1, GP_OFF = 2'd2;

// hps_io's joystick bits: the D-pad, then the buttons in CONF_STR's J1 order
localparam JOY_RIGHT = 0, JOY_LEFT = 1, JOY_DOWN = 2, JOY_UP = 3;
localparam JOY_A = 4, JOY_B = 5, JOY_X = 6, JOY_Y = 7;
localparam BUTTONS = 8;

localparam PS2_TOGGLE = 10, PS2_PRESSED = 9;

// PS/2 set 2 codes, {extended, code}
localparam [8:0] KEY_RIGHT = 9'h174, KEY_LEFT = 9'h16B, KEY_DOWN = 9'h172, KEY_UP = 9'h175;
localparam [8:0] KEY_KP6   = 9'h074, KEY_KP4  = 9'h06B, KEY_KP2  = 9'h072, KEY_KP8 = 9'h075;
localparam [8:0] KEY_SPACE = 9'h029, KEY_ENTER = 9'h05A, KEY_CTRL = 9'h014, KEY_ESC = 9'h076;

reg  [1:0] dpad_mode = GP_ARROWS;

function [8:0] key_of(input [2:0] button, input [1:0] dpad);
   case(button)
   JOY_RIGHT: key_of = dpad == GP_KEYPAD ? KEY_KP6 : KEY_RIGHT;
   JOY_LEFT:  key_of = dpad == GP_KEYPAD ? KEY_KP4 : KEY_LEFT;
   JOY_DOWN:  key_of = dpad == GP_KEYPAD ? KEY_KP2 : KEY_DOWN;
   JOY_UP:    key_of = dpad == GP_KEYPAD ? KEY_KP8 : KEY_UP;
   JOY_A:     key_of = KEY_SPACE;
   JOY_B:     key_of = KEY_ENTER;
   JOY_X:     key_of = KEY_CTRL;
   default:   key_of = KEY_ESC;
   endcase
endfunction

wire [BUTTONS-1:0] pressed = mode == GP_OFF ? {BUTTONS{1'b0}} : joystick[BUTTONS-1:0];
reg  [BUTTONS-1:0] sent = 0;       // the buttons forwarded as held
reg                old_toggle = 0;

// the lowest button whose state differs from what was sent
reg  [2:0] change;
reg        changed;
integer i;
always @(*) begin
   change  = 0;
   changed = 1'b0;
   for(i = BUTTONS - 1; i >= 0; i = i - 1)
      if(pressed[i] != sent[i]) begin change = i[2:0]; changed = 1'b1; end
end

always @(posedge clk) begin
   old_toggle <= ps2_in[PS2_TOGGLE];

   if(sent == 0 && mode != GP_OFF) dpad_mode <= mode;

   if(old_toggle != ps2_in[PS2_TOGGLE])
      ps2_out <= {~ps2_out[PS2_TOGGLE], ps2_in[PS2_PRESSED:0]};
   else if(reset)
      sent <= 0;
   else if(changed) begin
      ps2_out      <= {~ps2_out[PS2_TOGGLE], pressed[change], key_of(change, dpad_mode)};
      sent[change] <= pressed[change];
   end
end

endmodule
