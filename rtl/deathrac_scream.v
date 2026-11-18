// Death Race sheet W, scream audio. A behavioural model of the transistor delay
// chain and two 566 oscillators from their component values. See docs/ANALOG.md.
//
// LADO high discharges the 6.8uF node through the first 2N3904. While that node
// is below about 1.3 V the second transistor stays off and its 100k collector
// resistor charges the .2uF node through the diode. That is a current source of
// about (15-0.6-V)/100k = 0.12 mA, so the third transistor saturates within a few ms
// (attack) and the pitch jumps to the top, where it holds. When the 6.8uF node
// passes 1.3 V, about 0.6 s later through 1M, the .2uF node decays through the
// third transistor's base in about 0.1 s (decay) and the attenuator closes.
// The drawing labels this capacitor .2UF (read at full resolution 2026-11-09); an
// earlier reading of 2uF made the attack and the fall ten times too slow.
// That transistor pulls the 566 control pin down through 22k, so pitch follows
// the .2uF node. Its emitter also enables the MFC6040 attenuator.
//
// Voltages are Q16.16 volts. All inputs to the pipeline change only on fs.
module deathrac_scream(
 input wire clk,reset,fs,enable,lado,
 output reg signed [31:0] out
);
 localparam signed [31:0] V15=983040, V065=42598, V13=85197, V02=13107,
  VB_MAX=170394,      // 2.6 V: base of the third transistor when saturated
  V144=943718,        // 14.4 V: 15 V less the diode, where the 100k charge aims
  V_OFF=29491,        // 0.45 V: attenuator fully closed
  FM=78643;           // 1.2 V: LFO swing through .2uF
 // One-pole steps per 48 kHz sample, Q0.24.
 localparam signed [31:0] K_CAP=51,   // 6.8uF through 1M: dt/6.8 s
  K_CH=17476,                         // .2uF through 100k: dt/0.02 s, toward 14.4 V
  K_DIS=3495;                         // .2uF through the base, beta*3.3k: dt/0.1 s
 reg signed [31:0] vb,vb_n;
 // 6.8uF node with 24 fraction bits below Q16.16: its step is about 3 LSB of Q16.16 per
 // sample, and dropping the fraction made the hold 0.87 s instead of 0.62 s.
 reg signed [55:0] vcap_f;
 wire signed [31:0] vcap=vcap_f[55:24];
 reg [23:0] pha,phl;
 // Settled pipeline, recomputed every clock.
 reg signed [31:0] ve,vcr,vc,fm_v,x;
 reg sat;
 reg [23:0] inca,incl;
 reg signed [47:0] cap_d,vb_d;
 // Two stages before each multiply (choose the operand, then multiply) so the path fits
 // one 115 MHz clock. The inputs change only on fs, thousands of clocks apart.
 reg signed [31:0] cap_x,vb_x;
 reg signed [15:0] vb_k;
 wire signed [31:0] tri_l={{8{1'b0}},phl[23] ? ~phl : phl}; // 0..2^23
 wire q2_on=vcap>V13;
 always @(posedge clk) begin
  cap_x<=V15-vcap;
  cap_d<=cap_x*K_CAP;
  vb_x<=q2_on ? (vb>V065 ? vb-V065 : 32'sd0) : V144-vb;
  vb_k<=q2_on ? -K_DIS[15:0] : K_CH[15:0];
  vb_d<=vb_x*vb_k;
  // Next .2uF voltage, clamped at saturation while charging; registered here to keep the
  // add and compare off the fs path.
  vb_n<=(!q2_on && vb+(vb_d>>>24)>VB_MAX) ? VB_MAX : vb+(vb_d>>>24);
  ve<=vb>V065 ? vb-V065 : 32'sd0;
  // 15 - ve*22k/3.3k, the 6.67 ratio by shifts (6.656).
  vcr<=V15-((ve<<2)+(ve<<1)+(ve>>>1)+(ve>>>3)+(ve>>>5));
  sat<=vcr<ve+V02;
  // Triangle 0..2^23 maps to -FM..+FM (the 2^23 span scales to 2.37 V).
  fm_v<=(tri_l>>>6)+(tri_l>>>9)+(tri_l>>>10)-FM;
  // Saturated, the collector still follows the LFO: the .2uF base capacitor is 4k at
  // 200 Hz, not an AC ground. The full swing fits a cabinet recording
  // (sidebands 197 Hz either side of the carrier at -6 and -10 dB; this gives -8).
  vc<=(sat ? ve+V02 : vcr)+fm_v;
  x<=vc>=V15 ? 32'sd0 : V15-vc;
  // 566: f=2(15-Vc)/(R C 15). Both rates are fitted to a cabinet recording
  // (2026-11-09): 2042 Hz held, LFO 197.5 Hz.
  // Audio, C=.1uF: 158.9 Hz per volt (R=8.4k of the 1k + 10k pot).
  // inc=x*158.9/48000*2^24/2^16 = x*0.847.
  inca<=(x>>>1)+(x>>>2)+(x>>>4)+(x>>>5)+(x>>>8);
  // LFO, C=.5uF: 15.4 Hz per volt, inc=x*0.082. By the formula that is 17k, more than
  // the pot allows: the 566s run with pin 5 far below their rated range, where the
  // formula no longer holds, so the measured rate is used.
  incl<=(x>>>4)+(x>>>6)+(x>>>8);
 end
 // Triangle of the audio 566, -2^23..2^23-1 -> signed 16 bit.
 wire [23:0] tf=pha[23] ? ~pha : pha;
 wire signed [15:0] tri16={tf[22:8],1'b0}-16'sd32768;
 // MC3340/MFC6040 gain: closed at 0.45 V on the emitter, open at 0.65 V.
 reg [7:0] gain;
 reg signed [31:0] gd;
 reg signed [24:0] pm;
 always @(posedge clk) begin
  gd<=ve<V_OFF ? 32'sd0 : ve>=V065 ? 32'sd13107 : ve-V_OFF;
  gain<=gd[13:6];     // 0..204
  pm<=tri16*$signed({1'b0,gain});
  // WSCM pot setting (assumption): full triangle at full gain is about +/-3.2 V
  // at the amplifier output.
  out<=enable ? pm>>>5 : 32'sd0;
 end
 always @(posedge clk) begin
  if(reset) begin vcap_f<={V15,24'd0};vb<=0;pha<=0;phl<=0; end
  else begin
   if(lado) vcap_f<=0;
   else if(fs) vcap_f<=vcap_f+cap_d;
   if(fs) begin
    // Above 2.6 V the saturated base takes the excess charge current: vb_n holds there.
    vb<=vb_n;
    pha<=pha+inca;
    phl<=phl+incl;
   end
  end
 end
endmodule
