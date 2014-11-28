#!/usr/bin/perl

exit main();

sub main {
	my $width = 32;
	my $depth = 4096;

	print "WIDTH=$width;\n";
	print "DEPTH=$depth;\n";
	print "ADDRESS_RADIX=UNS;\n";
	print "DATA_RADIX=HEX;\n";

	print "CONTENT BEGIN\n";
	nike($width, $depth, [<>]);
	print "END;\n";
}

sub nike {
	my $i = 0;
	foreach (@{$_[2]}) {
		$_ =~ s/\s+//g;
		print "\t$i: $_;\n";
		$i++;
	}
	my $end = $_[1] - 1;
	print "\t[$i..$end]: " . ('0' x ($_[0] / 8 * 2)) . ";\n";
}
