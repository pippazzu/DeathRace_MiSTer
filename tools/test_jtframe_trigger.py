"""The patched hps_io (tools/jtframe_trigger.py) against Main's 0x46 and 0x3d packets.
Adapted from MonacoGP_MiSTer scripts/test_hps_trigger.py.
Usage: python tools/test_jtframe_trigger.py
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import pathlib, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root/'tools'))
from jtframe_trigger import patch_hps_io
jt = root/'jtcores/modules/jtframe'
iverilog = pathlib.Path('C:/iverilog/bin')
bench = r"""
`timescale 1ns/1ps
module tb;
reg clk=0; always #5 clk=~clk;
reg [15:0] din=0; reg strobe=0, enable=0;
wire [48:0] bus;
assign bus[31:16]=din; assign bus[33]=strobe; assign bus[34]=enable; assign bus[35]=1'b0;
wire [15:0] r0,r1,r2,r3,r4,r5;
wire [15:0] t0=r2,t1=r3;   // player 1 {RT, LT}, player 2 {RT, 0}, Monaco GP style
hps_io #(.STRLEN(8),.CONF_STR("DEATHRAC"),.CONF_STR_BRAM(0),.PS2DIV(32),.WIDE(0),.BLKSZ(1)) dut(
  .clk_sys(clk),.HPS_BUS(bus),.joystick_r_analog_0(r0),.joystick_r_analog_1(r1),.joystick_r_analog_2(r2),
  .joystick_r_analog_3(r3),.joystick_r_analog_4(r4),.joystick_r_analog_5(r5),
  .ioctl_wait(1'b0),.status_menumask(16'd0),.status_in(128'd0),.status_set(1'b0),.info_req(1'b0),.info(8'd0),
  .ioctl_din(8'd0),.sd_lba(),.sd_rd(1'b0),.sd_wr(1'b0),.sd_blk_cnt(),.sd_buff_din(),.TIMESTAMP(),.ps2_kbd_led_status(3'd0),
  .ps2_kbd_led_use(3'd0));
task word(input [15:0] w); begin @(negedge clk); din=w; strobe=1; @(negedge clk); strobe=0; end endtask
task start; begin @(negedge clk); enable=1; end endtask
task stop; begin @(negedge clk); enable=0; repeat(2) @(negedge clk); end endtask
task stick(input [3:0] p, input [15:0] v); begin start; word(16'h3d); word(p); word(v); stop; end endtask
initial begin
  repeat(4) @(negedge clk);
  if(t0!==16'h0 || t1!==16'h0) $fatal(1,"triggers not released at power-up: %h %h",t0,t1);
  start; word(16'h46); word(0); word(16'hC040); stop;
  if(t0!==16'hC040 || t1!==16'h0) $fatal(1,"player 1 {RT,LT}: %h %h",t0,t1);
  start; word(16'h46); word(1); word(16'h1234); stop;
  if(t1!==16'h1200 || t0!==16'hC040) $fatal(1,"player 2 {RT,0}: %h %h",t0,t1);
  start; word(16'h46); word(2); word(16'h5555); stop;
  start; word(16'h46); word(3); word(16'h6666); stop;
  if(t0!==16'hC040 || t1!==16'h1200) $fatal(1,"players 3 and 4 reached the triggers: %h %h",t0,t1);
  start; word(16'h46); word(0); word(16'hFF00); word(16'h1111); word(16'h2222); stop;
  if(t0!==16'hFF00) $fatal(1,"extra words were taken: %h",t0);
  // Right sticks 1 and 2 arrive; those of players 3 and 4 no longer touch the triggers.
  stick(0,16'h8877); stick(1,16'h7766); stick(2,16'h6655); stick(3,16'h5544);
  if(r0!==16'h8877 || r1!==16'h7766)
    $fatal(1,"right sticks: %h %h",r0,r1);
  if(t0!==16'hFF00 || t1!==16'h1200) $fatal(1,"a right stick reached the triggers: %h %h",t0,t1);
  $display("PASS hps_io 0x46: triggers of players 1 and 2, power-up, players 3-4 ignored, extra words, right sticks 1-2 kept, 3-4 dropped"); $finish;
end
endmodule
"""
with tempfile.TemporaryDirectory() as temp:
    temp = pathlib.Path(temp)
    (temp/'hps_io_trig.sv').write_text(patch_hps_io((jt/'target/mister/hdl/sys/hps_io.sv').read_text()))
    (temp/'tb.v').write_text(bench)
    subprocess.run([str(iverilog/'iverilog'), '-g2012', '-s', 'tb', '-o', str(temp/'sim'), str(temp/'tb.v'), str(temp/'hps_io_trig.sv')], check=True)
    r = subprocess.run([str(iverilog/'vvp'), str(temp/'sim')], text=True, capture_output=True)
    print(r.stdout, end='')
    if r.returncode or 'PASS' not in r.stdout:
        print(r.stderr, end='')
        raise SystemExit(1)
