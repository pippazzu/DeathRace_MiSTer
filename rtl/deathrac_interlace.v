// Interlaced 15 kHz output for CRT televisions. The game and its clocks are unchanged.
//
// The board draws 288 lines of 832 crystal samples at 60.07 Hz (17.3 kHz). This
// module keeps the pixel rate and the field rate and re-cuts time into 525 lines
// per two source frames: 262.5 lines per field, 912.8 samples per line, 15.77 kHz.
// Because a field lasts exactly one source frame, the TV scans down the screen at
// the same speed the arcade monitor did. Each output line shows the source line
// that finished most recently, so it stands where the beam stood on the original.
// The second field starts half a line later, so its lines land between those of
// the first and pick up the source rows the first one skipped: over a frame every
// row of the 256-line picture is drawn, score strip included, with no frame buffer.
//
// Source lines are kept in a four-line ring (two bits per pixel). A line is read
// at least one full source line after it was written and long before it is
// overwritten. The output raster is re-anchored every second source frame to the
// first active source line; once locked that re-anchoring is a no-op, because 525
// lines of 912/913 samples add up to exactly two frames of 832 x 288.
//
// Output line, in samples from the start of active video:
//   0..639 active, 640..739 front porch, 740..807 HSync (4.7 us), then back porch
//   up to the variable 912/913 line end. HSync and VSync are placed at fixed
//   positions after active start, the reference jtframe_resync measures from.
// VSync: three lines, starting with HSync in field 0 and half a line later in field 1.
module deathrac_interlace(
 input wire clk,reset,ce_in,ce2_in,
 input wire hb_in,vb_in,
 input wire [7:0] video_in,
 output reg ce_out,ce2_out,
 output reg hs_out,vs_out,hb_out,vb_out,field,
 output reg [7:0] video_out
);
 initial begin ce_out=0;ce2_out=0;hs_out=0;vs_out=0;hb_out=1;vb_out=1;field=0;video_out=0;end
 localparam PAIR=19'd479232;   // 2 x 832 x 288 samples: one interlaced frame
 localparam STEP=19'd525;      // output lines per interlaced frame
 localparam HS_X=10'd740, HS_W=10'd68, HALF=10'd456;
 localparam VS_LINE=10'd240;   // field 0; field 1 uses 263+VS_LINE at HS_X-HALF
 localparam VS_LINES=10'd3;

 // ---- Writer: source pixels into the ring --------------------------------
 reg old_hb=1;
 reg [1:0] wl=0;               // ring slot being written
 reg [9:0] wx=0;
 reg [3:0] line_on=4'b1111;    // slot holds an active (picture) line
 reg parity=0;                 // source frame parity
 (* ramstyle = "M10K, no_rw_check" *) reg [1:0] ring[0:4095];
 // The board has exactly three levels: 0, 136 and 255.
 wire [1:0] code_in=video_in[7] ? (video_in[6] ? 2'd2 : 2'd1) : 2'd0;
 wire line_start=!hb_in && old_hb;
 // First active line of a source frame: a picture line after a blank one.
 wire frame_start=line_start && !vb_in && !line_on[wl];
 wire anchor=frame_start && !parity;
 // Most recently completed source line, as seen by an output line starting now.
 wire [1:0] done_slot=line_start ? wl : wl-2'd1;

 always @(posedge clk) begin
  // All slots count as picture lines after reset, so the first anchor waits
  // for a real blank-to-picture transition.
  if(reset) begin old_hb<=1;wx<=0;line_on<=4'b1111;parity<=0;end
  else if(ce_in) begin
   old_hb<=hb_in;
   if(line_start) begin
    wl<=wl+2'd1;
    line_on[wl+2'd1]<=!vb_in;
    ring[{wl+2'd1,10'd0}]<=code_in;
    wx<=1;
    if(frame_start) parity<=~parity;
   end else if(!hb_in) begin
    if(wx<640) ring[{wl,wx}]<=code_in;
    wx<=wx+1'b1;
   end
  end
 end

 // ---- Output raster ------------------------------------------------------
 reg [18:0] phase=0;
 reg [9:0] ox=0;               // sample within output line
 reg [9:0] oy=0;               // line within the interlaced frame, 0..524
 reg [1:0] rd=0;               // slot shown on this output line
 reg rd_on=0;
 wire [19:0] phase_sum={1'b0,phase}+STEP;
 wire wrap=phase_sum>=PAIR;
 wire [9:0] oy_next=oy==10'd524 ? 10'd0 : oy+1'b1;

 // Prefetched synchronous read: the address is stable for the eight clocks
 // before the output strobe uses the data.
 reg [1:0] rd_code;
 always @(posedge clk) rd_code<=ring[{rd,ox}];

 wire vs_on0=oy==VS_LINE && ox==HS_X;
 wire vs_off0=oy==VS_LINE+VS_LINES && ox==HS_X;
 wire vs_on1=oy==10'd263+VS_LINE && ox==HS_X-HALF;
 wire vs_off1=oy==10'd263+VS_LINE+VS_LINES && ox==HS_X-HALF;
 wire hactive=ox<10'd640;

 always @(posedge clk) begin
  ce_out<=ce_in;
  ce2_out<=ce2_in;
  if(ce_in) begin
   // Emit the current position, then advance. Runs during reset as well:
   // JTFRAME counts pixel strobes to release the game reset.
   hs_out<=ox>=HS_X && ox<HS_X+HS_W;
   if(vs_on0 || vs_on1) vs_out<=1;
   if(vs_off0 || vs_off1) vs_out<=0;
   hb_out<=!hactive;
   vb_out<=reset || !rd_on;
   if(oy==10'd0 && ox==10'd0) field<=0;
   if(oy==10'd263 && ox==10'd0) field<=1;
   video_out<=!reset && hactive && rd_on ? (rd_code==2 ? 8'd255 : rd_code==1 ? 8'd136 : 8'd0) : 8'd0;
   if(anchor && !reset) begin
    phase<=0;ox<=0;oy<=0;
    rd<=done_slot;rd_on<=line_on[done_slot];
   end else if(wrap) begin
    phase<=phase_sum-PAIR;
    ox<=0;oy<=oy_next;
    rd<=done_slot;rd_on<=line_on[done_slot];
   end else begin
    phase<=phase_sum[18:0];
    ox<=ox+1'b1;
   end
  end
 end
endmodule
