`timescale 1ns/1ps
module tb_board;
 parameter FPGA=1;
 reg clk=0,reset=0,xtal=0,coin=0,start=0;
 generate if(FPGA) always #4.343 clk=~clk; endgenerate // 8x nominal 14.391MHz
 always #34.744 xtal=~xtal;
 wire hs,vs,hb,vb,pc,white,grey,game,p2,cr1,cr2;
 wire [2:0] m1,m2;
 wire [8:0] hc,vc;
 wire [7:0] timer;
 deathrac_board #(.FPGA(FPGA)) dut(clk,reset,xtal,coin,start,2'b10,
  2'b00,2'b00,2'b00,2'b00,1'b0,1'b0,
  hs,vs,hb,vb,pc,white,grey,game,p2,m1,m2,cr1,cr2,hc,vc,timer,1'b0,1'b0,,,,,,,1'b0,1'b0,12'd0,8'd0,,);
 integer frames=0,lines=0,pixels=0,unknowns=0,f,stats;
 integer frame_limit=4;
 integer capture_frame=2;
 real last_h=0,last_v=0;
 initial begin
  if($value$plusargs("frames=%d",frame_limit)) begin end
  if($value$plusargs("capture=%d",capture_frame)) begin end
  if(FPGA) begin f=$fopen("build/frame-fpga.raw","wb"); stats=$fopen("build/timing-fpga.csv","w"); end
  else begin f=$fopen("build/frame-reference.raw","wb"); stats=$fopen("build/timing-reference.csv","w"); end
  $fdisplay(stats,"kind,time_ns,period_ns,hcount,vcount,timer,game");
  #1 reset=1; #2000 reset=0;
  #300000000 coin=1; #150000000 coin=0;
  #100000000 start=1; #150000000 start=0;
 end
 always @(posedge hs) if(!reset) begin
  lines=lines+1;
  if(lines<10) $display("line %d period %.3f hc=%d vc=%d",lines,$realtime-last_h,hc,vc);
  $fdisplay(stats,"h,%.3f,%.3f,%d,%d,%h,%b",$realtime,$realtime-last_h,hc,vc,timer,game);
  last_h=$realtime;
 end
 always @(posedge vs) if(!reset) begin
  frames=frames+1;
  $display("frame %d period %.3f lines=%d unknown_pixels=%d timer=%h game=%b",frames,$realtime-last_v,lines,unknowns,timer,game);
  $display("enemy headings A=%h C=%h shape A=%h C=%h",
   {dut.circuit.n_J9_pin7_ACT3,dut.circuit.n_J9_pin6_ACT2,dut.circuit.n_J9_pin2_ACT1,dut.circuit.n_J9_pin3_ACT0},
   {dut.circuit.n_E5_pin7_CCT3,dut.circuit.n_E5_pin6_CCT2,dut.circuit.n_E5_pin2_CCT1,dut.circuit.n_E5_pin3_CCT0},
   {dut.circuit.n_J10_pin4_C7_pin3,dut.circuit.n_J10_pin3_C7_pin13,dut.circuit.n_J10_pin2_D7_pin3,dut.circuit.n_J10_pin1_D7_pin13},
   {dut.circuit.n_D5_pin4_C7_pin4,dut.circuit.n_D5_pin3_C7_pin12,dut.circuit.n_D5_pin2_D7_pin4,dut.circuit.n_D5_pin1_D7_pin12});
  $display("control EPOR=%b ECK0=%b ECDB=%b ECDC=%b ECDD_n=%b ECDG=%b H16=%b R5=%b",dut.circuit.n_L14_pin9_EPOR,dut.circuit.n_H15_pin8_1ECK0,dut.circuit.n_K16_pin5_K16_pin11,dut.circuit.n_K16_pin9_ECDC,dut.circuit.n_K15_pin6_5ECDD,dut.circuit.n_L16_pin11_ECDG,dut.circuit.s02_H16.q,dut.circuit.s02_R5.q);
  $fdisplay(stats,"v,%.3f,%.3f,%d,%d,%h,%b",$realtime,$realtime-last_v,hc,vc,timer,game);
  last_v=$realtime;
  if(frames>=frame_limit) begin $fclose(f);$fclose(stats);$finish; end
 end
 always @(negedge pc) if(!reset) begin
  // Records coordinates rather than assuming a television timing standard.
  #20;
  pixels=pixels+1;
  if((^({white,grey}))===1'bx) unknowns=unknowns+1;
  if(frames==capture_frame) begin
   $fwrite(f,"%c%c%c%c%c",hc[7:0],{7'b0,hc[8]},vc[7:0],{7'b0,vc[8]},
     (!(white===1'b1) ? 8'd0 : grey===1'b1 ? 8'd255 : 8'd136));
  end
 end
 initial begin #1000000000; $fatal(1,"Timeout: missing sync"); end
endmodule
