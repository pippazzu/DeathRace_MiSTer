// Interlaced sync through MiSTer's analogue video path: deathrac_interlace ->
// jtframe_resync -> arcade_video (the patched copy the build uses, or MiSTer's own
// with +stock) -> VGA_HS/VGA_VS. The source is a synthetic native raster with the
// board's geometry (832 x 288, 640 x 256 active), so this runs in seconds.
// Interlace means: in one field VSync rises with an HSync, in the other half a line
// later. With MiSTer's own arcade_video both land on an HSync (the reported bug).
`timescale 1ns/1ps
module tb_interlace_path;
 reg clk=0;
 always #4.342 clk=~clk;
 reg [2:0] div=0;
 reg nce=0,nce2=0;
 reg [9:0] sx=0;
 reg [8:0] sy=0;
 reg nhb=1,nvb=1;
 reg [7:0] nvideo=0;
 always @(posedge clk) begin
  div<=div+1'b1;
  nce<=div==7; nce2<=div[1:0]==3;
  if(div==7) begin
   sx<=sx==831 ? 10'd0 : sx+1'b1;
   if(sx==831) sy<=sy==287 ? 9'd0 : sy+1'b1;
   nhb<=!(sx<640); nvb<=!(sy<256);
   nvideo<=(sx<640 && sy<256 && (sx[3] ^ sy[0])) ? 8'd255 : 8'd0;
  end
 end
 wire oce,oce2,ohs,ovs,ohb,ovb,field;
 wire [7:0] ovideo;
 deathrac_interlace dut(.clk(clk),.reset(1'b0),.ce_in(nce),.ce2_in(nce2),.hb_in(nhb),.vb_in(nvb),
  .video_in(nvideo),.ce_out(oce),.ce2_out(oce2),.hs_out(ohs),.vs_out(ovs),.hb_out(ohb),.vb_out(ovb),
  .field(field),.video_out(ovideo));
 wire rhs,rvs;
 jtframe_resync resync(.clk(clk),.pxl_cen(oce),.hs_in(ohs),.vs_in(ovs),.LVBL(~ovb),.LHBL(~ohb),
  .hoffset(4'd0),.voffset(4'd0),.hs_out(rhs),.vs_out(rvs));
 wire [7:0] r,g,b;
 wire vhs,vvs,vde,cep,clkv;
 wire [1:0] sl;
 wire [21:0] gamma_bus;
 arcade_video #(.WIDTH(768),.DW(24)) av(.clk_video(clk),.ce_pix(oce),.RGB_in({ovideo,ovideo,ovideo}),
  .HBlank(ohb),.VBlank(ovb),.HSync(rhs),.VSync(rvs),.CLK_VIDEO(clkv),.CE_PIXEL(cep),
  .VGA_R(r),.VGA_G(g),.VGA_B(b),.VGA_HS(vhs),.VGA_VS(vvs),.VGA_DE(vde),.VGA_SL(sl),
  .fx(3'd0),.forced_scandoubler(1'b0),.gamma_bus(gamma_bus));

 // Measure on the system clock: VSync rising edge position from the last HSync rise.
 integer t=0, last_hs=-1, prev_hs=-1, line=0, vs_seen=0, at_hs=0, at_half=0;
 reg old_hs=0, old_vs=0;
 always @(posedge clk) begin
  // sync_fix inverts if it decides a polarity is negative; take the short pulse.
  if(vhs && !old_hs) begin prev_hs=last_hs; last_hs=t; end
  if(vvs && !old_vs && t>4*1916928) begin
   vs_seen=vs_seen+1;
   $display("VGA VS rise %0d clocks after VGA HS rise (line %0d clocks), field %0d",t-last_hs,last_hs-prev_hs,field);
   if(t-last_hs<16) at_hs=at_hs+1;
   else if(t-last_hs>3600 && t-last_hs<3700) at_half=at_half+1;
   else $fatal(1,"VS neither at HS nor half a line later");
  end
  if(t==6*1916928 && vs_seen==0) begin $display("no VGA VS: rvs=%b av.VS=%b vvs=%b vhs=%b cep=%b",rvs,av.VS,vvs,vhs,cep); $fatal(1,"no VS"); end
  old_hs=vhs; old_vs=vvs; t=t+1;
  if(vs_seen==6) begin
   if(at_hs!=3 || at_half!=3) $fatal(1,"not interlaced: %0d at HS, %0d at half line",at_hs,at_half);
   $display("PASS interlace survives arcade_video: VS alternates between HS and half a line");
   $finish;
  end
 end
 initial begin
  // Optional freeze input, unconnected in arcade_video: inactive, as Quartus ties it.
  force av.video_mixer.HDMI_FREEZE=1'b0;
  resync.field=0;resync.hs_hold=0;resync.vs_hold=0;
  resync.last_LHBL=0;resync.last_LVBL=0;resync.last_hsin=0;resync.last_vsin=0;
  #200000000; $fatal(1,"timeout");
 end
endmodule
