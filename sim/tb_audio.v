// Sound board test: deathrac_audio plus the sheet 15 U5/U7/U6 cells exactly
// as in netlist/sheet15.net, with 2TQLC at the line rate. Scenario matches
// tools/audio_ref.py: SEG seconds each of idle, speeds 12..15, crash, decay.
`timescale 1ns/1ps
module tb_audio;
 localparam SYS_HZ=115151515;
 reg clk=0,reset=1;
 always #(500.0/115.151515) clk=~clk;
 real tline=1e9*8*832/115151515;
 reg tqlc=0;
 always begin #(tline/2) tqlc=~tqlc; end
 integer seg_ms=500;
 reg [2:0] m=0;
 reg gthe=0,game=1,p2=1;
 reg [1:0] tone=0;
 reg dr=0;
 wire xcr1,xcr2,q5a,qn5a,q5b,qn5b,q7a,qn7a,q7b,qn7b;
 dd_jk112 u5a(.clk_sys(clk),.reset(reset),.ck(tqlc),.j(1'b1),.k(xcr1),.pre_n(1'b1),.clr_n(1'b1),.q(q5a),.qn(qn5a),.init(1'b0));
 dd_jk112 u5b(.clk_sys(clk),.reset(reset),.ck(tqlc),.j(qn5a),.k(qn5a),.pre_n(1'b1),.clr_n(1'b1),.q(q5b),.qn(qn5b),.init(1'b0));
 dd_jk112 u7a(.clk_sys(clk),.reset(reset),.ck(tqlc),.j(1'b1),.k(xcr2),.pre_n(1'b1),.clr_n(1'b1),.q(q7a),.qn(qn7a),.init(1'b0));
 dd_jk112 u7b(.clk_sys(clk),.reset(reset),.ck(tqlc),.j(qn7a),.k(qn7a),.pre_n(1'b1),.clr_n(1'b1),.q(q7b),.qn(qn7b),.init(1'b0));
 wire signed [15:0] a1,a2;
 deathrac_audio #(.SYS_HZ(SYS_HZ)) dut(clk,reset,game,p2,m,3'b000,gthe,1'b0,
  q5b,qn5b,q7b,qn7b,q5a,q7a,xcr1,xcr2,a1,a2,tone,32'sd0,,dr);
 integer f,n=0;
 reg [8*64-1:0] fname;
 initial begin
  if(!$value$plusargs("out=%s",fname)) fname="build/audio-rtl.raw";
  f=$fopen(fname,"wb");
  if($value$plusargs("seg_ms=%d",seg_ms)) begin end
  if($value$plusargs("tone=%d",tone)) begin end
  if($test$plusargs("dr")) dr=1;
  #1000 reset=0;
  #(seg_ms*1e6) m=3'b100;
  #(seg_ms*1e6) m=3'b101;
  #(seg_ms*1e6) m=3'b110;
  #(seg_ms*1e6) m=3'b111;
  #(seg_ms*1e6/2) gthe=1;
  #(1e9/60.058) gthe=0;
  #(seg_ms*1e6*3/2) $fclose(f);
  $display("samples %0d",n);
  $finish;
 end
 always @(posedge clk) if(dut.st_s==8 && dut.ch==1) begin
  $fwrite(f,"%c%c%c%c",a1[7:0],a1[15:8],a2[7:0],a2[15:8]); n=n+1;
 end
endmodule
