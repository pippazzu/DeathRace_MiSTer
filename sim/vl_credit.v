// Top for a fast C++ sweep of the sheet 2 credit logic: the whole traced board (FPGA model)
// with the crystal at clk/8, as in deathrac_fpga. Exposes the credit flip-flops.
module vl_credit(
 // cond=1 puts deathrac_credit between the buttons and the board, as deathrac_game does.
 input wire clk,reset,coin,start,cond,game_dr,prom_wr,
 input wire [11:0] prom_addr, input wire [7:0] prom_din,
 output wire vs,egme,e2pl,esgc,ecdg,stgo,epor,ecdb,eck0,esgb,staa,
 output wire [7:0] timer
);
 reg [2:0] div=0; reg xtal=0;
 always @(posedge clk) begin div<=div+1'b1; xtal<=div[2]; end
 wire hs,hb,vb,pc,white,grey,p2,cr1,cr2,lado;
 wire [2:0] m1,m2; wire [8:0] hc,vc;
 wire xc1a,xc1b,xc2a,xc2b,dis1_n,dis2_n;
 wire coin_c,start_c,started;
 deathrac_credit credit(clk,reset,coin,start,egme,started,coin_c,start_c);
 deathrac_board #(.FPGA(1)) board(clk,reset,xtal,cond ? coin_c : coin,cond ? start_c : start,2'b10,
  2'b00,2'b00,2'b00,2'b00,1'b0,1'b0,
  hs,vs,hb,vb,pc,white,grey,egme,e2pl,m1,m2,cr1,cr2,hc,vc,timer,1'b0,1'b0,
  xc1a,xc1b,xc2a,xc2b,dis1_n,dis2_n,game_dr,prom_wr,prom_addr,prom_din,lado,started);
 assign esgc=board.circuit.n_J15_pin9_ESGC;
 assign ecdg=board.circuit.n_L16_pin11_ECDG;
 assign stgo=board.circuit.n_G13_pin4_K15_pin12;
 assign epor=board.circuit.n_L14_pin9_EPOR;
 assign ecdb=board.circuit.n_K16_pin5_K16_pin11;
 assign eck0=board.circuit.n_H15_pin8_1ECK0;
 assign esgb=board.circuit.n_J15_pin5_J15_pin11;
 assign staa=board.circuit.n_N16_pin15_STAA;
endmodule
