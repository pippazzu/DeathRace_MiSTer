// Sheets 15-17 sound board. The U5/U7 flip-flops of sheet 15 are traced
// gates in deathrac_netlist.v; this module supplies the analog parts around
// them. Linear networks are state-space models discretized from component
// values by tools/design_audio.py; assumptions are listed in docs/ANALOG.md.
module deathrac_audio #(parameter SYS_HZ=115151515)(
 input wire clk,reset,game,p2,
 input wire [2:0] motor1,motor2,      // GMC2..0 / HMC2..0 (7407, 1 = released)
 input wire crash1,crash2,            // GTHE/HTHE, released = envelope charge
 input wire xc1a,xc1b,xc2a,xc2b,      // U6 7407 outputs, 1 = released
 input wire dis1_n,dis2_n,            // 6XC11/6XC21, low sinks the timing cap
 output wire xcr1,xcr2,               // timing caps as read by the K inputs
 output reg signed [15:0] audio1,audio2,
 input wire [1:0] tone,
 input wire signed [31:0] scream,      // sheet W, Q16.16 volts at the amplifier output
 output wire fs_out,
 input wire game_dr
);
`include "deathrac_audio_coef.vh"
 reg [31:0] tph,fph;
 reg tick,fs;
 assign fs_out=fs;
 always @(posedge clk) begin
  tick<=0;fs<=0;
  if(reset) begin tph<=0;fph<=0; end
  else begin
   if(tph>=SYS_HZ-TICK_HZ) begin tph<=tph-(SYS_HZ-TICK_HZ);tick<=1; end else tph<=tph+TICK_HZ;
   if(fph>=SYS_HZ-48000) begin fph<=fph-(SYS_HZ-48000);fs<=1; end else fph<=fph+48000;
  end
 end
 dd_vco vco1(clk,reset,tick,motor1,dis1_n,xcr1);
 dd_vco vco2(clk,reset,tick,motor2,dis2_n,xcr2);

 // U8 avalanche noise, band-limited by the 748 and clipped by Q12 (shared).
 reg [31:0] lfsr;
 reg signed [31:0] nlp,vn;
 wire signed [31:0] white={{16{lfsr[15]}},lfsr[15:0]};

 // One multiplier serves the state-space MAC and every scalar step. Operands
 // are registered from the issuing state; the product has two register
 // stages and is ready in the state after S_WAIT/S_WAIT2. Scalar steps register
 // their operands once more (ma_r/mb_r) and wait one more state (S_WAIT0): their
 // operand select (state decode, channel select, subtracts) straight into the DSP
 // input register was the slowest path at 115 MHz. The MAC loop keeps its timing.
 localparam S_IDLE=0,S_INIT=1,S_N1=2,S_P0=3,S_P1=4,S_P2=5,S_P3=6,S_P4=7,S_P5=8,
  S_FETCH=9,S_MUL=10,S_ACC=11,S_WB=12,S_NEXT=13,S_X0=14,S_X1=15,S_X2=16,S_X3=17,
  S_A0=18,S_A1=19,S_A2=20,S_A3=21,S_A4=22,S_A5=23,S_WAIT=24,S_N0=25,S_WAIT2=26,S_WB0=27,S_L0=28,S_L1=29,S_L2=30,S_L3=31,S_A1B=32,S_WAIT0=33;
 reg [5:0] st_s,ret;
 reg ch;
 reg [1:0] blk;
 reg [3:0] i,j;
 reg [5:0] widx;
 reg signed [31:0] stm [0:63];
 reg signed [31:0] nx [0:7];
 reg signed [31:0] st_q,coef_q,u0,u1,m1o,m2o,cro,mxo,r_a,r_e,va_r,ma,mb,ma_r,mb_r,ma_q,mb_q,wb_q;
 reg signed [63:0] prod1,prod,acc,amp_r;
 reg signed [31:0] vh [0:1];
 reg signed [31:0] hp [0:1];
 reg signed [31:0] sp1 [0:1];
 reg signed [31:0] sp2 [0:1];
 reg usel,var_sel;
 reg scal,scal_d;               // scalar step issued in the previous state

 reg [3:0] bn,bm;
 reg [4:0] bs,bout,bcl;
 always @* begin
  case(blk)
   0: begin bn=M1_N;bm=M1_M;bs=M1_S;bout=M1_OUT;bcl=M1_CL; end
   1: begin bn=M2_N;bm=M2_M;bs=M2_S;bout=M2_OUT;bcl=M2_CL; end
   2: begin bn=CR_N;bm=CR_M;bs=CR_S;bout=CR_OUT;bcl=CR_CL; end
   default: begin bn=MX_N;bm=MX_M;bs=MX_S;bout=MX_OUT;bcl=MX_CL; end
  endcase
 end
 // Coefficients are read in row-major order, so the ROM address is a counter
 // loaded with the block's base (variant chosen by the open-collector state).
 reg [10:0] caddr;
 // The coefficient table lives in block RAM (same one-clock read as before). As logic
 // it was the slowest path at 115 MHz. Its contents are computed from component values
 // by tools/design_audio.py: filter coefficients, not game data.
 (* romstyle="M10K" *) reg signed [31:0] crom [0:2047];
 integer ck;
 initial for(ck=0;ck<2048;ck=ck+1) crom[ck]=coef(ck[10:0]);
 reg [1:0] q6_on,q7_on;      // per channel, from each stage's base voltage
 reg [1:0] hp_new;           // per channel, no sample taken since reset
 wire [5:0] saddr={ch,bs+{1'b0,j}};
 wire signed [31:0] wb_val=(bs+i==bcl) ? (wb_q<CL_LO ? CL_LO : wb_q>CL_HI ? CL_HI : wb_q) : wb_q;
 // Per-channel scalars.
 wire gthe=ch ? crash2 : crash1;
 wire xa_low=ch ? !xc2a : !xc1a;
 wire xb_low=ch ? !xc2b : !xc1b;
 wire mute=ch ? !p2 : !game;
 // Continuous assignments: an always @* here never runs in simulation when its
 // inputs are constant, which leaves the coefficient address unknown.
 wire [10:0] mixer_b0=mute ? MX_B1 : MX_B0, mixer_b1=mute ? MX_B3 : MX_B2, mixer_b2=mute ? MX_B5 : MX_B4;
 wire [10:0] mixer_base=tone==1 ? mixer_b1 : tone==2 ? mixer_b2 : mixer_b0;
 wire q6c=q6_on[ch], q7c=q7_on[ch];
 wire [10:0] m1_dd=xa_low ? (q6c ? M1_B3 : M1_B2) : (q6c ? M1_B1 : M1_B0);
 wire [10:0] m1_dr=xa_low ? (q6c ? M1_B7 : M1_B6) : (q6c ? M1_B5 : M1_B4);
 wire [10:0] m1_base=game_dr ? m1_dr : m1_dd;
 wire [10:0] m2_base=xb_low ? (q7c ? M2_B3 : M2_B2) : (q7c ? M2_B1 : M2_B0);
 wire signed [31:0] vh_c=vh[ch];
 wire signed [31:0] hp_c=hp[ch];
 wire signed [31:0] sp1_c=sp1[ch];
 wire signed [31:0] sp2_c=sp2[ch];
 wire signed [31:0] p24=prod>>>24;
 wire signed [63:0] amp_in=mute ? prod : prod+scream;
 wire signed [31:0] p32=prod>>>32;
 always @* begin
  ma=0;mb=0;scal=1;
  case(st_s)
   S_N0: begin ma=white-nlp;mb=NOISE_A; end
   S_P0: begin ma=V_144-vh_c;mb=ENV_CH; end              // 1.2k charge
   S_P1: begin ma=vh_c;mb=ENV_DIS; end                   // 270k || 650k
   S_P3: begin ma=vh_c;mb=VA_K; end                      // 100k/550k divider
   S_X1: begin ma=r_a;mb=K_CRASH; end
   S_X2: begin ma=m2o;mb=K_MOTOR; end
   S_A0: begin ma=mxo;mb=AMP_GAIN; end
   S_A2: begin ma=r_a-hp_c;mb=HP_K; end                  // 400uF / 8 ohm
   // Cabinet speaker roll-off (not on the schematic, see docs/ANALOG.md).
   S_L0: begin ma=r_a-hp_c-sp1_c;mb=SPK_K; end
   S_L2: begin ma=sp1_c-sp2_c;mb=SPK_K; end
   S_A4: begin ma=sp2_c;mb=OUT_K; end
   default: scal=0;
  endcase
 end

 always @(posedge clk) begin
  coef_q<=crom[caddr];
  st_q<=stm[saddr];
  ma_r<=ma; mb_r<=mb; scal_d<=scal;
  ma_q<=scal_d ? ma_r : coef_q;                          // MAC: issued in S_MUL
  mb_q<=scal_d ? mb_r : usel ? (j-bn==0 ? u0 : u1) : st_q;
  prod1<=ma_q*mb_q;
  prod<=prod1;
  if(reset) begin
   st_s<=S_INIT;widx<=0;lfsr<=32'h1;nlp<=0;vn<=VN_LO;
   q6_on<=2'b11;q7_on<=2'b11;hp_new<=2'b11;
   vh[0]<=0;vh[1]<=0;hp[0]<=0;hp[1]<=0;audio1<=0;audio2<=0;
   sp1[0]<=0;sp1[1]<=0;sp2[0]<=0;sp2[1]<=0;
  end else case(st_s)
   S_INIT: begin
    stm[widx]<=init_state(widx[4:0]);
    widx<=widx+1'b1;
    if(widx==63) st_s<=S_IDLE;
   end
   S_WAIT0: st_s<=S_WAIT;
   S_WAIT: st_s<=S_WAIT2;
   S_WAIT2: st_s<=ret;
   S_IDLE: if(fs) begin
    lfsr<=(lfsr>>1)^(lfsr[0] ? 32'h80200003 : 32'h0);   // x^32+x^22+x^2+x+1
    st_s<=S_N0;
   end
   S_N0: begin ret<=S_N1;st_s<=S_WAIT0; end
   S_N1: begin
    nlp<=nlp+p24;
    vn<=nlp>0 ? VN_HI : VN_LO;
    ch<=0;st_s<=S_P0;
   end
   // Crash envelope (2.2uF node) and bias node A.
   S_P0: begin ret<=S_P1;st_s<=S_WAIT0; end
   S_P1: begin r_e<=(gthe && vh_c<V_144) ? p24 : 0;ret<=S_P2;st_s<=S_WAIT0; end
   S_P2: begin vh[ch]<=vh_c+r_e-p24;st_s<=S_P3; end
   S_P3: begin ret<=S_P4;st_s<=S_WAIT0; end
   S_P4: begin r_a<=p24+VA_0;st_s<=S_P5; end
   S_P5: begin
    va_r<=r_a<vn+V_06 ? r_a : vn+V_06;                  // diode to the noise node
    blk<=0;i<=0;j<=0;acc<=0;
    var_sel<=xa_low;caddr<=m1_base;u0<=ONE;u1<=vn;
    st_s<=S_FETCH;
   end
   S_FETCH: begin usel<=(j>=bn); st_s<=S_MUL; end   // coef_q/st_q registered this cycle
   S_MUL: begin ret<=S_ACC;st_s<=S_WAIT; end
   S_ACC: begin
    if(j==bn+bm-1) begin
     nx[i]<=(acc+prod)>>>24;acc<=0;j<=0;caddr<=caddr+1'b1;
     if(i==bn-1) begin i<=0;st_s<=S_WB0; end
     else begin i<=i+1'b1;st_s<=S_FETCH; end
    end else begin acc<=acc+prod;j<=j+1'b1;caddr<=caddr+1'b1;st_s<=S_FETCH; end
   end
   S_WB0: begin wb_q<=nx[i];st_s<=S_WB; end   // read, then clamp and write
   S_WB: begin
    stm[{ch,bs+{1'b0,i}}]<=wb_val;
    if(bs+i==M1_BN) q6_on[ch]<=wb_val>V_BE;
    if(bs+i==M2_BN) q7_on[ch]<=wb_val>V_BE;
    if(bs+i==bout) case(blk) 0:m1o<=wb_val; 1:m2o<=wb_val; 2:cro<=wb_val; default:mxo<=wb_val; endcase
    if(i==bn-1) begin i<=0;st_s<=S_NEXT; end else begin i<=i+1'b1;st_s<=S_WB0; end
   end
   S_NEXT: begin
    j<=0;acc<=0;
    case(blk)
     0: begin blk<=1;var_sel<=xb_low;caddr<=m2_base;u0<=ONE;u1<=m1o;st_s<=S_FETCH; end
     1: begin blk<=2;var_sel<=0;caddr<=CR_B0;u0<=ONE;u1<=va_r;st_s<=S_FETCH; end
     2: st_s<=S_X0;
     default: st_s<=S_A0;
    endcase
   end
   // Mixer inputs: 47k/100k crash node held by a diode to Q11, and the pots.
   S_X0: begin r_a<=cro+V_06<V_F ? cro+V_06 : V_F;st_s<=S_X1; end
   S_X1: begin ret<=S_X2;st_s<=S_WAIT0; end
   S_X2: begin u0<=p24;ret<=S_X3;st_s<=S_WAIT0; end
   S_X3: begin u1<=p24;blk<=3;var_sel<=mute;caddr<=mixer_base;j<=0;acc<=0;st_s<=S_FETCH; end
   // Bridged LM380 pair, rail clip, speaker coupling, 16-bit output.
   S_A0: begin ret<=S_A1;st_s<=S_WAIT0; end
   // Sum, then clip, in two clocks: together they were too slow for 115 MHz.
   S_A1: begin amp_r<=amp_in;st_s<=S_A1B; end
   S_A1B: begin r_a<=amp_r>AMP_CLIP ? AMP_CLIP : amp_r< -AMP_CLIP ? -AMP_CLIP : amp_r[31:0];st_s<=S_A2; end
   S_A2: begin ret<=S_A3;st_s<=S_WAIT0; end
   // The first sample after reset charges the 400uF coupling cap to the amplifier's
   // resting voltage at once, otherwise every reset is a loud click through the speaker.
   S_A3: begin hp[ch]<=hp_new[ch] ? r_a : hp_c+p24;hp_new[ch]<=0;st_s<=S_L0; end
   S_L0: begin ret<=S_L1;st_s<=S_WAIT0; end
   S_L1: begin sp1[ch]<=sp1_c+p24;st_s<=S_L2; end
   S_L2: begin ret<=S_L3;st_s<=S_WAIT0; end
   S_L3: begin sp2[ch]<=sp2_c+p24;st_s<=S_A4; end
   S_A4: begin ret<=S_A5;st_s<=S_WAIT0; end
   S_A5: begin
    if(ch) audio2<=p32>32767 ? 16'sh7fff : p32< -32768 ? -16'sh8000 : p32[15:0];
    else   audio1<=p32>32767 ? 16'sh7fff : p32< -32768 ? -16'sh8000 : p32[15:0];
    if(ch) st_s<=S_IDLE; else begin ch<=1;st_s<=S_P0; end
   end
   default: st_s<=S_IDLE;
  endcase
 end
endmodule

// Sheet 15 timing capacitor (33uF, see tools/design_audio.py) for one motor:
// 2N3904/2N3906 current mirror from the GMC DAC node (33uF), 68k to +5 V,
// and the 7407 discharge when 6XC11 is low.
module dd_vco(
 input wire clk,reset,tick,input wire [2:0] m,input wire dis_n,output wire xcr
);
`include "deathrac_audio_coef.vh"
 reg signed [31:0] vb,vc;
 reg [5:0] vbn;
 wire signed [31:0] vt=m[1] ? (m[0] ? VB_T11 : VB_T10) : (m[0] ? VB_T01 : VB_T00);
 wire signed [31:0] va=m[1] ? (m[0] ? VB_A11 : VB_A10) : (m[0] ? VB_A01 : VB_A00);
 // Three stages (difference, product, sum); vb/vc change only on tick, at
 // least 29 clocks apart. Differences drop to Q20 so each product fits one
 // 27x27 DSP; the sum is rescaled by 2^32.
 reg signed [26:0] d_b,d_src,d_68,d_dis;
 reg signed [63:0] vbs,i_src,i_68,i_dis,isum;
 wire signed [31:0] db_w=(vt-vb)>>>4, ds_w=(vb-V_065)>>>4, d6_w=(V_5-vc)>>>4,
  dd_w=(vc-V_01)>>>4;
 always @(posedge clk) begin
  d_b<=db_w[26:0];
  d_src<=vb>V_065 ? ds_w[26:0] : 27'sd0;
  d_68<=d6_w[26:0];
  d_dis<=(!dis_n && vc>V_01) ? dd_w[26:0] : 27'sd0;
  vbs<=d_b*va;
  i_src<=d_src*K_SRC; i_68<=d_68*K_68K; i_dis<=d_dis*K_DIS;
  isum<=i_src+i_68-i_dis;
 end
 wire signed [31:0] vc_n=vc+(isum>>>32);
 always @(posedge clk) begin
  if(reset) begin vb<=V_IDLE;vc<=0;vbn<=0; end
  else if(tick) begin
   vc<=vc_n>V_MAX ? V_MAX : vc_n<0 ? 0 : vc_n;
   vbn<=vbn+1'b1;
   if(!m[2]) vb<=V_IDLE;                      // GMC2 low clamps the DAC node
   else if(vbn==0) vb<=vb+(vbs>>>20);
  end
 end
 assign xcr=vc>V_TH;
endmodule
