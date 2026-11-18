// deathrac_credit alone, against a stand-in for sheet 2: EGME one 1ECK0 period after a
// coin edge, ESGC after Start with EGME. 1 ms is 100 clocks here.
`timescale 1ns/1ps
module tb_credit;
 reg clk=0,reset=1,coin_btn=0,start_btn=0,credit=0,started=0;
 always #5 clk=~clk;
 wire coin,start;
 deathrac_credit #(.SYS_HZ(100000)) dut(clk,reset,coin_btn,start_btn,credit,started,coin,start);
 localparam MS=1000;   // ns per ms
 integer coins=0,starts=0,second=0;
 time coin_up=0,coin_down=0;
 always @(posedge coin) begin
  if(start) $fatal(1,"coin with start down");
  if(coins && $time-coin_down<200*MS) $fatal(1,"coins too close: %0d ms",($time-coin_down)/MS);
  coins=coins+1; coin_up=$time;
  if(credit) second=1;
  #(100*MS) credit=1;          // EGME within 133 ms
 end
 always @(negedge coin) begin
  if(coins && $time-coin_up<90*MS) $fatal(1,"coin too short");
  coin_down=$time;
 end
 always @(posedge start) begin
  if(coin || $time-coin_down<200*MS) $fatal(1,"start before the coin is through");
  if(!credit) $fatal(1,"start without credit");
  starts=starts+1;
  #(67*MS) started=1;          // ESGC on the next 1ECK0 edge
 end
 task press_coin; begin coin_btn=1; #(80*MS) coin_btn=0; end endtask
 task press_start; begin start_btn=1; #(80*MS) start_btn=0; end endtask
 task game_over; begin credit=0; started=0; second=0; coins=0; starts=0; #(100*MS); end endtask
 initial begin
  #(2*MS) reset=0;
  // Start with no credit does nothing.
  #(600*MS) press_start; #(600*MS);
  if(starts) $fatal(1,"start with no credit");
  // Coin and Start in the same instant: one coin, then one start, one-player.
  coin_btn=1; start_btn=1; #(80*MS) coin_btn=0; start_btn=0; #(900*MS);
  if(coins!=1 || starts!=1 || !started || second) $fatal(1,"coin+start: coins=%0d starts=%0d",coins,starts);
  if(start) $fatal(1,"start left down");
  // Coins and Start during play are dropped.
  press_coin; #(50*MS) press_start; #(800*MS);
  if(coins!=1 || starts!=1) $fatal(1,"buttons got through during play");
  game_over;
  // Coin straight after game over waits for the board, then counts once.
  press_coin; #(1200*MS);
  if(coins!=1 || starts) $fatal(1,"coin after game over: %0d",coins);
  press_start; #(600*MS);
  if(starts!=1 || !started) $fatal(1,"start after a waiting credit");
  game_over; #(600*MS);
  // Two quick coins and Start: two spaced coins, then Start. A third coin is not queued.
  press_coin; #(40*MS) press_coin; #(40*MS) press_coin; #(40*MS) press_start; #(1500*MS);
  if(coins!=2 || !second || starts!=1 || !started) $fatal(1,"two-player: coins=%0d starts=%0d",coins,starts);
  // A held coin button is one coin.
  game_over; #(600*MS);
  coin_btn=1; #(1500*MS) coin_btn=0; #(300*MS);
  if(coins!=1) $fatal(1,"held coin: %0d",coins);
  $display("PASS credit: one clean coin per press, Start held for the board, no coins during play");
  $finish;
 end
endmodule
