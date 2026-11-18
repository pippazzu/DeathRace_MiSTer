// Top for the start-position check: the whole traced board (FPGA cell models) with the
// crystal at clk/8, as in deathrac_fpga. Exposes the picture and the four position counters.
// X is {74192 tens digit, 74193}, Y is {74193, 74193}; the preset pins are on sheets
// 8, 10, 12 and 14 (DR-1A sheets B, D, M, N). Driven by sim/vl_spawn.cpp.
module vl_spawn(
 input wire clk,reset,coin,start,game_dr,prom_wr,
 input wire [11:0] prom_addr, input wire [7:0] prom_din,
 input wire [1:0] gas1,gas2,
 output wire xtal_o,hs,vs,hb,vb,white,grey,egme,e2pl,
 output wire [7:0] ax,ay,cx,cy,mx,my,nx,ny,   // enemy A (sheet 8), enemy C (10), player 1 (12), player 2 (14)
 output wire [3:0] ah,ch,                     // enemy headings
 output wire aprs_n,cprs_n
);
 reg [2:0] div=0; reg xtal=0;
 always @(posedge clk) begin div<=div+1'b1; xtal<=div[2]; end
 assign xtal_o=xtal;
 wire pc,cr1,cr2,lado,started;
 wire [2:0] m1,m2; wire [8:0] hc,vc; wire [7:0] timer;
 wire xc1a,xc1b,xc2a,xc2b,dis1_n,dis2_n;
 deathrac_board #(.FPGA(1)) board(clk,reset,xtal,coin,start,2'b10,
  2'b00,2'b00,gas1,gas2,1'b1,1'b1,
  hs,vs,hb,vb,pc,white,grey,egme,e2pl,m1,m2,cr1,cr2,hc,vc,timer,1'b0,1'b0,
  xc1a,xc1b,xc2a,xc2b,dis1_n,dis2_n,game_dr,prom_wr,prom_addr,prom_din,lado,started);
 assign ax={board.circuit.s08_H5.q,board.circuit.s08_J5.q};
 assign ay={board.circuit.s08_J6.q,board.circuit.s08_K6.q};
 assign cx={board.circuit.s10_B1.q,board.circuit.s10_C1.q};
 assign cy={board.circuit.s10_C2.q,board.circuit.s10_D2.q};
 assign mx={board.circuit.s12_N4.q,board.circuit.s12_N5.q};
 assign my={board.circuit.s12_L5.q,board.circuit.s12_K4.q};
 assign nx={board.circuit.s14_P3.q,board.circuit.s14_P4.q};
 assign ny={board.circuit.s14_K3.q,board.circuit.s14_L3.q};
 assign ah=board.circuit.s07_J9.q;
 assign ch=board.circuit.s09_E5.q;
 assign aprs_n=board.circuit.n_L10_pin8_5APRS;
 assign cprs_n=board.circuit.n_F4_pin8_5CPRS;
endmodule
