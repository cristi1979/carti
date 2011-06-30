package WikiTxtClean;

use Exporter 'import';
@EXPORT = qw(wiki_fix_chars wiki_get_images wiki_fix_small_issues wiki_fix_empty_center);

use warnings;
use strict;


sub wiki_fix_chars {
    my $wiki = shift;
    ## fix strange characters
    $wiki =~ s/\x{1f}//gsi;
    $wiki =~ s/\x{1e}//gsi;
    # copyright
    $wiki =~ s/\x{EF}\x{192}\x{A3}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{EF}\x{192}\x{201C}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{C3}\x{AF}\x{C6}\x{92}\x{E2}\x{80}\x{9C}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{a3}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{93}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{a3}/\x{C2}\x{A9}/gsi;
    ## registered
    $wiki =~ s/\x{EF}\x{192}\x{2019}/\x{C2}\x{AE}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{e2}\x{80}\x{99}/\x{C2}\x{AE}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{92}/\x{C2}\x{AE}/gsi;
    ## trademark
    $wiki =~ s/\x{EF}\x{192}\x{201D}/\x{E2}\x{84}\x{A2}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{e2}\x{80}\x{9d}/\x{E2}\x{84}\x{A2}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{94}/\x{E2}\x{84}\x{A2}/gsi;
    ## long line
    $wiki =~ s/\x{E2}\x{20AC}\x{201D}/\x{E2}\x{80}\x{93}/gsi;
    $wiki =~ s/\x{E2}\x{20AC}\x{201C}/\x{E2}\x{80}\x{93}/gsi;
    ## puiu / amanda
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{bf}/\x{e2}\x{97}\x{bb}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{bf}/\x{e2}\x{97}\x{bb}/gsi;
    ## RIGHTWARDS arrow
    $wiki =~ s/\x{EF}\x{192}\x{A8}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{E2}\x{2020}\x{2019}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{EF}\x{192}\x{A0}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{a8}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{a0}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{a0}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{ef}\x{80}\x{b0}/\x{e2}\x{86}\x{92}/gsi;
    ## LEFTWARDS arrow
    $wiki =~ s/\x{EF}\x{192}\x{178}/\x{e2}\x{86}\x{90}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c5}\x{b8}/\x{e2}\x{86}\x{90}/gsi;
    ## double arrow:
    $wiki =~ s/\x{EF}\x{192}\x{17E}/\x{e2}\x{87}\x{92}/gsi;
    ## 3 points
    $wiki =~ s/\x{E2}\x{20AC}\x{A6}/.../gsi;
    ## black circle
    $wiki =~ s/\x{EF}\x{201A}\x{B7}/\x{e2}\x{97}\x{8f}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{e2}\x{80}\x{9a}\x{c2}\x{b7}/\x{e2}\x{97}\x{8f}/gsi;
    $wiki =~ s/\x{ef}\x{82}\x{b7}/\x{e2}\x{97}\x{8f}/gsi;
    ## black square
    $wiki =~ s/\x{c3}\x{af}\x{e2}\x{80}\x{9a}\x{c2}\x{a7}/\x{e2}\x{96}\x{a0}/gsi;
    ## CHECK MARK
    $wiki =~ s/\x{EF}\x{81}\x{90}/\x{e2}\x{9c}\x{94}/gsi;
    $wiki =~ s/\x{EF}\x{192}\x{BC}/\x{e2}\x{9c}\x{94}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{bc}/\x{e2}\x{9c}\x{94}/gsi;
    ## BALLOT X
    $wiki =~ s/\x{EF}\x{81}\x{8F}/\x{e2}\x{9c}\x{98}/gsi;
    $wiki =~ s/\x{EF}\x{192}\x{BB}/\x{e2}\x{9c}\x{98}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{bb}/\x{e2}\x{9c}\x{98}/gsi;
    ## CIRCLE BACKSLASH
    $wiki =~ s/\x{EF}\x{81}\x{2014}/\x{e2}\x{9c}\x{98}/gsi;
    ## strange still: make some stars
    $wiki =~ s/\x{ef}\x{80}\x{b6}/\x{e2}\x{98}\x{85}/gsi;
    ## some strange spaces
    $wiki =~ s/\x{c2}\x{a0}/ /gsi;
    ## garbage it seems
    $wiki =~ s/\x{ef}\x{82}\x{bc}//gsi;
    $wiki =~ s/\x{c2}\x{ad}//gsi;

    return $wiki;
}

sub wiki_get_images {
    my ($wiki, $adir) = @_;
    my $final_wiki = $wiki;
    my $image_files = ();
    print "\tFix images from wiki.\n";
    while ($wiki =~ m/(\[\[Image:)([[:print:]].*?)(\]\])/g ) {
	my $full_img = $1;
	my $pic_name = uri_unescape( $2 );
	$pic_name =~ s/(.*?)(\|.*)/$1/;
	my $info = image_info("$adir/$pic_name");
	if (my $error = $info->{error}) {
	    print "Can't parse image info for dir \"$adir\", file \"$pic_name\":\n\t $error.\n";
# 	    die "" if $dir !~ m/CMS:MIND-IPhonEX CMS 80.00.020/;
	    my $temp = quotemeta($full_img);
# 	    $final_wiki =~ s/$temp//;
	    next;
	}
	push (@$image_files,  "$adir/$pic_name");
    }
    return ($final_wiki, $image_files);
}

sub wiki_fix_small_issues {
    my $wiki = shift;

    ## replace breaks
    $wiki =~ s/(<BR>)|(<br\ \/>)/\n\n/gmi;
    ## remove empty sub
    $wiki =~ s/<sub>[\s]{0,}<\/sub>//gsi;
    ## remove empty tables
    $wiki =~ s/\n\{\|.*\n+\|\}\n//gm;;
    $wiki =~ s/\r\n?/\n/gs;
    ## remove empty headings
    $wiki =~ s/\n=+\n/\n/gm;;
    ## remove consecutive blank lines
    $wiki =~ s/(\n){4,}/\n\n\n/gs;
    $wiki =~ s/^[ \t]+//mg;
    ## collapse spaces
    $wiki =~ s/[ \t]{2,}/ /mg;
    ## more new lines for menus and tables
    $wiki =~ s/^([ \t]*=+[ \t]*)(.*?)([ \t]*=+[ \t]*)$/\n\n$1$2$3\n/gm;
    $wiki =~ s/^\{\|(.*)$/\n\{\|$1 class="wikitable" /mg;
    $wiki =~ s/\|}\s*{\|/\|}\n\n\n{\|/mg;
    $wiki =~ s/^:*$//gm;
    $wiki =~ s/\-\-\-\-\n+=Note de subsol=\n*//m;
    ## me
    $wiki =~ s/<br_io><\/br_io>/<br \\>/gm;
#     $wiki =~ s/(<br \\>)+/<br \\>/mg;
    $wiki =~ s/<br \\><\/ref>/<\/ref>/mg;
    ### wiki specific
    ## strange stuff
    $wiki =~ s/\x{ef}\x{83}\x{b3}/<nowiki>***<\/nowiki>/gsi;
    ## semicolon start
    $wiki =~ s/^;/\n<nowiki>;<\/nowiki>/gm;
    ## dashes, lists
    $wiki =~ s/^\s*\*\s*$//gm;
    $wiki =~ s/^\s*((<font color="#[0-9]{6}">)?)\s*(\x{e2}\x{80}\x{93})\s*/\n$1\x{e2}\x{80}\x{94} /gm;
    $wiki =~ s/^\s*((<font color="#[0-9]{6}">)?)\s*(-{1,2})\s*([^-])/\n$1\x{e2}\x{80}\x{94} $4/gm;
    ## some bokks have dialogs as lists
    $wiki =~ s/^\s*((<font color="#[0-9]{6}">)?)\s*\*\s*/\n$1\x{e2}\x{80}\x{94} /gm;

    return $wiki;
}

sub wiki_fix_empty_center {
    my $wiki = shift;
    print "\t-Fix empty center.\n";
    $wiki =~ s/<center>(\s|<br \/>)*<\/center>//gms;
    $wiki =~ s/(<center>)\n*/\n$1/gm;
    $wiki =~ s/\n*(<\/center>)\n*/$1\n/gm;
    print "\t+Fix empty center.\n";

    return $wiki;
}

return 1;
