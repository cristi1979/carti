package HtmlClean;

use warnings;
use strict;
# use Exporter 'import';
our (@ISA, @EXPORT_OK);
BEGIN {
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(clean_html_from_oo);
}

use HTML::Tidy;
use URI::Escape;
use CSS::Tiny;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use HTML::TreeBuilder;
use HTML::TreeBuilder::XPath;
# use XML::LibXML;
use Cwd 'abs_path';
use File::Basename;
use Encode;
use Carti::Common;
my $counter = 0;

sub get_tree {
    my $html = shift;
    Common::my_print "\t".(++$counter)." Building html tree.\n";
    my $tree = HTML::TreeBuilder->new(api_version => 3);
    $tree = $tree->parse_content(decode_utf8($html));
    return $tree;
}

sub doc_tree_clean_css_from_oo {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean css from oo.\n";
    ## delete all css from oo
    foreach my $a_tag ($tree->guts->look_down(_tag => 'style')) {
	$a_tag->detach if (defined $a_tag->attr('type') && $a_tag->attr('type') eq "text/css");
    }

    my $css_txt = "p,table,li {line-height: 1.2em; font-size: .91em; margin: .5em;text-align:justify;}\n";
    $css_txt .= "table {margin: .5em;}\n";
    $css_txt .= "h1,h2,h3,h4,h5,h6,h7,h8 {text-align:center;}\n";
    my $style = HTML::Element->new('style');
    $style->push_content($css_txt);
    my $head = $tree->findnodes( '/html/head')->[0];
    $head->push_content($style);
#     $style->delete;
    return $tree;
}

sub doc_tree_clean_tables_attributes {
    my $a_tag = shift;
    Common::my_print "\t".(++$counter)." Clean table attributes.\n";
    ### clean table attributes
    foreach my $attr_name ($a_tag->all_external_attr_names){
	my $attr_value = $a_tag->attr($attr_name);
	if ( $attr_name eq "border"
		|| $attr_name eq "bordercolor"
		|| $attr_name eq "cellspacing"
		|| $attr_name eq "frame"
		|| $attr_name eq "rules"
		|| $attr_name eq "dir"
# 		|| $attr_name eq "bgcolor"
		|| $attr_name eq "align"
		|| $attr_name eq "style"
		|| $attr_name eq "cols"
# 			&& ( $attr_value =~ "page-break-(before|after|inside)")
		|| $attr_name eq "hspace"
		|| $attr_name eq "vspace"){
	    $a_tag->attr("$attr_name", undef);
	} elsif ($attr_name eq "cellpadding"
		|| $attr_name eq "width") {
	} else {
	    die "Unknown attr in table: $attr_name = $attr_value.\n";
	    return undef;
	}
    }
}

sub doc_tree_is_empty_p {
    my $tag = shift;
    foreach my $a_tag ($tag->content_list) {
	return 0  if (! ref $a_tag || (ref $a_tag && $a_tag->tag ne "br") );
    }
    return 1;
}

sub doc_tree_clean_tables {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean tables.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "table")) {
	### replace all headings with bold
	foreach my $b_tag ($a_tag->descendants()) {
	    if ($b_tag->tag =~ m/^h[0-9]{1,2}$/) {
		$b_tag->tag('b');
	    }
	}
	$a_tag->postinsert(['br']);
	$a_tag->preinsert(['br']);
	doc_tree_clean_tables_attributes($a_tag);
	### replace thead and tbody with content
	foreach my $b_tag ($a_tag->content_list){
	    if (ref $b_tag){
		my $tag = $b_tag->tag;
		if ( $tag eq "thead" || $tag eq "tbody"){
		    $b_tag->replace_with_content;
		}
	    }
	}

	### expect only col and tr
	foreach my $b_tag ($a_tag->content_list){
	    die "not reference in table\n" if ! ref $b_tag;
	    my $tag = $b_tag->tag;
	    if ( $tag eq "col" || $tag eq "colgroup"){
		$b_tag->detach;
	    } elsif ( $tag eq "tr" ){
		### clean tr attributes
		foreach my $attr_name ($b_tag->all_external_attr_names){
		    my $attr_value = $b_tag->attr($attr_name);
		    if ( $attr_name eq "valign"){
			$a_tag->attr("$attr_name", undef);
		    } elsif ( $attr_name eq "bgcolor") {
		    } else {
			die "Unknown attr in tr: $attr_name = $attr_value.\n";
			return undef;
		    }
		}
		### expect only td in tr
		my $has_content = 0;
		foreach my $c_tag ($b_tag->content_list){
		    die "not reference in tr\n" if ! ref $c_tag;
		    my $tag = $c_tag->tag;
		    die "Unknown tag in tr: $tag\n" if $tag ne "td" && $tag ne "th";
		    ### clean td attributes
		    foreach my $attr_name ($c_tag->all_external_attr_names){
			my $attr_value = $c_tag->attr($attr_name);
			if ( $attr_name eq "align"
				|| $attr_name eq "style"
				|| $attr_name eq "sdnum"
				|| $attr_name eq "sdval"
				|| $attr_name eq "valign"){
			    $c_tag->attr("$attr_name", undef);
			} elsif ($attr_name eq "bgcolor" || $attr_name eq "colspan" || $attr_name eq "rowspan"
				|| $attr_name eq "width"
				|| $attr_name eq "height") {
			} else {
			    die "Unknown attr in $tag: $attr_name = $attr_value.\n";
			}
		    }
		    ### remove empty td, add new lines
		    foreach my $d_tag ($c_tag->content_refs_list){
			if ( ref $$d_tag && ( $$d_tag->tag eq "p" || $$d_tag->tag eq "br") ) {
			    $$d_tag->postinsert(['br']) if $$d_tag->tag ne "br";
			    $has_content++ if $$d_tag->tag eq "p" && ! doc_tree_is_empty_p($$d_tag);
			} elsif ( ref $$d_tag ) {
			    $has_content++;
			} else {
			    $$d_tag =~ s/$/\n/gm;
			}
		    }
		    next if $has_content;
		    my $txt = $c_tag->as_text();
		    $txt =~ s/\s*//gs;
		    $has_content++ if ( $txt ne '');
		}
		$b_tag->detach if ( ! $has_content );
	    } else {
		die "Unknown tag in table: $tag.\n";
		return undef;
	    }
	}
    }
    return $tree;
}

sub doc_tree_clean_pre {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean pre.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "pre")) {
	die "\tActually I don't know what to do with pre.\n";
	foreach my $b_tag ($a_tag->content_refs_list){
	    die "strange pre.\n" if ref $$b_tag;
	    my $txt = $$b_tag;
	    my @lines = split "\n", $txt;
	    my $a_ref = HTML::Element->new('p');
	    foreach my $line (@lines) {
		if ($line !~ m/^\s*$/) {
		    $a_ref->push_content(['p'],$line);
		} else {
		    $a_ref->push_content(['br']);
		}
	    }
	    $a_tag->replace_with( $a_ref );
	}
    }
    return $tree;
}

sub doc_tree_fix_links_from_oo {
    my ($tree, $no_links) = @_;
    Common::my_print "\t".(++$counter)." Fix links.\n";

    my $images = {};
    my $first_image = 0;
    foreach (@{  $tree->extract_links()  }) {
	my($link, $element, $attr, $tag) = @$_;
	if ($tag eq "img" || $tag eq "body") {
	    foreach my $attr_name ($element->all_external_attr_names){
		my $attr_value = $element->attr($attr_name);
		if ( $attr_name eq "align" ){
		    $element->attr("$attr_name", undef);
		}
	    }
	    my $name_ext = Common::normalize_text(uri_unescape($link));
	    $name_ext =~ s/^\.\.\///;
	    my ($name,$dir,$ext) = fileparse($name_ext, qr/\.[^.]*/);
	    my $new_name = $name."_conv.jpg";
# 	    $images->{"$name$ext"}->{$first_image++} = "$new_name";
	    $images->{"$name$ext"}->{"name"} = "$new_name";
	    $images->{"$name$ext"}->{"nr"} = $first_image++;
	    $element->attr($attr, uri_escape $new_name);
	} elsif ($tag eq "a") {
	    $element->detach if $element->as_text =~ m/^\s*$/;
	} else {
	    $element->replace_with_content();
	    Common::my_print "\t".(++$counter)." Hey, there's tag $tag that links to ", $link, ", in its $attr attribute.\n";
	    die if $no_links;
	}
    }
    return ($tree, $images);
}

sub doc_find_unknown_elements {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Find unknown elements.\n";
    foreach my $a_tag ($tree->descendants()) {
	die "Unknown tag: ".$a_tag->tag."\n" if $a_tag->tag !~ m/^h[0-9]{1,2}$/ &&
	      $a_tag->tag !~ m/^(head|meta|font|p|div|br|a|dd|dl|dt|table|td|tr|title|i|img|span|sup|body|style|b|u|ul|ol|li|center|hr|blockquote|strike)$/;
    }
    return $tree;
}

sub doc_tree_remove_TOC {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean table of contents.\n";
    foreach my $a_tag ($tree->descendants()) {
	next if $a_tag->tag !~ m/^h[0-9]{1,2}$/;
	if (defined $a_tag->attr('class') && $a_tag->attr('class') eq "toc-heading-western" ){
	    Common::my_print "\t".(++$counter)." found TOC: ".$a_tag->attr('class')."\n" ;
	    $a_tag->detach;
	}
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => "div")) {
	if (defined $a_tag->attr('id') && $a_tag->attr('id') =~ m/^Table of Contents[0-9]$/ ){
	    Common::my_print "\t".(++$counter)." found TOC: ".$a_tag->attr('id')."\n" ;
	    $a_tag->detach;
	}
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => "multicol")) {
	if (defined $a_tag->attr('id') && $a_tag->attr('id') =~ m/^Alphabetical Index[0-9]$/ ){
	    Common::my_print "\t".(++$counter)." found index: ".$a_tag->attr('id')."\n" ;
	    $a_tag->detach;
	}
    }
    return $tree;
}

sub doc_tree_clean_defs {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean dd, dl, dt.\n";
    foreach my $a_tag ($tree->descendants()) {
	next if $a_tag->tag !~ m/^(dl|dd|dt)$/;
	$a_tag->replace_with_content;
    }
    return $tree;
}

sub doc_tree_clean_sub {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean sub.\n";
    $_->replace_with_content foreach ($tree->guts->look_down(_tag => 'sub'));
    return $tree;
}

sub doc_tree_clean_multicol {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean multicol.\n";
    $_->replace_with_content foreach ($tree->guts->look_down(_tag => 'multicol'));
    return $tree;
}

sub doc_tree_find_encoding {
    my $tree = shift;
    my $enc = "";
    Common::my_print "\t".(++$counter)." Find encoding.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => 'META')){
	if ( defined $a_tag->attr('HTTP-EQUIV') && $a_tag->attr('HTTP-EQUIV') eq "CONTENT-TYPE" ) {
	    if (defined $a_tag->attr('CONTENT') && $a_tag->attr('CONTENT') =~ m/^text\/html; charset=utf-8$/ ){
		$enc = "utf-8";
		Common::my_print "\t\t".(++$counter)." Found encoding: $enc.\n";
		last;
	    } else {
		die "Unknown encoding: ".($a_tag->attr('CONTENT'))."\n";
	    }
	}
    }
    return $enc;
}

sub doc_tree_clean_h {
    my ($tree, $br_io_fix) = shift;
    Common::my_print "\t".(++$counter)." Clean headings.\n";
    my @delete_later = ();
    foreach my $a_tag ($tree->descendants()) {
	next if $a_tag->tag !~ m/^h[0-9]{1,2}$/;
	if ($a_tag->as_text =~ m/^\s*$/) {
	    $a_tag->replace_with_content;
	    next;
	}
	my $tmp = 1;
	## stuff still there after first run
	while ($tmp){
	    $tmp = 0;
	    foreach my $b_tag ($a_tag->descendants()) {
		if ($b_tag->tag eq "a" ||
			$b_tag->tag eq "b" ||
			$b_tag->tag eq "strong" ||
			$b_tag->tag eq "i" ||
			$b_tag->tag eq "em" ||
			$b_tag->tag eq "u" ||
			$b_tag->tag eq "center" ||
			$b_tag->tag eq "font" ||
			$b_tag->tag eq "span" )  {
		    $b_tag->replace_with_content;
		} elsif ($b_tag->tag eq "br" && $br_io_fix) {
		    $b_tag->tag('br_io');
		}
	    }
	    foreach my $content_tag ($a_tag->content_refs_list) {
		if (ref $$content_tag) {
		    if ($$content_tag->tag eq "img") {
			my $img = $$content_tag->clone;
			$$content_tag->detach;
			my $p = HTML::Element->new('p');
			my $b = HTML::Element->new('br');
			$b->push_content($p);
			$b->push_content($img);
			$a_tag->postinsert($b);
		    } elsif ($$content_tag->tag eq "br_io" ||
			$$content_tag->tag eq "sup" ||
			$$content_tag->tag eq "ref") {
		    } elsif ($$content_tag->tag eq "table") {
			my $table = $$content_tag->clone;
			push @delete_later, $$content_tag;
# 			$$content_tag->delete;
			$a_tag->preinsert($table);
		    } else {
			die "heading: ".$$content_tag->tag.".\n".$a_tag->as_HTML.".\n"  if ref $$content_tag && $br_io_fix;
		    }
		} else {
		    $$content_tag =~ s/^\s*([0-9]{1,}\.)+\s*//;
# 		    $$$content_tag =~ s/^\s*[0-9]{1,}([a-z])\s*/$1/i;
		    $$content_tag =~ s/^\s*([0-9]{1,}\.)+[0-9]{1,}\s*//;
		    $$content_tag =~ s/^\s*[0-9]{1}\s+//;
# 		    die "$$content_tag\n";
		}
	    }
	}
    }
    $_->delete foreach (@delete_later);
    return $tree;
}

sub doc_tree_fix_paragraphs_start {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Fix paragraph start.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "p")) {
	foreach my $content_tag ($a_tag->content_refs_list) {
	    last if ref $$content_tag;
	    if ($$content_tag =~ m/^\s*[-\x{2015}\x{2013}\x{2014}]/i) {
# 		print "Fixing ".($a_tag->as_text).").\n";
		$$content_tag =~ s/^\s*(-|\x{2015}|\x{2013}|\x{2014})+\s*(\p{L})/\x{2014} $2/i;
		last;
	    }
#	    print "Paragraph starts with : ".(encode_utf8($$content_tag)).":$$content_tag (".($a_tag->as_text).").\n" if
#		      $a_tag->as_text !~ m/^\s*(\x{2014}|\x{a9}|\x{a3}|\x{25a0}|\x{2022}|\x{201c}|\x{2018}|\x{201e}|\x{2026}|\x{201d}|\x{be}|\x{a7}|\x{bb}|\x{ab})/i &&
#		      $a_tag->as_text !~ m/^\s*[\p{L} a-z0-9 !@#$%^&*()\[\]{};'\\:"|,\.\/<>\_?~`]/i &&
#		      $a_tag->as_text !~ m/^\s*$/i;
	}
    }
    return $tree;
}

sub doc_tree_remove_empty_font {
    my $tree = shift;
    my $worky = 1;
    while ($worky) {
	$worky = 0;
	Common::my_print "\t".(++$counter)." Remove empty font.\n";
	foreach my $a_tag ($tree->guts->look_down(_tag => "font")) {
	    if (! scalar $a_tag->all_external_attr_names) {
		$a_tag->replace_with_content ;
		$worky = 1;
	    }
	}
    }
    return $tree;
}

sub doc_tree_remove_empty_list {
    my $tree = shift;
    my $worky = 1;
    while ($worky) {
	$worky = 0;
	Common::my_print "\t".(++$counter)." Remove empty list.\n";
	foreach my $a_tag ($tree->guts->look_down(_tag => "li")) {
	    my $txt = $a_tag->as_text;
	    if ($txt =~ m/^\s*$/) {
		$a_tag->replace_with_content;
		$worky = 1;
	    }
	}
    }
    return $tree;
}

sub doc_tree_remove_empty_span {
    my $tree = shift;
    my $worky = 1;
    while ($worky) {
	$worky = 0;
	Common::my_print "\t".(++$counter)." Remove empty span.\n";
	foreach my $a_tag ($tree->guts->look_down(_tag => "span")) {
	    if (! scalar $a_tag->all_external_attr_names || $a_tag->as_text =~ m/^\s*$/) {
		$a_tag->replace_with_content ;
		$worky = 1;
	    }
	}
    }
    return $tree;
}

sub doc_tree_clean_font {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean font.\n";
    my $worky = 1;
    while ($worky) {
      $worky = 0;
      foreach my $a_tag ($tree->guts->look_down(_tag => "font")) {
# $a_tag->replace_with_content ;next;
	  foreach my $attr_name ($a_tag->all_external_attr_names()) {
	      my $attr_value = $a_tag->attr($attr_name);
	      next if ( $attr_name eq "color" );
	      if ( $attr_name eq "face"  ||
		  ($attr_name eq "style" && $attr_value =~ m/^font-size: [0-9]{1,}pt$/i ) || $attr_name eq "size"){
		  $a_tag->attr("$attr_name", undef);
		  $worky = 0;
  # 		next;
	      } else {
		  die "Attr name for font: $attr_name = $attr_value.\n";
	      }
	  }
	  if ($a_tag->as_text =~ m/^\s*$/) {
	      $a_tag->replace_with_content;
	      $worky = 0;
	  }
      }
    }
    return $tree;
}

sub doc_tree_clean_color {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean color.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "font")) {
	foreach my $attr_name ($a_tag->all_external_attr_names()) {
	    my $attr_value = $a_tag->attr($attr_name);
	    if ( $attr_name eq "color"){
		$a_tag->attr("$attr_name", undef);
		next;
	    }
	}
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => "span")) {
	foreach my $attr_name ($a_tag->all_external_attr_names()) {
	    my $attr_value = $a_tag->attr($attr_name);
	    if ( $attr_name eq "style") {
		my @attr = split ';', $attr_value;
		my $res = undef;
		foreach my $att (@attr) {
		    $res .= $att.";" if ($att !~ m/^\s*color: #[a-z0-9]{6}\s*$/i);
		}
		$a_tag->attr("$attr_name", $res);
	    }
	}
    }
    return $tree;
}

sub doc_tree_clean_span {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean span.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "span")) {
	my $imgs = "";
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    if ( $attr_name eq "style") {
		my @attr = split ';', $attr_value;
		my $res = undef;
		foreach my $att (@attr) {
		    if ($att =~ m/^\s*background: (#[0-9a-fA-F]{6}|transparent)\s*$/i
			|| $att =~ m/^\s*(font-(weight|style): (normal|italic))\s*$/i
			|| $att =~ m/^\s*color: #[a-z0-9]{6}\s*$/i
			|| $att =~ m/^\s*(width|height): [0-9.]{1,}(px|in|cm)\s*$/i ) {
			$res .= $att.";";
			$imgs = $1 if ($att =~ m/^\s*width: ([0-9.]{1,}(px|in|cm))\s*$/i);
		    } elsif ($att =~ m/^\s*background: #[0-9a-fA-F]{6} url(.*)\((.*)\)(.*)/i) {
# die "Attr name for background span_style = $att.\n";
			my $img = $2;
			my $p = HTML::Element->new('p');
			my $imge = HTML::Element->new('img');
			$imgs = $1*100 if ($imgs ne "" && $imgs =~ m/\s*(.*)(in|cm)\s*$/);
# 			$imgs = 500 if $imgs>500;
			$imge->attr("width", "$imgs") if $imgs ne "";
			$imge->attr("src", "$img");
			$p->push_content($imge);
			$a_tag->postinsert($p);
		    } else {
			next if $att =~ m/^\s*float: (top|left|right)\s*$/i
				    || $att =~ m/^\s*text-decoration:/i
				    || $att =~ m/^\s*font-variant: (small-caps|normal)\s*$/i
				    || $att =~ m/^\s*position: absolute\s*$/i
				    || $att =~ m/^\s*(top|left|right): -?[0-9]{1,}(\.[0-9]{1,})?(in|cm)\s*$/i
				    || $att =~ m/^\s*margin-(right): -?[0-9]{1,}(\.[0-9]{1,})?(in|cm)\s*$/i
				    || $att =~ m/^\s*(border|padding)/i
				    || $att =~ m/^\s*font-family:/i
				    || $att =~ m/^\s*so-language: /i
				    || $att =~ m/^\s*letter-spacing: /i
				    || $att =~ m/^\s*text-transform: uppercase$/i
				    || $att =~ m/^\s*font-size: [0-9]{1,}%\s*$/i;
die "Attr name for span_style = $att.\n";
			$res .= $att.";";
		    }
		}
		$a_tag->attr("$attr_name", $res);
	    } elsif ( $attr_name eq "id" ) {
	    } elsif ( $attr_name eq "class"
		    || $attr_name eq "dir" || $attr_name eq "lang") {
		$a_tag->attr("$attr_name", undef);
	    } else {
		die "Attr name for span: $attr_name = $attr_value.\n";
	    }
	}
    }
    return $tree;
}

sub doc_tree_fix_img {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Fix img.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "p")) {
	foreach my $content_tag ($a_tag->content_refs_list) {
	    if (ref $$content_tag) {
		if ($$content_tag->tag eq "img") {
		    my $img = $$content_tag->clone;
		    $$content_tag->detach;
			my $p = HTML::Element->new('p');
# 			my $b = HTML::Element->new('br');
# 			$b->push_content($p);
			$p->push_content($img);
# 			$a_tag->postinsert($b);
			$a_tag->postinsert($p);
		}
	    }
	}
    }
#     $_->delete foreach (@delete_later);
    return $tree;
}

sub doc_tree_clean_div {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean div.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "div")) {
	my $tag_name = $a_tag->tag;
	my $id = 0;
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    if ( ($attr_name eq "type" && $attr_value =~ m/^HEADER$/i)
		    || ($attr_name eq "type" && $attr_value =~ m/^FOOTER$/i)
		    || $attr_name eq "dir"
		    || $attr_name eq "lang"
		    || $attr_name eq "title"
		    || $attr_name eq "align") {
		$a_tag->attr("$attr_name", undef);
	    } elsif ($attr_name eq "style" ) {
	    } elsif ($attr_name eq "id" ) {
		$id++;
	    } else {
		die "Unknown tag in div: $attr_name = $attr_value\n";
	    }
	}
	my $nr_attr = scalar $a_tag->all_external_attr_names();
	$a_tag->replace_with_content() if ( ( $nr_attr == 1 && $id > 0) || $nr_attr == 0 );
    }
    return $tree;
}

sub doc_tree_clean_b_i {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean b,i.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "em")) {
	$a_tag->tag('i');
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => "strong")) {
	$a_tag->tag('b');
    }
    return $tree;
}

sub doc_tree_fix_paragraph {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Fix paragraph.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "p")) {
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    if ($attr_name eq "style") {
		my @attr_values = split ';', $attr_value;
		my $new_attr_value = "";
		foreach my $attr_val (@attr_values) {
		    if ($attr_val =~ m/^\s*margin-(top|bottom|left|right): -?([0-9]+\.)?[0-9]+(in|cm)\s*$/i
			  || $attr_val =~ m/^\s*(text-indent|padding): -?([0-9]+\.)?[0-9]+(in|cm)\s*$/i
			  || $attr_val =~ m/^\s*line-height: [0-9]+%\s*$/i
			  || $attr_val =~ m/^\s*(widows|orphans): [0-9]+\s*$/i
			  || $attr_val =~ m/^\s*border-(top|bottom|left|right): .+\s*$/i
			  || $attr_val =~ m/^\s*border: (([0-9]+\.)?[0-9]+pt\s*) double #[0-9a-f]{6}\s*$/i
			  || $attr_val =~ m/^\s*border: (none|-?([0-9]+\.)?[0-9]+px solid #[0-9a-f]{6})\s*$/i
			  || $attr_val =~ m/^\s*page-break-(after|before|inside): (avoid|always|auto)\s*$/i
			  || $attr_val =~ m/^\s*background: (#[0-9a-f]{6}|transparent)\s*$/i
			  || $attr_val =~ m/^\s*padding-(top|bottom|left|right): ([0-9]+\.)?[0-9]+(in|cm)\s*$/i
			  || $attr_val =~ m/^\s*padding: (([0-9]+\.)?[0-9]+(in|cm)\s*)+$/i
			  || $attr_val =~ m/^\s*line-height: ([0-9]+\.)?[0-9]+(in|cm)\s*$/i
			  || $attr_val =~ m/^\s*text-transform: uppercase$/i
			  || $attr_val =~ m/^\s*text-decoration: none\s*$/i
			  || $attr_val =~ m/^\s*letter-spacing: -?(([0-9]+\.)?[0-9]+pt\s*)+$/i
			  || $attr_val =~ m/^\s*letter-spacing: (normal|small-caps)\s*$/i
			) {
		    } elsif ($attr_val =~ m/^\s*font-(weight|style|variant): (normal|small-caps)\s*$/i) {
			$new_attr_value = "$new_attr_value;$attr_val";
		    } else {
			die "\t\tUnknown value for style in paragraph: $attr_val.\n";
		    }
		}
		undef $new_attr_value if $new_attr_value eq "";
		$a_tag->attr($attr_name, $new_attr_value);
	    } elsif ($attr_name eq "align") {
		die "\t\tUnknown value for align in paragraph: $attr_value.\n" if $attr_value !~ m/^(center|justify|left|right)$/i;
	    } elsif ($attr_name eq "lang" || $attr_name eq "class" || $attr_name eq "dir") {
		$a_tag->attr($attr_name, undef)
	    } else {
		die "\t\tUnknown attr in paragraph: $attr_name.\n";
	    }
	}
    }
    return $tree;
}

sub doc_tree_fix_center {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Fix centers.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "center")) {
	foreach my $b_tag ($a_tag->descendants) {
	    next if $b_tag->tag ne "center";
	    $b_tag->tag('p');
Common::write_file("./q.html", $tree->as_HTML('<>&', "\t"));
die "what the fuck is this?\n";
	}
    }
    return $tree;
}

sub doc_tree_fix_a {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Fix <a>.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "a")) {
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    $a_tag->replace_with_content if ( $attr_name =~ m/^href$/i);
	    $a_tag->attr($attr_name, undef) if ( $attr_name =~ m/^SDFIXED$/i);
	}
    }
    return $tree;
}

sub doc_tree_clean_body {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean script.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => 'body')) {
	foreach my $attr_name ($a_tag->all_external_attr_names()) {
	    $a_tag->attr("$attr_name", undef);
	}
    }
    return $tree;
}

sub clean_html_from_ms {
    my $html = shift;
    my $images = ();
    my $tree = get_tree($html);
    $html = $tree->as_HTML('<>&', "\t");
    $tree = $tree->delete;
    return ($html, $images);
}

use Devel::Size qw(size total_size);
my $colors = "no";
sub clean_html_from_oo {
    my ($html, $title, $work_dir) = @_;
    my $no_links = 0;
    ## this should be minus, but it's actually control character RS
    $html =~ s/\x{1e}/-/gsi;
    $html =~ s/\x{2}//gsi;
    $html =~ s/&shy;//g;
    $html =~ s/&nbsp;/ /g;
    my ($txt1, $txt2, $images);
    my $tree;
    eval{
    $tree = get_tree($html);
    my $enc = doc_tree_find_encoding($tree);
    $tree = doc_tree_remove_TOC($tree);
    $txt1 = $tree->as_trimmed_text;
#     start with fucking removing colors
    $tree = doc_tree_clean_color($tree) if $colors !~ m/^yes$/i;
    $tree = doc_tree_clean_font($tree);
    $tree = doc_tree_remove_empty_font($tree);
    $tree = doc_tree_clean_span($tree);
    $tree = doc_tree_remove_empty_span($tree);
    $tree = doc_tree_clean_defs($tree);
    $tree = doc_tree_clean_body($tree);
    $tree = doc_tree_fix_img($tree);
    ($tree, $images) = doc_tree_fix_links_from_oo($tree, $no_links);
#     $tree = doc_tree_clean_h($tree, 0);
    $tree = doc_tree_clean_div($tree);
    $tree = doc_tree_clean_multicol($tree);
    $tree = doc_tree_clean_b_i($tree);
    $tree = doc_tree_remove_empty_list($tree);
    $tree = doc_tree_clean_tables($tree);
    $tree = doc_tree_fix_center($tree);
    $tree = doc_tree_fix_paragraph($tree);
    $tree = doc_tree_fix_a($tree);
    $tree = doc_tree_clean_css_from_oo($tree);
    $tree = doc_tree_clean_sub($tree);
    $tree = doc_tree_clean_pre($tree);
# $html = $tree->as_HTML('<>&', "\t");Common::write_file("./html1.html", $html);
    $txt2 = $tree->as_trimmed_text;
    $tree = doc_tree_fix_paragraphs_start($tree);
    $tree = doc_find_unknown_elements($tree);
    };
    my $msg = $@;

    $html = $tree->as_HTML('<>&', "\t") || die "can't get html from tree\n";
    $tree = $tree->delete();
#     first clean up and after that die
    die Dumper($msg) if ($msg);
    $txt1 =~ s/\s+/\n/gm;$txt2 =~ s/\s+/\n/gm;
    if ($txt1 ne $txt2) {
	$txt1 =~ s/,/\n/g;    $txt2 =~ s/,/\n/g;
	Common::write_file("$work_dir/html2.html", $html);
	Common::write_file("$work_dir/txt1.txt", $txt1);
	Common::write_file("$work_dir/txt2.txt", $txt2);
	die "Text mismatch.\n";
    }
    return (html_tidy($html), $images);
}

sub html_tidy {
    my $html = shift;
    Common::my_print "\t".(++$counter)." Tidy up.\n";
    my $tidy = HTML::Tidy->new({ indent => "auto", tidy_mark => 0, doctype => 'omit',
	char_encoding => "raw", clean => 'yes', preserve_entities => 0});
    $html = $tidy->clean($html);
    my @msgs = $tidy->messages();
    undef($tidy);
    foreach (@msgs) {
	die $_ if $_->{'_text'} !~ m/^<style> inserting "type" attribute$/
		    && $_->{'_text'} !~ m/^trimming empty <(i|u|b|p|sup)>$/
		    && $_->{'_text'} !~ m/^nested emphasis <i>$/
		    && $_->{'_text'} !~ m/^<a> converting backslash in URI to slash$/
		    && $_->{'_text'} !~ m/^<table> lacks "summary" attribute$/
		    && $_->{'_text'} !~ m/^<img> lacks "alt" attribute$/
		    && $_->{'_text'} !~ m/^Document content looks like HTML 4.01 Strict$/
		    && $_->{'_text'} !~ m/^Document content looks like HTML 4.01 Transitional$/
		    && $_->{'_text'} !~ m/^<h[0-9]+> attribute "lang" lacks value$/
		    && $_->{'_text'} !~ m#^Doctype given is "-//W3C//DTD HTML 4.0 Transitional//EN"$#
		    && $_->{'_text'} !~ m/^Document content looks like HTML Proprietary$/
		    && $_->{'_text'} !~ m/^<a> cannot copy name attribute to id$/
		    && $_->{'_text'} !~ m/^<img> anchor "[a-z0-9_ ]+" already defined$/i
		    && $_->{'_text'} !~ m/^<img> cannot copy name attribute to id$/
		    && $_->{'_text'} !~ m/^inserting implicit <span>$/
		    && $_->{'_text'} !~ m/^missing <\/span> before <p>$/
		    && $_->{'_text'} !~ m/^missing <li>$/
		    && $_->{'_text'} !~ m/^missing optional end tag <\/li>$/
		    && $_->{'_text'} !~ m/^<div> proprietary attribute "type"$/
# 		    $_->{'_text'} !~ m/^<a> anchor "_[a-b]i[0-9]+" already defined$/i &&
# 		    ;
    }
    return $html;
}

return 1;
