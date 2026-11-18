`timescale 1ns/1ps
module tb_cells;
 parameter FPGA=1;
 reg clk=0,reset=0;
 always #5 clk=~clk;
 reg up=1,down=1,load_n=1,clear=0;
 reg [3:0] d=0;
 wire [3:0] q;
 wire co,bo;
 dd_updown #(.FPGA(FPGA),.BCD(1)) c(clk,reset,down,up,load_n,clear,d,q,co,bo,4'd0);
 reg jkclock=1,j=0,k=0,pre_n=1,clr_n=1;
 wire jq,jn;
 dd_jk112 #(.FPGA(FPGA)) ff(clk,reset,jkclock,j,k,pre_n,clr_n,jq,jn,1'b0);
 reg [7:0] address=0;
 reg ce=0,we=1,di=0;
 wire ro;
 dd_74s200 #(.FPGA(FPGA)) ram(clk,reset,address,ce,we,di,ro);
 reg [3:0] expected_up[0:15],expected_down[0:15];
 integer i;
 task preset(input [3:0] val);
 begin d=val;load_n=0;#30;load_n=1;#30;end
 endtask
 task assert_count(input [3:0] value);
 begin if(q!==value) $fatal(1,"counter state %h expected %h",q,value);end
 endtask
 initial begin
  for(i=0;i<10;i=i+1) begin expected_up[i]=(i+1)%10;expected_down[i]=(i+9)%10;end
  expected_up[10]=11;expected_up[11]=6;expected_up[12]=13;
  expected_up[13]=4;expected_up[14]=15;expected_up[15]=2;
  for(i=10;i<16;i=i+1) expected_down[i]=i-1;
  #1;reset=1;#30;reset=0;#30;
  for(i=0;i<16;i=i+1) begin
   preset(i);assert_count(i);up=0;#30;up=1;#30;assert_count(expected_up[i]);
   preset(i);down=0;#30;down=1;#30;assert_count(expected_down[i]);
  end
  // Load follows changing data even without clock edges; clear has priority.
  load_n=0;d=7;#30;assert_count(7);d=4;#30;assert_count(4);
  clear=1;#30;assert_count(0);clear=0;#30;assert_count(4);load_n=1;
  preset(9);up=0;#30;if(co!==0)$fatal(1,"missing carry");up=1;#30;assert_count(0);
  down=0;#30;if(bo!==0)$fatal(1,"missing borrow");down=1;#30;assert_count(9);
  j=1;k=0;jkclock=0;#30;if(jq!==1 || jn!==0)$fatal(1,"JK set");
  jkclock=1;k=1;#30;jkclock=0;#30;if(jq!==0)$fatal(1,"JK toggle");
  pre_n=0;#30;if(jq!==1)$fatal(1,"JK async preset");
  clr_n=0;#30;if(jq!==1 || jn!==1)$fatal(1,"JK illegal controls");
  pre_n=1;#30;if(jq!==0)$fatal(1,"JK async clear");clr_n=1;
  // SRAM complement, disabled write protection and write-time output release.
  address=8'ha5;di=1;we=0;#30;if(ro!==1)$fatal(1,"RAM write release");
  we=1;#30;if(ro!==0)$fatal(1,"RAM complement read");
  ce=1;di=0;we=0;#30;we=1;ce=0;#30;if(ro!==0)$fatal(1,"RAM chip enable");
  address=8'h5a;di=0;we=0;#30;we=1;#30;if(ro!==1)$fatal(1,"RAM address/write");
  address=8'ha5;#30;if(ro!==0)$fatal(1,"RAM address isolation");
  $display("PASS: FPGA=%0d BCD all presets, async control, carry/borrow, JK, SRAM",FPGA);$finish;
 end
endmodule
