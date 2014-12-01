module playground
	(
		input 	CLOCK_50, 
		input 	[2:0] KEY, 
		input 	[15:0] SW, 
		output 	[7:0] LEDG, 
		output [17:0] LEDR, 
		output 	VGA_CLK, VGA_BLANK, VGA_HS, VGA_VS, VGA_SYNC, 
		output	[9:0] VGA_R, VGA_G, VGA_B,
		output[6:0] HEX0, HEX1, HEX2, HEX3,
		inout		PS2_CLK, PS2_DAT

		);
		
	assign LEDG[7:3] = { 5{ 1'd0 } };
	reg[3:0] something = 0;
	reg signed [15:0] pc = 0, sp = 0, save_pc;
	reg read_instruction_start = 0;
	wire read_instruction_done;
	reg idle = 1;
		

	reg keyreset = 1;
	always@(posedge CLOCK_50) begin
		if (key_pressed) begin
			if(keycode == 8'd39)
				keyreset <= 0;
			else keyreset <= 1;
		end 
		else keyreset <= 1;
	end
	
	
	wire clock, reset_n;
	wire nike;
	assign nike = (~KEY[1] || (key_pressed && keycode == 8'd28));
	assign clock = CLOCK_50;
	assign reset_n = (KEY[0] && (keyreset));
	
	wire [31:0] instruction;
	wire signed [7:0] opcode, instr_a, instr_b, instr_c;
	assign { opcode, instr_a, instr_b, instr_c } = instruction;
	reg unknown_command = 0;
	reg program_running = 0;
	reg segfault = 0, heap_segfault = 0;
	reg stack_read_start = 0, stack_write_start = 0;
	wire program_error = segfault | unknown_command | heap_segfault;
	reg program_done;

	assign LEDG[0] = program_running;
	assign LEDG[1] = program_done;
	assign LEDR[1] = segfault;
	assign LEDR[2] = heap_segfault;
	assign LEDR[0] = unknown_command;
	assign LEDR[17] = program_error;

	parameter
		  OP_EOF = 8'd0
		, OP_LOAD = 8'd1 // <
		, OP_STORE = 8'd2
		, OP_LITERAL = 8'd3
		, OP_INPUT = 8'd4
		, OP_OUTPUT = 8'd5
		, OP_ADD = 8'd6
		, OP_SUB = 8'd7
		, OP_MUL = 8'd8
		, OP_DIV = 8'd9
		, OP_KEYDEC = 8'd10
		, OP_BRANCH = 8'd11
		, OP_JUMP = 8'd12
		, OP_STACK = 8'd13
		, OP_SUPERMANDIVE = 8'd14
		, OP_GETUP = 8'd15
		, OP_PRINTDEC = 8'd16
		, OP_DRAW = 8'd17 // <char_code> <x> <y>
		, OP_KEYBOARD = 8'd18
		, OP_HEAP = 8'd19
		, OP_UNHEAP = 8'd20
		, OP_KEYHEX = 8'd21
		, OP_PRINTHEX = 8'd22
		, OP_INC = 8'd23
		, OP_DEC = 8'd24
		, OP_MOV = 8'd25
		, OP_NOT = 8'd26
		, OP_OR = 8'd27
		, OP_AND = 8'd28
		, OP_EQ = 8'd29
		, OP_LT = 8'd30
		, OP_GT = 8'd31
		, OP_RAND = 8'd32
		, OP_MOD = 8'd33
		, OP_INTERRUPT = 8'd34
		, OP_UNINTERRUPT = 8'd35
		, OP_HR_RESET = 8'd36
		, OP_KEY_COUNT = 8'd37
		, OP_UNKEY = 8'd38;

	// Output LED
	// Use: led_output_in, led_output_write_enable
	reg [15:0] led_output_in = 0;
	reg led_output_write_enable = 0;
	wire [15:0]out;
	led_output_dffr u0(clock, led_output_write_enable, reset_n, led_output_in, out);

	sevsegDecoder h0(out[3:0], HEX0);
	sevsegDecoder h1(out[7:4], HEX1);
	sevsegDecoder h2(out[11:8], HEX2);
	sevsegDecoder h3(out[15:12], HEX3);
	
	
	// Output VGA	
	wire[8:0] draw_x;
	reg [8:0] draw_X = 0; //lowercase for location of pixel, uppercase for location of character's top-left pixel
	wire [7:0] draw_y;
	reg [7:0] draw_Y = 0;
	reg [39:0] char_code = 0;
	reg [2:0] num_chars = 0;
	wire draw_colour, draw_en;
	reg vga_draw_start = 0;
	wire vga_draw_done;
	vga_draw_character u1(clock, vga_draw_start, reset_n, draw_X, draw_Y, char_code, num_chars, draw_en, vga_draw_done, draw_colour, draw_x, draw_y);
	vga_adapter VGA(
		.resetn(reset_n),
		.clock(CLOCK_50),
		.colour(draw_colour),
		.x(draw_x + 3'd3),
		.y(draw_y + 5'd14),
		.plot(draw_en),
		// Signals for the DAC to drive the monitor. 
		.VGA_R(VGA_R),
		.VGA_G(VGA_G),
		.VGA_B(VGA_B),
		.VGA_HS(VGA_HS),
		.VGA_VS(VGA_VS),
		.VGA_BLANK(VGA_BLANK),
		.VGA_SYNC(VGA_SYNC),
		.VGA_CLK(VGA_CLK));
	defparam VGA.RESOLUTION = "320x240";
	defparam VGA.MONOCHROME = "TRUE";
	defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
	defparam VGA.BACKGROUND_IMAGE = "background.mif";
	

	//Interrupt
	reg keyboard_interrupt = 0, timer_interrupt = 0, interrupt_received = 0, interrupt_done = 0;
	wire[1:0] interrupt_code;
	wire interrupt_high;
	reg[15:0]interrupt_jumpcode[0:3];
	integer k;
	initial begin
		for (k = 0; k < 4; k = k + 1) begin
			interrupt_jumpcode[k] = 16'b0;
		end
	end
	interrupt_handler ih(clock, reset_n, interrupt_done, interrupt_received, timer_interrupt, keyboard_interrupt, interrupt_high, interrupt_code);
	
	//Timer_interrupt
	wire pulse;
	myTimer timer1(CLOCK_50, reset_n, LEDR[3], pulse);
	always@(*)begin
		timer_interrupt = 0;
		if (pulse) begin
			if (interrupt_jumpcode[2'd0] != 0) begin
				timer_interrupt = 1'b1;
			end
		end
	end
	
	// Input keyboard
	wire key_pressed;
	reg[15:0] keycount = 0;
	wire [7:0] keycode;
	reg [15:0] key_int;

	keyboard_decoder keyboard(clock, PS2_CLK, PS2_DAT, key_pressed, keycode);
	
	always@(posedge clock)begin
		keyboard_interrupt <= 0;
		if (key_pressed) begin
			if (interrupt_jumpcode[2'd1] != 0) begin
				keyboard_interrupt <= 1'b1;
			end
		end
	end
	
	
	// Input fpga
	wire [15:0] input_fpga_out;
	wire input_fpga_returned;
	reg input_fpga_returned_prev_value = 0;
	reg input_fpga_waiting;
	assign input_fpga_out = SW[15:0];
	assign input_fpga_returned = ~KEY[2];
	assign LEDG[2] = input_fpga_waiting;
	
	//RNG
	wire [15:0] randnum;
	random rand1(randnum, clock);

	// CPU registers
	wire [255:0] cpu_registers;
	reg [255:0] save_registers;
	reg cpu_registers_write_enable;
	reg [7:0] cpu_registers_write_index;

	wire signed [15:0] cpu_registers_read_a, cpu_registers_read_b, cpu_registers_read_c;
	cpu_registers_read_mux u2(instr_a[3:0], cpu_registers, cpu_registers_read_a);
	cpu_registers_read_mux u3(instr_b[3:0], cpu_registers, cpu_registers_read_b);
	cpu_registers_read_mux u4(instr_c[3:0], cpu_registers, cpu_registers_read_c);
	
	reg [255:0] cpu_registers_write;
	cpu_registers_write_mux u5(clock, cpu_registers_write_enable, cpu_registers_write_index[4:0], cpu_registers_write, cpu_registers);
	
	// Stack
	wire [255:0] stack_read;
	reg [255:0] stack_write = 0;
	reg [15:0] stack_address = 0, stack_words = 0;

	wire [15:0] stack_write_values, stack_read_values, read_address, write_address; 
	reg [11:0] stack_address_real = 0;
	wire stack_read_done, stack_write_done, stack_write_go;
	stack_ram_read u8(clock, stack_read_start, stack_read_values, stack_address, stack_words, stack_read, read_address, stack_read_done);
	stack_ram_write u9(clock, stack_write_start, stack_address, stack_words, stack_write, stack_write_values, write_address, stack_write_done, stack_write_go);
	
	always@(*) begin
		segfault = 0;
		stack_address_real = read_address;
		if(stack_write_start) begin
			if (write_address > 16'd2047) begin
				segfault = 1;
			end else begin
				stack_address_real = write_address;
			end
		end else if (stack_read_start) begin
			if ((read_address > 16'd3) && ((read_address - 16'd2) > 16'd2047)) begin
				segfault = 1;
			end else begin
				stack_address_real = read_address;
			end
		end else begin
			segfault = 0;
			stack_address_real = read_address;
		end
	end
	
	stack_ram u11(
			.address(stack_address_real),
			.clock(clock),
			.data(stack_write_values),
			.wren(stack_write_go),
			.q(stack_read_values));
			
	//Heap
	reg [11:0] heap_address_real = 0, heap_address_read = 0, heap_address = 0;
	wire heap_read_done, heap_write_done, heap_write_enable;
	reg heap_read_start = 0;
	reg heap_write_start = 0, heap_reset_start = 0;
	reg [15:0] heap_write = 0;
	wire [15:0] heap_read, heap_read_values, heap_write_values, heap_address_write;

	heap_ram_read u6(clock, heap_read_start, heap_read, heap_read_values, heap_read_done);
	heap_ram_write u7(clock, heap_write_start, reset_n, heap_reset_start, heap_address, heap_write, heap_write_enable, heap_write_values, heap_address_write, heap_write_done);
	heap_ram u13(
			.address(heap_address_real),
			.clock(clock),
			.data(heap_write_values),
			.wren(heap_write_enable),
			.q(heap_read));

	always@(*) begin
		heap_segfault = 0;
		heap_address_real = heap_address_read;
		if(heap_write_start || heap_write_enable) begin
			if (heap_address_write > 16'd1023) begin
				heap_segfault = 1;
			end else begin
				heap_address_real = heap_address_write;
			end
		end else if (heap_read_start) begin
			if (heap_address_read > 16'd1023) begin
				heap_segfault = 1;
			end else begin
				heap_address_real = heap_address_read;
			end
		end
	end		
			
	// Read instruction
	wire [31:0] instr_read_values;
	instruction_ram_read u10(clock, read_instruction_start, instr_read_values, instruction, read_instruction_done);

	instruction_ram u12(
			.address(pc),
			.clock(clock),
			.data(32'bx),
			.wren(1'b0),
			.q(instr_read_values));
	
	wire signed[15:0] do_math_add, do_math_sub, do_math_mul, do_math_div, do_math_mod, do_math_inc, do_math_dec;
	assign do_math_add = cpu_registers_read_a + cpu_registers_read_b;
	assign do_math_sub = cpu_registers_read_a - cpu_registers_read_b;
	assign do_math_mul = cpu_registers_read_a * cpu_registers_read_b;
	assign do_math_inc = cpu_registers_read_a + 16'b1;
	assign do_math_dec = cpu_registers_read_a - 16'b1;
	
	//divider megafunction
	reg signed[15:0] denom = 1;
	reg signed[15:0] numer = 0;
	divider divide(
	.clock(clock),
	.denom(denom),
	.numer(numer),
	.quotient(do_math_div),
	.remain(do_math_mod));
	
	
	reg[10:0] count = 0;
	reg[39:0] display_int = { 8'd36, 8'd36, 8'd36, 8'd36, 8'd36 };
	integer i;
	always@(posedge clock) begin
		cpu_registers_write_enable = 0;
		led_output_write_enable = 0;
		program_running = 1;
		program_done = 0;
		input_fpga_waiting = 0;
		cpu_registers_write = 0;
		cpu_registers_write_index = 0;
		interrupt_done = 0;


		input_fpga_returned_prev_value <= input_fpga_returned;
		if (!reset_n) begin
			program_running <= 0;
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
			heap_read_start <= 0;
			heap_write_start <= 0;
			heap_address_read <= 0;
			heap_address <= 0;
			heap_reset_start <= 0;
			vga_draw_start <= 0;
			count <= 0;
			keycount <= 0;
			save_registers <= 0;
			save_pc <= 0;
			for (k = 0; k < 4; k = k + 1)
				interrupt_jumpcode[k] = 16'b0;
			interrupt_received <= 0;
			interrupt_done <= 0;
			display_int <= { 8'd36, 8'd36, 8'd36, 8'd36 };
			unknown_command <= 0;
		end else begin
			if (program_error) begin
				program_running = 0;
			end else if (idle) begin // idle state
				program_running = 0;
				if (nike) begin
					idle <= 0;
					read_instruction_start <= 1;
				end
			end else if (read_instruction_start) begin // read instruction state
				if (interrupt_high && !interrupt_received) begin
						interrupt_received <= 1;
						save_registers <= cpu_registers;
						save_pc <= pc;
						pc <= interrupt_jumpcode[interrupt_code];
						count <= 5'd25;
				end else if (read_instruction_done) begin
					if (count == 5'd25)
						count <= 0;
					else
						read_instruction_start <= 0;
				end
			end else begin // operate state
				case (opcode)
					OP_LOAD: begin
						if (stack_read_start) begin
							if (stack_read_done) begin
								cpu_registers_write <= { stack_read[255:240], 240'bx };
								cpu_registers_write_index <= instr_c;
								cpu_registers_write_enable <= 1;
								stack_read_start <= 0;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
						end else begin
							stack_address <= sp - { instr_a, instr_b };
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
							stack_address <= sp - { instr_b, instr_c };
							stack_words <= 16'd1;
							stack_write_start <= 1;
						end
					end
					OP_LITERAL: begin
						cpu_registers_write <= { instr_a, instr_b, 240'bx };
						cpu_registers_write_index <= instr_c;
						cpu_registers_write_enable <= 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_INPUT: begin
						input_fpga_waiting = 1;
						if (input_fpga_returned) begin
							if (!input_fpga_returned_prev_value) begin
								cpu_registers_write = { input_fpga_out, 240'bx };
								cpu_registers_write_index = instr_a;
								cpu_registers_write_enable = 1;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
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
						if(count == 6) begin
							cpu_registers_write = { do_math_div, 240'bx };
							cpu_registers_write_index = instr_c;
							cpu_registers_write_enable = 1;
							count <= 0;
							pc <= pc + 16'd1;
							read_instruction_start <= 1;
						end else begin
							numer <= cpu_registers_read_a;
							denom <= cpu_registers_read_b;
							count <= count + 1;
						end
					end
					OP_MOD: begin
						if(count == 6	) begin
							cpu_registers_write = { do_math_mod, 240'bx };
							cpu_registers_write_index = instr_c;
							cpu_registers_write_enable = 1;
							count <= 0;
							pc <= pc + 16'd1;
							read_instruction_start <= 1;
						end else begin
							numer <= cpu_registers_read_a;
							denom <= cpu_registers_read_b;
							count <= count + 1;
						end
					end
					OP_BRANCH: begin
						if (cpu_registers_read_a == 0) begin
							pc <= pc + 16'd2;
							read_instruction_start <= 1;
						end else begin
							pc <= pc + 16'd1;
							read_instruction_start <= 1;
						end
					end
					OP_JUMP: begin
						if (instr_a == 0) begin
							pc <= { instr_b, instr_c };
							read_instruction_start <= 1;
						end
						else begin
							pc <= cpu_registers_read_b;
							read_instruction_start <= 1;
						end
					end
					OP_STACK: begin
						sp <= sp + { instr_a, instr_b };
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_SUPERMANDIVE: begin
						if (stack_write_start) begin
							if (stack_write_done) begin
								stack_write_start <= 0;
								pc <= pc + 16'd1;
								sp <= sp + 16'd15;	
								read_instruction_start <= 1;
							end
						end else begin
							stack_write <= cpu_registers;
							stack_address <= sp;
							stack_words <= 16'd15;
							stack_write_start <= 1;
						end
					end
					OP_GETUP: begin
						if (stack_read_start) begin
							if (stack_read_done) begin
								cpu_registers_write = stack_read;
								cpu_registers_write_index = 8'd16;
								cpu_registers_write_enable = 1;
								stack_read_start <= 0;
								pc <= pc + 16'd1;
								sp <= sp - 16'd15;
								read_instruction_start <= 1;
							end
						end else begin
							stack_address <= sp - 16'd15;
							stack_words <= 16'd15;
							stack_read_start <= 1;
						end
					end
					OP_PRINTHEX: begin
						if (vga_draw_start) begin
							if (vga_draw_done) begin
								vga_draw_start <= 0;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
						end else begin
							char_code <= { 4'b0, cpu_registers_read_a[15:12], 4'b0, cpu_registers_read_a[11:8], 
								4'b0, cpu_registers_read_a[7:4], 4'b0, cpu_registers_read_a[3:0], 8'd36 };
							draw_X <= cpu_registers_read_b[8:0];
							draw_Y <= cpu_registers_read_c[7:0];
							num_chars <= 2'd3;
							vga_draw_start <= 1;
						end								
					end
					OP_PRINTDEC: begin
						if (vga_draw_start) begin
							if (vga_draw_done) begin
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
								vga_draw_start <= 0;
							end
						end else begin
							count <= count + 1;
							if (count == 0) begin
								numer <= cpu_registers_read_a;
								denom <= 16'd10;
							end else if (count == 7) begin
								char_code[7:0] <= do_math_mod[8:0];
								numer <= do_math_div;
								denom <= 16'd10;
							end else if (count == 14) begin
								char_code[15:8] <= do_math_mod[8:0];
								numer <= do_math_div;
								denom <= 16'd10;
							end else if (count == 21) begin
								char_code[23:16] <= do_math_mod[8:0];
								numer <= do_math_div;
								denom <= 16'd10;
							end else if (count == 28) begin
								char_code[31:24] <= do_math_mod[8:0];
								numer <= do_math_div;
								denom <= 16'd10;
							end else if (count == 35) begin
								char_code[39:32] <= do_math_mod[8:0];
								draw_X <= cpu_registers_read_b[8:0];
								draw_Y <= cpu_registers_read_c[7:0];
								num_chars <= 3'd4;
								count <= 0;
								vga_draw_start <= 1'b1;
							end
						end
					end
					OP_DRAW: begin
						if (vga_draw_start) begin
							if (vga_draw_done) begin
								vga_draw_start <= 0;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
						end else begin
							char_code <= { cpu_registers_read_a[7:0], 32'b0 };
							draw_X <= cpu_registers_read_b[8:0];
							draw_Y <= cpu_registers_read_c[7:0];
							num_chars <= 0;
							vga_draw_start <= 1;
						end	
					end
					OP_KEYBOARD: begin
						if (key_pressed) begin
							if (keycode != 8'd255) begin
								char_code <= { keycode, 32'b0 };
								if (cpu_registers_read_a != -1) begin
									draw_X <= cpu_registers_read_a[8:0];
									draw_Y <= cpu_registers_read_b[7:0];
									num_chars <= 0;
									vga_draw_start <= 1;
								end
								cpu_registers_write = { 8'b0, keycode, 240'bx };
								cpu_registers_write_index = instr_c;
								cpu_registers_write_enable = 1;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
						end
					end
					OP_KEYHEX: begin
						input_fpga_waiting = 1;
						if (vga_draw_start) begin
							if (vga_draw_done) begin
								vga_draw_start <= 0;
							end
						end else if (key_pressed || count == 4'd5) begin
							if (keycode != 8'd255) begin
								if (keycode == 8'd98) begin
									if (display_int == { 8'd36, 8'd36, 8'd36, 8'd36, 8'd36 }) begin
										char_code <= {8'b0, display_int[31:0]};
										display_int[39:32] <= 8'b0;
										draw_X <= cpu_registers_read_a[8:0];
										draw_Y <= cpu_registers_read_b[7:0];
										num_chars <= 1'b1;
										keycount <= 1'd1;
										vga_draw_start <= 1;
										count <= 4'd5;
									end else begin
										cpu_registers_write <= { key_int, 240'bx };
										cpu_registers_write_index <= instr_c;
										cpu_registers_write_enable <= 1;
										display_int <= { 8'd36, 8'd36, 8'd36, 8'd36, 8'd36 };
										key_int <= 0;
										count <= 0;
										pc <= pc + 16'd1;
										input_fpga_waiting = 0;
										read_instruction_start <= 1;
									end
								end else if (keycode < 8'd16)begin
									if(count != 4) begin
										key_int = key_int << 4;
										key_int[3:0] = keycode [3:0];
										display_int[39:32] = { 4'b0, key_int [15:12] };
										display_int[31:24] = { 4'b0, key_int [11:8] };
										display_int[23:16] = { 4'b0, key_int [7:4] };
										display_int[15:8] = {4'b0, key_int [3:0] };
										display_int[7:0] = {8'd36};
										for (i = 0; i < (2'd3 - count) && i < 2'd3; i = i + 1)
											display_int = display_int << 8;
										char_code = { display_int };
										draw_X <= cpu_registers_read_a[8:0];
										draw_Y <= cpu_registers_read_b[7:0];
										num_chars <= count;
										vga_draw_start <= 1'b1;
										count <= count + 1'b1;
										keycount <= count + 1'b1;
									end
								end else if (keycode == 8'd37) begin
									if (count > 0) begin
										key_int <= key_int >> 4;
										display_int[39:32] = { 8'b0 };
										display_int[31:24] = { 4'b0, key_int [15:12] };
										display_int[23:16] = { 4'b0, key_int [11:8] };
										display_int[15:8] = {4'b0, key_int [7:4] };
										display_int[7:0] = 8'd36;
										for (i = 0; i < (2'd3 - count + 2'd2) && i < 2'd3; i = i + 1) begin
											display_int = display_int << 8;
											display_int[7:0] = 8'd36;
										end
										char_code = { display_int };
										draw_X <= cpu_registers_read_a[8:0];
										draw_Y <= cpu_registers_read_b[7:0];
										num_chars <= count - 1'b1;
										vga_draw_start <= 1'b1;
										count <= count - 1'b1;
										keycount <= count - 1'b1;
									end
								end
							end
						end
					end
					OP_KEYDEC: begin
						input_fpga_waiting = 1'b1;
						if (vga_draw_start) begin
							if (vga_draw_done) begin
								vga_draw_start <= 0;
							end
						end else if (key_pressed || count == 3'd6) begin
							if (keycode != 8'd255) begin
								if (keycode == 8'd98) begin
									if (display_int == { 8'd36, 8'd36, 8'd36, 8'd36, 8'd36 }) begin
										char_code <= {8'b0, 8'd36, 8'd36, 8'd36, 8'd36};
										display_int[39:32] = 8'b0;
										num_chars <= 1'b1;
										draw_X <= cpu_registers_read_a[8:0];
										draw_Y <= cpu_registers_read_b[7:0];
										vga_draw_start <= 1'b1;
										count <= 3'd6;
										keycount <= 1'b1;
									end
									cpu_registers_write <= { key_int, 240'bx };
									cpu_registers_write_index <= instr_c;
									cpu_registers_write_enable <= 1'b1;
									display_int <= { 8'd36, 8'd36, 8'd36, 8'd36, 8'd36 };
									key_int <= 0;
									count <= 0;
									pc <= pc + 16'd1;
									input_fpga_waiting = 0;
									read_instruction_start <= 1'b1;
								end else if (keycode < 8'd10)begin
									if(count != 3'd5) begin
										key_int <= (key_int * 4'd10) + keycode;
										char_code <= { keycode, 32'b0 };
										draw_X <= cpu_registers_read_a[8:0] + count;
										draw_Y <= cpu_registers_read_b[7:0];
										num_chars <= 1'b1;
										vga_draw_start <= 1'b1;
										count <= count + 1'b1;
										keycount <= count + 1'b1;
									end
								end else if (keycode == 8'd37) begin
									if (something == 4'd7) begin
										key_int <= do_math_div;
										something <= 0;
										char_code <= {8'd36, 32'd0};
										draw_X <= cpu_registers_read_a[8:0] + count - 1'b1;
										draw_Y <= cpu_registers_read_b[7:0];
										num_chars <= 0;
										vga_draw_start <= 1'b1;
										count <= count - 1'b1;
										keycount <= count - 1'b1;
									end else if (count > 0) begin
										numer <= key_int;
										denom <= 5'd10;
										something <= something + 1'b1;
									end
								end
							end
						end
					end
					OP_HEAP: begin
						if (heap_write_start) begin
							if (heap_write_done) begin
								heap_write_start <= 0;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
						end else begin
							heap_write <= cpu_registers_read_a;
							heap_address <= cpu_registers_read_b;
							heap_write_start <= 1;
						end
					end
					OP_UNHEAP: begin
						if (heap_read_start) begin
							if (heap_read_done) begin
								cpu_registers_write <= { heap_read_values, 240'bx };
								cpu_registers_write_index <= instr_b;
								cpu_registers_write_enable = 1'b1;
								heap_read_start <= 0;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
						end else begin
							heap_address_read <= cpu_registers_read_a;
							heap_read_start <= 1;
						end
					end
					OP_INC: begin
						cpu_registers_write = { do_math_inc, 240'bx };
						cpu_registers_write_index = instr_a;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_DEC: begin
						cpu_registers_write <= { do_math_dec, 240'bx };
						cpu_registers_write_index <= instr_a;
						cpu_registers_write_enable <= 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_MOV: begin
						cpu_registers_write <= { cpu_registers_read_a, 240'bx };
						cpu_registers_write_index <= instr_b;
						cpu_registers_write_enable <= 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_NOT: begin
						cpu_registers_write <= { !(cpu_registers_read_a), 240'bx };
						cpu_registers_write_index <= instr_b;
						cpu_registers_write_enable <= 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_OR: begin
						cpu_registers_write <= { (cpu_registers_read_a || cpu_registers_read_b), 240'bx };
						cpu_registers_write_index <= instr_c;
						cpu_registers_write_enable <= 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_AND: begin
						cpu_registers_write <= { (cpu_registers_read_a && cpu_registers_read_b), 240'bx };
						cpu_registers_write_index <= instr_c;
						cpu_registers_write_enable <= 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_EQ: begin
						if (cpu_registers_read_a == cpu_registers_read_b) begin
							cpu_registers_write = { 16'd1, 240'bx };
						end else begin
							cpu_registers_write = { 16'd0, 240'bx };
						end	
						cpu_registers_write_index = instr_c;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_LT: begin
						if (cpu_registers_read_a < cpu_registers_read_b) begin
							cpu_registers_write = { 16'd1, 240'bx };
						end else begin
							cpu_registers_write = { 16'd0, 240'bx };
						end
						cpu_registers_write_index = instr_c;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_GT: begin
						if (cpu_registers_read_a > cpu_registers_read_b) begin
							cpu_registers_write = { 16'd1, 240'bx };
						end else begin
							cpu_registers_write = { 16'd0, 240'bx };
						end
						cpu_registers_write_index = instr_c;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_RAND: begin
						cpu_registers_write <= { randnum, 240'bx };
						cpu_registers_write_index <= instr_a;
						cpu_registers_write_enable = 1;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_INTERRUPT: begin
						interrupt_jumpcode[instr_a[1:0]] <= cpu_registers_read_b;
						pc <= pc + 16'd1;
						read_instruction_start <= 1;
					end
					OP_UNINTERRUPT: begin
						pc <= save_pc;
						cpu_registers_write <= save_registers;
						cpu_registers_write_index <= 5'd17;
						cpu_registers_write_enable <= 1;
						interrupt_received <= 0;
						interrupt_done <= 1;
						read_instruction_start <= 1;
					end
					OP_HR_RESET: begin
						if (heap_reset_start) begin
							if (heap_write_done) begin
								heap_reset_start <= 0;
								pc <= pc + 16'd1;
								read_instruction_start <= 1;
							end
						end
						heap_reset_start <= 1;
					end
					OP_KEY_COUNT: begin
						cpu_registers_write <= { keycount, 240'bx };
						cpu_registers_write_index <= instr_a;
						cpu_registers_write_enable <= 1'b1;
						pc <= pc + 1'b1;
						read_instruction_start <= 1'b1;
					end
					OP_UNKEY: begin
						cpu_registers_write <= { 8'b0, keycode, 240'bx };
						cpu_registers_write_index <= instr_a;
						cpu_registers_write_enable <= 1'b1;
						pc <= pc + 1'b1;
						read_instruction_start <= 1'b1;
					end
					OP_EOF: begin
						program_done <= 1;
						program_running <= 0;
					end
					default: begin
						unknown_command <= 1;
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

module instruction_ram_read(input clock, start, input [31:0] ram_data, output reg[31:0] q, output reg done);
	reg count = 0;
	always@(posedge clock) begin
		if (start) begin
			if (!done) begin
				if (count == 0) count <= count + 1;
				else begin
					q <= ram_data;
					done <= 1;
				end
			end else begin
				done <= 0;
			end
		end else begin
			done <= 0;
			count <= 0;
		end
	end
endmodule

// label: stack RAM
module stack_ram_read(input clock, start, input [15:0] ram_data, address, words, output reg [255:0] q, output reg [15:0] real_address, output reg done);
	reg [4:0] count = 0;
	integer i, k;
	always@(posedge clock) begin
		if (start) begin
			if (!done) begin
				real_address <= address + count;
				count <= count + 1;
				if (count == words + 2'd2) begin
					done <= 1;
				end
				else if (count > 1) begin
					k = (16'd255 - (count - 2) * 16);
					for (i = 0; i < 16; i = i + 1) begin
						q[k - i] = ram_data[15 - i];
					end
				end
			end
		end else begin
			done <= 0;
			count <= 0;
			real_address <= 0;
			q <= 0;
		end
	end
endmodule

module stack_ram_write(input clock, start, input [15:0] address, words, input [255:0] data, output reg[15:0] stuff_to_write, real_address, output reg done, write);
	reg [4:0] count = 0;
	integer i, k;
	always@(posedge clock) begin
		if (start) begin
			if (!done) begin
				if (count == words) begin
					done <= 1;
					write <= 0;
				end
				else begin
					write <= 1;
					count <= count + 1;
					real_address <= address + count;
					k = (16'd255 - (count * 16));
					for (i = 0; i < 16; i = i + 1) begin
						stuff_to_write[15 - i] <= data [k - i];
					end
				end
			end
		end else begin
			write <= 0;
			done <= 0;
			count <= 0;
			real_address <= 0;
			stuff_to_write <= 0;
		end
	end
endmodule


module heap_ram_write(input clock, start, resetn, heap_reset, input [15:0] address, input [15:0] data, output reg heap_write_enable, output reg[15:0] stuff_to_write, real_address, output reg done);
	reg [15:0] count = 0;
	reg resetting = 0;
	always@(posedge clock) begin
		if (resetting) begin
			if (count == 16'd1023) begin
				done <= 1'b1;
				resetting <= 0;
				count <= 0;
				heap_write_enable <= 0;
			end else begin
				heap_write_enable <= 1'b1;
				stuff_to_write <= 0;
				real_address <= count;
				count <= count + 1'b1;	
			end
		end else if (!resetn || heap_reset) begin
			resetting <= 1'b1;
		end else if (start) begin
			if (!done) begin
				if (count == 1'b1) begin
					done <= 1'b1;
					heap_write_enable <= 0;
					count <= 0;
				end
				else begin
					heap_write_enable <= 1;
					stuff_to_write <= data;
					real_address <= address;
					count <= count + 1'b1;
				end
			end
		end else begin
			done <= 0;
			count <= 0;
			real_address <= 0;
			stuff_to_write <= 0;
			heap_write_enable <= 0;
		end
	end
endmodule

module heap_ram_read(input clock, start, input [15:0] ram_data, output reg[15:0] q, output reg done);
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


module cpu_registers_read_mux(input [3:0] s, input [255:0] cpu_registers, output reg [15:0] out);
	always@(*) begin
		case (s)
			4'd0: out = cpu_registers[255:240];
			4'd1: out = cpu_registers[239:224];
			4'd2: out = cpu_registers[223:208];
			4'd3: out = cpu_registers[207:192];
			4'd4: out = cpu_registers[191:176];
			4'd5: out = cpu_registers[175:160];
			4'd6: out = cpu_registers[159:144];
			4'd7: out = cpu_registers[143:128];
			4'd8: out = cpu_registers[127:112];
			4'd9: out = cpu_registers[111:96];
			4'd10: out = cpu_registers[95:80];
			4'd11: out = cpu_registers[79:64];
			4'd12: out = cpu_registers[63:48];
			4'd13: out = cpu_registers[47:32];
			4'd14: out = cpu_registers[31:16];
			4'd15: out = cpu_registers[15:0];
			default: out = cpu_registers[255:240];
		endcase
	end
endmodule

module cpu_registers_write_mux(input clock, enable, input [4:0] s, input [255:0] in, output reg [255:0] cpu_registers);
	always@(posedge clock) begin
		if (enable) begin
			case (s)
				5'd0: cpu_registers[255:240] = in[255:240];
				5'd1: cpu_registers[239:224] = in[255:240];
				5'd2: cpu_registers[223:208] = in[255:240];
				5'd3: cpu_registers[207:192] = in[255:240];
				5'd4: cpu_registers[191:176] = in[255:240];
				5'd5: cpu_registers[175:160] = in[255:240];
				5'd6: cpu_registers[159:144] = in[255:240];
				5'd7: cpu_registers[143:128] = in[255:240];
				5'd8: cpu_registers[127:112] = in[255:240];
				5'd9: cpu_registers[111:96] = in[255:240];
				5'd10: cpu_registers[95:80] = in[255:240];
				5'd11: cpu_registers[79:64] = in[255:240];
				5'd12: cpu_registers[63:48] = in[255:240];
				5'd13: cpu_registers[47:32] = in[255:240];
				5'd14: cpu_registers[31:16] = in[255:240];
				5'd15: cpu_registers[15:0] = in[255:240];
				5'd16: cpu_registers[255:16] = in[255:16];
				5'd17: cpu_registers = in;
				default: cpu_registers[255:240] = in[255:240];
			endcase
		end
	end
endmodule

module interrupt_handler (input clock, resetn, interrupt_done, interrupt_received, timer_interrupt, keyboard_interrupt, output reg interrupt_high, output reg [1:0] interrupt_code);
	reg timer_received = 0, key_received = 0;
	always@(posedge clock) begin
		if (!resetn) begin
			timer_received <= 0;
			key_received <= 0;
			interrupt_high <= 0;
			interrupt_code <= 0;
		end else if (timer_interrupt || timer_received) begin
			timer_received <= 1;
			interrupt_high <= 1;
			interrupt_code <= 2'd0;
			if (interrupt_received)
				interrupt_high <= 0;
			if (interrupt_done) begin
				interrupt_high <= 0;
				timer_received <= 0;
			end
		end else if (keyboard_interrupt || key_received) begin
			key_received <= 1;
			interrupt_high <= 1;
			interrupt_code <= 2'd1;
			if (interrupt_received)
				interrupt_high <= 0;
			if (interrupt_done) begin
				interrupt_high <= 0;
				key_received <= 0;
			end
		end else begin
			interrupt_high <= 0;
			interrupt_code <= 0;
		end
	end
endmodule

module myTimer (input clock, input [32:0]counter, output reg LEDR, output reg pulse);
	reg[32:0] count = 0;
	always@(posedge clock) begin
		if (!reset_n) begin
			count <= 0;
			pulse <= 0;
			LEDR <= 0;
		end else if (count == 33'd50_000_000) begin
			pulse <= 1'b1;
			LEDR <= ~LEDR;
			count <= 0;
		end else begin
			count <= count + 1'b1;
			pulse <= 0;
		end
		
	end
endmodule
			


module vga_draw_character (input clock, start, reset_n, input [8:0] X, input [7:0] Y, input [39:0] char_code, input [2:0] num_chars, output reg draw_en, done, colour, output reg [8:0] x, output reg [7:0] y);
	wire [0:47]  pixels;
	reg [7:0] chars;
	reg [3:0] count = 0;
	reg resetting = 0;
	reg started = 0;
	reg [5:0] i = 6'd39;
   // Data path
	reg [16:0] counterX = 0;
	reg [9:0] counterY = 0;
   char_to_pixels u0(chars, pixels);


	integer k;
   always@(posedge clock) begin
		if (resetting) begin
			counterX <= counterX + 1'b1;
			if(counterX == 9'd313) begin
				if(counterY == 9'd223) begin
					resetting <= 0;
					counterX <= 0;
					counterY <= 0;
				end else begin
					counterY <= counterY + 1'b1;
					counterX <= 0;
				end
			end
			draw_en <= 1;
			x <= counterX;
			y <= counterY;
			colour <= 0;
		end
		else if (!reset_n) begin
			resetting <= 1'b1;
		end
		else if (start) begin
			if (!started) begin
				chars[7:0] = char_code[39:32];
				started <= 1'b1;
			end else if (!done) begin
				counterX <= counterX + 1'b1;
				if (counterX == 9'd5) begin
					if (counterY == 9'd7) begin
						counterX <= 0;
						counterY <= 0;
						if (count == num_chars) begin
							done <= 1;
							started <= 0;
						end
						else begin
							count <= count + 1'b1;
							i = 6'd39 - ((count + 1'b1) * 4'd8);
							for (k = 0; k < 8; k = k + 1)
								chars[7 - k] = char_code[i - k];
						end
					end else begin
						counterY <= counterY + 1'b1;
						counterX <= 0;
					end
				end
				draw_en <= 1;
				x <= ((X + count) * 3'd6) + counterX;
				y <= (Y * 4'd8) + counterY;
				colour <= pixels[((6 * counterY) + counterX)];
			end
		end 
		else begin
			started <= 0;
			resetting <= 0;
			draw_en <= 0;
			counterX <= 0;
			counterY <= 0;
			count <= 0;
			done <= 0;
			i = 6'd39;
			for (k = 0; k < 8; k = k + 1)
					chars[7 - k] <= char_code[i - k];
		end
	end
 endmodule

module char_to_pixels (input [7:0] code, output reg [0:47] pixels);
   always@(*) begin
      case (code)
	8'h0: pixels = 48'b011100100010100110101010110010100010011100000000;
	8'h1: pixels = 48'b001000011000101000001000001000001000111110000000;
	8'h2: pixels = 48'b011100100010000010000100001000010000111110000000;
	8'h3: pixels = 48'b011100100010000010001100000010100010011100000000;
	8'h4: pixels = 48'b001100010100100100100100111110000100000100000000;
	8'h5: pixels = 48'b111110100000100000111100000010000010111100000000;
	8'h6: pixels = 48'b011100100010100000111100100010100010011100000000;
	8'h7: pixels = 48'b111110000010000010000100000100001000001000000000;
	8'h8: pixels = 48'b011100100010100010011100100010100010011100000000;
	8'h9: pixels = 48'b011100100010100010011110000010100010011100000000;
	8'hA: pixels = 48'b011100100010100010111110100010100010100010000000;
	8'hB: pixels = 48'b111100100010100010111100100010100010111100000000;
	8'hC: pixels = 48'b011110100000100000100000100000100000011110000000;
	8'hD: pixels = 48'b111100100010100010100010100010100010111100000000;
	8'hE: pixels = 48'b111110100000100000111110100000100000111110000000;
	8'hF: pixels = 48'b111110100000100000111110100000100000100000000000;
	8'd16: pixels = 48'b011100100010100000100000100110100010011100000000; // G
	8'd17: pixels = 48'b100010100010100010111110100010100010100010000000; // H
	8'd18: pixels = 48'b111110001000001000001000001000001000111110000000; // I
	8'd19: pixels = 48'b111110000100000100000100000100100100011000000000; // J
	8'd20: pixels = 48'b100010100100101000110000101000100100100010000000; // K
	8'd21: pixels = 48'b100000100000100000100000100000100000111110000000; // L
	8'd22: pixels = 48'b100010110110101010101010100010100010100010000000; // M
	8'd23: pixels = 48'b110010110010101010101010101010100110100110000000; // N
	8'd24: pixels = 48'b011100100010100010100010100010100010011100000000; // O
	8'd25: pixels = 48'b111100100010100010111100100000100000100000000000; // P
	8'd26: pixels = 48'b011100100010100010100010101010100100011010000000; // Q
	8'd27: pixels = 48'b111100100010100010111100101000100100100010000000; // R
	8'd28: pixels = 48'b011110100000100000011100000010000010111100000000; // S
	8'd29: pixels = 48'b111110001000001000001000001000001000001000000000; // T
	8'd30: pixels = 48'b100010100010100010100010100010100010011100000000; // U
	8'd31: pixels = 48'b100010100010100010100010010100010100001000000000; // V
	8'd32: pixels = 48'b100010100010100010101010101010110110100010000000; // W
	8'd33: pixels = 48'b100010100010010100001000010100100010100010000000; // X
	8'd34: pixels = 48'b100010100010100010010100001000001000001000000000; // Y
	8'd35: pixels = 48'b111110000010000100001000010000100000111110000000; // Z
	8'd36: pixels = 48'b000000000000000000000000000000000000000000000000; // space
        default:  pixels = 48'b000000000000000000000000000000000000000000000000;
      endcase // case (code)
   end
endmodule // char_to_pixels
	

module sevsegDecoder(input[3:0] in, output reg[6:0] HEX);

   always @(in)
     case (in)
       4'h0: HEX = 7'b1000000;
       4'h1: HEX = 7'b1111001;
       4'h2: HEX = 7'b0100100;
       4'h3: HEX = 7'b0110000;
       4'h4: HEX = 7'b0011001;
       4'h5: HEX = 7'b0010010;
       4'h6: HEX = 7'b0000010;
       4'h7: HEX = 7'b1111000;
       4'h8: HEX = 7'b0000000;
       4'h9: HEX = 7'b0011000;
       4'hA: HEX = 7'b0001000;
       4'hB: HEX = 7'b0000011;
       4'hC: HEX = 7'b1000110;
       4'hD: HEX = 7'b0100001;
       4'hE: HEX = 7'b0000110;
       4'hF: HEX = 7'b0001110;
       default: HEX = 7'b0110110;
     endcase
endmodule