#!/bin/bash

./assembler.pl $1 | perl -e 'foreach (<>) { $_ =~ s/\s+//g; print($_); }' | xxd -r -p - $2
