// Analog accelerator: travel order, all axis modes, hysteresis, trigger, button.
`timescale 1ns/1ps
module tb_pedal;
 reg clk=0,reset=1,button_n=1;
 reg [7:0] l=0,r=0,t=0;
 reg [1:0] mode=0;
 wire [1:0] gas;
 always #5 clk=~clk;
 deathrac_pedal dut(clk,reset,l,r,t,button_n,mode,gas);
 task expect_gas(input [7:0] left,right,input [1:0] want,input [255:0] what);
  begin
   l=left;r=right;repeat(3) @(posedge clk);#1;
   if(gas!==want) begin
    $display("FAIL %0s: l=%0d r=%0d gas=%b want=%b",what,$signed(left),$signed(right),gas,want);
    $fatal(1);
   end
  end
 endtask
 function [7:0] neg(input integer v);neg=-v;endfunction
 initial begin
  repeat(3) @(posedge clk);reset=0;
  // Mode 0, right stick up. Board order 00,01,11,10.
  expect_gas(0,0,2'b00,"centre");
  expect_gas(0,neg(31),2'b00,"below first");
  expect_gas(0,neg(32),2'b01,"slow");
  expect_gas(0,neg(64),2'b11,"medium");
  expect_gas(0,neg(96),2'b10,"fast");
  expect_gas(0,neg(127),2'b10,"full");
  expect_gas(0,neg(128),2'b10,"full -128");
  // Hysteresis on the way back.
  expect_gas(0,neg(90),2'b10,"hold fast");
  expect_gas(0,neg(87),2'b11,"drop to medium");
  expect_gas(0,neg(58),2'b11,"hold medium");
  expect_gas(0,neg(55),2'b01,"drop to slow");
  expect_gas(0,neg(26),2'b01,"hold slow");
  expect_gas(0,neg(23),2'b00,"drop to stopped");
  // Stick pulled down never accelerates. The other stick is ignored.
  expect_gas(0,8'd127,2'b00,"down");
  expect_gas(neg(127),0,2'b00,"other stick");
  // Mode 1, left stick.
  mode=1;expect_gas(neg(127),0,2'b10,"left full");
  expect_gas(0,neg(127),2'b00,"left mode ignores right");
  // Mode 2, right Y as a full-travel pedal: +127 is released.
  mode=2;expect_gas(0,8'd127,2'b00,"pedal released");
  expect_gas(0,8'd60,2'b01,"pedal slow");    // travel 33
  expect_gas(0,neg(2),2'b11,"pedal medium");  // travel 64
  expect_gas(0,neg(128),2'b10,"pedal floor");
  expect_gas(0,8'd127,2'b00,"pedal back to rest");
  // Mode 3, left Y.
  mode=3;expect_gas(8'd127,neg(128),2'b00,"left pedal released");
  expect_gas(neg(128),8'd127,2'b10,"left pedal floor");
  // Right trigger, 0..255 halved to the stick's 0..127 travel, in any mode.
  mode=0;expect_gas(0,0,2'b00,"trigger mode 0 rest");
  t=8'd63;expect_gas(0,0,2'b00,"trigger below first");     // travel 31
  t=8'd64;expect_gas(0,0,2'b01,"trigger slow");            // travel 32
  t=8'd128;expect_gas(0,0,2'b11,"trigger medium");         // travel 64
  t=8'd192;expect_gas(0,0,2'b10,"trigger fast");           // travel 96
  t=8'd255;expect_gas(0,0,2'b10,"trigger full");
  // Whichever of stick and trigger is further.
  t=8'd60;expect_gas(0,neg(100),2'b10,"stick beats trigger");
  t=8'd255;expect_gas(0,neg(30),2'b10,"trigger beats stick");
  // Released: the pedal steps down one position a clock and stops at the stick's 30.
  t=0;expect_gas(0,neg(30),2'b01,"trigger released, stick slow");
  // Pedal mode: the released pedal gives 0 travel, so the trigger still works.
  mode=3;t=8'd255;expect_gas(8'd127,0,2'b10,"trigger with pedal released");
  t=0;expect_gas(8'd127,0,2'b00,"trigger off, back to stopped");
  // Button forces full travel and releases back to the axis.
  expect_gas(8'd127,0,2'b00,"axis off");
  button_n=0;expect_gas(8'd127,0,2'b10,"button");
  button_n=1;expect_gas(8'd127,0,2'b00,"button released");
  // R mapped as the Accelerate button too: Main sends its digital press with the analog
  // value, and the analog value must win.
  mode=0;t=8'd128;button_n=0;expect_gas(0,0,2'b11,"R as button and analog: medium");
  t=8'd100;expect_gas(0,0,2'b01,"R as button and analog: slow");
  t=0;expect_gas(0,0,2'b10,"button alone, trigger at rest");
  button_n=1;
  $display("PASS pedal: order, 4 axis modes, hysteresis, right trigger, button");
  $finish;
 end
endmodule
