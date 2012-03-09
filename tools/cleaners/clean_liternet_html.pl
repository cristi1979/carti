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
	} elsif  ($a_tag->as_text =~ m/^Tudor Popescu - 4 comedii$/i){
	  $name = "Tudor Popescu - 4 comedii";
	  last;
	} elsif  ($a_tag->as_text =~ m/^3 PIESE CU FEMEI: LA NOROC, MELODIA PREFERAT\x{102}, NOI PERSPECTIVE...$/i){
	  $name = "3 PIESE CU FEMEI: LA NOROC, MELODIA PREFERATA, NOI PERSPECTIVE...";
	  last;
	} elsif  ($a_tag->as_text =~ m/^7 scenarii$/i){
	  $name = "7 scenarii";
	  last;
	} elsif  ($a_tag->as_text =~ m/^Nicole Sima .i Iuliana V.lsan - Povestea m.g.ru.ului$/i){
	  $name = "povestea magarusului";
	  last;
	} elsif  ($a_tag->as_text =~ m/^Iulian T.nase \/ IUBITAFIZICA$/i){
	  $name = "IUBITAFIZICA";
	  last;
	} elsif  ($a_tag->as_text =~ m/^CARTOGRAFII .N TRANZI.IE. Eseuri de sociologia artei .i literaturii$/i){
	  $name = "Eseuri de sociologia artei";
	  last;
	} elsif  ($a_tag->as_text =~ m/^Daniel Cristea-Enache :: Concert de deschidere$/i){
	  $name = "Concert de deschidere";
	  last;
	} elsif  ($a_tag->as_text =~ m/^Krikor H. Zambaccian - .nsemn.rile unui amator de art.$/i){
	  $name = "insemnarile unui amator de arta";
	  last;
	} elsif  ($a_tag->as_text =~ m/^Lumea lui Ciupicil. - Mofturici$/i){
	  $name = "Lumea lui Ciupicila - Mofturici";
	  last;
	} elsif  ($a_tag->as_text =~ m/^Radu .uculescu - Degetele lui Marsias$/i){
	  $name = "Degetele lui Marsias";
	  last;
	} elsif  ($a_tag->as_text =~  m/^A.P. Cehov - Livada de vi.ini\s*$/){
	  $name = "Livada de visini";
	  last;
	} elsif  ($a_tag->as_text =~  m/^George Banu - Livada de vi.ini, teatrul nostru\s*$/){
	  $name = "Livada de visini, teatrul nostru";
	  last;
	} elsif  ($a_tag->as_text =~  m/^Cartea Cuceririlor$/i){
	  $name = "Cartea Cuceririlor";
	  last;
	} elsif  ($a_tag->as_text =~  m/^Radu Cosasu - As time goes by $/i){
	  $name = "Radu Cosasu - As time goes by ";
	  last;
	} elsif  ($a_tag->as_text =~  m/^Bogdan Suceav. - Imperiul generalilor t.rzii$/i){
	  $name = "Imperiul generalilor";
	  last;
	}
    }

    foreach my $a_tag ($tree->guts->look_down(_tag => 'span')) {
	if ($a_tag->as_text =~ m/^Radu-Ilarion Munteanu\s*NISIP PESTE BORDUL NACELEI\s*$/i){
	  $name = "NISIP PESTE BORDUL NACELEI";
	  last;
	} elsif  ($a_tag->as_text =~  m/^Geta Pop \/ Editura \s*2004$/){
	  $name = "Scrisorile Getei";
	  last;
	} elsif ($a_tag->as_text =~  m/^Horia Bernea \x{a0}\x{a0}\x{a0} C\x{c2}TEVA G\x{c2}NDURI DESPRE MUZEU, CANTIT\x{102}\x{162}I, MATERIALITATE\s*\x{15e}I \x{ce}NCRUCI\x{15e}ARE  Irina Nicolau, Carmen Hulu\x{163}\x{103} \x{a0}\x{a0}\x{a0} DOSAR SENTIMENTAL$/i){
	  $name = "dosar sentimental";
	  last;
	} elsif ($a_tag->as_text =~  m/^Radu Cosa.u\s*UN AUGUST PE UN BLOC DE GHEA..$/i){
	  $name = "UN AUGUST PE UN BLOC DE GHEA";
	  last;
	} elsif  ($a_tag->as_text =~  m/^Alexandru Freiberg\s*MAESTRUL .I .OARECELE $/i){
	  $name = "maestrul si soarecele";
	  last;
	} elsif  ($a_tag->as_text =~  m/^Capul de zimbru$/i){
	  $name = "Capul de zimbru";
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
#     foreach my $a_tag ($tree->guts->look_down(_tag => 'span')) {
# 	$a_tag->delete if ($a_tag->as_text =~ m/^Editura LiterNet,? 200.\s*$/i || $a_tag->as_text =~ m/^Pagina urm\x{103}toare/i || $a_tag->as_text =~ m/^Continuare( \x{bb})?$/i);
#     }

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
		$a_tag->replace_with_content;
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
	    } elsif ($name eq "Tudor Popescu - 4 comedii") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000006.jpg/i)
		);
	    } elsif ($name eq "3 PIESE CU FEMEI: LA NOROC, MELODIA PREFERATA, NOI PERSPECTIVE...") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000007.jpg/i)
		);
	    } elsif ($name eq "7 scenarii") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000000.jpg/i)
		);
	    } elsif ($name eq "povestea magarusului") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000011.jpg/i)
		);
	    } elsif ($name eq "IUBITAFIZICA") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000002.jpg/i)
		);
	    } elsif ($name eq "Eseuri de sociologia artei") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000004.jpg/i)
		);
	    } elsif ($name eq "Concert de deschidere") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000001.jpg/i)
		);
	    } elsif ($name eq "insemnarile unui amator de arta") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000010.jpg/i)
		);
	    } elsif ($name eq "Lumea lui Ciupicila - Mofturici") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000022.gif/i || $attr_value =~ m/^images\/000029.gif/i || $attr_value =~ m/^images\/000012.gif/i)
		);
	    } elsif ($name eq "Degetele lui Marsias") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000009.jpg/i)
		);
	    } elsif ($name eq "NISIP PESTE BORDUL NACELEI") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000003.gif/i || $attr_value =~ m/^images\/000008.gif/i || $attr_value =~ m/^images\/000017.gif/i || $attr_value =~ m/^images\/000004.gif/i || $attr_value =~ m/^images\/000007.gif/i || $attr_value =~ m/^images\/000016.gif/i)
		);
	    } elsif ($name eq "Livada de visini") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000008.jpg/i)
		)
	    } elsif ($name eq "Livada de visini, teatrul nostru") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000009.jpg/i)
		);
	    } elsif ($name eq "Scrisorile Getei") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000003.gif/i)
		);
	    } elsif ($name eq "Cartea Cuceririlor") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000001.gif/i || $attr_value =~ m/^images\/000012.gif/i || $attr_value =~ m/^images\/000008.gif/i || $attr_value =~ m/^images\/000006.gif/i)
		);
	    } elsif ($name eq "dosar sentimental") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000007.gif/i || $attr_value =~ m/^images\/000001.gif/i || $attr_value =~ m/^images\/000010.gif/i || $attr_value =~ m/^images\/000008.gif/i || $attr_value =~ m/^images\/000006.gif/i || $attr_value =~ m/^images\/000009.gif/i)
		);
	    } elsif ($name eq "Radu Cosasu - As time goes by ") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000004.gif/i || $attr_value =~ m/^images\/000002.gif/i || $attr_value =~ m/^images\/000008.gif/i || $attr_value =~ m/^images\/000011.gif/i)
		);
	    } elsif ($name eq "UN AUGUST PE UN BLOC DE GHEA") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000007.gif/i || $attr_value =~ m/^images\/000015.gif/i || $attr_value =~ m/^images\/000001.gif/i || $attr_value =~ m/^images\/000004.gif/i || $attr_value =~ m/^images\/000002.gif/i || $attr_value =~ m/^images\/000013.gif/i || $attr_value =~ m/^images\/000008.gif/i)
		);
	    } elsif ($name eq "maestrul si soarecele") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000020.gif/i || $attr_value =~ m/^images\/000022.gif/i || $attr_value =~ m/^images\/000016.gif/i || $attr_value =~ m/^images\/000004.gif/i || $attr_value =~ m/^images\/000023.gif/i || $attr_value =~ m/^images\/000018.gif/i)
		);
	    } elsif ($name eq "Imperiul generalilor") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^images\/000009.jpg/i)
		);
	    } elsif ($name eq "Capul de zimbru") {
		$a_tag->delete if ($attr_name eq "src" &&
		    ($attr_value =~ m/^lpintiliezimbru1_files\/e05.gif/i)
		);
	    }
	}
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => 'div')) {
	$a_tag->delete if $a_tag->as_text =~ m/^Lumea lui Ciupicil\x{103} - MofturiciValentina Carmen Dinc\x{103} \/ Editura LiterNet 2004 $/;
	$a_tag->delete if $a_tag->as_text =~ m/^A.P. Cehov - Livada de vi.ini\s*$/;
	$a_tag->delete if $a_tag->as_text =~ m/^George Banu - Livada de vi.ini, teatrul nostru\s*$/;
	$a_tag->delete if $a_tag->as_text =~ m/^Radu Cosasu - As time goes by \s*$/;

    }
    foreach my $a_tag ($tree->guts->look_down(_tag => 'span')) {
# print Dumper($a_tag->as_text);
	$a_tag->delete if $a_tag->as_text =~ m/^Radu-Ilarion Munteanu\s*NISIP PESTE BORDUL NACELEI\s*$/i;
	$a_tag->delete if $name eq "Cartea Cuceririlor" && ($a_tag->as_text =~ m/^Cornel Ivanciuc \/ Editura LiterNet 2003$/i );
	$a_tag->delete if $a_tag->as_text =~ m/^Horia Bernea \x{a0}\x{a0}\x{a0} C\x{c2}TEVA G\x{c2}NDURI DESPRE MUZEU, CANTIT\x{102}\x{162}I, MATERIALITATE\s*\x{15e}I \x{ce}NCRUCI\x{15e}ARE  Irina Nicolau, Carmen Hulu\x{163}\x{103} \x{a0}\x{a0}\x{a0} DOSAR SENTIMENTAL$/i;
	$a_tag->delete if $name eq "UN AUGUST PE UN BLOC DE GHEA" && ($a_tag->as_text =~ m/^Radu Cosa.u\s*UN AUGUST PE UN BLOC DE GHEA..$/i );
	$a_tag->delete if $name eq "maestrul si soarecele" && ($a_tag->as_text =~ m/^Alexandru Freiberg \x{a0}\x{a0}\x{a0} MAESTRUL \x{15e}I \x{15e}OARECELE $/i );
	$a_tag->delete if $name eq "Imperiul generalilor" && ($a_tag->as_text =~ m/^Bogdan Suceav. - Imperiul generalilor t.rzii$/i );
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => 'strong')) {
# print Dumper($a_tag->as_text) if ($name eq "Cartea Cuceririlor");
	$a_tag->delete if $name eq "Cartea Cuceririlor" && ($a_tag->as_text =~ m/^Cornel Ivanciuc \/ Editura LiterNet 2003$/i || $a_tag->as_text =~ m/^CARTEA CUCERIRILOR$/i);
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
