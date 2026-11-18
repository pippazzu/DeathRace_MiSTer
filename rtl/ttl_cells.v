// Schematic functional models. No propagation delay claims are made.
// FPGA=1 samples each chip's clock and asynchronous controls on clk_sys.
// FPGA=0 retains event-driven derived clocks for simulation only.
`timescale 1ns/1ps
`default_nettype none

module dd_jk112 #(parameter FPGA=1)(
 input wire clk_sys, reset, ck, j, k, pre_n, clr_n,
 output wire q, qn,
 input wire init   // state while reset is held: the chip's power-on state
);
 reg state, old_ck;
 // Illegal simultaneous preset/clear drives BOTH outputs high (TI SDLS011).
 assign q = !pre_n ? 1'b1 : (!clr_n ? 1'b0 : state);
 assign qn = !clr_n ? 1'b1 : (!pre_n ? 1'b0 : ~state);
 function next_jk;
 input s,jv,kv;
 begin next_jk=(jv & ~s) | (~kv & s); end
 endfunction
 generate if(FPGA) begin : sampled
   always @(posedge clk_sys) begin
     old_ck <= ck;
     if(reset) begin state<=init; old_ck<=ck; end
     else if(!clr_n) state<=0;
     else if(!pre_n) state<=1;
     else if(old_ck && !ck) state<=next_jk(state,j,k);
   end
 end else begin : reference
   always @(negedge ck or negedge pre_n or negedge clr_n or posedge reset)
     if(reset) state<=init;
     else if(!clr_n && !pre_n) state<=1'bx;
     else if(!clr_n) state<=0;
     else if(!pre_n) state<=1;
     else state<=next_jk(state,j,k);
 end endgenerate
endmodule

module dd_74161 #(parameter FPGA=1)(
 input wire clk_sys,reset,ck,clr_n,load_n,enp,ent,
 input wire [3:0] d, output reg [3:0] q, output wire carry,
 input wire [3:0] init   // value while reset is held: the chip's power-on state
);
 reg old_ck;
 assign carry=ent & (&q);
 generate if(FPGA) begin : sampled
   always @(posedge clk_sys) begin
     old_ck<=ck;
     if(reset) q<=init;
     else if(!clr_n) q<=0;
     else if(ck && !old_ck) begin
       if(!load_n) q<=d;
       else if(enp && ent) q<=q+4'd1;
     end
   end
 end else begin : reference
   always @(posedge ck or negedge clr_n or posedge reset)
     if(reset) q<=init;
     else if(!clr_n) q<=0;
     else if(!load_n) q<=d;
     else if(enp && ent) q<=q+4'd1;
 end endgenerate
endmodule

module dd_updown #(parameter FPGA=1, parameter BCD=0)(
 input wire clk_sys,reset,down,up,load_n,clear,
 input wire [3:0] d, output reg [3:0] q, output wire co_n,bo_n,
 input wire [3:0] init   // value while reset is held: the chip's power-on state
);
 reg old_up,old_down;
 // BCD carry decode uses QA and QD, including non-BCD preset states.
 assign co_n=~((BCD ? (q[3]&q[0]) : (&q)) & ~up);
 assign bo_n=~((~|q) & ~down);
 function [3:0] count_up;
 input [3:0] s;
 begin
   // Toggle equations from TI SDLS074 p2, including presets 10..15.
   if(BCD) count_up=s ^ {s[0]&(s[3]|(s[1]&s[2])), s[0]&s[1], s[0]&~s[3], 1'b1};
   else count_up=s+4'd1;
 end
 endfunction
 function [3:0] count_down;
 input [3:0] s;
 begin
   if(BCD) count_down=s ^ {~s[0]&~s[1]&~s[2], ~s[0]&~s[1]&(s[2]|s[3]), ~s[0]&(s[1]|s[2]|s[3]), 1'b1};
   else count_down=s-4'd1;
 end
 endfunction
 generate if(FPGA) begin : sampled
   always @(posedge clk_sys) begin
     old_up<=up; old_down<=down;
     if(reset) q<=init;
     else if(clear) q<=0;
     else if(!load_n) q<=d;
     else if(up && !old_up && down) q<=count_up(q);
     else if(down && !old_down && up) q<=count_down(q);
   end
 end else begin : reference
   // Explicit edge history also permits transparent asynchronous data loading.
   always @(up or down or load_n or clear or d or reset or init) begin
     if(reset) q<=init;
     else if(clear) q<=0;
     else if(!load_n) q<=d;
     else if(up && !old_up && down) q<=count_up(q);
     else if(down && !old_down && up) q<=count_down(q);
     old_up=up; old_down=down;
   end
 end endgenerate
endmodule

module dd_74174 #(parameter FPGA=1)(
 input wire clk_sys,reset,ck,clr_n,input wire [5:0] d,output reg [5:0] q,
 input wire [5:0] init   // value while reset is held: the chip's power-on state
);
 reg old_ck;
 generate if(FPGA) begin : sampled
   always @(posedge clk_sys) begin
     old_ck<=ck;
     if(reset) q<=init;
     else if(!clr_n) q<=0;
     else if(ck && !old_ck) q<=d;
   end
 end else begin : reference
   always @(posedge ck or negedge clr_n or posedge reset)
     if(reset) q<=init; else if(!clr_n) q<=0; else q<=d;
 end endgenerate
endmodule

module dd_74166 #(parameter FPGA=1)(
 input wire clk_sys,reset,ck,inhibit,clr_n,load_n,serial,
 input wire [7:0] d,output wire q
);
 reg [7:0] state;
 wire gated_ck=ck | inhibit;
 reg old_ck;
 assign q=state[7];
 generate if(FPGA) begin : sampled
   always @(posedge clk_sys) begin
     old_ck<=gated_ck;
     if(reset || !clr_n) state<=0;
     else if(gated_ck && !old_ck) state<=!load_n ? d : {state[6:0],serial};
   end
 end else begin : reference
   always @(posedge gated_ck or negedge clr_n or posedge reset)
     if(reset || !clr_n) state<=0;
     else state<=!load_n ? d : {state[6:0],serial};
 end endgenerate
endmodule

module dd_feedback #(parameter FPGA=1)(input wire clk_sys,reset,a,b,output reg q);
 // Exact stable-state equation q=a & (~b | q), sheets 12 and 14.
 generate if(FPGA) begin : sampled
   always @(posedge clk_sys)
     if(reset || !a) q<=0; else if(!b) q<=1;
 end else begin : reference
   always @* if(reset || !a) q=0; else if(!b) q=1;
 end endgenerate
endmodule

module dd_prom #(parameter AW=5, DW=8, BASE=0, ROM_FILE="", REG=0, FPGA=1)(
 input wire clk_sys,prom_wr,input wire [11:0] prom_addr,input wire [7:0] prom_din,
 input wire [AW-1:0] a,input wire enable_n,output wire [DW-1:0] q
);
 // Loaded from the MRA byte stream. Asynchronous read, as the bipolar PROM.
 (* ramstyle="MLAB, no_rw_check" *) reg [DW-1:0] mem[0:(1<<AW)-1];
 always @(posedge clk_sys)
  if(prom_wr && prom_addr[11:AW]==BASE[11:AW]) mem[prom_addr[AW-1:0]]<=prom_din[DW-1:0];
 // synthesis translate_off
 initial $readmemh(ROM_FILE,mem);   // Demolition Derby default for the older benches
 // synthesis translate_on
 // Disabled tri-state outputs resolve high at receiving TTL inputs.
 // 82S123 enables in this board are all grounded.
 // REG=1: data one system clock (8.7 ns) after the address, where the real 82S129 takes
 // about 50 ns. Used for the image PROMs B8-E8, whose zero-delay read through C15 was the
 // slowest path at 115 MHz. tb_game checks the address is steady a clock before each load.
 reg [DW-1:0] q_r;
 always @(posedge clk_sys) q_r<=mem[a];
`ifdef DD_PROM_COMB
 wire [DW-1:0] q_mem=mem[a];   // bench only: the old zero-delay read, for comparison runs
`else
 wire [DW-1:0] q_mem=(REG && FPGA) ? q_r : mem[a];   // the event-driven reference keeps zero delay
`endif
 assign q=enable_n ? {DW{1'b1}} : q_mem;
endmodule

module dd_74s200 #(parameter FPGA=1)(
 input wire clk_sys,reset,input wire [7:0] a,
 input wire ce_n,we_n,d,output wire q_n
);
 reg mem[0:255];
 // National 1977 memory databook p2-11: stores complement of input;
 // output is high impedance while disabled OR writing. TTL receiver is high.
 // FPGA model: data appears one system clock (8.7 ns) after the address, where the
 // real part takes about 40 ns. A zero-delay read was the slowest path at 115 MHz.
 // tb_game checks that the address is always steady a clock before A10/A11 load.
 reg q_r;
`ifdef DD_A12_COMB
 wire q_mem=mem[a];   // bench only: the old zero-delay read, for comparison runs
`else
 wire q_mem=FPGA ? q_r : mem[a];
`endif
 assign q_n=(ce_n || !we_n) ? 1'b1 : q_mem;
 generate if(FPGA) begin : sampled
   always @(posedge clk_sys) q_r<=mem[a];
   always @(posedge clk_sys) if(!reset && !ce_n && !we_n) mem[a]<=~d;
 end else begin : reference
   always @* if(!reset && !ce_n && !we_n) mem[a]=~d;
 end endgenerate
endmodule
`default_nettype wire
