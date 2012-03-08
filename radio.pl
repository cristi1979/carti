#!/usr/bin/perl

use warnings;
use strict;

$SIG{__WARN__} = sub { die @_ };

use Cwd 'abs_path','chdir';
use File::Basename;

BEGIN {
    unless ($ENV{BEGIN_BLOCK}) {
	$ENV{BEGIN_BLOCK} = 1;
        exec 'env',$0,@ARGV;
    }
}

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
$mon += 1;
$mday += 1;
# print "$sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst";exit 1;
my $html_file = $ENV{"HOME"} . "/radio.html";
my $link = "http://www.radioromaniacultural.ro/program/?d=$year-$mon-$mday";
`wget $link -O $html_file -o /dev/null`;
use HTML::TreeBuilder;
use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Unicode::Normalize 'NFD','NFC','NFKD','NFKC';

sub normalize_text {
    my $str = shift;
    ## from http://www.ahinea.com/en/tech/accented-translate.html
    for ( $str ) {  # the variable we work on
	##  convert to Unicode first
	##  if your data comes in Latin-1, then uncomment:
	$_ = Encode::decode( 'utf8', $_ );

	s/\xe4/ae/g;  ##  treat characters ä ñ ö ü ÿ
	s/\xf1/ny/g;  ##  this was wrong in previous version of this doc
	s/\xf6/oe/g;
	s/\xfc/ue/g;
	s/\xff/yu/g;
	## various apostrophes   http://www.mikezilla.com/exp0012.html
	s/\x{02B9}/\'/g;
	s/\x{2032}/\'/g;
	s/\x{0301}/\'/g;
	s/\x{02C8}/\'/g;
	s/\x{02BC}/\'/g;
	s/\x{2019}/\'/g;

	$_ = NFD( $_ );   ##  decompose (Unicode Normalization Form D)
	s/\pM//g;         ##  strip combining characters

	# additional normalizations:

	s/\x{00df}/ss/g;  ##  German beta ß -> ss
	s/\x{00c6}/AE/g;  ##  Æ
	s/\x{00e6}/ae/g;  ##  æ
	s/\x{0132}/IJ/g;  ##  ?
	s/\x{0133}/ij/g;  ##  ?
	s/\x{0152}/Oe/g;  ##  
	s/\x{0153}/oe/g;  ##  

	tr/\x{00d0}\x{0110}\x{00f0}\x{0111}\x{0126}\x{0127}/DDddHh/; # ÐÐðdHh
	tr/\x{0131}\x{0138}\x{013f}\x{0141}\x{0140}\x{0142}/ikLLll/; # i??L?l
	tr/\x{014a}\x{0149}\x{014b}\x{00d8}\x{00f8}\x{017f}/NnnOos/; # ???Øø?
	tr/\x{00de}\x{0166}\x{00fe}\x{0167}/TTtt/;                   # ÞTþt

	s/[^\0-\x80]//g;  ##  clear everything else; optional
    }
    return Encode::encode( 'utf8', $str );  ;
}

# my $html = read_file("$html_file");
my $tree = HTML::TreeBuilder->new();
$tree = $tree->parse_file($html_file);
my $program = {};
my $last = "";
my @needs = (
    "Teatru National Radiofonic",
    "Teatru radiofonic - Mari spectacole",
    "Teatru radiofonic in serial",
    "Noptile Radio Romania Cultural. Teatru radiofonic in serial",
    "Spectacolele serii - Teatrul National Radiofonic",
    "Biografii, memorii",
    "Teatru scurt",
    "Jazz lexicon",
    "Jazz pe romaneste",
    "Titanii jazz-ului",
    "Muzica pe vinil",
    "A fost odata ca niciodata",
);
# my $pos = 0;

foreach my $a_tag ($tree->guts->look_down(_tag => "div",  class => "content program")) {
    foreach my $b_tag ($a_tag->look_down(_tag => "p")){
	my $txt = $b_tag->as_text;
	$txt = encode_utf8($txt);
	$txt = normalize_text($txt);
# 	$txt =~ s/\x{c2}\x{a0}/ /gsi;
	next if $txt =~ m/^\s+$/;
	print "linie necunoscuta: $txt.\n", next if $txt !~ m/^([0-9]{1,2}\.[0-9]{2})\s+(.*)$/;
	my ($ora, $nume) = ($1, $2);
	
	my $ok = 0;
	foreach my $want (@needs) {
	    if ($nume =~ m/$want/msi) {
		$ok ++;
		last;
	    }
	}
	$ora = "0".$ora if length $ora == 4;
	$nume = encode_utf8($nume);
	$nume =~ s/[^0-9a-z\.\- ]//ig;
	$nume =~ s/^(.{1,100})(.*)$/$1/;
	$program->{$ora}->{'titlu'} = $nume if $ok;
	$program->{$last}->{'sfarsit'} = $ora if $last ne "";
	$last = $ora;
    }
}
$program->{$last}->{'sfarsit'} = "23.59" if ! defined $program->{$last}->{'sfarsit'};

use Time::Local;
my $offset = 10;
my $reap = "HOME=".$ENV{"HOME"}."
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games
# m h dom mon dow command
45 23 * * * perl ".$ENV{"HOME"}."/radio.pl";

#time=timelocal($sec, $min, $hours, $day, $mon, $year)
foreach (sort keys %$program){
    if (defined $program->{$_}->{'titlu'}) {
	my ($hour_s, $min_s) = split /\./, $_;
	my ($hour_l, $min_l) = split /\./, $program->{$_}->{'sfarsit'};
	my $time1 = timelocal(00, $min_s, $hour_s, $mday, $mon, $year);
	my $time2 = timelocal(00, $min_l, $hour_l, $mday, $mon, $year);
	my $duration = $time2 - $time1 + 2*$offset*60;
	my ($secq,$minq,$hourq,$mdayq,$monq,$yearq,$wdayq,$ydayq,$isdstq) =                                                localtime($time1 - $offset*60);

	$reap .= "\n$minq $hourq $mdayq * * streamripper http://stream2.srr.ro:8012 -s -d \"/".$ENV{"HOME"}."/rrc/$year-$mon-$mday -- ".$program->{$_}->{'titlu'}."\" -l $duration > /dev/null 2>&1\n";
    } else {
	delete $program->{$_};
    }
}

my $crontab_file = $ENV{"HOME"}."/cron.txt";

open (FILE, ">$crontab_file") or die "at generic write can't open file $crontab_file for writing: $!\n";
print FILE "$reap";
close (FILE);

`crontab $crontab_file`;
unlink $html_file;
