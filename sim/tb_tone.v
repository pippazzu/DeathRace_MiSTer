`timescale 1ns/1ps
module tb_tone;
 reg clk=0,reset=1;
 always #4.342 clk=~clk;
 reg xa=0;
 always #1250000 xa=~xa;
 reg [1:0] tone=0;
 wire signed [15:0] a,b;
 deathrac_audio #(.SYS_HZ(115151515)) dut(clk,reset,1'b1,1'b1,
  3'b100,3'b100,1'b0,1'b0,xa,!xa,xa,!xa,1'b1,1'b1,,,a,b,tone,32'sd0,,1'b0);
 integer count=0,cycles=0,f;
 initial begin
  f=$fopen("build/tone.raw","wb");
  #1000 reset=0;
  #30000000 tone=1;
  #30000000 tone=2;
  #30000000;
  if(count<4310 || count>4330)$fatal(1,"Audio sample deadline missed: %d",count);
  $fclose(f);$display("PASS tone settings, samples=%d",count);$finish;
 end
 always @(posedge clk) if(!reset) begin
  if(dut.st_s==23 && dut.ch) begin
   count=count+1;
   if((^a)===1'bx || (^b)===1'bx)$fatal(1,"Unknown audio");
   $fwrite(f,"%c%c%c",tone,a[7:0],a[15:8]);
  end
 end
endmodule
