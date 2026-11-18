// Scream envelope and pitch: silent when idle or disabled, then a fast attack, a held
// top pitch and a falling sweep after one LADO pulse. Runs fs fast because all state is per sample.
`timescale 1ns/1ps
module tb_scream;
 reg clk=0,reset=1,fs=0,lado=0,enable=1;
 wire signed [31:0] out;
 always #5 clk=~clk;
 deathrac_scream dut(clk,reset,fs,enable,lado,out);
 integer n=0,crossings=0,f,window=0,lastpeak=0;
 real t;
 reg last_sign=0;
 integer peak=0;
 integer audible_first=-1,audible_last=-1;
 integer best=0;
 initial begin
  if($test$plusargs("dump")) f=$fopen("build/scream.raw","wb");
  repeat(4) @(posedge clk);reset=0;
  repeat(4800) sample();           // 0.1 s idle
  if(peak!=0) begin $display("FAIL idle not silent peak=%0d",peak);$fatal(1); end
  lado=1;repeat(48) sample();lado=0; // one 1 ms pulse
  repeat(4800*30) sample();        // 3 s
  $display("audible from %0.3f s to %0.3f s after the pulse, peak %0.2f V",
   (audible_first-4800)/48000.0,(audible_last-4800)/48000.0,peak/65536.0);
  $display("loudest-window pitch %0d Hz",best);
  if(audible_first<0) begin $display("FAIL never audible");$fatal(1); end
  // The 100k charges the 2uF node at about 57 V/s, so the sound opens within tens of ms.
  if(audible_first-4800>48*40) begin $display("FAIL slow attack");$fatal(1); end
  if(audible_last-audible_first<9600 || audible_last-audible_first>144000) begin $display("FAIL duration");$fatal(1); end
  if(peak/65536.0<2.0 || peak/65536.0>4.5) begin $display("FAIL level %0d",peak);$fatal(1); end
  if(best<500 || best>3500) begin $display("FAIL pitch %0d",best);$fatal(1); end
  // Disabled: Derby stays silent whatever LADO does.
  enable=0;repeat(20) @(posedge clk);peak=0;
  lado=1;repeat(48) sample();lado=0;repeat(48000) sample();
  if(peak!=0) begin $display("FAIL disabled peak=%0d",peak);$fatal(1); end
  $display("PASS scream: silent idle, one pulse, level, pitch, disable");
  $finish;
 end
 task sample;
  integer a;
  begin
   repeat(10) @(posedge clk);
   fs<=1;@(posedge clk);fs<=0;
   repeat(10) @(posedge clk);
   n=n+1;
   a=out<0 ? -out : out;
   if(a>peak) peak=a;
   if(a>65536/4) begin if(audible_first<0) audible_first=n; audible_last=n; end
   if((out<0)!=last_sign) crossings=crossings+1;
   last_sign=out<0;
   if($test$plusargs("dump")) $fwrite(f,"%c%c",out[15:8],out[23:16]);
   window=window+1;
   if(window==4800) begin
    if(n<48000 && crossings/2*10>best) best=crossings/2*10;
    crossings=0;window=0;
   end
  end
 endtask
endmodule
