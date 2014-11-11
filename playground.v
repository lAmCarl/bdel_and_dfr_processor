module playground(input CLOCK_50, input [2:0] KEY, input [15:0] SW, output [7:0] LEDG, output [17:0] LEDR);
	// TODO: consecutive inputs
	assign LEDG[7:3] = { 5{ 1'd0 } };
	assign LEDR[16] = 0;

	reg [15:0] pc = 0, sp = 0;
	reg read_instruction_start = 0;
	wire read_instruction_done;
	reg idle = 1;
	
	wire clock, reset_n;
	wire nike;
	
	assign nike = ~KEY[1];
	assign clock = CLOCK_50;
	assign reset_n = KEY[0];
	
	wire [63:0] instruction;
	wire [15:0] opcode, instr_a, instr_b, instr_c;
	assign { opcode, instr_a, instr_b, instr_c } = instruction;

	reg program_running, program_done, program_error;
	assign LEDG[0] = program_running;
	assign LEDG[1] = program_done;
	assign LEDR[17] = program_error;

	parameter
		  OP_EOF = 16'd0
		, OP_LOAD = 16'd1
		, OP_STORE = 16'd2
		, OP_LITERAL = 16'd3
		, OP_INPUT = 16'd4
		, OP_OUTPUT = 16'd5
		, OP_ADD = 16'd6
		, OP_SUB = 16'd7
		, OP_MUL = 16'd8
		, OP_DIV = 16'd9
		, OP_CMP = 16'd10
		, OP_BRANCH = 16'd11
		, OP_JUMP = 16'd12
		, OP_STACK = 16'd13
		, OP_SUPERMANDIVE = 16'd14
		, OP_GETUP = 16'd15
		, OP_PRINT = 16'd16 // opcodes including and after 16 should later be system functions
		, OP_DRAW = 16'd17
		, OP_KEYBOARD = 16'd18;

	// Output LED
	// Use: led_output_in, led_output_write_enable
	reg [15:0] led_output_in = 0;
	reg led_output_write_enable = 0;
	led_output_dffr u0(clock, led_output_write_enable, reset_n, led_output_in, LEDR[15:0]);

	// Input fpga
	wire [15:0] input_fpga_out;
	wire input_fpga_returned;
	reg input_fpga_waiting;
	assign input_fpga_out = SW[15:0];
	assign input_fpga_returned = ~KEY[2];
	assign LEDG[2] = input_fpga_waiting;

	// CPU registers
	// Use: cpu_registers_<read>_<a|b|c>, cpu_registers_write, cpu_registers_write_enable, cpu_registers_write_index
	wire [255:0] cpu_registers;
	reg cpu_registers_write_enable;
	reg [15:0] cpu_registers_write_index;

	wire [15:0] cpu_registers_read_a, cpu_registers_read_b;
	cpu_registers_read_mux u2(instr_a, cpu_registers, cpu_registers_read_a);
	cpu_registers_read_mux u3(instr_b, cpu_registers, cpu_registers_read_b);
	
	reg [255:0] cpu_registers_write;
	cpu_registers_write_mux u5(clock, cpu_registers_write_enable, cpu_registers_write_index, cpu_registers_write, cpu_registers);
	
	// Stack
	// Use: stack_address, stack_words, stack_read, stack_write
	wire [255:0] stack_read;
	reg [255:0] stack_write = 0;
	reg [15:0] stack_address = 0, stack_words = 0;
	reg stack_read_start = 0, stack_write_start = 0;
	wire [15:0] stack_write_values, stack_read_values, read_address, write_address, stack_address_real;
	wire stack_read_done, stack_write_done;
	stack_ram_read u8(clock, stack_read_start, stack_read_values, stack_address, stack_words, stack_read, write_address, stack_read_done);
	stack_ram_write u9(clock, stack_write_start, stack_address, stack_words, stack_write, stack_write_values, read_address, stack_write_done);
	assign stack_address_real = (stack_read_start == 0) ? write_address : read_address;
	
	stack_ram u11(
			.address(stack_address_real),
			.clock(clock),
			.data(stack_write_values),
			.wren((stack_write_start && !stack_write_done)),
			.q(stack_read_values));

	// Read instruction
	wire [63:0] instr_read_values;
	instruction_ram_read u10(clock, read_instruction_start, instr_read_values, instruction, read_instruction_done);

	instruction_ram u12(
			.address(pc),
			.clock(clock),
			.data(16'bx),
			.wren(1'b0),
			.q(instr_read_values));
	
	wire [15:0] do_math_add, do_math_sub, do_math_mul, do_math_div;
	assign do_math_add = cpu_registers_read_a + cpu_registers_read_b;
	assign do_math_sub = cpu_registers_read_a - cpu_registers_read_b;
	assign do_math_mul = cpu_registers_read_a * cpu_registers_read_b;
	assign do_math_div = cpu_registers_read_a / cpu_registers_read_b;
	always@(posedge clock) begin
		cpu_registers_write_enable = 0;
		led_output_write_enable = 0;
		program_running = 1;
		program_done = 0;
		program_error = 0;
		input_fpga_waiting = 0;
		cpu_registers_write = 0;
		cpu_registers_write_index = 0;
		if (!reset_n) begin
			program_running = 0;
			idle <= 1;
			pc <= 0;
			sp <= 0;
			led_output_in <= 0;
			read_instruction_start <= 0;
			stack_read_start <= 0;
			stack_write_start <= 0;
			stack_address <= 0;
			stack_words <= 0;
			stack_write <= 0;
		end else begin
			if (idle) begin // idle state
				program_running = 0;
				if (nike) begin
					idle <= 0;
					read_instruction_start <= 1;
				end
			end else if (read_instruction_start) begin // read instruction state
				if (read_instruction_done) begin
					read_instruction_start <= 0;
				end
			end else begin // operate state
				case (opcode)
					OP_LOAD: begin
						if (stack_read_start) begin
							if (stack_read_done) begin
								cpu_registers_write = { stack_read[255:240], 240'bx };
								cpu_registers_write_index = instr_b;
								cpu_registers_write_enable = 1;
								stack_read_start <= 0;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
						end else begin
							stack_address <= sp - instr_a;
							stack_words <= 16'd1;
							stack_read_start <= 1;
						end
					end
					OP_STORE: begin
						if (stack_write_start) begin
							if (stack_write_done) begin
								stack_write_start <= 0;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
						end else begin
							stack_write[255:240] <= cpu_registers_read_a;
							stack_address <= sp - instr_b;
							stack_words <= 16'd1;
							stack_write_start <= 1;
						end
					end
					OP_LITERAL: begin
						cpu_registers_write = { instr_a, 240'bx };
						cpu_registers_write_index = instr_b;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_INPUT: begin
						input_fpga_waiting = 1;
						if (input_fpga_returned) begin
							cpu_registers_write = { input_fpga_out, 240'bx };
							cpu_registers_write_index = instr_a;
							cpu_registers_write_enable = 1;
							pc <= pc + 16'd1;
							read_instruction_start <= 1;
						end
					end
					OP_OUTPUT: begin
						led_output_in <= cpu_registers_read_a;
						led_output_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_ADD: begin
						cpu_registers_write = { do_math_add, 240'bx };
						cpu_registers_write_index = instr_c;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_SUB: begin
						cpu_registers_write = { do_math_sub, 240'bx };
						cpu_registers_write_index = instr_c;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_MUL: begin
						cpu_registers_write = { do_math_mul, 240'bx };
						cpu_registers_write_index = instr_c;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_DIV: begin
						cpu_registers_write = { do_math_div, 240'bx };
						cpu_registers_write_index = instr_c;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_CMP: begin
						if (cpu_registers_read_a == cpu_registers_read_b) begin
							cpu_registers_write = { 16'd0, 240'bx };
							cpu_registers_write_index = instr_c;
							cpu_registers_write_enable = 0;
							pc <= pc + 16'd1;
							read_instruction_start <= 1;
						end else if (cpu_registers_read_a < cpu_registers_read_b) begin
							cpu_registers_write = { -16'd1, 240'bx };
							cpu_registers_write_index = instr_c;
							cpu_registers_write_enable = 0;
							pc <= pc + 16'd1;
							read_instruction_start <= 1;
						end else begin
							cpu_registers_write = { 16'd1, 240'bx };
							cpu_registers_write_index = instr_c;
							cpu_registers_write_enable = 0;
							pc <= pc + 16'd1;
							read_instruction_start <= 1;
						end
					end
					OP_BRANCH: begin
						if (cpu_registers_read_a == 0) begin
							pc <= pc + 16'd1;
							read_instruction_start <= 1;
						end else begin
							pc <= pc + 16'd2;
							read_instruction_start <= 1;
						end
					end
					OP_JUMP: begin
						pc <= instr_a;
						read_instruction_start <= 1;
					end
					OP_STACK: begin
						sp <= sp + instr_a;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_SUPERMANDIVE: begin
						if (stack_write_start) begin
							if (stack_write_done) begin
								stack_write_start <= 0;
								pc <= pc + 16'd1;
								sp <= sp + 16'd16;
								read_instruction_start <= 1;
							end
						end else begin
							stack_write <= cpu_registers;
							stack_address <= sp;
							stack_words <= 16'd16;
							stack_write_start <= 1;
						end
					end
					OP_GETUP: begin
						if (stack_read_start) begin
							if (stack_read_done) begin
								cpu_registers_write = stack_read;
								cpu_registers_write_index = 16'd16;
								cpu_registers_write_enable = 1;
								stack_read_start <= 0;
								pc <= pc + 16'd1;
								sp <= sp - 16'd16;
								read_instruction_start <= 1;
							end
						end else begin
							stack_address <= sp - 16'd16;
							stack_words <= 16'd16;
							stack_read_start <= 1;
						end
					end
					OP_PRINT: begin
						// TODO
					end
					OP_DRAW: begin
						// TODO
					end
					OP_KEYBOARD: begin
						// TODO
					end
					OP_EOF: begin
						program_done = 1;
						program_running = 0;
					end
					default: begin
						program_error = 1;
						program_running = 0;
					end
				endcase
			end
		end
	end
endmodule

//label: LED output
module led_output_dffr(input clock, enable, reset_n, input [15:0] d, output reg [15:0] q);
	always@(posedge clock) begin
		if (!reset_n) begin
			q <= 0;
		end else if (enable) begin
			q <= d;
		end
	end
endmodule

module instruction_ram_read(input clock, start, input [63:0] ram_data, output reg[63:0] q, output reg done);
	reg count = 0;
	always@(posedge clock) begin
		if (start) begin
			if (!done) begin
				if (count == 0) count <= count + 1;
				else begin
					q <= ram_data;
					done <= 1;
				end
			end
		end else begin
			done <= 0;
			count <= 0;
		end
	end
endmodule

// label: RAM
module stack_ram_read(input clock, start, input [15:0] ram_data, address, words, output reg [255:0] q, output reg [15:0] real_address, output reg done);
	reg [4:0] count = 0;
	integer i, k;
	always@(posedge clock) begin
		if (start) begin
			if (!done) begin
				real_address <= address + count;
				if (count == words + 1) begin 
					done <= 1;
				end
				else if (count == 0) count <= count + 1;
				else begin
					count <= count + 1;
					for (i = 0, k = 255 - (count - 1) * 16; i < 16; i = i + 1)
						q[k - i] = ram_data[15 - i];
				end
			end
		end else begin
			done <= 0;
			count <= 0;
			real_address <= 0;
		end
	end
endmodule

module stack_ram_write(input clock, start, input [15:0] address, words, input [255:0] data, output reg[15:0] stuff_to_write, real_address, output reg done);
	reg [4:0] count = 0;
	integer i, k;
	always@(posedge clock) begin
		if (start) begin
			if (!done) begin
				if (count == words) begin
					done <= 1;
				end
				else begin
					count <= count + 1;
					for(i = 0, k = 255 - (count * 16); i < 16; i = i + 1) begin
						stuff_to_write[15 - i] <= data[k - i];
					end
				end
			end
		end else begin
			done <= 0;
			count <= 0;
			real_address <= 0;
		end
	end
endmodule

module cpu_registers_read_mux(input [15:0] s, input [255:0] cpu_registers, output reg [15:0] out);
	always@(*) begin
		case (s)
			16'd0: out = cpu_registers[255:240];
			16'd1: out = cpu_registers[239:224];
			16'd2: out = cpu_registers[223:208];
			16'd3: out = cpu_registers[207:192];
			16'd4: out = cpu_registers[191:176];
			16'd5: out = cpu_registers[175:160];
			16'd6: out = cpu_registers[159:144];
			16'd7: out = cpu_registers[143:128];
			16'd8: out = cpu_registers[127:112];
			16'd9: out = cpu_registers[111:96];
			16'd10: out = cpu_registers[95:80];
			16'd11: out = cpu_registers[79:64];
			16'd12: out = cpu_registers[63:48];
			16'd13: out = cpu_registers[47:32];
			16'd14: out = cpu_registers[31:16];
			16'd15: out = cpu_registers[15:0];
			default: out = cpu_registers[255:240];
		endcase
	end
endmodule

module cpu_registers_write_mux(input clock, enable, input [15:0] s, input [255:0] in, output reg [255:0] cpu_registers);
	always@(posedge clock) begin
		if (enable) begin
			case (s)
				16'd0: cpu_registers[255:240] = in[255:240];
				16'd1: cpu_registers[239:224] = in[255:240];
				16'd2: cpu_registers[223:208] = in[255:240];
				16'd3: cpu_registers[207:192] = in[255:240];
				16'd4: cpu_registers[191:176] = in[255:240];
				16'd5: cpu_registers[175:160] = in[255:240];
				16'd6: cpu_registers[159:144] = in[255:240];
				16'd7: cpu_registers[143:128] = in[255:240];
				16'd8: cpu_registers[127:112] = in[255:240];
				16'd9: cpu_registers[111:96] = in[255:240];
				16'd10: cpu_registers[95:80] = in[255:240];
				16'd11: cpu_registers[79:64] = in[255:240];
				16'd12: cpu_registers[63:48] = in[255:240];
				16'd13: cpu_registers[47:32] = in[255:240];
				16'd14: cpu_registers[31:16] = in[255:240];
				16'd15: cpu_registers[15:0] = in[255:240];
				16'd16: cpu_registers = in;
				default: cpu_registers[255:240] = in[255:240];
			endcase
		end
	end
endmodule
