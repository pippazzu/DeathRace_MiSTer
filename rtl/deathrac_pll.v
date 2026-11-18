// 50 MHz board reference -> 115.2 MHz (exact 288/125 ratio).
// An NCO in deathrac_fpga produces the schematic's nominal 14.391 MHz.
module deathrac_pll(input wire refclk,output wire clk_sys,locked);
 altera_pll #(.fractional_vco_multiplier("false"),
 .reference_clock_frequency("50.0 MHz"),.operation_mode("direct"),
 .number_of_clocks(1),.output_clock_frequency0("115.200000 MHz"),
 .phase_shift0("0 ps"),.duty_cycle0(50),.pll_type("General"),.pll_subtype("General")) pll_i
 (.refclk(refclk),.rst(1'b0),.outclk(clk_sys),.locked(locked),.fbclk(1'b0),.fboutclk());
endmodule
