module processor();
	// TODO: load program end
	wire [15:0] pc, sp, program_end;
	wire read_instruction_start, read_instruction_done;
	wire clock, reset_n;
	
	wire [63:0] instruction;
	wire [15:0] opcode, instr_a, instr_b, instr_c;
	assign { opcode, instr_a, instr_b, instr_c } = instruction;

	parameter OP_LOAD = 16'd1
		, OP_STORE = 16'd2
		, OP_LITERAL = 16'd3
		, OP_OUTPUT = 16'd4
		, OP_ADD = 16'd5
		, OP_SUB = 16'd6
		, OP_MUL = 16'd7
		, OP_DIV = 16'd8
		, OP_BRANCH = 16'd9
		, OP_JUMP = 16'd10
		, OP_NJUMP = 16'd11
		, OP_INPUT = 16'd12
		, OP_STACK = 16'd13
		, OP_NSTACK = 16'd14
		, OP_SUPERMANDIVE = 16'd15
		, OP_GETUP = 16'd16
		, OP_PRINT = 16'd17;

	// Registers (search for "label: CPU registers")
	// Use: cpu_registers_<read|write> <a|b|c>
	wire [255:0] cpu_registers_in, cpu_registers_out;
	cpu_registers_dffr(clock, reset_n, cpu_registers_in, cpu_registers_out);

	// load 10 4;

	wire [15:0] cpu_registers_read_a, cpu_registers_read_b, cpu_registers_read_c;
	cpu_registers_read_mux(instr_a, cpu_registers_out, cpu_registers_read_a);
	cpu_registers_read_mux(instr_b, cpu_registers_out, cpu_registers_read_b);
	cpu_registers_read_mux(instr_c, cpu_registers_out, cpu_registers_read_c);

	wire [15:0] cpu_registers_write_a, cpu_registers_write_b, cpu_registers_write_c;
	cpu_registers_write_mux(instr_a, cpu_registers_write_a, cpu_registers_in);
	cpu_registers_write_mux(instr_b, cpu_registers_write_b, cpu_registers_in);
	cpu_registers_write_mux(instr_c, cpu_registers_write_c, cpu_registers_in);
	
	// Stack
	// Use: stack_address, stack_bytes, stack_read, stack_write
	wire [255:0] stack_read, stack_write;
	wire [15:0] stack_address, stack_bytes;
	wire stack_read_start, stack_read_done, stack_write_start, stack_write_done;
	ram_read(clock, stack_read_start, stack_address, stack_bytes, stack_read, stack_read_done);
	ram_write(clock, stack_write_start, stack_address, stack_bytes, stack_write, stack_write_done);

	// Read instruction
	ram_read(clock, read_instruction_start, pc, 16'd64, { instruction, 192{ 1'bz } }, read_instruction_done);

	// TODO: how to set initial state?
	// TODO: reset
	always@(posedge clock) begin
		if (read_instruction_start) begin // read instruction state
			if (read_instruction_done) begin
				read_instruction_start <= 0;
			end
		end else begin // operate state
			if (pc == program_end) begin // done state
				// TODO: set an LED?
			else
				case (opcode)
					OP_LOAD: begin // load 8 0
						if (stack_read_start) begin
							if (stack_read_done) begin
								cpu_registers_write_b <= stack_read[255:240];
								stack_read_start <= 0;
								pc <= pc + 16;
								read_instruction_start <= 1;
							end
						end else begin
							stack_address <= sp - instr_a;
							stack_bytes <= 16'd1;
							stack_read_start <= 1;
						end
					end
					OP_STORE: begin
						if (stack_write_start) begin
							if (stack_write_done) begin
								stack_write_start <= 0;
								pc <= pc + 16;
								read_instruction_start <= 1;
							end
						end else begin
							stack_write[255:240] <= cpu_registers_read_a;
							stack_address <= sp - instr_b;
							stack_bytes <= 16'd1;
							stack_write_start <= 1;
						end
					end
					OP_LITERAL: begin // literal 12 0
						cpu_registers_write_b <= instr_a;
						pc <= pc + 16;
						read_instruction_start <= 1;
					end
					OP_OUTPUT: begin
						// TODO
					end
					OP_ADD: begin
						cpu_registers_write_c <= cpu_registers_read_a + cpu_registers_read_b;
						pc <= pc + 16;
						read_instruction_start <= 1;
					end
					OP_SUB: begin
						cpu_registers_write_c <= cpu_registers_read_a - cpu_registers_read_b;
						pc <= pc + 16;
						read_instruction_start <= 1;
					end
					OP_MUL: begin
						cpu_registers_write_c <= cpu_registers_read_a * cpu_registers_read_b;
						pc <= pc + 16;
						read_instruction_start <= 1;
					end
					OP_DIV: begin
						cpu_registers_write_c <= cpu_registers_read_a / cpu_registers_read_b;
						pc <= pc + 16;
						read_instruction_start <= 1;
					end
					OP_BRANCH: begin // branch 0
						if (cpu_registers_read_a == 0) begin
							pc <= pc + 16;
							read_instruction_start <= 1;
						end else begin
							pc <= pc + 32;
							read_instruction_start <= 1;
						end
					end
					OP_JUMP: begin
						pc <= pc + instr_a;
						read_instruction_start <= 1;
					end
					OP_NJUMP: begin
						pc <= pc - instr_a;
						read_instruction_start <= 1;
					end
					OP_INPUT: begin
						// TODO
					end
					OP_STACK: begin
						sp <= sp + instr_a;
						pc <= pc + 16;
						read_instruction_start <= 1;
					end
					OP_NSTACK: begin
						sp <= sp - instr_a;
						pc <= pc + 16;
						read_instruction_start <= 1;
					end
					OP_SUPERMANDIVE: begin
						if (stack_write_start) begin
							if (stack_write_done) begin
								stack_write_start <= 0;
								pc <= pc + 16;
								sp <= sp + 256;
								read_instruction_start <= 1;
							end
						end else begin
							stack_write <= cpu_registers_out;
							stack_address <= sp;
							stack_bytes <= 16'32;
							stack_write_start <= 1;
						end
					end
					OP_GETUP: begin
						if (stack_read_start) begin
							if (stack_read_done) begin
								cpu_registers_in <= stack_read;
								stack_read_start <= 0;
								pc <= pc + 16;
								sp <= sp - 256
								read_instruction_start <= 1;
							end
						end else begin
							stack_address <= sp - 256;
							stack_bytes <= 16'32;
							stack_read_start <= 1;
						end
					end
					OP_PRINT: begin
						// TODO
					end
					default: begin
						// TODO: quit program, go to error state
					end
				endcase
			end
		end
	end
endmodule

// label: RAM
module ram_read(input clock, start, input [15:0] address, bytes, output [255:0] q, output done);
	// TODO: state machine reading number of bytes
	always@(posedge clock) begin
		if (start) begin
			// output to q
			// set done to high when finished
		end else begin
			// reset to ready/starting state
			done <= 0
		end
	end
endmodule

module ram_write(input clock, start, input [15:0] address, bytes, input [255:0] data, output done);
	// TODO: state machine write number of bytes
	always@(posedge clock) begin
		if (start) begin
			// write from data
			// set done to high when finished
		end else begin
			// reset to ready/starting state
			done <= 0
		end
	end
endmodule

// label: CPU registers
module cpu_registers_dffr(input clock, input reset_n, input [255:0] d, output reg [255:0] q);
	always@(posedge clock, negedge reset_n) begin
		if (!reset_n) begin
			q <= 0;
		end else begin
			q <= d;
		end
	end
endmodule

module cpu_registers_read_mux(input [15:0] s, input [255:0] cpu_registers, output [15:0] out);
	case (s)
		16'd0: assign out = cpu_registers[255:240];
		16'd1: assign out = cpu_registers[239:224];
		16'd2: assign out = cpu_registers[223:208];
		16'd3: assign out = cpu_registers[207:192];
		16'd4: assign out = cpu_registers[191:176];
		16'd5: assign out = cpu_registers[175:160];
		16'd6: assign out = cpu_registers[159:144];
		16'd7: assign out = cpu_registers[143:128];
		16'd8: assign out = cpu_registers[127:112];
		16'd9: assign out = cpu_registers[111:96];
		16'd10: assign out = cpu_registers[95:80];
		16'd11: assign out = cpu_registers[79:64];
		16'd12: assign out = cpu_registers[63:48];
		16'd13: assign out = cpu_registers[47:32];
		16'd14: assign out = cpu_registers[31:16];
		16'd15: assign out = cpu_registers[15:0];
		default: assign out = cpu_registers[255:240];
	endcase
endmodule

module cpu_registers_write_mux(input [15:0] s, input [15:0] in, output [255:0] cpu_registers);
	case (s)
		16'd0: assign cpu_registers[255:240] = in;
		16'd1: assign cpu_registers[239:224] = in;
		16'd2: assign cpu_registers[223:208] = in;
		16'd3: assign cpu_registers[207:192] = in;
		16'd4: assign cpu_registers[191:176] = in;
		16'd5: assign cpu_registers[175:160] = in;
		16'd6: assign cpu_registers[159:144] = in;
		16'd7: assign cpu_registers[143:128] = in;
		16'd8: assign cpu_registers[127:112] = in;
		16'd9: assign cpu_registers[111:96] = in;
		16'd10: assign cpu_registers[95:80] = in;
		16'd11: assign cpu_registers[79:64] = in;
		16'd12: assign cpu_registers[63:48] = in;
		16'd13: assign cpu_registers[47:32] = in;
		16'd14: assign cpu_registers[31:16] = in;
		16'd15: assign cpu_registers[15:0] = in;
		default: assign cpu_registers[255:240] = in;
	endcase
endmodule
