#!/usr/bin/perl

use strict;
use warnings;

exit main();

sub main {
	my (@files) = @ARGV;
	my @all_lines = ();
	foreach my $f (@files) {
		load_file($f, \@all_lines);
	}
	my @filtered_lines = ();
	my $labels = {};
	my $count = 0;
	foreach my $l (@all_lines) {
		my @parts = split(/\s+/, $l);
		if (@parts) {
			if ($parts[0] =~ /([a-zA-Z]\w*):/) {
				$labels->{$1} = $count;
			} else {
				push @filtered_lines, \@parts;
				$count++;
			}
		}
	}
	process_code(\@filtered_lines, $labels);
	return 0;
}

sub load_file {
	open (my $f, '<', $_[0]) or die "Failed to open file \"$_[0]\"";
	my @lines = <$f>;
	close $f;
	chomp(@lines);
	push $_[1], @lines;
}

sub process_code {
	my $lines = $_[0];
	foreach my $l (@$lines) {
		process_instruction($l->[0], [@$l[1..@$l - 1]], $_[1]);
	}
}

sub process_instruction {
	my $opcode = $_[0];
	my $args = $_[1];
	my $labels = $_[2];
	# Yes I know I just joined the line I split
	# I wanted to try out more perl stuff
	# e.g. slicing and passing an array ref, capturing matches
	my $instr = $opcode . ' ' . join(' ', @$args);
	my @match;
	if ($instr =~ /eof/) {
		print_binary_instruction(0);
	} elsif (@match = $instr =~ /(load) (\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($match[0]), $match[1], $match[2]);
	} elsif ($instr =~ /(store) r(\d+) (\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2, $3);
	} elsif ($instr =~ /(literal) (\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2, $3);
	} elsif ($instr =~ /(input) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2);
	} elsif ($instr =~ /(output) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2);
	} elsif ($instr =~ /(add) r(\d+) r(\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2, $3, $4);
	} elsif ($instr =~ /(sub) r(\d+) r(\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2, $3, $4);
	} elsif ($instr =~ /(mul) r(\d+) r(\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2, $3, $4);
	} elsif ($instr =~ /(div) r(\d+) r(\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2, $3, $4);
	} elsif ($instr =~ /(cmp) r(\d+) r(\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2, $3, $4);
	} elsif ($instr =~ /(branch) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2);
	} elsif ($instr =~ /(jump) (\d) ([a-zA-Z]\w*)/) {
		if (exists($labels->{$3})) {
			print_binary_instruction(binary_opcode_from_string($1), $2, $labels->{$3});
		} else {
			die "Unknown label \"$3\"";
		}
	} elsif ($instr =~ /(jump) (\d) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1, $2, $3));
	} elsif ($instr =~ /(stack) (\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2);
	} elsif ($instr =~ /(supermandive)/) {
		print_binary_instruction(binary_opcode_from_string($1));
	} elsif ($instr =~ /(getup)/) {
		print_binary_instruction(binary_opcode_from_string($1));
	} elsif ($instr =~ /(print) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2);
	} elsif ($instr =~ /(draw) r(\d+) r(\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2, $3, $4);
	} elsif ($instr =~ /(keyboard) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1), $2);
	} elsif ($instr =~ /(heap) r(\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1, $2, $3));
	} elsif ($instr =~ /(unheap) r(\d+) r(\d+)/) {
		print_binary_instruction(binary_opcode_from_string($1, $2, $3));
	} else {
		die "Unknown instruction \"$instr\"";
	}
	print "\n";
}

sub binary_opcode_from_string {
	my %map = (
		'eof' => 0,
		'load' => 1,
		'store' => 2,
		'literal' => 3,
		'input' => 4,
		'output' => 5,
		'add' => 6,
		'sub' => 7,
		'mul' => 8,
		'div' => 9,
		'cmp' => 10,
		'branch' => 11,
		'jump' => 12,
		'stack' => 13,
		'supermandive' => 14,
		'getup' => 15,
		'print' => 16,
		'draw' => 17,
		'keyboard' => 18,
		'heap' => 19,
		'unheap' => 20,
	);
	return $map{$_[0]};
}

sub print_binary_instruction {
	my $i = 0;
	foreach (@_) {
		print sprintf('%04x ', $_);
		$i++;
	}
	foreach ($i..4 - 1) {
		print sprintf('%04x ', 0);
	}
}
