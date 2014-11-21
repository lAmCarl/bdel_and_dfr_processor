// A simulation testbench for the accserial design by Prof. Chow
//
// Version 1.0	November 7 2013
//
// Stuart Byma
//

`timescale 1 ns / 10 ps	// this maps dimensionless Verilog time units into real time units
						// 1ns is the min time delay (#) and 10ps is the
						// minimum time unit that Modelsim will display


module project_tb(PS2_CLK, PS2_DAT); // no I/O ports, this is a testbench file

	// signals 
		reg 	CLOCK_50; 
		reg 	[2:0] KEY; 
		reg 	[15:0] SW;
		wire 	[7:0] LEDG; 
		wire 	[17:0] LEDR;
		wire VGA_CLK, VGA_BLANK, VGA_HS, VGA_VS, VGA_SYNC;
		wire	[9:0] VGA_R, VGA_G, VGA_B;
		inout 	PS2_CLK, PS2_DAT;
	wire 	oSO;

	wire [7:0] 	AdderSum;
	wire 	DoneShift, DoneAdd;
	
	// instantiate the DUT - Design Under Test
	playground dut(CLOCK_50, KEY, SW, LEDG, LEDR, VGA_CLK, VGA_BLANK, VGA_HS, VGA_VS, VGA_SYNC, VGA_R, VGA_G, VGA_B, PS2_CLK, PS2_DAT); 

	initial begin
		CLOCK_50 = 0;
		KEY = 3'b110; // start clk and resetn at 0
		SW = 16'd2; // set the start control signal to 0
	end

	always #10 CLOCK_50 = ~CLOCK_50; // generate a clock - every 10ns, toggle clock - what's the period and frequency?


	initial begin
		#20 // advance one clock cycle so reset takes effect

		KEY = 3'b111;
		#40
		KEY = 3'b101;
		
		#20
		KEY = 3'b111;
		 
		#80
		KEY = 3'b011;
		
		#20
		KEY = 3'b111;

		
		
		#10000 // advance 25 cycles

		$stop;  // suspend the simulation, but do not $finish
			    // $finish will try to close Modelsim, and that's annoying
	end
endmodule

	
