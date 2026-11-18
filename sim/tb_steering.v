`timescale 1ns/1ps
module tb_steering;
 reg clk=0,reset=1;
 reg [1:0] phase=0;
 wire [1:0] out;
 always #5 clk=~clk;
 deathrac_steering_div3 dut(clk,reset,phase,out);
 task step(input [1:0] p,input [1:0] want);
 begin phase=p;#20;if(out!==want)$fatal(1,"input %b output %b expected %b",p,out,want);end
 endtask
 initial begin
  #20;reset=0;
  step(1,0);step(3,0);step(2,1);
  step(0,1);step(1,1);step(3,3);
  step(1,3);step(0,3);step(2,1);
  step(3,1);step(2,1);step(0,1); // reversal cancels a partial step
  step(3,1); // invalid two-bit change is ignored
  reset=1;#20;reset=0;step(2,0);step(0,0);step(1,1);
  $display("PASS quadrature division, reversals, invalid jump, reset");$finish;
 end
endmodule
