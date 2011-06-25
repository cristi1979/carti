#!/usr/bin/perl -w
print "Start.\n";
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };
# #     get utf8 codes from http://www.fileformat.info/info/unicode/char/25cb/index.htm
# perl -e 'print sprintf("\\x{%x}", $_) foreach (unpack("C*", "Ó"));print"\n"'
use Cwd 'abs_path';
use File::Basename;

BEGIN {
  unless ($ENV{BEGIN_BLOCK}) {
#     $ENV{LD_LIBRARY_PATH} = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."/tools/calibre/lib/";
    $ENV{BEGIN_BLOCK} = 1;
    exec 'env',$0,@ARGV;
  }
}

use File::Find;
use File::Copy;
my $script_dir = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";

use HTML::WikiConverter;
use File::Path qw(make_path remove_tree);
use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use HTML::Tidy;
# use HTML::TextToHTML;

use Carti::WikiWork;
use Carti::HtmlClean;
use Carti::Common;
use Carti::WikiTxtClean;

# my $wiki_site = "http://10.11.4.45/wiki";
# my $wiki_site = "http://localhost:2900/wiki";
my $wiki_site = "http://192.168.0.163/wiki";
# my $wiki_site = "http://localhost/wiki";

my $docs_prefix = shift;
my $work_prefix = "work_carti";

my $colors = "yes";
my $our_wiki;
my $debug = 1;
my $url_sep = " -- ";
my $font = "BookmanOS.ttf";

sub generate_html_file {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
#     return 0 if $suffix =~ m/^\.html?$/i;
    if ($suffix =~ m/^\.txt$/i) {
	`iconv -f cp1250 -t utf-8 "$doc_file" > "$dir/utf_$name$suffix"`;
	move("$dir/utf_$name$suffix", "$doc_file") || die "can't move file.\n";
    }
    print "\t-Generating html file from $doc_file.\n";
    my $status;
    eval {
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 600; # 13 hours
	system("python", "$script_dir/tools/unoconv", "-f", "html", "$doc_file") == 0 or die "unoconv failed: $?";
	alarm 0;
    };
    $status = $?;
    if ($status) {
	printf "Error: Timed out: $status. Child exited with value %d\n", $status >> 8;
	eval {
	    local $SIG{ALRM} = sub { die "alarm\n" };
	    alarm 600; # 13 hours
	    system("Xvfb :10235 -screen 0 1024x768x16 &> /dev/null &");
	    system("libreoffice", "-display", ":10235", "-unnaccept=all", "-invisible", "-nocrashreport", "-nodefault", "-nologo", "-nofirststartwizard", "-norestore", "-convert-to", "html:HTML (StarWriter)", "-outdir", "$dir", "$doc_file") == 0 or die "libreoffice failed: $?";
	    alarm 0;
	};
	$status = $?;
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
# my $i = 1;
    my $html = Common::read_file("$html_file");
    ## this should be minus?
    $html =~ s/\x{1e}/-/gsi;
    $html =~ s/\x{2}//gsi;
    ### clean_html_from_doc
    my $tree = HtmlClean::get_tree($html);
# Common::write_file("$work_dir/".$i++." html.html", HtmlClean::html_tidy($tree->as_HTML('<>&', "\t")));
    $tree = HtmlClean::wiki_tree_clean_script($tree, "/dev/null");
    $tree = HtmlClean::doc_tree_clean_defs($tree);
    $tree = HtmlClean::doc_tree_remove_TOC($tree);
# Common::write_file("$work_dir/".$i++." html.html", $tree->as_HTML('<>&', "\t"));
    ($tree, $image_files) = HtmlClean::doc_tree_fix_links($tree, $no_links);
# Common::write_file("$work_dir/".$i++." html.html", $tree->as_HTML('<>&', "\t"));
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
    $tree = HtmlClean::doc_tree_clean_pre($tree);
    $html = $tree->as_HTML('<>&', "\t");
    $tree = $tree->delete;
# Common::write_file("$work_dir/cleaned.html", HtmlClean::html_tidy($html));
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
# Common::write_file("$work_dir/1.wiki", Encode::decode('utf8', $wiki));
    unlink $html_file;
    return ($wiki, $image_files);
}

sub import_wiki {
    my ($wiki, $title, $image_files, $work_dir, $author) = @_;
    $our_wiki = new WikiWork("$wiki_site", 'admin', 'qazwsx');
# Common::write_file("$work_dir/$title 0.wiki", Encode::decode('utf8', $wiki));
    $wiki = WikiTxtClean::wiki_fix_chars($wiki);
# Common::write_file("$work_dir/$title 1.wiki", Encode::decode('utf8', $wiki));
    $wiki = WikiTxtClean::wiki_fix_empty_center($wiki);
# Common::write_file("$work_dir/$title 2.wiki", Encode::decode('utf8', $wiki));
    $wiki = WikiTxtClean::wiki_fix_small_issues($wiki);
# Common::write_file("$work_dir/$title 3.wiki", Encode::decode('utf8', $wiki));
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

sub work_docs {
    my ($author, $books) = @_;
    die "no author.\n" if $author =~ m/^\s*$/;
    foreach my $book (sort keys %$books) {
	my $file = $books->{$book};
# next if $file !~ m/Avatarul/i;
# 	print "\n". '-'x10 ."\t".$crt++." out of $total\n$book\n";
	my $title = "$author$url_sep$book";
	$book = "$author$url_sep$book";
	### import doc to wiki
	my ($name,$dir,$ext) = fileparse(Common::normalize_text($file), qr/\.[^.]*/);
# Common::makedir("/home/cristi/$dir");
# copy("$file", "/home/cristi/$dir");
# unlink $file;
# next;
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

sub wikiweb_to_epub {
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
    my $html = Common::read_file("$html_file");
    ### clean_html_from_wikiweb
    my $images;
    my $tree = HtmlClean::get_tree($html);
    $tree = HtmlClean::wiki_tree_clean_script($tree, $work_dir);
    $tree = HtmlClean::doc_tree_clean_color($tree);
    $tree = HtmlClean::wiki_tree_clean_css($tree, $work_dir);
    $tree = HtmlClean::wiki_tree_clean_wiki($tree);
    ($tree, $images) = HtmlClean::wiki_tree_fix_links($tree, $wiki_site);
    $html = $tree->as_HTML('<>&', "\t");
# Common::write_file(encode_utf8("$html_file"), $tree->as_HTML('<>&', "\t"));
    ### html_to_epub
    Common::write_file(encode_utf8("$html_file"), HtmlClean::html_tidy($tree->as_HTML('<>&', "\t")));
#     Common::write_file(encode_utf8("$html_file"), $tree->as_HTML('<>&', "\t"));
    $tree = $tree->delete;
    my ($name,$dir,$ext) = fileparse($html_file, qr/\.[^.]*/);
    my ($authors, $title) = $name =~ m/^(.*?)$url_sep(.*)$/;
    $authors =~ s/(\s*&\s*)/&/g;

    my $epub_parameters = "--disable-font-rescaling --minimum-line-height=0 --smarten-punctuation --chapter=\"//*[(name()='h1' or name()='h2' or name()='h3' or name()='h4' or name()='h5')]\" --input-profile=default --output-profile=sony300 --max-toc-links=0 --language=ro --authors=\"$authors\" --title=\"$title\"";
    my ($out_file, $in_file, $output);
    ### normal epub
    print "Converting to epub.\n";
    $in_file = "$html_file";
    $out_file = "$dir/normal/$name.epub";
    Common::makedir("$dir/normal/");
    $output = `$script_dir/tools/calibre/ebook-convert \"$in_file\" \"$out_file\" --no-default-epub-cover $epub_parameters`;
# print Dumper($in_file, $out_file, $output);
    die "file $out_file not created.\n" if ! -s $out_file;

    $in_file = "$out_file";
    ### epub with external font
    print "Converting to epub with external font.\n";
    $out_file = "$dir/external/$name.epub";
    Common::makedir("$dir/external/");
    $output = `$script_dir/tools/calibre/ebook-convert \"$in_file\" \"$out_file\" --extra-css=\"$script_dir/tools/external_font.css\" --no-default-epub-cover $epub_parameters`;
    die "file $out_file not created.\n" if ! -s $out_file;

    ### epub with embedded font
    print "Converting to epub with embedded font.\n";
    $out_file = "$dir/internal/$name.epub";
    Common::makedir("$dir/internal/");
    $output = `$script_dir/tools/calibre/ebook-convert \"$in_file\" \"$out_file\" --extra-css=\"$script_dir/tools/internal_font.css\" --no-default-epub-cover $epub_parameters`;
    Common::add_file_to_zip("$out_file", "$script_dir/tools/$font");
    die "file $out_file not created.\n" if ! -s $out_file;

    ### epub with ascii chars
    print "Converting to ascii epub.\n";
    $out_file = Common::normalize_text("$dir/ascii/$name.epub");
    Common::makedir("$dir/ascii/");
    `$script_dir/tools/calibre/ebook-convert \"$in_file\" \"$out_file\" --asciiize --no-default-epub-cover $epub_parameters`;
    die "file $out_file not created.\n" if ! -s $out_file;

#     ### normal mobi
#     print "Converting to mobi.\n";
#     $out_file = "$dir/mobi/$name.mobi";
#     Common::makedir("$dir/mobi/");
#     $output = `$script_dir/tools/calibre/ebook-convert \"$in_file\" \"$out_file\" $epub_parameters`;
#     die "file $out_file not created.\n" if ! -s $out_file;
# 
#     ### mobi with ascii chars
#     print "Converting to ascii mobi.\n";
#     $out_file = Common::normalize_text("$dir/ascii_mobi/$name.mobi");
#     Common::makedir("$dir/ascii_mobi/");
#     $output = `$script_dir/tools/calibre/ebook-convert \"$in_file\" \"$out_file\" --asciiize $epub_parameters`;
#     die "file $out_file not created.\n" if ! -s $out_file;

#     ### normal fb2
#     print "Converting to fb2.\n";
#     $out_file = "$dir/fb2/$name.fb2";
#     Common::makedir("$dir/fb2/");
#     `$script_dir/tools/calibre/ebook-convert \"$in_file\" \"$out_file\" $epub_parameters`;
}
#  - --cover --series --series-index --tags=comma separated  --rating=between 1 and 5

#     wikiweb_to_odt
#     odt/wikiweb_to_pdf
#     odt_to_rtf
#     odt_to_doc
#     odt_to_docx
# extract_html();
# wikiweb_to_html;

sub import_documents {
    $docs_prefix = abs_path($docs_prefix);
    my $files_to_import = get_documents;
    foreach my $type (keys %$files_to_import) {
	if ($type =~ m/\.docx?$/i || $type =~ m/\.odt$/i || $type =~ m/\.rtf$/i || $type =~ m/\.txt$/i) {
# 	    $total += scalar (keys %{$files_to_import->{$type}->{$_}}) foreach (keys %{$files_to_import->{$type}});
	    print "Start working for $type.\n";
	    foreach my $author (sort keys %{$files_to_import->{$type}}) {
		work_docs($author, $files_to_import->{$type}->{$author});
	    }
	} elsif ($type =~ m/\.gif$/i || $type =~ m/\.jpg$/i) {
	} elsif ($type =~ m/\.html?$/i) {
# rm -rf ~/.libreoffice/
# libreoffice -headless -invisible -nodefault -nologo -nofirststartwizard -norestore -convert-to swriter /dev/null
# cp /home/cristi/programe/scripts/carti/tools/libreoffice/Standard/* ~/.libreoffice/3/user/basic/Standard/
# libreoffice -headless -invisible -nocrashreport -nodefault -nologo -nofirststartwizard -norestore "macro:///Standard.Module1.embedImagesInWriter(/home/cristi/programe/scripts/carti/qq/index.html)"
# libreoffice -infilter="HTML (StarWriter)" -convert-to "ODF Text Document" ./q/Poul\ Anderson/index.html
# http://user.services.openoffice.org/en/forum/viewtopic.php?f=20&t=23909
# my $tree = HtmlClean::get_tree($html);
# $tree = HtmlClean::wiki_tree_clean_script($tree, "/dev/null");
# "C:\Program Files\OpenOffice.org1.1.4\program\soffice.exe" "macro:///Standard.Module1.Test(C:\Documents and Settings\dbrewer\Desktop\Test\test.sxw)" 
	} elsif ($type =~ m/\.pdf$/i) {
	} elsif ($type =~ m/\.epub$/i) {
	} elsif ($type =~ m/\.zip$/i) {
	} elsif ($type =~ m/\.js$/i) {
	} else {
	    print Dumper($files_to_import->{$type})."\nUnknown file type: $type.\n";
	}
    }
}

# import_documents();
# exit 1;
$our_wiki = new WikiWork("$wiki_site", 'admin', 'qazwsx');
# my $docs = $our_wiki->wiki_get_all_pages;
foreach my $book (@{$our_wiki->wiki_get_all_pages}) {
#     $book = Encode::encode('utf8', $book);
# next if $book !~ m/M.nu.a de o.el/i;
    my $work_dir = "$script_dir/$work_prefix/$book";
next if -d "$work_dir";
    Common::makedir($work_dir);
    wikiweb_to_epub($book, $work_dir);
}
