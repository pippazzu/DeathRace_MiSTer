// Interlaced output against the real game. The PROMs arrive as on MiSTer, the
// board runs at native timing, and every output line is checked against the source
// row that ended most recently, computed here from sample counts alone. Sync is
// checked at the module and after JTFRAME's jtframe_resync, which MiSTer applies.
// +game=0 Derby, +game=1 Death Race. Writes build/il<game>_native.pgm (one source
// frame) and build/il<game>_woven.pgm (two fields woven into 525 lines).
`timescale 1ns/1ps
module tb_interlace;
 reg clk=0,reset=1;
 always #4.342 clk=~clk;
 integer game=1,i;
 reg [7:0] stream[0:2303];
 reg prom_wr=0;
 reg [11:0] prom_addr=0;
 reg [7:0] prom_din=0;
 reg game_dr=0;
 wire nce,nce2,nhs,nvs,nhb,nvb,de;
 wire [7:0] nvideo;
 deathrac_fpga #(.SYS_HZ(115151515)) game_i(.clk_sys(clk),.reset_in(reset),.coin(1'b0),.start(1'b0),
  .time_select(2'b10),.steer1(2'b00),.steer2(2'b00),.gas1(2'b00),.gas2(2'b00),.gear1(1'b0),.gear2(1'b0),
  .ce_pixel(nce),.ce_pixel2(nce2),.hsync(nhs),.vsync(nvs),.hblank_out(nhb),.vblank_out(nvb),.de(de),
  .video(nvideo),.tone(2'b00),.game_dr(game_dr),.prom_wr(prom_wr),.prom_addr(prom_addr),.prom_din(prom_din));
 wire oce,oce2,ohs,ovs,ohb,ovb,field;
 wire [7:0] ovideo;
 deathrac_interlace dut(.clk(clk),.reset(reset),.ce_in(nce),.ce2_in(nce2),.hb_in(nhb),.vb_in(nvb),
  .video_in(nvideo),.ce_out(oce),.ce2_out(oce2),.hs_out(ohs),.vs_out(ovs),.hb_out(ohb),.vb_out(ovb),
  .field(field),.video_out(ovideo));
 // MiSTer's sync relocation stage, as built (hoffset = voffset = 0).
 wire rhs,rvs;
 jtframe_resync resync(.clk(clk),.pxl_cen(oce),.hs_in(ohs),.vs_in(ovs),.LVBL(~ovb),.LHBL(~ohb),
  .hoffset(4'd0),.voffset(4'd0),.hs_out(rhs),.vs_out(rvs));

 // ---- Source side: sample counter, frame starts, stored rows ----
 integer n=0;                       // native sample count
 integer fs=-1, fs_prev=-1;         // sample index of the first active line start
 integer sframes=0, srow=-1, sx=0, src_lines=0, src_len=0;
 reg old_nhb=1, last_on=0;
 reg [7:0] src[0:1][0:255][0:639];  // last two source frames by parity
 integer sp=0;                      // parity slot of the frame being written
 always @(posedge clk) if(nce) begin
  if(!nhb && old_nhb) begin
   if(src_len && sframes>1 && src_len!=832) $fatal(1,"source line %0d samples",src_len);
   src_len=0;
   if(!nvb && !last_on) begin
    if(fs>=0 && sframes>1 && n-fs!=832*288) $fatal(1,"source frame %0d samples",n-fs);
    fs_prev=fs; fs=n; sframes=sframes+1; srow=0; sp=sframes%2;
   end else if(srow>=0) srow=srow+1;
   last_on=!nvb; sx=0;
  end
  src_len=src_len+1;
  if(!nhb && !nvb && srow>=0 && srow<256 && sx<640) begin src[sp][srow][sx]=nvideo; sx=sx+1; end
  old_nhb=nhb;
  n=n+1;
 end

 // ---- Output side ----
 integer on=0, ox=0, olen=0, hs_at=-1, lines=0, field_lines=0, checked=0, active_lines=0;
 integer pred, pfs, psp, row_seen[0:1][0:255], fcount=0, vs_x=-1, vs_line=0;
 integer woven_y, fld_line=0, oframes=0, rows_f0=0, rows_f1=0;
 reg old_ohb=1, old_ohs=0, old_ovs=0, old_field=0, cur_on=0, started=0;
 reg [7:0] woven[0:524][0:639];
 integer line_sample=0, line_pred=0, line_sp=0;
 always @(posedge clk) if(oce) begin
  if(field!=old_field) begin
   fld_line=0;
   if(field==0) begin
    oframes=oframes+1;
    if(oframes>=2) started=1;
    if(oframes==4) begin
     // Coverage over the last frame: both fields together draw every row.
     for(i=0;i<256;i=i+1) begin
      if(row_seen[0][i]) rows_f0=rows_f0+1;
      if(row_seen[1][i]) rows_f1=rows_f1+1;
      if(!row_seen[0][i] && !row_seen[1][i]) $fatal(1,"row %0d never drawn",i);
     end
     $display("rows drawn: field 0 %0d, field 1 %0d, union 256 of 256",rows_f0,rows_f1);
    end
    for(i=0;i<256;i=i+1) begin row_seen[0][i]=0; row_seen[1][i]=0; end
    if(oframes==4) dump;
    if(oframes==5) begin
     $display("PASS interlace: %0d pixels match their source rows, 912/913-sample lines, 262.5-line fields, VS at HS and half a line later, through jtframe_resync",checked);
     $finish;
    end
   end
  end
  // Line boundaries are at active start, one sample after the module decides.
  if(!ohb && old_ohb) begin
   if(started && olen!=912 && olen!=913) $fatal(1,"output line %0d samples",olen);
   olen=0; ox=0; lines=lines+1; field_lines=field_lines+1;
   line_sample=n-2;   // emitted one sample after the decision, seen one clock later
   // Row that ended most recently, from counts only.
   pfs=(line_sample>=fs) ? fs : fs_prev; psp=(line_sample>=fs) ? sframes%2 : (sframes-1)%2;
   pred=(line_sample-pfs)/832-1;
   line_pred=pred; line_sp=psp;
   cur_on=!ovb;
   if(started && fs_prev>=0) begin
    if(cur_on !== (pred>=0 && pred<256)) $fatal(1,"line blank=%b but predicted row %0d",ovb,pred);
   end
   if(fld_line<263) begin
    woven_y=field ? 2*fld_line+1 : 2*fld_line;
   end
   fld_line=fld_line+1;
  end
  if(!ohb) begin
   if(started && fs_prev>=0 && cur_on) begin
    if(ovideo!==src[line_sp][line_pred][ox]) $fatal(1,"pixel row %0d x %0d out %0d src %0d",line_pred,ox,ovideo,src[line_sp][line_pred][ox]);
    checked=checked+1;
    if(ox==0) begin row_seen[field][line_pred]=1; end
   end
   if(woven_y<525 && ox<640) woven[woven_y][ox]=cur_on ? ovideo : 8'd40;
   ox=ox+1;
  end
  if(ohs && !old_ohs) begin
   if(hs_at>=0 && started && on-hs_at!=912 && on-hs_at!=913) $fatal(1,"HS spacing %0d",on-hs_at);
   hs_at=on;
   if(olen!=740) $fatal(1,"HS at x=%0d",olen);
  end
  if(ovs && !old_ovs) begin
   vs_x=olen;
   if(started) begin
    if(field==0 && vs_x!=740) $fatal(1,"field 0 VS at x=%0d",vs_x);
    if(field==1 && vs_x!=284) $fatal(1,"field 1 VS at x=%0d",vs_x);
    $display("field %0d: VS at x=%0d, %0d lines since previous VS",field,vs_x,field_lines);
    if(oframes>2 && field_lines!=262 && field_lines!=263) $fatal(1,"field lines %0d",field_lines);
   end
   field_lines=0;
  end
  old_ohb=ohb; old_ohs=ohs; old_ovs=ovs; old_field=field;
  olen=olen+1; on=on+1;
 end

 // Sync after jtframe_resync: HS cadence and the per-field VS offset survive.
 integer rn=0, rhs_at=-1, rvs_count=0;
 reg old_rhs=0, old_rvs=0;
 always @(posedge clk) if(oce) begin
  if(rhs && !old_rhs) begin
   if(rhs_at>=0 && oframes>2 && rn-rhs_at!=912 && rn-rhs_at!=913) $fatal(1,"resync HS spacing %0d",rn-rhs_at);
   rhs_at=rn;
  end
  if(rvs && !old_rvs && oframes>2) begin
   $display("resync VS: %0d samples after resync HS (field %0d)",rn-rhs_at,field);
   if(rn-rhs_at!=0 && (rn-rhs_at<450 || rn-rhs_at>462)) $fatal(1,"resync VS not at HS or half line");
   rvs_count=rvs_count+1;
  end
  old_rhs=rhs; old_rvs=rvs; rn=rn+1;
 end

 task dump;
  integer fd,y,x;
  reg [8*40-1:0] name;
  begin
   $sformat(name,"build/il%0d_woven.pgm",game);
   fd=$fopen(name,"wb"); $fwrite(fd,"P5\n640 525\n255\n");
   for(y=0;y<525;y=y+1) for(x=0;x<640;x=x+1) $fwrite(fd,"%c",woven[y][x]);
   $fclose(fd);
   $sformat(name,"build/il%0d_native.pgm",game);
   fd=$fopen(name,"wb"); $fwrite(fd,"P5\n640 256\n255\n");
   for(y=0;y<256;y=y+1) for(x=0;x<640;x=x+1) $fwrite(fd,"%c",src[(sframes-1)%2][y][x]);
   $fclose(fd);
   if(rvs_count<2) $fatal(1,"resync produced no VS");
  end
 endtask

 initial begin
  // Quartus powers these framework registers up at zero; Icarus leaves them X.
  resync.field=0;resync.hs_hold=0;resync.vs_hold=0;
  resync.last_LHBL=0;resync.last_LVBL=0;resync.last_hsin=0;resync.last_vsin=0;
  for(i=0;i<256;i=i+1) begin row_seen[0][i]=0; row_seen[1][i]=0; end
  if($value$plusargs("game=%d",game)) begin end
  $readmemh(game ? "build/rom_dr.hex" : "build/rom_derby.hex",stream);
  #100;
  for(i=0;i<2304;i=i+1) begin
   @(posedge clk);prom_addr<=i;prom_din<=stream[i];prom_wr<=1;
   if(i==0) game_dr<=stream[0][0];
  end
  @(posedge clk);prom_wr<=0;
  #2000 reset=0;
 end
 initial begin #200000000; $fatal(1,"timeout"); end
endmodule
