package Common;

use warnings;
use strict;

use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Basename;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Unicode::Normalize 'NFD','NFC','NFKD','NFKC';
use Archive::Zip qw( :ERROR_CODES );
use XML::Simple;
use Cwd 'abs_path';
use Encode;

sub xmlfile_to_hash {
    my $file = shift;
    my $xml = new XML::Simple;
    my $hash = $xml->XMLin("$file", SuppressEmpty => 1);
    $hash->{$_} = Encode::encode('utf8', $hash->{$_}) foreach (keys %$hash);
    return $hash;
}

sub hash_to_xmlfile {
    my ($hash, $name, $root_name) = @_;
    my ($file,$dir,$suffix) = fileparse("$name", qr/\.[^.]*/);
    makedir($dir);
    $root_name = "out" if ! defined $root_name;
    my %hash_copy = %$hash;
    $hash_copy{$_} = decode_utf8($hash_copy{$_}) foreach (keys %hash_copy);

    my $xs = new XML::Simple();
    unlink $name;
    my $xml = $xs->XMLout(\%hash_copy,
		    NoAttr => 1,
		    RootName=>$root_name,
		    OutputFile => $name,
		    SuppressEmpty => 1,
		    XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>'
		    );
#     $hash->{$_} = Encode::encode('utf8', $hash->{$_}) foreach (keys %$hash);
}

sub get_file_md5 {
    my $doc_file = shift;
    open(FILE, $doc_file) or die "Can't open '$doc_file': $!\n";
    binmode(FILE);
    my $doc_md5 = Digest::MD5->new->addfile(*FILE)->hexdigest;
    close(FILE);
    return $doc_md5;
}

sub add_file_to_zip {
    my ($zip_file, $add_file, $txt) = @_;
    my $member;

    my $zip = Archive::Zip->new();
    if (-f $zip_file){$zip->read("$zip_file") == AZ_OK or die "read error\n"};
    if (! defined $txt) {
	my ($name,$dir,$suffix) = fileparse($add_file, qr/\.[^.]*/);
	$zip->removeMember( "$name$suffix" );
	$member = $zip->addFile("$add_file", "$name$suffix") or die "Error adding file $name$suffix to zip";
    } else {
	$zip->removeMember( $add_file );
	$member = $zip->addString($txt, $add_file) or die "Error adding txt $add_file to zip";
    }
    $member->desiredCompressionLevel( 9 );
    if (-f $zip_file){
	$zip->overwrite()     == AZ_OK or die "write error\n"
    } else {
	$zip->writeToFileNamed( "$zip_file" ) == AZ_OK or die "write new zip error\n"
    };
}

sub read_file_from_zip {
    my ($zip_file, $read_file) = @_;
    my ($name,$dir,$suffix) = fileparse($read_file, qr/\.[^.]*/);

    my $zip = Archive::Zip->new();
    if (-f $zip_file){$zip->read("$zip_file") == AZ_OK or die "read error\n"};
    return $zip->contents($read_file);
}

our $str_append = "";
our $str_prepand = "";
sub my_print {
  my $message = shift;
  print "$str_prepand$message$str_append";
}
sub my_print_append {
  $str_append = shift;
}
sub my_print_prepand {
  $str_prepand = shift;
}

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

sub array_diff {
    print "-Compute difference and uniqueness.\n";
    my ($arr1, $arr2) = @_;
    my %seen = (); my @uniq1 = grep { ! $seen{$_} ++ } @$arr1; $arr1 = \@uniq1;
    %seen = (); my @uniq2 = grep { ! $seen{$_} ++ } @$arr2; $arr2 = \@uniq2;

    my (@only_in_arr1, @only_in_arr2, @common) = ();
## union: all, intersection: common, difference: unique in a and b
    my (@union, @intersection, @difference) = ();
    my %count = ();
    foreach my $element (@$arr1, @$arr2) { $count{"$element"}++ }
    foreach my $element (sort keys %count) {
	push @union, $element;
	push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
# 	push @difference, $element if $count{$element} <= 1;
    }
    print "\tdifference done.\n";

    my $arr1_hash = ();
    $arr1_hash->{$_} = 1 foreach (@$arr1);

    foreach my $element (@difference) {
	if (exists $arr1_hash->{$element}) {
	    push @only_in_arr1, $element;
	} else {
	    push @only_in_arr2, $element;
	}
    }
    print "+Compute difference and uniqueness.\n";
    return \@only_in_arr1,  \@only_in_arr2,  \@intersection;
}

sub makedir {
    my $dir = shift;
    my $err;
    make_path ("$dir", {error => \$err});
    if (@$err) {
	for my $diag (@$err) {
	    my ($file, $message) = %$diag;
	    if ($file eq '') { Common::my_print "general error: $message.\n"; }
	    else { Common::my_print "problem unlinking $file: $message.\n"; }
	}
	die "Can't make dir $dir: $!.\n";
    }
}

sub read_file {
    my $file = shift;
    open (FILEHANDLE, "$file") or die "Can't open for read file $file: ".$!."\n";
    my $txt = do { local $/; <FILEHANDLE> };
    close (FILEHANDLE);
    return $txt;
}

sub copy_dir {
    my ($from_dir, $to_dir) = @_;
    opendir my($dh), $from_dir or die "Could not open dir '$from_dir': $!";
    for my $entry (readdir $dh) {
#         next if $entry =~ /$regex/;
        my $source = "$from_dir/$entry";
        my $destination = "$to_dir/$entry";
        if (-d $source) {
	    next if $source =~ "\.?\.";
            mkdir $destination or die "mkdir '$destination' failed: $!" if not -e $destination;
            copy_dir($source, $destination);
        } else {
            copy($source, $destination) or die "copy failed: $source to $destination $!";
        }
    }
    closedir $dh;
    return;
}

sub move_dir {
    my ($src, $trg) = @_;
    die "\tTarget $trg is a file.\n" if (-f $trg);
    makedir("$trg", 1) if (! -e $trg);
    opendir(DIR, "$src") || die("Cannot open directory $src.\n");
    my @files = grep { (!/^\.\.?$/) } readdir(DIR);
    closedir(DIR);
    foreach my $file (@files){
	move("$src/$file", "$trg/$file") or die "Move file $src/$file to $trg failed: $!\n";
    }
    remove_tree("$src") || die "Can't remove dir $src.\n";
}

sub write_file {
    my ($path,$obj) = @_;
    my $text;
    if (ref($obj) eq 'HTML::TreeBuilder') {
	$text = HtmlClean::html_tidy($obj->as_HTML('<>&', "\t"));
    } elsif (ref($obj) eq '') {
	$text = $obj;
    } else {
	die "Trying to write type:\n".Dumper(ref($obj));
    }
    $text = Encode::encode('utf8', $text);
    my ($name,$dir,$suffix) = fileparse($path, qr/\.[^.]*/);
    Common::my_print "\tWriting file $name$suffix.\n";
    open (FILE, ">$path") or die "at generic write can't open file $path for writing: $!\n";
    ### don't decode/encode to utf8 ???
    print FILE "$text";
    close (FILE);
}

return 1;
