#!/usr/bin/perl -w
print "Start.\n";
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };

# #     get utf8 codes from http://www.fileformat.info/info/unicode/char/25cb/index.htm
# perl -e 'print sprintf("\\x{%x}", $_) foreach (unpack("C*", "Ó"));print"\n"'

use File::Find;
use File::Copy;
use Cwd 'abs_path';
use File::Basename;
my $script_dir = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";

use HTML::WikiConverter;
use File::Path qw(make_path remove_tree);
use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use HTML::Tidy;

use Carti::WikiWork;
use Carti::HtmlClean;
use Carti::Common;
use Carti::WikiTxtClean;

my $wiki_site = "http://10.11.4.45/wiki";
# my $wiki_site = "http://localhost:2900/wiki";
# my $wiki_site = "http://192.168.0.102/wiki";

my $docs_prefix = shift;
# $docs_prefix = "/mnt/home/cristi/programe/scripts/carti/code/books";
$docs_prefix = abs_path($docs_prefix);
my $work_prefix = "work";
# my $work_dir = "";
my $colors = "yes";
my $our_wiki;
my $debug = 1;
my $total = 0;
my $crt = 0;

sub generate_html_file {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    print "\t-Generating html file from $doc_file.\n";
    my $status;
    eval {
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 46800; # 13 hours
	system("python", "$script_dir/unoconv", "-f", "html", "$doc_file") == 0 or die "unoconv failed: $?";
	$status = $?;
	alarm 0;
    };
    if ($status) {
	printf "Error: Timed out: $status. Child exited with value %d\n", $status >> 8;
	eval {
	    local $SIG{ALRM} = sub { die "alarm\n" };
	    alarm 46800; # 13 hours
	    system("Xvfb :10235 -screen 0 1024x768x16 &> /dev/null &");
	    system("libreoffice", "-display", ":10235", "-unnaccept=all", "-invisible", "-nocrashreport", "-nodefault", "-nologo", "-nofirststartwizard", "-norestore", "-convert-to", "html:HTML (StarWriter)", "-outdir", "$dir", "$doc_file") == 0 or die "libreoffice failed: $?";
	    $status = $?;
	    alarm 0;
	};
	if ($status) {
	    printf "Error: Timed out: $status. Child exited with value %d\n", $status >> 8;
	} else {
	    print "\tFinished: $status.\n";
	}
    }
    print "\t+Generating html file from $doc_file.\n";
    return 0;
}

sub get_documents {
    our $files_to_import = {};
    sub add_document {
	my $file = shift;
	$file = abs_path($file);
	my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
	my $auth = $dir;
	$auth =~ s/^$docs_prefix\/([^\/]*).*$/$1/;
	$auth = "Autor necunoscut" if $auth =~ m/^\s*$/;
	$files_to_import->{"$suffix"}->{$auth}->{$name} = $file;
    }

    find ({wanted => sub { add_document ($File::Find::name) if -f },},"$docs_prefix") if -d "$docs_prefix";
    return $files_to_import;
}

sub wiki_guess_headings {
    my $wiki = shift;
#     if (-f)
    return $wiki;
}

sub make_wiki {
    my ($html_file, $work_dir) = @_;
    my $image_files = ();
    my $no_links = 0;
#     $no_links = 0 if $book eq "dudu -- Fracurile Negre III - 01 Manusa de otel";
    my $i = 1;
    my $html = Common::read_file("$html_file");
    ## this should be minus?
    $html =~ s/\x{1e}/-/gsi;
    $html =~ s/\x{2}//gsi;
    $html =~ s/&nbsp;/-/gsi;
    ### clean_html_from_doc
    my $tree = HtmlClean::get_tree($html);
    $tree = HtmlClean::doc_tree_remove_TOC($tree);
    ($tree, $image_files) = HtmlClean::doc_tree_fix_links($tree, $no_links);
# Common::write_file("$work_dir/".$i++." html.html", HtmlClean::html_tidy($tree->as_HTML('<>&', "\t")));
    $tree = HtmlClean::doc_tree_clean_color($tree) if $colors !~ m/^yes$/i;
    $tree = HtmlClean::doc_tree_clean_font($tree);
    $tree = HtmlClean::doc_tree_remove_empty_font($tree);
    $tree = HtmlClean::doc_tree_clean_span($tree);
    $tree = HtmlClean::doc_tree_remove_empty_span($tree);
    $tree = HtmlClean::doc_tree_clean_h($tree);
    $tree = HtmlClean::doc_tree_clean_div($tree);
    $tree = HtmlClean::doc_tree_clean_b_i($tree);
    $tree = HtmlClean::doc_tree_remove_empty_list($tree);
    $tree = HtmlClean::doc_tree_clean_tables($tree);
    $tree = HtmlClean::doc_tree_fix_paragraph_center($tree);
    $tree = HtmlClean::doc_tree_fix_center($tree);
    $html = $tree->as_HTML('<>&', "\t");
    $tree = $tree->delete;
#     Common::write_file("$work_dir/$book cleaned.html", HtmlClean::html_tidy($html));
    my $orig_images = $image_files;
    $image_files = ();
    foreach (sort keys %$orig_images) {
	my $orig_name = $_;
	my $new_name = $orig_images->{$_};
	if (! -f "$work_dir/$orig_name") {
	    die "Missing image $work_dir/$orig_name.\n";
	    next;
	}
	print "\tConverting file $orig_name to $new_name.\n";
	system("convert", "$work_dir/$orig_name", "-background", "white", "-flatten", "$work_dir/$new_name") == 0 or die "error runnig convert: $!.\n";

	push @$image_files, "$work_dir/$new_name";
	unlink "$work_dir/$orig_name";
    }

    ### html_to_wikitext
    print "\tStart to wikify.\n";
    my $strip_tags = [ '~comment', 'head', 'script', 'style', 'strike'];
    my $wc = new HTML::WikiConverter(
	dialect => 'MediaWiki',
	strip_tags => $strip_tags,
    );

    my $wiki = $wc->html2wiki(Encode::encode('utf8', $html));
# Common::write_file("$work_dir/$book 1.wiki", Encode::decode('utf8', $wiki));
    unlink $html_file;
    return ($wiki, $image_files);
}

sub import_wiki {
    my ($wiki, $title, $image_files, $work_dir, $author) = @_;
    $our_wiki = new WikiWork("$wiki_site", 'admin', 'qazwsx');
    $wiki = WikiTxtClean::wiki_fix_chars($wiki);
# Common::write_file("$work_dir/$title 2.wiki", Encode::decode('utf8', $wiki));
    $wiki = WikiTxtClean::wiki_fix_empty_center($wiki);
    $wiki = WikiTxtClean::wiki_fix_small_issues($wiki);
#     $wiki = WikiTxtClean::wiki_guess_headings($wiki);
    $wiki .= "\n\n----\n=Note de subsol=\n\n<references />\n\n";
    foreach my $tmp (split "&", $author) {
	$tmp =~s/(^\s+|\s+$)//g;
	$wiki .= "[[Category:$tmp]]\n";
	$our_wiki->wiki_edit_page("Category:$tmp", "[[Category:Autori]]\n----") if ! $our_wiki->wiki_exists_page("Category:$tmp");
    }
    ### wikitext_to_wikiweb
    $our_wiki->wiki_upload_file($image_files);
    unlink "$_" foreach (@$image_files); #, "align", "right"
    $our_wiki->wiki_delete_page("$title") if $our_wiki->wiki_exists_page("$title");
    $our_wiki->wiki_edit_page("$title", $wiki);
}

# sub wikiweb_to_html {
#     my $book = shift;
#     my $i = 1;
# # $book = "NASA";
# # $work_dir = "/mnt/home/cristi/programe/scripts/carti/code/work/$book";
# # remove_tree("$work_dir") || die "Can't remove dir $work_dir: $!.\n" if -d "$work_dir";
# # Common::makedir($work_dir);
# 
#     my @cmd_output = `wget -P "$work_dir" -k --no-directories --no-host-directories --adjust-extension --convert-links --page-requisites "$wiki_site/index.php?title=$book&printable=yes"`;
#     rename("$work_dir/index.php?title=$book&printable=yes.html", "$work_dir/$book.html");
#     my $html_file = "$work_dir/index.php.html";
#     my $html = Common::read_file("$html_file");
#     ### clean_html_from_wikiweb
#     my $tree = HtmlClean::get_tree($html);
#     $tree = HtmlClean::wiki_tree_clean_css($tree, $work_dir);
#     $tree = HtmlClean::wiki_tree_clean_wiki($tree);
# #     $tree = HtmlClean::wiki_tree_fix_links($tree, $wiki_site);
#     Common::write_file("$work_dir/$book.html", $tree->as_HTML('<>&', "\t"));
#     $tree = HtmlClean::wiki_tree_clean_script($tree);
#     ### html_to_epub
#     `ebook-convert "$work_dir/$book.html" .epub --no-default-epub-cover --disable-font-rescaling --minimum-line-height=0 --smarten-punctuation --chapter=/ --no-chapters-in-toc --input-profile=default --output-profile=sony300`;
# }

sub work_docs {
    my ($author, $books) = @_;
    die "no author.\n" if $author =~ m/^\s*$/;
    foreach my $book (sort keys %$books) {
	my $file = $books->{$book};
# next if $file !~ m/Un comando pe dou\x{c4}\x{83} continente/i;
	print "\n". '-'x10 ."\t".$crt++." out of $total\n$book\n";
	my $title = "$author -- $book";
	$book = "$author -- $book";
	### import doc to wiki
	my ($name,$dir,$ext) = fileparse(Common::normalize_text($file), qr/\.[^.]*/);
	my $work_dir = "$script_dir/$work_prefix/$book";
	my $working_file = "$work_dir/$name$ext";
next if -d "$work_dir";
# 	remove_tree("$work_dir") || die "Can't remove dir $work_dir: $!.\n" if -d "$work_dir";
	Common::makedir($work_dir);
	copy("$file", $working_file) or die "Copy failed $working_file: $!\n";
	my $res = generate_html_file("$working_file");
	if ($res || ! -s "$work_dir/$name.html") {print "Can't generate html.\n";next;}
	my ($wiki_text, $image_files) = make_wiki("$work_dir/$name.html", $work_dir);
	import_wiki($wiki_text, $title, $image_files, $work_dir, $author);
	unlink "$working_file" || die "Can't remove file $file:$!.\n";
# 	rmdir "$work_dir" || print "Can't remove dir $work_dir:$!.\n";
# exit 1;
    }
}

sub extract_from_wiki {
      ### extract html from wiki
#       $work_dir = "$script_dir/$work_prefix/$book/wiki";
#       remove_tree("$work_dir") || die "Can't remove dir $work_dir: $!.\n" if -d "$work_dir";
#       Common::makedir($work_dir);
#       wikiweb_to_html($book);
}
#     
#     
#     
#     epub/html_to_mobi
#     wikiweb_to_pdf
#     wikiweb_to_odt
#     odt_to_rtf
#     odt_to_doc
#     odt_to_docx
# extract_html();
# wikiweb_to_html;
# exit 1;
# $work_dir = "$script_dir/work/";
my $files_to_import = get_documents;
foreach my $type (keys %$files_to_import) {
    if ($type =~ m/\.docx?$/i || $type =~ m/\.odt$/i || $type =~ m/\.rtf$/i) { # || $type =~ m/\.rtf$/i 
	$total += scalar (keys %{$files_to_import->{$type}->{$_}}) foreach (keys %{$files_to_import->{$type}});
	print "Start working for $type: $total books.\n";
	foreach my $author (sort keys %{$files_to_import->{$type}}) {
	    work_docs($author, $files_to_import->{$type}->{$author});
	}
    } elsif ($type =~ m/\.rtf$/i) {
    } elsif ($type =~ m/\.gif$/i || $type =~ m/\.jpg$/i) {
    } elsif ($type =~ m/\.txt$/i) {
    } elsif ($type =~ m/\.html?$/i) {
    } elsif ($type =~ m/\.pdf$/i) {
    } elsif ($type =~ m/\.epub$/i) {
    } elsif ($type =~ m/\.zip$/i) {
    } elsif ($type =~ m/\.js$/i) {
    } else {
	print Dumper($files_to_import->{$type})."\nUnknown file type: $type.\n";
    }
}
