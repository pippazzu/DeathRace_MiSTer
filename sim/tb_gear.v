`timescale 1ns/1ps
module tb_gear;
 reg clk=0,reset=1,separate=1,drive_n=1,reverse_n=1;
 wire reverse;
 always #5 clk=~clk;
 deathrac_gear dut(clk,reset,separate,drive_n,reverse_n,reverse);
 task check(input value);
 begin #20;if(reverse!==value)$fatal(1,"reverse=%b expected=%b",reverse,value);end
 endtask
 initial begin
  // Separate buttons (default): starts in Drive, Reverse latches, Drive returns.
  check(0);reset=0;reverse_n=0;check(1);reverse_n=1;check(1);
  drive_n=0;check(0);drive_n=1;check(0);
  reverse_n=0;check(1);drive_n=0;check(0);   // Drive wins a tie
  drive_n=1;reverse_n=1;check(0);
  // Toggle mode: each Drive press flips, holding does not repeat, Reverse is ignored.
  separate=0;drive_n=0;check(1);check(1);drive_n=1;check(1);
  drive_n=0;check(0);drive_n=1;reverse_n=0;check(0);reverse_n=1;
  $display("PASS shifter: Drive/Reverse buttons, tie, toggle and hold");$finish;
 end
endmodule
