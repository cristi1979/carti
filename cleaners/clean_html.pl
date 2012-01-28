#!/usr/bin/perl -w
print "Start.\n";
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };
use HTML::TreeBuilder;
use Encode;
use HTML::Tidy;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

    my $file = shift;
    open (FILEHANDLE, "$file") or die "at wiki from html Can't open file $file: ".$!."\n";
    my $html = do { local $/; <FILEHANDLE> };
    close (FILEHANDLE);
    my $tree = HTML::TreeBuilder->new();
    $tree = $tree->parse_content(decode_utf8($html));

    my $name = "";
    foreach my $a_tag ($tree->guts->look_down(_tag => 'b')) {
# print Dumper($a_tag->as_text);
	if ($a_tag->as_text =~ m/^Max Solomon - LA 90 $/i){
	  $name = "Max Solomon - LA 90 ";
	  last;
	} elsif  ($a_tag->as_text =~ m/^Medita\x{163}iile lui Theophil Magus $/i){
	  $name = "Meditatiile lui Theophil Magus";
	  last;
	} elsif  ($a_tag->as_text eq "OPERE(TE) (IN)COMPLETE"){
	  $name = "OPERE(TE) (IN)COMPLETE";
	  last;
	} elsif  ($a_tag->as_text =~ m/^Iubiri in c\x{103}ma\x{15f}\x{103} de for\x{163}\x{103}$/i){
	  $name = "iubiri in camasa de forta";
	  last;
	} elsif  ($a_tag->as_text =~ m/^AUDIENTA 0$/i){
	  $name = "AUDIENTA 0";
	  last;
	} elsif  ($a_tag->as_text =~ m/^Adio, Europa! $/i){
	  $name = "Adio, Europa! ";
	  last;
	} elsif  ($a_tag->as_text =~ m/^LA CULES \x{ce}NGERI vol ..? $/i){
	  $name = "la cules ingeri";
	  last;
	}
    }
print "$name\n";

$_->delete foreach ($tree->guts->look_down(_tag => "hr"));
$_->delete foreach ($tree->guts->look_down(_tag => "noscript"));
$_->delete foreach ($tree->guts->look_down(_tag => "script"));
$_->replace_with_content foreach ($tree->guts->look_down(_tag => "table"));
$_->replace_with_content foreach ($tree->guts->look_down(_tag => "tr"));
$_->replace_with_content foreach ($tree->guts->look_down(_tag => "td"));
    foreach my $a_tag ($tree->guts->look_down(_tag => 'span')) {
print "w\n".Dumper($a_tag->as_text, $a_tag->as_HTML) if defined $a_tag;
print "q\n";
	if ($a_tag->as_text =~ m/^Editura LiterNet,? 200.\s*$/i || $a_tag->as_text =~ m/^Pagina urm\x{103}toare/i || $a_tag->as_text =~ m/^Continuare( \x{bb})?$/i) {
	    $a_tag->delete;
	    next;
	}
    }

    foreach my $a_tag ($tree->guts->look_down(_tag => 'div')) {
	$a_tag->delete if $a_tag->as_text =~ m/^Table of Contents/i || $a_tag->as_text =~ m/^Editura LiterNet, 200.\s*$/i;
    }


    foreach my $a_tag ($tree->guts->look_down(_tag => 'a')) {
# print Dumper($a_tag->as_text);
	$a_tag->delete if $a_tag->as_text eq "Prima pagin\x{103}" || $a_tag->as_text eq "Pagina anterioar\x{103}"
	       || $a_tag->as_text eq "Pagina urm\x{103}toare" || $a_tag->as_text =~ m/^Cuprins$/i
		|| $a_tag->as_text eq "Pagina urm\x{103}toare \x{bb}"  || $a_tag->as_text eq "Pagina precedent\x{103}";
	foreach my $attr_name ($a_tag->all_external_attr_names()) {
	    my $attr_value = $a_tag->attr($attr_name);
	    if ($attr_name eq "href" && ($attr_value =~ m/^http:\/\/editura.liternet.ro/i ||
				$attr_value =~ m/^mailto:/i)){
		$a_tag->delete;
		next;
	    }
	    $a_tag->replace_with_content if ($attr_name eq "href" && $attr_value =~ m/\.html?$/i);
	}
    }

    foreach my $a_tag ($tree->guts->look_down(_tag => 'img')) {
	foreach my $attr_name ($a_tag->all_external_attr_names()) {
	    my $attr_value = $a_tag->attr($attr_name);
	    if ($name eq "Max Solomon - LA 90 ") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000000.gif/i || $attr_value =~ m/^images\/000011.gif/i || $attr_value =~ m/^images\/000006.gif/i || $attr_value =~ m/^images\/000004.gif/i)
		);
	    } elsif ($name eq "Meditatiile lui Theophil Magus") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000008.gif/i || $attr_value =~ m/^images\/000018.gif/i || $attr_value =~ m/^images\/000006.gif/i || $attr_value =~ m/^images\/000011.gif/i || $attr_value =~ m/^images\/000003.gif/i)
		);
	    } elsif ($name eq "OPERE(TE) (IN)COMPLETE") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000003.gif/i || $attr_value =~ m/^images\/000010.gif/i
			  || $attr_value =~ m/^images\/000006.gif/i || $attr_value =~ m/^images\/000008.gif/i)
		);
	    } elsif ($name eq "iubiri in camasa de forta") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000003.gif/i || $attr_value =~ m/^images\/000006.gif/i || $attr_value =~ m/^images\/000004.gif/i)
		);
	    } elsif ($name eq "AUDIENTA 0") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000010.gif/i || $attr_value =~ m/^images\/000021.gif/i
		      || $attr_value =~ m/^images\/000009.gif/i || $attr_value =~ m/^images\/000020.gif/i || $attr_value =~ m/^images\/000011.gif/i)
		);
	    } elsif ($name eq "Adio, Europa! ") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000000.gif/i)
		);
	    } elsif ($name eq "la cules ingeri") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000013.gif/i || $attr_value =~ m/^images\/000017.gif/i ||
		      $attr_value =~ m/^images\/000004.gif/i || $attr_value =~ m/^images\/000006.gif/i || $attr_value =~ m/^images\/000007.gif/i)
		);
	    }
	}
    }

    $html = $tree->as_HTML('<>&', "\t");
    $tree = $tree->delete;
#     my $tidy = HTML::Tidy->new({ indent => "auto", tidy_mark => 0, doctype => 'omit',
# 	char_encoding => "raw", clean => 'yes', preserve_entities => 0});
#     $html = $tidy->clean($html);
    $html = Encode::encode('utf8', $html);
    open (FILE, ">$file.html") or die "at generic write can't open file for writing: $!\n";
    print FILE "$html";
    close (FILE);
