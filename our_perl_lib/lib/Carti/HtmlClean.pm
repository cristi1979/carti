
package HtmlClean;

use warnings;
use strict;

use URI::Escape;
use CSS::Tiny;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use HTML::TreeBuilder::XPath;
use HTML::TreeBuilder;
# use XML::LibXML;
use Cwd 'abs_path';
use File::Basename;
use Encode;

sub get_tree {
    my $html = shift;
    my $tree = HTML::TreeBuilder->new();
    $tree = $tree->parse_content(decode_utf8($html));
    return $tree;
}
# selector  property:value
# h1	 {color:blue}
# . - class
# # - id
# : - ??
# the following rule matches any P element whose "class" attribute has been assigned a list of space-separated values that includes "pastoral" and "marine":
# p.marine.pastoral { color: green }
# sets the text color to blue whenever an EM occurs anywhere within an H1:
# h1 em { color: blue }

sub css_clean {
    my $file = shift;
    my $css = CSS::Tiny->new();
    $css = CSS::Tiny->read( "$file" );
    my @no_display = ();
    my @delete_selectors = ();
    foreach my $selector (keys %$css) {
	my $bad=0;
	foreach my $elem1 (split ' ', $selector) {
	    my @search = ();
	    foreach my $elem (split (/(?=[.:#])/, $elem1)) {
		$elem =~ s/^\s*//g;
		next if $elem =~ m/^\s*$/;
		my ($tag, $id, $class, $unknown);
		if ($elem =~ m/[^\.#:0-9a-z\-_]/i) {
		    $bad++;
		    last;
		}
		die "Unknown element: $elem\n" if $elem =~ m/[^\.#:0-9a-z\-_]/i;
		if ($elem =~ m/^\.(.*)$/){
		    $class = $1;
		    push @search, ("class", $class);
		} elsif ($elem =~ m/^#(.*)$/){
		    $id = $1;
		    push @search, ("id", $id);
		} elsif ($elem =~ m/^\-(.*)$/){
		    $unknown = $1;
		} else {
		    $tag = $elem;

		    push @search, ("_tag", $tag);
		}
		## we don't like links or html
		if (defined $tag && $tag =~ m/^(a|html)$/) {
		    push @delete_selectors, $selector;
		    $bad++;
		    last;
		}
	    }
	    next if $bad;
	    foreach (keys %{$css->{$selector}}){
		if ($_ eq "display" && $css->{$selector}->{$_} eq "none") {
		    push @no_display, \@search;
		    push @delete_selectors, $selector;
		    last;
		}
	    }
	}
    }
    delete $css->{$_} foreach @delete_selectors;

    return ($css, @no_display);
}

sub wiki_tree_clean_css {
    my ($tree, $work_dir) = @_;
    print "\tClean css.\n";
    my @css_files = ();
    foreach my $a_tag ($tree->guts->look_down(_tag => 'link')) {
	if (defined $a_tag->attr('rel') && $a_tag->attr('rel') eq "stylesheet") {
	    my $css_file = "$work_dir/".uri_unescape($a_tag->attr('href'));
	    push @css_files, $css_file if -s $css_file;
	}
    }

    my $css_txt = "";
    foreach my $a_tag ($tree->guts->look_down(_tag => 'style')) {
	if (defined $a_tag->attr('type') && $a_tag->attr('type') eq "text/css") {
	    $a_tag->detach;
	    $css_txt .= $_ foreach ($a_tag->content_list());
	}
    }

    $css_txt .= Common::read_file("$_"), unlink "1".$_ foreach (@css_files);
    $css_txt .= 'p,table,li {line-height: 1.2em; font-size: .91em; margin: .5em;text-align:justify;}';
#     $css_txt .= "p,table {text-indent: 2.0em;text-align:justify}";
    $css_txt .= 'table.wikitable {margin: .5em;}';
    $css_txt .= 'h1,h2,h3,h4,h5,h6,h7,h8 {text-align:center;}';
    $css_txt =~ s/\@media only screen and \(max-device-width:[0-9]+px\){body{-webkit-text-size-adjust:none}}//gm;
    $css_txt =~ s/\@media handheld\s*\{//gm;
    $css_txt =~ s/\@media screen,handheld{//gm;
    $css_txt =~ s/}}//gm;
    Common::write_file("$work_dir/css_file.css", $css_txt);
    $css_txt = `csstidy "$work_dir/css_file.css" --silent=true --discard_invalid_properties=true --merge_selectors=1`;
    Common::write_file("$work_dir/css_file.css", $css_txt);
    push @css_files, "$work_dir/css_file.css";
    my ($css, @no_display) = css_clean("$work_dir/css_file.css");

    foreach (@no_display) {
	foreach my $a_tag ($tree->guts->look_down( @$_ )) {
	    $a_tag->delete;
	}
    }
    my $html_css = HTML::Element->new('~literal', 'text' => $css->write_string());
    my $style = HTML::Element->new('style');
    $style->push_content($html_css);
    my $head = $tree->findnodes( '/html/head')->[0];
    $head->push_content($style);
    unlink "$_" foreach (@css_files);

    return $tree;
}

sub doc_tree_clean_css_from_oo {
    my ($tree, $work_dir) = @_;
    print "\tClean css.\n";
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
    return $tree;
}

sub doc_tree_clean_tables_attributes {
    my $a_tag = shift;
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
    print "\tClean tables.\n";
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
		    die "Unknown tag: $tag\n" if $tag ne "td" && $tag ne "th";
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

sub wiki_tree_clean_pre {
    my $tree = shift;
    print "\tClean pre.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "pre")) {
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

sub doc_tree_clean_pre {
    my $tree = shift;
    print "\tClean pre.\n";
    $_->replace_with_content foreach ($tree->guts->look_down(_tag => "pre"));
    return $tree;
}

sub wiki_tree_clean_wiki {
    my $tree = shift;
    print "\tClean wiki.\n";
    my @to_delete = ();
    push @to_delete, $tree->guts->look_down(_tag => 'link');
    push @to_delete, $tree->guts->look_down(_tag => 'meta');
    my $meta = HTML::Element->new("meta", 'http-equiv' => "Content-Type", 'content' => "text/html; charset=utf-8");
    my $elem = $tree->findnodes( '/html/head')->[0];
    $elem->preinsert($meta);

    $elem = $tree->findnodes( '//div[@id="content"]')->[0];
    $elem->replace_with_content;
    $elem = $tree->findnodes( '//div[@id="bodyContent"]')->[0];
    $elem->replace_with_content;

    push @to_delete, $tree->findnodes( '//div[@id="footer"]');
    push @to_delete, $tree->findnodes( '//div[@class="portal"]');
    push @to_delete, $tree->findnodes( '//div[@id="siteSub"]');
    push @to_delete, $tree->findnodes( '//div[@id="contentSub"]');
    push @to_delete, $tree->findnodes( '//div[@id="catlinks"]');
    push @to_delete, $tree->findnodes( '//div[@class="printfooter"]');
    push @to_delete, $tree->findnodes( '//span[@id="External_links"]');
    push @to_delete, $tree->findnodes( '//div[@id="section_SpokenWikipedia"]');
    push @to_delete, $tree->findnodes( '//table[@class="metadata mbox-small plainlinks"]');
    foreach my $elem ($tree->guts->descendants()) {
	foreach my $attr_name ($elem->all_external_attr_names()) {
	    next if $attr_name ne "style";
	    foreach my $val (split ';', $elem->attr($attr_name)) {
		next if $val !~ m/^\s*display\s*:\s*none\s*$/;
		$elem->delete;
	    }
	}
    }

    $_->delete foreach @to_delete;
    return $tree;
}

sub wiki_tree_fix_links {
    my ($tree, $wiki_site) = @_;
    my @images = ();
    print "\tFix links from wiki.\n";
    my $refs;
    foreach (@{  $tree->extract_links()  }) {
	my($link, $element, $attr, $tag) = @$_;
	if ($tag eq "img") {
	    push @images, $link;
	} elsif ($tag eq "a") {
	    if ($link =~ m/^$wiki_site/) {
		$element->replace_with_content;
	    } elsif ($link =~ m/#(.*)?$/) {
		my $orig = "#$1";
		my $new_name = $orig;
		$new_name =~ s/:/_/gi;
		$orig =~ s/^#//;
		$refs->{$orig} = $new_name if $new_name ne "#".$orig;
		die "check name $new_name.\n" if $new_name =~ m/[^a-z0-9_\-\.#]/i;
		my $name = $element->attr("name");
		my $href = $element->attr("href");
		die "check href: $attr.\n" if $attr ne "href";
		die "check name $name.\n" if defined $name;
		$element->attr($attr, "$new_name");
	    } else {
		die "Hey, there's tag $tag that links to ", $link, ", in its $attr attribute.\n";
	    }
	} else {
	    die "Hey, there's tag $tag that links to ", $link, ", in its $attr attribute.\n";
	}
    }

    foreach my $a_tag ($tree->descendants()) {
	foreach my $attr_name ($a_tag->all_external_attr_names()) {
	    my $attr_value = $a_tag->attr($attr_name);
	    next if ! defined $refs->{$attr_value};
	    die "unknown attribute: $attr_name.\n" if $attr_name ne "id";
	    my $value = $refs->{$attr_value};
	    $value =~ s/^#//;
	    $a_tag->attr($attr_name, $value);
	    delete $refs->{$attr_value};
	}
    }
    die Dumper($refs) if scalar keys %$refs;
    return $tree, \@images;
}

sub wiki_tree_clean_body {
    my $tree = shift;
    print "\tClean script.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => 'body')) {
	foreach my $attr_name ($a_tag->all_external_attr_names()) {
	    $a_tag->attr("$attr_name", undef);
	}
    }
    return $tree;
}

sub wiki_tree_clean_script {
    my ($tree, $work_dir) = @_;
    print "\tClean script.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => 'script')) {
	my $file = $a_tag->attr("src");
	unlink "$work_dir/".uri_unescape($file) if defined $file;
	$a_tag->delete;
    }
    return $tree;
}

# A NAME="sdfootnote122anc" HREF="#sdfootnote122sym" CLASS="sdfootnoteanc"
# DIV ID="sdfootnote122"
# A NAME="sdfootnote122sym" HREF="#sdfootnote122anc" CLASS="sdfootnotesym-western"

# A NAME="_ftnref11" HREF="#_ftn11"
# DIV ID="ftn11" DIR="LTR">
# A NAME="_ftn11" HREF="#_ftnref11"

# <A NAME="cite_ref-0"></A>
# <A HREF="#cite_note-0"><FONT COLOR="#7030a0"><SUP>[1]</SUP></FONT></A>
# <A NAME="cite_note-0"></A>
# <A HREF="#cite_ref-0">↑</A>
sub doc_tree_fix_links_for_wiki {
    my ($tree, $no_links) = @_;
    print "\tFix links and notes for wiki.\n";
    my $ref_hash = {};
    my $footnote = {};
    $footnote->{'1'} = [qr/sdfootnote([0-9]{1,})anc/, qr/sdfootnote([0-9]{1,})sym/];
    $footnote->{'2'} = [qr/_ftnref([0-9]{1,})/, qr/_ftn([0-9]{1,})/];
    $footnote->{'3'} = [qr/cite_ref-([0-9]{1,})/, qr/cite_note-([0-9]{1,})/];

    my $images = {};
    foreach (@{  $tree->extract_links()  }) {
	my($link, $element, $attr, $tag) = @$_;
	if ($tag eq "img" || $tag eq "body") {
	    my $name_ext = Common::normalize_text(uri_unescape($link));
	    $name_ext =~ s/^\.\.\///;
	    my ($name,$dir,$ext) = fileparse($name_ext, qr/\.[^.]*/);
	    my $new_name = $name."_conv.jpg";
	    $images->{"$name$ext"} = "$new_name";
	    $element->attr($attr, uri_escape $new_name);
	} elsif ($tag eq "a") {
	    my $is_footnote = 0;
	    foreach (keys %$footnote){
		my $anc = $footnote->{$_}[0];
		my $sym = $footnote->{$_}[1];
		$ref_hash->{$1}->{'h_anc'} = $element if ($link =~ m/^#$anc$/);
		$ref_hash->{$1}->{'n_anc'} = $element if ($link =~ m/^$anc$/);
		$ref_hash->{$1}->{'h_sym'} = $element if ($link =~ m/^#$sym$/);
		$ref_hash->{$1}->{'n_sym'} = $element if ($link =~ m/^$sym$/);
		$is_footnote = $_, last if $link =~ m/^#$anc$/ || $link =~ m/^#$sym$/;
	    }
	    if (! $is_footnote){
		$element->replace_with_content();
		die "Unknown a: $link with attr $attr\n" if $no_links;
	    }
	} else {
	    $element->replace_with_content();
	    print "Hey, there's tag $tag that links to ", $link, ", in its $attr attribute.\n";
	    die if $no_links;
	}
    }
    foreach my $nr (sort keys %$ref_hash) {
	die "Strange ref nr $nr.\n" if !defined $ref_hash->{$nr}->{'h_anc'} || !defined $ref_hash->{$nr}->{'h_sym'};
	my $txt;
	$txt = ($ref_hash->{$nr}->{'h_anc'}->look_up("_tag", 'p'))[0];
# print Dumper($nr);
	if (! defined $txt) {
	    $txt = ($ref_hash->{$nr}->{'h_anc'}->look_up("_tag", 'h6'))[0];
	    $txt = ($ref_hash->{$nr}->{'h_anc'}->look_up("_tag", 'h1'))[0] if ! defined $txt;
	    $txt->tag('p');
	}
	my $a_ref = HTML::Element->new('ref');
	my $have_text = 0;
	if ($txt->parent->tag eq "div" && defined $txt->parent->attr('id') &&
		($txt->parent->attr('id') =~ m/^sdfootnote/ || $txt->parent->attr('id') =~ m/^Section/)) {
	    $txt = $txt->parent;
	    foreach my $a_tag ($txt->look_down(_tag => 'p')) {
		my $tmp = $a_tag->as_text;
		$a_tag->detach;
		$tmp =~ s/^\s*([0-9]+-?|\x{e2}\x{86}\x{91}|\x{5e})\s+//;
		next if $tmp =~ m/^\s+$/gsm;
		$a_ref->push_content($tmp, ['br_io']);
		$have_text++;
	    }
	} else {
	    die "still fixing notes.\n";
	}
	die "reference empty.\n" if ! $have_text;
	$ref_hash->{$nr}->{'h_sym'}->replace_with( $a_ref ) if $have_text;
    }

    return ($tree, $images);
}

sub doc_tree_fix_links_from_oo {
    my ($tree, $no_links) = @_;
    print "\tFix links.\n";

    my $images = {};
    foreach (@{  $tree->extract_links()  }) {
	my($link, $element, $attr, $tag) = @$_;
	if ($tag eq "img" || $tag eq "body") {
	    my $name_ext = Common::normalize_text(uri_unescape($link));
	    $name_ext =~ s/^\.\.\///;
	    my ($name,$dir,$ext) = fileparse($name_ext, qr/\.[^.]*/);
	    my $new_name = $name."_conv.jpg";
	    $images->{"$name$ext"} = "$new_name";
	    $element->attr($attr, uri_escape $new_name);
	} elsif ($tag eq "a") {
	} else {
	    $element->replace_with_content();
	    print "Hey, there's tag $tag that links to ", $link, ", in its $attr attribute.\n";
	    die if $no_links;
	}
    }
    return ($tree, $images);
}

sub doc_find_unknown_elements {
    my $tree = shift;
    print "\tFind unknown elements.\n";
    foreach my $a_tag ($tree->descendants()) {
	die "Unknown tag: ".$a_tag->tag."\n" if $a_tag->tag !~ m/^h[0-9]{1,2}$/ &&
	      $a_tag->tag !~ m/^(head|meta|font|p|div|br|a|dd|dl|dt|table|td|tr|title|i|img|span|sup|body|style|b|u|ul|ol|li|center|sub)$/;
    }
    return $tree;
}

sub doc_tree_remove_TOC {
    my $tree = shift;
    print "\tClean table of contents.\n";
    foreach my $a_tag ($tree->descendants()) {
	next if $a_tag->tag !~ m/^h[0-9]{1,2}$/;
	if (defined $a_tag->attr('class') && $a_tag->attr('class') eq "toc-heading-western" ){
	    print "\tfound TOC: ".$a_tag->attr('class')."\n" ;
	    $a_tag->detach;
	}
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => "div")) {
	if (defined $a_tag->attr('id') && $a_tag->attr('id') =~ m/^Table of Contents[0-9]$/ ){
	    print "\tfound TOC: ".$a_tag->attr('id')."\n" ;
	    $a_tag->detach;
	}
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => "multicol")) {
	if (defined $a_tag->attr('id') && $a_tag->attr('id') =~ m/^Alphabetical Index[0-9]$/ ){
	    print "\tfound index: ".$a_tag->attr('id')."\n" ;
	    $a_tag->detach;
	}
    }
    return $tree;
}

sub doc_tree_clean_defs {
    my $tree = shift;
    print "\tClean dd, dl, dt.\n";
    foreach my $a_tag ($tree->descendants()) {
	next if $a_tag->tag !~ m/^(dl|dd|dt)$/;
	$a_tag->replace_with_content;
    }
    return $tree;
}

sub doc_tree_clean_sub {
    my $tree = shift;
    print "\tClean sub.\n";
    $_->replace_with_content foreach ($tree->guts->look_down(_tag => 'sub'));
    return $tree;
}

sub doc_tree_clean_multicol {
    my $tree = shift;
    print "\tClean multicol.\n";
    $_->replace_with_content foreach ($tree->guts->look_down(_tag => 'multicol'));
    return $tree;
}

# sub doc_tree_clean_sub {
#     my $tree = shift;
#     print "\tClean empty sub.\n";
#     foreach my $a_tag ($tree->guts->look_down(_tag => "sub")) {
# 	$a_tag->replace_with_content if ($a_tag->as_text =~ m/^\s*$/);
#     }
#     return $tree;
# }

sub doc_tree_find_encoding {
    my $tree = shift;
    my $enc = "";
    print "\tFind encoding.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => 'META')){
	if ( defined $a_tag->attr('HTTP-EQUIV') && $a_tag->attr('HTTP-EQUIV') eq "CONTENT-TYPE" ) {
	    if (defined $a_tag->attr('CONTENT') && $a_tag->attr('CONTENT') =~ m/^text\/html; charset=utf-8$/ ){
		$enc = "utf-8";
		print "\t\tFound encoding: $enc.\n";
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
    print "\tClean headings.\n";
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

sub doc_tree_remove_empty_font {
    my $tree = shift;
    my $worky = 1;
    while ($worky) {
	$worky = 0;
	print "\tRemove empty font.\n";
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
	print "\tRemove empty list.\n";
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
	print "\tRemove empty span.\n";
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
    print "\tClean font.\n";
    my $worky = 1;
    while ($worky) {
      $worky = 0;
      foreach my $a_tag ($tree->guts->look_down(_tag => "font")) {
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
    print "\tClean color.\n";
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
    print "\tClean span.\n";
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
			|| $att =~ m/^\s*(width|height): [0-9.]{1,}(px|in)\s*$/i ) {
			$res .= $att.";";
			$imgs = $1 if ($att =~ m/^\s*width: ([0-9.]{1,}(px|in))\s*$/i);
		    } elsif ($att =~ m/^\s*background: #[0-9a-fA-F]{6} url(.*)\((.*)\)(.*)/i) {
# die "Attr name for background span_style = $att.\n";
			my $img = $2;
			my $p = HTML::Element->new('p');
			my $imge = HTML::Element->new('img');
			$imgs = $1*100 if ($imgs ne "" && $imgs =~ m/\s*(.*)in\s*$/);
# 			$imgs = 500 if $imgs>500;
			$imge->attr("width", "$imgs") if $imgs ne "";
			$imge->attr("src", "$img");
			$p->push_content($imge);
			$a_tag->postinsert($p);
		    } else {
			next if $att =~ m/^\s*float: (top|left|right)\s*$/i
				    || $att =~ m/^\s*text-decoration:/i
				    || $att =~ m/^\s*position: absolute\s*$/i
				    || $att =~ m/^\s*(top|left|right): -?[0-9]{1,}(\.[0-9]{1,})?in\s*$/i
				    || $att =~ m/^\s*(border|padding)/i
				    || $att =~ m/^\s*font-family:/i
				    || $att =~ m/^\s*so-language: /i
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

sub doc_tree_clean_div {
    my $tree = shift;
    print "\tClean div.\n";
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
    print "\tClean b,i.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "em")) {
	$a_tag->tag('i');
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => "strong")) {
	$a_tag->tag('b');
    }
    return $tree;
}

sub doc_tree_fix_paragraph_center {
    my $tree = shift;
    print "\tFix paragraph centers.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "p")) {
	my $exists_center = 0;
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    $exists_center++ if $attr_name eq "align" && $attr_value =~ m/center/i;
	    $a_tag->attr($attr_name, undef);
	}
	if ($exists_center) {
	    my $center = HTML::Element->new('center');
	    $center->push_content($a_tag->clone);
	    $a_tag->preinsert($center);
	    $a_tag->detach;
	}
    }
    return $tree;
}

sub doc_tree_fix_paragraph {
    my $tree = shift;
    print "\tFix paragraph.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "p")) {
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    if ($attr_name eq "style") {
		my @attr_values = split ';', $attr_value;
		foreach my $attr_val (@attr_values) {
		    if ($attr_val =~ m/^\s*margin-(top|bottom|left|right): -?([0-9]+\.)?[0-9]+in\s*$/i
			  || $attr_val =~ m/^\s*(text-indent|padding): -?([0-9]+\.)?[0-9]+in\s*$/i
			  || $attr_val =~ m/^\s*line-height: [0-9]+%\s*$/i
			  || $attr_val =~ m/^\s*(widows|orphans): [0-9]+\s*$/i
			  || $attr_val =~ m/^\s*border-(top|bottom|left|right): .+\s*$/i
			  || $attr_val =~ m/^\s*text-decoration: none\s*$/i
			  || $attr_val =~ m/^\s*border: (none|-?([0-9]+\.)?[0-9]+px solid #[0-9a-f]{6})\s*$/i
			  || $attr_val =~ m/^\s*page-break-(after|before|inside): (avoid|always|auto)\s*$/i
			  || $attr_val =~ m/^\s*background: (#[0-9a-f]{6}|transparent)\s*$/i
			  || $attr_val =~ m/^\s*padding-(top|bottom|left|right): ([0-9]+\.)?[0-9]+in\s*$/i
			  || $attr_val =~ m/^\s*padding: (([0-9]+\.)?[0-9]+in\s*)+$/i
			  || $attr_val =~ m/^\s*line-height: ([0-9]+\.)?[0-9]+in\s*$/i
			) {
			$a_tag->attr($attr_name, undef);
		    } elsif ($attr_val =~ m/^\s*font-(weight|style): normal\s*$/i) {
		    } else {
			die "\t\tUnknown value for style in paragraph: $attr_val.\n";
		    }
		}
	    } elsif ($attr_name eq "align") {
		die "\t\tUnknown value for align in paragraph: $attr_value.\n" if $attr_value !~ m/^(center|justify|left|right)$/i;
	    } elsif ($attr_name eq "lang" || $attr_name eq "class") {
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
    print "\tFix centers.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "center")) {
	foreach my $b_tag ($a_tag->descendants) {
	    next if $b_tag->tag ne "center";
	    $b_tag->tag('p');
	}
    }
    return $tree;
}

sub html_tidy {
    my $html = shift;
    print "\tTidy up.\n";
    my $tidy = HTML::Tidy->new({ indent => "auto", tidy_mark => 0, doctype => 'omit',
	char_encoding => "raw", clean => 'yes', preserve_entities => 0, new_inline_tags => 'ref', new_inline_tags => 'br_io'});
    $html = $tidy->clean($html);
    return $html;
}

return 1;
