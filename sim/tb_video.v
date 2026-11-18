// Video levels at the JTFRAME boundary. Background must be black.
`timescale 1ns/1ps
module tb_video;
 reg clk=0,reset=1;
 always #4.342 clk=~clk;
 wire ce;
 wire [7:0] video;
 deathrac_fpga #(.SYS_HZ(115151515)) dut(.clk_sys(clk),.reset_in(reset),.coin(1'b0),.start(1'b0),
  .time_select(2'b10),.steer1(2'b00),.steer2(2'b00),.gas1(2'b00),.gas2(2'b00),.gear1(1'b0),.gear2(1'b0),
  .ce_pixel(ce),.video(video),.tone(2'b00),.game_dr(1'b0),.prom_wr(1'b0));
 task check(input w,g,input [7:0] want,input [127:0] what);
  begin
   force dut.white=w;force dut.grey=g;
   repeat(4) @(posedge ce);
   #1;
   if(video!==want) begin $display("FAIL %0s: white=%b grey=%b video=%0d want %0d",what,w,g,video,want);$fatal(1); end
  end
 endtask
 // Every pixel exactly 8 system clocks long, in and out of reset.
 integer since=-1;
 always @(posedge clk) begin
  if(ce) begin
   if(since>=0 && since!=7) begin $display("FAIL pixel spacing %0d clocks",since+1);$fatal(1); end
   since=0;
  end else if(since>=0) since=since+1;
 end
 initial begin
  repeat(20) @(posedge clk);reset=0;
  repeat(40) @(posedge clk);
  check(0,1,8'd0,"background");
  check(1,1,8'd255,"objects");
  check(1,0,8'd136,"player 2");
  check(0,0,8'd0,"below black");
  $display("PASS video: black background, white objects, 53%% player 2");
  $finish;
 end
endmodule
