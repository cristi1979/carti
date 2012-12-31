#!/usr/bin/perl -w
print "Start.\n";
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };

use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

my $file = shift;
open (FILEHANDLE, "$file") or die "at wiki from html Can't open file $file: ".$!."\n";
my $txt = do { local $/; <FILEHANDLE> };
close (FILEHANDLE);

## some strange chars
$txt =~ s/[^a-z0-9\n _:.,!?\-"=\$';*()&îăşţ—|\\\/^>»\s\[\]<~{}]//gmsi;

$txt =~ s/[{}|]//gmsi;

print Dumper($txt);