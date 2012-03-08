#!/bin/perl
use File::Find;
use File::Copy;
my $script_dir = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";
use HTML::SimpleLinkExtor;
my $file = new HTML::SimpleLinkExtor();

# Extracts Links from a HTML File
# Written by Vaibhav Gupta guptav@cse.iitb.ac.in
$filename = $ARGV[0];
$url = $ARGV[1]; #base url else empty string

if($filename eq "" ) {
print "\nUsages: ./extractlink.pl filename.html\n";
exit ;
}

$file->parse_file($filename);
my @links= $file->a;
foreach $link (@links){
chomp;
print "$url$link\n";
}
