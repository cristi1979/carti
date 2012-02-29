
use Carti::WikiWork;
use HTML::WikiConverter;
my $wiki_site = "http://192.168.0.163/wiki";
my ($wiki_user, $wiki_pass, $wiki_original_files) = ("admin", "qwaszx", "$wiki_site/fisiere_originale");
my $our_wiki;

sub doc_tree_fix_paragraph_center {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Fix paragraph centers.\n";
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

sub wiki_tree_clean_wiki {
    my $tree = shift;
    Common::my_print "\t".(++$counter)." Clean wiki.\n";
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
    Common::my_print "\t".(++$counter)." Fix links from wiki.\n";
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

sub wiki_tree_clean_script {
    my ($tree, $work_dir) = @_;
    Common::my_print "\t".(++$counter)." Clean script.\n";
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
    Common::my_print "\t".(++$counter)." Fix links and notes for wiki.\n";
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
	    Common::my_print "\t".(++$counter)." Hey, there's tag $tag that links to ", $link, ", in its $attr attribute.\n";
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
    Common::my_print "\t".(++$counter)." Clean css.\n";
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
    Common::my_print "\t".(++$counter)." Clean css from wiki.\n";
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

sub clean_html_from_wiki {
    my ($html, $work_dir, $wiki_site) = @_;
    my $images = ();
    my $tree = get_tree($html);
    $tree = wiki_tree_clean_script($tree, $work_dir);
    $tree = doc_tree_clean_color($tree);
    $tree = wiki_tree_clean_css($tree, $work_dir);
    $tree = wiki_tree_clean_wiki($tree);
    ($tree, $images) = wiki_tree_fix_links($tree, $wiki_site);
#     ($tree, $images) = doc_tree_fix_links_for_wiki($tree, $no_links);
#     $tree = wiki_tree_clean_script($tree, "/dev/null");
    $html = $tree->as_HTML('<>&', "\t");
    $tree = $tree->delete;
    return ($html, $images);
}

sub make_wiki {
    my $html = shift;
    ### html_to_wikitext
    print "\tStart to wikify.\n";
    my $strip_tags = [ '~comment', 'head', 'script', 'style', 'strike'];
    my $wc = new HTML::WikiConverter(
	dialect => 'MediaWiki',
	strip_tags => $strip_tags,
    );

    my $wiki = $wc->html2wiki(Encode::encode('utf8', $html));
    return $wiki;
}

sub import_to_wiki {
    my ($wiki, $title, $image_files, $work_dir, $author) = @_;
    $our_wiki = new WikiWork($wiki_site, $wiki_user, $wiki_pass);
    $wiki = WikiTxtClean::wiki_fix_chars($wiki);
    $wiki = WikiTxtClean::wiki_fix_empty_center($wiki);
    $wiki = WikiTxtClean::wiki_fix_small_issues($wiki);
    $wiki .= "\n\n----\n=Note de subsol=\n\n<references />\n\n";
    ### wikitext_to_wikiweb
    $our_wiki->wiki_upload_file($image_files);
    unlink "$_" foreach (@$image_files); #, "align", "right"
    ### adauga categoriile
    foreach (sort keys %$author) {
	$wiki .= "[[Category:$_]]\n";
	if ($author->{$_} eq "nume prenume") {# && ! $our_wiki->wiki_exists_page("Category:$_")
	    $our_wiki->wiki_edit_page("Category:$_", "[[Category:Autori sortati alfabetic]]\n----");
	}
	if ($author->{$_} eq "prenume, nume") {
	    $our_wiki->wiki_edit_page("Category:$_", "[[Category:Autori sortati]]\n----");
	}
    }
    my $nr_chars = length($wiki);
    $wiki .= "\n[{{fullurl:Template:Taguri $title|action=edit}} Adauga/modifica taguri]\n\n";
#     $our_wiki->wiki_edit_page("Template:Taguri $title", "----");
    $wiki .= "[[Category:Carti scurte]]\n" if ($nr_chars < 20000);
    $wiki .= "[[Category:Carti medii]]\n" if ($nr_chars > 19000 && $nr_chars < 500000);
    $wiki .= "[[Category:Carti lungi]]\n" if ($nr_chars > 450000);
    $our_wiki->wiki_delete_page("$title") if $our_wiki->wiki_exists_page("$title");
    $our_wiki->wiki_edit_page("$title", $wiki);
    return $wiki;
}

sub import_html_to_wiki {
    my ($html, $images, $book) = @_;
    my ($author, $file, $title) =($book->{"auth"}, $book->{"file"}, $book->{"title"});
    my $work_dir = "$work_prefix/$title";
    my $wiki_text = make_wiki ($html);
    $wiki_text = "<center>Fisierul original poate fi gasit [$wiki_original_files/".uri_escape($title).".zip aici]</center>\n----\n\n\n".$wiki_text;
    import_to_wiki($wiki_text, $title, $images, $work_dir, $author);
    Common::write_file("$work_dir/$title.wiki", $wiki_text);

    ## tests for extra files
    my @files = <"$work_dir/*">;
    my $files_hash = {};
    $files_hash->{$_} = 1 foreach (@files);
    delete $files_hash->{"$work_dir/$title.wiki"};
    delete $files_hash->{"$work_dir/$title.zip"};
    delete $files_hash->{"$work_dir/$title.epub"};
    delete $files_hash->{"$work_dir/$control_file"};
    die "Files still exist in $work_dir:\n".Dumper($files_hash) if scalar (keys %$files_hash) > 0;
}

sub get_html_from_wikisite {
    my ($book, $work_dir) = @_;
    my $link = $book;
    $link =~ s/&/\%26/;
    my @cmd_output = `wget -P "$work_dir" -k --no-directories --no-host-directories --adjust-extension --convert-links --page-requisites "$wiki_site/index.php?title=$link&printable=yes" -o /dev/null`;
    my @files;
    find( sub {push @files, "$File::Find::name" if (/\.html$/)}, $work_dir);
    die "too many html: ". Dumper(@files). "\n" if scalar @files != 1;
    ### because wget is insane
    my $html_file = "$work_dir/$book.html";
    my $q = `find \"$work_dir\" -print0 | grep -z \".html\$\" | xargs -0 -I {} mv {} \"$html_file\"`;
    return $html_file;
}

sub wiki_site_to_epub {
    foreach my $book (sort @{$our_wiki->wiki_get_all_pages}) {
	my $work_dir = "$work_prefix/$book";
	next if -d "$work_dir";
	print "Start working for ".Encode::encode('utf8', $book).".\n";
	Common::makedir($work_dir);
	my $html_file = get_html_from_wikisite($book, $work_dir);
	my ($html, $images) = clean_html_wiki($html_file);
	Common::write_file(encode_utf8("$html_file"), HtmlClean::html_tidy($html));
	html_to_epub($html_file);
    }
}
