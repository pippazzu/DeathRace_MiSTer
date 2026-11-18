`timescale 1ns/1ps
module tb_enemy_heading;
 parameter FPGA=1;
 reg clk=0,reset=1,update=0;
 always #5 clk=~clk;
 deathrac_board #(.FPGA(FPGA)) dut(.clk_sys(clk),.reset(reset),.xtal(1'b0),.game_dr(1'b0),.prom_wr(1'b0));
 integer h,slot;
 reg [3:0] heading;
 reg [3:0] shape[0:15];
 reg [3:0] selected;
 initial begin
  // The verified -34 heading PROM's shape indices; straight headings
  // select vertical (4) or horizontal (2/6), never diagonal (3/5).
  shape[0]=4;shape[1]=3;shape[2]=3;shape[3]=3;
  shape[4]=2;shape[5]=3;shape[6]=3;shape[7]=3;
  shape[8]=4;shape[9]=5;shape[10]=5;shape[11]=5;
  shape[12]=6;shape[13]=5;shape[14]=5;shape[15]=5;
  force dut.circuit.n_K10_pin8_J11_pin9=update;
  force dut.circuit.n_F5_pin8_C5_pin9=update;
  force dut.circuit.n_C16_pin7_5TEC9=0;
  #100;reset=0;#50;
  for(h=0;h<16;h=h+1) begin
   heading=h;
   force dut.circuit.s07_J9.q=heading;
   force dut.circuit.s09_E5.q=heading;
   update=0;#50;update=1;#50;
   // J11/C5 pin 4 is the inverter output; pin 3 is heading bit 3.
   if({dut.circuit.n_J11_pin2_1ACT3,dut.circuit.n_J11_pin5_K8_pin1}!=={heading[3],~heading[2]})
    $fatal(1,"enemy A heading=%d direction latch lost inverter",h);
   if({dut.circuit.n_C5_pin2_1CCT3,dut.circuit.n_C5_pin5_K8_pin13}!=={heading[3],~heading[2]})
    $fatal(1,"enemy C heading=%d direction latch lost inverter",h);
   if(dut.circuit.n_K8_pin3_L6_pin9!==(heading[3]^~heading[2]) ||
      dut.circuit.n_K8_pin11_E2_pin9!==(heading[3]^~heading[2]))
    $fatal(1,"vertical movement quadrant wrong, heading=%d",h);
   // Follow each enemy through the shared car-shape multiplexers.
   for(slot=2;slot<4;slot=slot+1) begin
    force dut.circuit.n_A15_pin12_TEC3=slot[0];
    force dut.circuit.n_A15_pin11_TEC4=slot[1];#50;
    selected={dut.circuit.n_C7_pin7_KKC3,dut.circuit.n_C7_pin9_KKC2,dut.circuit.n_D7_pin7_KKC1,dut.circuit.n_D7_pin9_F15_pin12};
    if(selected!==shape[h])$fatal(1,"enemy slot=%d heading=%d shape=%d expected=%d",slot,h,selected,shape[h]);
   end
  end
  $display("PASS both enemy direction latches, quadrants and shape selection: 16 headings each");$finish;
 end
endmodule
