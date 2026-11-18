`timescale 1ns/1ps
module tb_jtframe_reset;
reg clk=0,locked=0,request=1;
always #4.342 clk=~clk;
wire game_reset,ce,ce2,hs,vs,de;
wire [7:0] video;
jtframe_reset reset_controller(.clk_sys(clk),.clk_rom(clk),.pxl_cen(ce),
 .sdram_init(1'b0),.ioctl_rom(1'b0),.dip_flip(1'b0),.soft_rst(1'b0),
 .rst_req(request),.pll_locked(locked),.rst(),.rst_n(),
 .game_rst(game_reset),.game_rst_n());
deathrac_fpga #(.SYS_HZ(115151515)) dut(.clk_sys(clk),.reset_in(game_reset),.game_dr(1'b0),.prom_wr(1'b0),
 .coin(1'b0),.start(1'b0),.time_select(2'b10),
 .steer1(2'b00),.steer2(2'b00),.gas1(2'b00),.gas2(2'b00),
 .gear1(1'b0),.gear2(1'b0),.ce_pixel(ce),.ce_pixel2(ce2),
 .hsync(hs),.vsync(vs),.de(de),.video(video));
integer pixels=0,lines=0;
always @(posedge clk) if(ce && !game_reset) pixels=pixels+1;
always @(posedge hs) lines=lines+1;
initial begin
 #100;locked=1;#200;request=0;
 #10000;if(game_reset!==0)$fatal(1,"JTFRAME startup reset deadlock");
 #150000;if(pixels<500 || lines<2)$fatal(1,"No running game video");
 request=1;#1000;if(game_reset!==1)$fatal(1,"Reset did not assert");
 request=0;#10000;if(game_reset!==0)$fatal(1,"JTFRAME soft reset deadlock");
 $display("PASS JTFRAME startup and soft reset; pixels=%0d lines=%0d",pixels,lines);$finish;
end
endmodule
