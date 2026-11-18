// Cabinet Drive/Reverse shifter. Buttons are active low, as in JTFRAME.
// reverse=1 drives MTSR/NTSR high: H3/N1 then allow GRPR/HRPR, the reverse motion.
// Separate mode (default): the Drive button selects Drive, Reverse selects Reverse;
// Drive wins a tie. Toggle mode: the Drive button flips Drive/Reverse on each press.
module deathrac_gear(
 input wire clk,reset,separate,drive_n,reverse_n,
 output reg reverse
);
 reg old_drive_n,old_reverse_n;
 always @(posedge clk) begin
  old_drive_n<=drive_n;
  old_reverse_n<=reverse_n;
  if(reset) begin
   reverse<=0;
   old_drive_n<=drive_n;
   old_reverse_n<=reverse_n;
  end else if(separate) begin
   if(old_drive_n && !drive_n) reverse<=0;
   else if(old_reverse_n && !reverse_n) reverse<=1;
  end else if(old_drive_n && !drive_n) reverse<=~reverse;
 end
endmodule
// Coin and Start buttons of a pad, turned into what the cabinet gives sheet 2.
// The board is unchanged; it expects a coin switch and a player who then presses Start:
//  - Start is dead until EGME, 67 to 133 ms after the coin (two 1ECK0 edges), and
//    J15.a toggles at 7 MHz if Start is down while ECDG is high, so Start pressed
//    with or just after the coin is lost or lands at random;
//  - a second coin needs ECDB low for one 1ECK0 period (67 ms) or it merges with the first;
//  - a coin after Start clears ESGB: the game stops and waits for Start again, and one
//    more coin then makes it a two-player game.
// So: each coin press is queued (two at most) and played as 100 ms on, 250 ms off; Start
// is remembered and held, once the coins are through and EGME is up, until ESGC answers;
// coin presses are dropped from the Start press to the end of the game.
// credit=EGME, started=ESGC. Buttons and outputs are active high.
module deathrac_credit #(parameter SYS_HZ=115151515)(
 input wire clk,reset,coin_btn,start_btn,credit,started,
 output reg coin,start
);
 localparam [9:0] COIN_ON=10'd100,COIN_OFF=10'd250,START_MAX=10'd400,SETTLE=10'd500;
 localparam [1:0] IDLE=2'd0,COIN=2'd1,GAP=2'd2,START=2'd3;
 localparam integer MS=SYS_HZ/1000;
 reg [17:0] div;
 wire tick=div==MS-1;
 reg [1:0] state,queue,total;   // total: coins taken since the last game, two at most
 reg [9:0] timer;
 reg want,old_coin,old_start,old_credit;
 wire coin_press=coin_btn && !old_coin && !started && !want && state!=START && total!=2;
 wire take=state==IDLE && tick && queue!=0;
 always @(posedge clk) begin
  div<=tick ? 18'd0 : div+18'd1;
  old_coin<=coin_btn; old_start<=start_btn; old_credit<=credit;
  if(coin_press) total<=total+2'd1;
  if(coin_press && !take) queue<=queue+2'd1;
  else if(take && !coin_press) queue<=queue-2'd1;
  // Start counts only if a credit is there or on its way.
  if(start_btn && !old_start && !started && (credit || coin_press || queue!=0 || state==COIN || state==GAP)) want<=1;
  if(tick) case(state)
   IDLE: if(queue!=0) begin coin<=1; timer<=COIN_ON; state<=COIN; end
         else if(want && credit && !started) begin start<=1; timer<=START_MAX; state<=START; end
         else want<=0;
   COIN: if(timer==0) begin coin<=0; timer<=COIN_OFF; state<=GAP; end else timer<=timer-10'd1;
   GAP:  if(timer==0) state<=IDLE; else timer<=timer-10'd1;
   default: if(started || timer==0) begin start<=0; want<=0; timer<=COIN_OFF; state<=GAP; end
            else timer<=timer-10'd1;
  endcase
  // Power-up (EPOR) and game over (STAA holds STGO up to 267 ms): let the board settle.
  if(reset || (old_credit && !credit)) begin
   coin<=0; start<=0; want<=0; queue<=0; total<=0; timer<=SETTLE; state<=GAP;
  end
  if(reset) div<=0;
 end
endmodule

// Divide quadrature movement by three, retaining direction and cancelling
// partial steps on reversal. Invalid two-bit jumps are ignored and resynced.
module deathrac_steering_div3(
 input wire clk,reset,input wire [1:0] in_phase,
 output reg [1:0] out_phase
);
 reg [1:0] previous;
 reg signed [2:0] remainder;
 wire forward=(previous==2'b00 && in_phase==2'b01) ||
              (previous==2'b01 && in_phase==2'b11) ||
              (previous==2'b11 && in_phase==2'b10) ||
              (previous==2'b10 && in_phase==2'b00);
 wire backward=(previous==2'b01 && in_phase==2'b00) ||
               (previous==2'b11 && in_phase==2'b01) ||
               (previous==2'b10 && in_phase==2'b11) ||
               (previous==2'b00 && in_phase==2'b10);
 function [1:0] advance(input [1:0] p);
  case(p) 0:advance=1;1:advance=3;3:advance=2;default:advance=0;endcase
 endfunction
 function [1:0] retreat(input [1:0] p);
  case(p) 0:retreat=2;2:retreat=3;3:retreat=1;default:retreat=0;endcase
 endfunction
 always @(posedge clk) begin
  previous<=in_phase;
  if(reset) begin previous<=in_phase;out_phase<=0;remainder<=0;end
  else if(forward) begin
   if(remainder==2) begin remainder<=0;out_phase<=advance(out_phase);end
   else remainder<=remainder+3'sd1;
  end else if(backward) begin
   if(remainder== -2) begin remainder<=0;out_phase<=retreat(out_phase);end
   else remainder<=remainder-3'sd1;
  end
 end
endmodule

// Analog accelerator for the two-channel opto pedal of sheet 18 (466-2501).
// The board only ever sees four positions; H3/N1 settle on 00 stopped, 01 slow,
// 11 medium, 10 fast, so travel is the Gray sequence below. Hysteresis stops an
// analog axis chattering across a boundary. Button 1 forces full travel.
// mode 0: right stick, up from centre    1: left stick, up from centre
// mode 2: right Y as a full-travel pedal 3: left Y as a full-travel pedal
//         (rests at +127, floored at -128)
module deathrac_pedal(
 input wire clk,reset,
 input wire [7:0] left_y,right_y,
 input wire [7:0] trigger,          // right analog trigger, 0 released .. 255 full
 input wire button_n,
 input wire [1:0] mode,
 output wire [1:0] gas
);
 // A quarter, half and three quarters of the travel, as in the Monaco GP core.
 localparam [7:0] T1=8'd32,T2=8'd64,T3=8'd96,HYST=8'd8;
 wire [7:0] y=mode[0] ? left_y : right_y;
 // Offset binary: 0 at -128, 255 at +127. Pedal travel is 255 minus that, /2.
 wire [7:0] offset=y^8'h80;
 wire [7:0] stick=y[7] ? (~y)+8'd1 : 8'd0;
 wire [7:0] pedal={1'b0,~offset[7:1]};
 wire [7:0] axis=mode[1] ? pedal : stick;
 // The right trigger works in every mode, as in the Monaco GP core: whichever of the
 // axis and the trigger is pressed further. Without a MiSTer Main that sends triggers
 // the input stays 0 and changes nothing.
 wire [7:0] pull={1'b0,trigger[7:1]};
 wire [7:0] travel=axis>pull ? axis : pull;
 reg [1:0] pos;
 always @(posedge clk) begin
  if(reset) pos<=0;
  else case(pos)
   0: if(travel>=T1) pos<=1;
   1: if(travel>=T2) pos<=2; else if(travel<T1-HYST) pos<=0;
   2: if(travel>=T3) pos<=3; else if(travel<T2-HYST) pos<=1;
   default: if(travel<T3-HYST) pos<=2;
  endcase
 end
 // MiSTer Main sends a trigger both as an analog value and, past its press level, as a
 // digital button. If R is mapped to Accelerate in the pad map, the button half would floor
 // the pedal and hide the analog half, so the button counts only while the trigger is at
 // rest. Accelerate on A, with R unpulled, still floors the pedal.
 wire [1:0] p=(button_n || trigger!=0) ? pos : 2'd3;
 assign gas={p[1],p[1]^p[0]};
endmodule
