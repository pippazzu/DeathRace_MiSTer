// Leaving reset must not click: the settled idle motor peaks near 3300, so nothing in
// the first 30 ms may reach 10000. Before the coupling cap was precharged it hit 23326.
`timescale 1ns/1ps
module tb_audio_click;
 reg clk=0,reset=1;
 always #4.342 clk=~clk;
 wire signed [15:0] a,b;
 deathrac_audio #(.SYS_HZ(115151515)) dut(clk,reset,1'b1,1'b1,
  3'b000,3'b000,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,,,a,b,2'b00,32'sd0,,1'b0);
 integer peak=0,v,n=0;
 always @(posedge clk) if(!reset && dut.st_s==23 && dut.ch) begin
  #1 v=a<0 ? -a : a;
  if(v>peak) peak=v;
  v=b<0 ? -b : b;
  if(v>peak) peak=v;
  n=n+1;
 end
 initial begin
  #1000 reset=0;
  #30000000;
  $display("samples %0d, peak %0d",n,peak);
  if(n<1400 || peak>=10000) $fatal(1,"FAIL startup click, peak %0d",peak);
  $display("PASS no click leaving reset");
  $finish;
 end
endmodule
