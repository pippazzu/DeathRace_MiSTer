// JTFRAME integration. Cabinet switches are active low at this interface.
module deathrac_game(
 `ifdef JTFRAME_INTERLACED
 // Field flag for the MiSTer scaler (VGA_F1); 0 at native timing.
 output field,
 `endif
 `include "jtframe_game_ports.inc"
);
wire [7:0] mono,native_mono,il_mono;
wire active, de;
wire native_ce,native_ce2,native_hs,native_vs,native_hb,native_vb;
wire il_ce,il_ce2,il_hs,il_vs,il_hb,il_vb,il_field;
// Sheet 3 switch: 2 minutes or 1 minute grounded, or neither for 1 1/2 minutes.
wire [1:0] duration=status[21:20]==1 ? 2'b01 : status[21:20]==3 ? 2'b00 : 2'b10;
// Gas pedal. See deathrac_pedal in deathrac_controls.v.
// MRA byte stream: byte 0 selects the game, then the PROMs (tools/make_mra.py).
wire prom_wr=ioctl_rom & ioctl_wr;
// Byte 0: bit 0 = Death Race, bit 1 = this MRA wants the native progressive picture.
reg game_dr=0,mra_native=0;
always @(posedge clk) if(prom_wr && ioctl_addr[11:0]==0) {mra_native,game_dr}<=ioctl_dout[1:0];
assign dwnld_busy=ioctl_rom;
wire [1:0] gas1,gas2;
// The right trigger (RT, bits 15:8) also works the pedal, in every axis mode. The patched
// hps_io (tools/jtframe_trigger.py) puts each player's {RT, LT} on right sticks 3 and 4,
// as the Monaco GP core does; 0 when MiSTer Main does not send them.
deathrac_pedal pedal1(clk,rst,joyana_l1[15:8],joyana_r1[15:8],joyana_r3[15:8],joystick1[4],status[26:25],gas1);
deathrac_pedal pedal2(clk,rst,joyana_l2[15:8],joyana_r2[15:8],joyana_r4[15:8],joystick2[4],status[26:25],gas2);
// Drive/Reverse shifters. OSD bit 22: 0 separate Drive and Reverse buttons, 1 Drive toggles.
wire gear1,gear2;
wire [1:0] steer1,steer2;
deathrac_steering_div3 steering1(clk,rst,dial_x,steer1);
deathrac_steering_div3 steering2(clk,rst,dial_y,steer2);
deathrac_gear shifter1(clk,rst,!status[22],joystick1[5],joystick1[6],gear1);
deathrac_gear shifter2(clk,rst,!status[22],joystick2[5],joystick2[6],gear2);
// Pad Coin and Start, either player, shaped for sheet 2. See deathrac_credit.
wire coin_sw,start_sw,started;
deathrac_credit #(.SYS_HZ(115151515)) credit(clk,rst,!(&coin[1:0]),!(&cab_1p[1:0]),active,started,coin_sw,start_sw);
deathrac_fpga #(.SYS_HZ(115151515)) game(
 .clk_sys(clk),.reset_in(rst),.coin(coin_sw),.start(start_sw),
 .time_select(duration),.steer1(steer1),.steer2(steer2),
 .gas1(gas1),.gas2(gas2),
 .gear1(gear1),.gear2(gear2),
 .ce_pixel(native_ce),.ce_pixel2(native_ce2),.hsync(native_hs),.vsync(native_vs),
 .hblank_out(native_hb),.vblank_out(native_vb),.de(de),.video(native_mono),
 .game_active(active),.audio1(amp1),.audio2(amp2),.tone(status[24:23]),
 .game_dr(game_dr),.prom_wr(prom_wr),.prom_addr(ioctl_addr[11:0]),.prom_din(ioctl_dout),
 .game_started(started));
// Speakers (OSD bit 29). The cabinet has a speaker per player, and player 2's is muted in
// a one-player game. 0 (default): both amplifiers summed, saturated, on both channels.
// 1: one per player, player 1 left and player 2 right, as the cabinet. Bit 28 is skipped:
// it was the Trigger test, and configs saved with it On would come back as one per player.
wire signed [15:0] amp1,amp2;
wire signed [16:0] amp_sum=amp1+amp2;
wire signed [15:0] amp_mono=amp_sum>17'sd32767 ? 16'sh7fff : amp_sum< -17'sd32768 ? -16'sh8000 : amp_sum[15:0];
assign snd_left=status[29] ? amp1 : amp_mono;
assign snd_right=status[29] ? amp2 : amp_mono;
wire hblank,vblank;
deathrac_interlace interlace(.clk(clk),.reset(rst),.ce_in(native_ce),.ce2_in(native_ce2),
 .hb_in(native_hb),.vb_in(native_vb),.video_in(native_mono),
 .ce_out(il_ce),.ce2_out(il_ce2),.hs_out(il_hs),.vs_out(il_vs),
 .hb_out(il_hb),.vb_out(il_vb),.field(il_field),.video_out(il_mono));
// The MRA picks the picture: the 15 kHz set gives interlaced 15.7 kHz for TVs, the
// plain set the board's own 17.3 kHz progressive picture. OSD bit 27 swaps the two.
// Switched during native VBlank.
reg native_mode=0;
always @(posedge clk) if(native_ce && (rst || native_vb)) native_mode<=mra_native^status[27];
assign pxl_cen=native_mode ? native_ce : il_ce;
assign pxl2_cen=native_mode ? native_ce2 : il_ce2;
assign HS=native_mode ? native_hs : il_hs;
assign VS=native_mode ? native_vs : il_vs;
assign hblank=native_mode ? native_hb : il_hb;
assign vblank=native_mode ? native_vb : il_vb;
wire [7:0] game_mono=native_mode ? native_mono : il_mono;
assign mono=game_mono;
`ifdef JTFRAME_INTERLACED
assign field=!native_mode && il_field;
`endif
assign LHBL=~hblank;
assign LVBL=~vblank;
assign red=mono,green=mono,blue=mono;
assign dip_flip=0;
assign debug_view={7'b0,active};
assign {ba0_addr,ba1_addr,ba2_addr,ba3_addr}=0;
assign {ba_rd,ba_wr,ba0_din,ba1_din,ba2_din,ba3_din}=0;
assign {ba0_dsn,ba1_dsn,ba2_dsn,ba3_dsn}=8'hff;
assign {prog_data,prog_ba,prog_we,prog_rd,prog_mask,prog_addr}=0;
assign snd_vu=0,snd_peak=0;
reg [26:0] sample_phase;
reg sample_strobe;
assign sample=sample_strobe;
always @(posedge clk) begin
 sample_strobe<=0;
 if(rst) sample_phase<=0;
 else if(sample_phase>=115151515-48000) begin sample_phase<=sample_phase-(115151515-48000);sample_strobe<=1;end
 else sample_phase<=sample_phase+48000;
end
endmodule
