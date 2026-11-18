`timescale 1ns/1ps
// Exercise the traced sheet-3 ROM/mux network against recognizable glyphs.
module tb_score;
 parameter FPGA=1;
 reg clk=0, reset=1;
 always #5 clk=~clk;
 reg [3:0] digit=0, x=0, y=0;
 deathrac_board dut(.clk_sys(clk),.reset(reset),.xtal(1'b0),.game_dr(1'b0),.prom_wr(1'b0));
 reg [7:0] col[0:29];
 integer d,h,v,c;
 reg expected;
 initial begin
  {col[0],col[1],col[2]}=24'h3e413e;
  {col[3],col[4],col[5]}=24'h00007f;
  {col[6],col[7],col[8]}=24'h714946;
  {col[9],col[10],col[11]}=24'h494936;
  {col[12],col[13],col[14]}=24'h0f087f;
  {col[15],col[16],col[17]}=24'h4f4931;
  {col[18],col[19],col[20]}=24'h3e4930;
  {col[21],col[22],col[23]}=24'h01017f;
  {col[24],col[25],col[26]}=24'h364936;
  {col[27],col[28],col[29]}=24'h06493e;
  force dut.circuit.n_S999=1;
  force dut.circuit.n_C15_pin3_TSS0=0;
  force dut.circuit.n_C15_pin4_TSS1=0;
  force dut.circuit.n_N14_pin6_M14_pin11=1;
  #50 reset=0;
  for(d=0;d<10;d=d+1) begin
   digit=d;
   for(v=0;v<16;v=v+1) for(h=0;h<16;h=h+1) begin
    x=h;y=v;
  force dut.circuit.n_P12_pin5_SCS0=digit[0];
  force dut.circuit.n_N12_pin5_P13_pin5=digit[1];
  force dut.circuit.n_M12_pin5_P13_pin2=digit[2];
  force dut.circuit.n_L12_pin5_SCS3=digit[3];
  force dut.circuit.n_A15_pin13_TEC2=x[1];
  force dut.circuit.n_A15_pin12_TEC3=x[2];
  force dut.circuit.n_A15_pin11_TEC4=x[3];
  force dut.circuit.n_A14_pin13_TLC2=y[1];
  force dut.circuit.n_A14_pin12_TLC3=y[2];
  force dut.circuit.n_A14_pin11_TLC4=y[3];
    #20;
    c=h<2 ? 0 : h<8 ? 1 : 2;
    expected=h<10 ? col[3*d+c][v/2] : 0;
    if(dut.circuit.n_M13_pin5_L13_pin11!==expected)
     $fatal(1,"digit %0d x=%0d y=%0d actual=%b expected=%b",d,h,v,dut.circuit.n_M13_pin5_L13_pin11,expected);
   end
  end
  $display("PASS: all ten timer digits, 2560 pixel checks");
  $finish;
 end
endmodule
