// Whole game through the same PROM byte stream as MiSTer, with dual-rate picture
// capture. +game=0 Demolition Derby, +game=1 Death Race. Writes build/f<game>_<n>.pgm.
`timescale 1ns/1ps
module tb_game;
 reg clk=0,reset=1,xtal=0,coin=0,start=0;
 always #4.343 clk=~clk;      // 115 MHz, 8x the crystal as in tb_board
 always #34.744 xtal=~xtal;
 integer game=0,last=60,every=10;
 reg [8*32-1:0] rom;
 reg [7:0] stream[0:2303];
 reg prom_wr=0;
 reg [11:0] prom_addr=0;
 reg [7:0] prom_din=0;
 reg game_dr=0;
 reg [1:0] gas1=0,gas2=0,steer1=0,steer2=0;
 wire hs,vs,hb,vb,pc,white,grey,active,p2,cr1,cr2,lado;
 wire [2:0] m1,m2;
 wire [8:0] hc,vc;
 wire [7:0] timer;
 deathrac_board #(.FPGA(1)) dut(clk,reset,xtal,coin,start,2'b10,
  steer1,steer2,gas1,gas2,1'b1,1'b1,
  hs,vs,hb,vb,pc,white,grey,active,p2,m1,m2,cr1,cr2,hc,vc,timer,1'b0,1'b0,,,,,,,
  game_dr,prom_wr,prom_addr,prom_din,lado,);
 // Picture at the crystal rate: 912 x 264 samples.
 reg [7:0] fb[0:912*288-1];
 integer x=0,y=0,frames=0,i,fd,lado_count=0;
 reg old_vs=0,old_hs=0;
 reg [8*40-1:0] name;
 always @(posedge xtal) begin
  #8;
  if(hs && !old_hs) begin x=0;y=y+1; end
  old_hs=hs;
  if(x<912 && y<288) fb[y*912+x]=(hb|vb) ? 8'd40 : (!(white===1'b1) ? 8'd0 : grey===1'b1 ? 8'd255 : 8'd136);
  x=x+1;
 end
 always @(posedge lado) lado_count=lado_count+1;
 // Registered reads in the FPGA model: A12 (74S200) and the image PROMs B8-E8 give their
 // data one system clock after the address. That is harmless only if, at every clock edge
 // a shift register acts on, the address it depends on was already the same a clock
 // earlier. Sampled at posedge, before the edge's updates: the values the cells act on.
 // A12 feeds the load select of A10/A11 (through 5LCEN), so it matters at each of their
 // clock edges. The PROMs feed only the parallel inputs, so they matter at loads.
 integer a12_edges=0,a12_bad=0,prom_loads=0,prom_bad=0;
 reg [7:0] a12_a_prev=0,prom_a_prev=0;
 reg a12_wr_prev=0;
 wire a12_on=!dut.circuit.s05_A12.ce_n && dut.circuit.s05_A12.we_n;
 `define SR_LOAD(sr) (dut.circuit.sr.gated_ck && !dut.circuit.sr.old_ck && !dut.circuit.sr.load_n && dut.circuit.sr.clr_n)
 wire any_load=`SR_LOAD(s06_A10)||`SR_LOAD(s06_A11)||`SR_LOAD(s06_B10)||`SR_LOAD(s06_B11)||`SR_LOAD(s06_C10)||
  `SR_LOAD(s06_C11)||`SR_LOAD(s06_D10)||`SR_LOAD(s06_D11)||`SR_LOAD(s06_E10)||`SR_LOAD(s06_E11);
 always @(posedge clk) if(!reset) begin
  if(dut.circuit.s06_A10.gated_ck && !dut.circuit.s06_A10.old_ck && dut.circuit.s06_A10.clr_n && a12_on) begin
   a12_edges=a12_edges+1;
   if(dut.circuit.s05_A12.a!==a12_a_prev || a12_wr_prev) begin
    a12_bad=a12_bad+1;
    if(a12_bad<=5) $display("A12 address moved before an A10 edge at %t: %h -> %h wr_prev=%b",$time,a12_a_prev,dut.circuit.s05_A12.a,a12_wr_prev);
   end
  end
  if(any_load) begin
   prom_loads=prom_loads+1;
   if(dut.circuit.s04_B8.a!==prom_a_prev) begin
    prom_bad=prom_bad+1;
    if(prom_bad<=5) $display("Image PROM address moved before a load at %t: %h -> %h",$time,prom_a_prev,dut.circuit.s04_B8.a);
   end
  end
  a12_a_prev=dut.circuit.s05_A12.a;
  a12_wr_prev=!dut.circuit.s05_A12.ce_n && !dut.circuit.s05_A12.we_n;
  prom_a_prev=dut.circuit.s04_B8.a;
 end
 always @(posedge vs) begin
  frames=frames+1;
  $display("Read check after frame %0d: A12 %0d edges, %0d moved; image PROMs %0d loads, %0d moved",frames,a12_edges,a12_bad,prom_loads,prom_bad);
  $display("frame %0d lines=%0d timer=%h active=%b p2=%b lado=%0d A=%h C=%h G=%h H=%h",frames,y,timer,active,p2,lado_count,
   {dut.circuit.n_J9_pin7_ACT3,dut.circuit.n_J9_pin6_ACT2,dut.circuit.n_J9_pin2_ACT1,dut.circuit.n_J9_pin3_ACT0},
   {dut.circuit.n_E5_pin7_CCT3,dut.circuit.n_E5_pin6_CCT2,dut.circuit.n_E5_pin2_CCT1,dut.circuit.n_E5_pin3_CCT0},
   {dut.circuit.n_E1_pin7_GCT3,dut.circuit.n_E1_pin6_GCT2,dut.circuit.n_E1_pin2_G2_pin11,dut.circuit.n_E1_pin3_G2_pin10},
   {dut.circuit.n_Q2_pin7_HCT3,dut.circuit.n_Q2_pin6_HCT2,dut.circuit.n_Q2_pin2_R1_pin11,dut.circuit.n_Q2_pin3_R1_pin10});
  if(frames%every==0 || frames==last) begin
   $sformat(name,"build/f%0d_%0d.pgm",game,frames);
   fd=$fopen(name,"wb");
   $fwrite(fd,"P5\n912 288\n255\n");
   for(i=0;i<912*288;i=i+1) $fwrite(fd,"%c",fb[i]);
   $fclose(fd);
  end
  y=0;
  if(frames>=last) $finish;
 end
 // Steering: a slow continuous turn for both cars.
 always #3000000 if(!reset) begin steer1={steer1[0],~steer1[1]}; steer2={steer2[0],~steer2[1]}; end
 initial begin
  if($value$plusargs("game=%d",game)) begin end
  if($value$plusargs("last=%d",last)) begin end
  if($value$plusargs("every=%d",every)) begin end
  $readmemh(game ? "build/rom_dr.hex" : "build/rom_derby.hex",stream);
  // Download with the game held in reset, as JTFRAME does.
  #100;
  for(i=0;i<2304;i=i+1) begin
   @(posedge clk);prom_addr<=i;prom_din<=stream[i];prom_wr<=1;
   if(i==0) game_dr<=stream[0][0];
  end
  @(posedge clk);prom_wr<=0;
  #2000 reset=0;
  // Two coins and two starts through the frame-rate debounce: both players on.
  #150000000 coin=1; #100000000 coin=0; #100000000 coin=1; #100000000 coin=0;
  #100000000 start=1; #100000000 start=0;
  gas1=2'b11;gas2=2'b11;
 end
endmodule
