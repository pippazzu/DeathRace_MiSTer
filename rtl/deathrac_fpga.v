// MiSTer-facing timing/video boundary. All registers use clk_sys.
module deathrac_fpga #(parameter SYS_HZ=115151515)(
 input wire clk_sys,reset_in,coin,start,input wire [1:0] time_select,
 input wire [1:0] steer1,steer2,gas1,gas2,input wire gear1,gear2,
 output reg ce_pixel,hsync,vsync,de,output reg [7:0] video,
 output reg ce_pixel2,hblank_out,vblank_out,
 output wire game_active,output wire signed [15:0] audio1,audio2,
 input wire [1:0] tone,
 input wire game_dr,prom_wr,input wire [11:0] prom_addr,input wire [7:0] prom_din,
 // ESGC of sheet 2, for the MiSTer button conditioner (deathrac_credit).
 output wire game_started
);
 // Local copy of the frame reset; it fans out to every traced cell.
 reg [1:0] reset_sr;
 always @(posedge clk_sys) reset_sr<={reset_sr[0],reset_in};
 wire reset=reset_sr[1];
 // The crystal is an exact divide by 8 of the 115.1515 MHz system clock: 14.394 MHz,
 // 0.02% above the drawn 14.391 MHz, so every pixel is exactly 8 clocks long. It runs
 // freely with no reset because JTFRAME counts pxl_cen to release the game reset.
 reg [2:0] div=0;
 reg xtal=0;
 always @(posedge clk_sys) begin
  div<=div+1'b1;
  xtal<=div[2];
 end
 wire hs,vs,hb,vb,pc,white,grey,p2,cr1,cr2;
 wire [2:0] m1,m2;
 wire [8:0] hc,vc;
 wire [7:0] timer;
 deathrac_board board(clk_sys,reset,xtal,coin,start,time_select,
  steer1,steer2,gas1,gas2,gear1,gear2,hs,vs,hb,vb,pc,white,grey,
  game_active,p2,m1,m2,cr1,cr2,hc,vc,timer,xcr1,xcr2,xc1a,xc1b,xc2a,xc2b,dis1_n,dis2_n,
  game_dr,prom_wr,prom_addr,prom_din,lado,game_started);
 // Pixels leave at the crystal rate. Death Race draws half pixels: video latch
 // 14A runs on rising 1TQ14. Derby's F16 updates on falling 1TQ14 and simply holds
 // across two output pixels. div==7 is 3 clocks after xtal rises, once the latch
 // has settled, and it coincides with a pxl2_cen so the two enables stay aligned.
 always @(posedge clk_sys) begin
  ce_pixel<=div==7;
  ce_pixel2<=div[1:0]==3;
  if(reset) begin
   hsync<=0;vsync<=0;de<=0;video<=0;hblank_out<=1;vblank_out<=1;
  end else if(div==7) begin
   hsync<=hs;vsync<=vs;de<=!(hb|vb);
   hblank_out<=hb;vblank_out<=vb;
   // Sheet 1/T summing node. grey is 5TNVD, inverted: high everywhere, blanking
   // included, and low only on the player 2 car. The 6.8uF output coupling makes
   // the monitor take blanking as black, so white=0 grey=1 is black. Relative to
   // that, white+grey is 1/2.2k (full) and white alone is 1/2.2k - 1/4.7k = 53%.
   video<=!white ? 8'd0 : grey ? 8'd255 : 8'd136;
  end
 end
 wire xcr1,xcr2,xc1a,xc1b,xc2a,xc2b,dis1_n,dis2_n;
 wire lado;
 wire fs48;
 wire signed [31:0] scream;
 // Death Race sheet Y has a single crash generator feeding both speakers.
 deathrac_audio #(.SYS_HZ(SYS_HZ)) sound(clk_sys,reset,game_active,p2,m1,m2,cr1,game_dr ? cr1 : cr2,
  xc1a,xc1b,xc2a,xc2b,dis1_n,dis2_n,xcr1,xcr2,audio1,audio2,tone,scream,fs48,game_dr);
 deathrac_scream scream_gen(clk_sys,reset,fs48,game_dr,lado,scream);
endmodule
