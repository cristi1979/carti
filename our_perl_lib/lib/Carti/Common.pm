package Common;

# use Exporter qw( import );
# @EXPORT = qw(read_file copy_dir move_dir write_file);

use warnings;
use strict;

use File::Basename;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

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
	    if ($file eq '') { print "general error: $message.\n"; }
	    else { print "problem unlinking $file: $message.\n"; }
	}
	die "Can't make dir $dir: $!.\n";
    }
}

sub read_file {
    my $file = shift;
    open (FILEHANDLE, "$file") or die "at wiki from html Can't open file $file: ".$!."\n";
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
    print "\tWriting file $name$suffix.\n";
    open (FILE, ">$path") or die "at generic write can't open file $path for writing: $!\n";
    ### don't decode/encode to utf8 ???
    print FILE "$text";
    close (FILE);
}

return 1;
