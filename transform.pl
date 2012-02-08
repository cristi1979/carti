#!/usr/bin/perl -w
print "Start.\n";
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };
# #     get utf8 codes from http://www.fileformat.info/info/unicode/char/25cb/index.htm
# perl -e 'print sprintf("\\x{%x}", $_) foreach (unpack("C*", "Ó"));print"\n"'
use Cwd 'abs_path';
use File::Basename;
$| = 1;

BEGIN {
  unless ($ENV{BEGIN_BLOCK}) {
    $ENV{BEGIN_BLOCK} = 1;
	if ($^O ne "MSWin32") { exec 'env',$0,@ARGV;}
  }
}

my $os = $^O;
$os = "windows" if $^O eq "MSWin32";
use File::Find;
use File::Copy;
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";

use HTML::WikiConverter;
use File::Path qw(make_path remove_tree);
use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use HTML::Tidy;
use URI::Escape;
use Time::HiRes qw(usleep nanosleep);

use threads;
use threads::shared;
use Thread::Semaphore;
use Thread::Queue;

use Carti::WikiWork;
use Carti::HtmlClean;
use Carti::Common;
use Carti::WikiTxtClean;

my $DataQueue = Thread::Queue->new();
my $max_html_parse_threads = 6;

my $script_dir = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
my $extra_tools_dir = "$script_dir/tools";
my $wiki_site = "http://192.168.0.163/wiki";
my ($wiki_user, $wiki_pass, $wiki_original_files) = ("admin", "qwaszx", "$wiki_site/fisiere_originale");
my $our_wiki;

my $workign_mode = shift;
my $docs_prefix = shift;
$docs_prefix = abs_path($docs_prefix);
my $work_prefix = "work";
my $duplicate_file = "$script_dir/duplicate_files";
our $duplicate_files = {};
my $control_file = "doc_info_file.xml";

my $good_files_dir = "$docs_prefix/aaa_aaa/";
my $bad_files_dir = "$docs_prefix/ab_aaa - RAU/";
my $new_files_dir = "$docs_prefix/ac_noi/";

my $colors = "no";
my $debug = 1;
my $url_sep = " -- ";
my $font = "BookmanOS.ttf";
my $Xdisplay = ":12345";

sub get_files_from_dir {
    my $dir_q = shift;
    $dir_q = abs_path($dir_q);
    our $hash_q = {};
    print "Get files from $dir_q.\n";
    our $count = 0;
    sub add_documents {
	my $file = shift;
	print "$count\r" if ++$count % 10 == 0;
	$file = abs_path($file);
	my $md5 = "md5_".Common::get_file_md5($file);
	if ( defined $hash_q->{$md5} ) {
	    $duplicate_files->{$file} = 1;
	    print Dumper("duplicate $file");
	    return;
	}
	$hash_q->{$md5} = $file; #Encode::decode('utf8', );
    }

    find ({wanted => sub { add_documents ($File::Find::name) if -f }, follow => 1}, $dir_q) if -d $dir_q;
    print "$count\n";
    return $hash_q;
}

sub get_authors {
    my $author = shift;
    my $authors;
    foreach my $tmp (split "&", $author) {
	$tmp =~s/(^\s+|\s+$)//g;
	my @tmp1 = split /\s/, $tmp;
	my $tmp1 = (pop @tmp1).", ". join " ", @tmp1;
	$tmp1 =~s/(^\s+|\s+$)//g;
	$authors->{$tmp} = "nume prenume";
	$authors->{$tmp1} = "prenume, nume";
    }
    return $authors;
}

sub get_version {
    my $file = shift;
    my $ver;
    $ver = $2 if ($file =~ m/(\s\[([0-9]+(\.[0-9]+))\])$/i);
    $file =~ s/\s\[$ver\]// if defined $ver;
    return ($ver, $file);
}

sub get_series {
    my $file = shift;
    my ($series, $series_no) = ();
    if ($file =~ m/^(.+)? - ([0-9]+)\. /i) {
	($series, $series_no) = ($1, $2);
    }
    $file =~ s/$series - $series_no\. // if defined $series && defined $series_no;
    return ($series, $series_no, $file);
}

my $first_time = 0;
sub doc_to_html_macro {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    print "\t-Generating html file from $doc_file.\n";
    my $status;
    if ($first_time == 0) {
	remove_tree($ENV{"HOME"} ."/.libreoffice/") || die "Can't remove dir ".$ENV{"HOME"}."/.libreoffice/: $!.\n" if -d $ENV{"HOME"} ."/.libreoffice/";
	system("libreoffice", "--headless", "--invisible", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", "swriter", "/dev/null") == 0 or die "libreoffice failed: $?";
	copy("$extra_tools_dir/libreoffice/Standard/Module1.xba", $ENV{"HOME"} ."/.libreoffice/3/user/basic/Standard/") or die "Copy failed libreoffice macros: $!\n";
	$first_time++;
    }

    `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
    system("Xvfb $Xdisplay -screen 0 1024x768x16 &> /dev/null &") if $os ne "windows";
    eval {
	die  if $os eq "windows";
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 600;
# 	system("libreoffice", "--display", "$Xdisplay", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "macro:///Standard.Module1.ReplaceNBHyphenHTML($doc_file)") == 0 or die "libreoffice failed: $?";
	system("libreoffice", "--headless", "--invisible", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "macro:///Standard.Module1.ReplaceNBHyphenHTML($doc_file)") == 0 or die "libreoffice failed: $?";
	alarm 0;
    };
    $status = $?;
    if ($status) {
	printf "Error: Timed out: $status. Child exited with value %d\n", $status >> 8;
        `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
    } else {
	print "\tFinished with status: $status.\n";
    }
    print "\t+Generating html file from $doc_file.\n";
    return 0;
}

sub doc_to_html {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    print "\t-Generating html file from $doc_file.\n";
    my $status;
    `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
    eval {
	die  if $os eq "windows";
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 600;
	system("python", "$extra_tools_dir/unoconv", "-f", "html", "$doc_file") == 0 or die "unoconv failed: $?";
	alarm 0;
    };
    $status = $?;
    if ($status) {
	printf "Error: Timed out: $status. Child exited with value %d\n", $status >> 8;
	`kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
	eval {
	    local $SIG{ALRM} = sub { die "alarm\n" };
	    alarm 600;
	    system("Xvfb $Xdisplay -screen 0 1024x768x16 &> /dev/null &") if $os ne "windows";
	    system("libreoffice", "--display", "$Xdisplay", "--unnaccept=all", "--invisible", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", "html:HTML (StarWriter)", "--outdir", "$dir", "$doc_file") == 0 or die "libreoffice failed: $?";
	    alarm 0;
	};
	$status = $?;
	if ($status) {
	    printf "Error: Timed out: $status. Child exited with value %d\n", $status >> 8;
	    `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
	} else {
	    print "\tFinished with status: $status.\n";
	}
    }
    print "\t+Generating html file from $doc_file.\n";
    return 0;
}

sub get_existing_documents {
    my $new_files = shift;
    our $files_already_imported = {};
    my $work_dir = "$script_dir/$work_prefix/";
    die "Working dir $work_dir is a file.\n" if -f $work_dir;
    print "Get already done files from $work_dir.\n";
    Common::makedir($work_dir);
    $work_dir = abs_path("$script_dir/$work_prefix/");
    opendir(DIR, "$work_dir") || die("Cannot open directory $work_dir.\n");
    my @alldirs = grep { (!/^\.\.?$/) && -d "$work_dir/$_" } readdir(DIR);
    closedir(DIR);
    foreach my $dir (sort @alldirs) {
# 	print "Found document $dir.\n";
	my $title = $dir;
	$dir = "$work_dir/$dir";
	if (! -f "$dir/$control_file"){
	    print "Remove wrong dir $dir.\n";
	    remove_tree("$dir") || die "Can't remove dir $dir: $!.\n";
	    next;
	}

	my $book_info = Common::xmlfile_to_hash("$dir/$control_file");

	foreach my $key (keys %$book_info){
	    my $tmp = $book_info->{$key};
	    $new_files->{$title}->{$key} = $book_info->{$key} if ! defined $new_files->{$title}->{$key};
	}
	$files_already_imported->{$title} = 0;
	if ( defined $book_info->{"libreoffice"} && $book_info->{"libreoffice"} eq "done" &&
	  $book_info->{"md5"} eq $new_files->{$title}->{"md5"}) {
	    $files_already_imported->{$title} = $book_info->{"md5"}
	} else {
	    print "Remove wrong dir $dir.\n";
	    remove_tree("$dir") || die "Can't remove dir $dir: $!.\n";
	}
    }
    return ($files_already_imported, $new_files);
}

sub get_new_documents {
    our $files_to_import = {};
    our $count = 0;
    sub add_document {
	my $file = shift;
	print "$count\r" if ++$count % 10 == 0;
	$file = abs_path($file);
	my ($book,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
	if ($book =~ m/(^\s+|\s+$|\s{2,})/ || $suffix ne lc($suffix)){
	    my $tmp1 = $book;
	    $tmp1 =~ s/(^\s+|\s+$)//i;
	    $tmp1 =~ s/\s+/ /ig;
	    my $tmp2 = $suffix;
	    $tmp2 = lc($suffix);
	    print "\"$book$suffix\" ==> \"$tmp1$tmp2\"\n";
	    move("$dir/$book$suffix", "$dir/$tmp1$tmp2") || die "can't move file $book$suffix.\n";
	    $file = "$dir/$tmp1$tmp2";
	    $book = $tmp1;
	    $suffix = $tmp2;
	}
	return if $suffix =~ m/\.jpe?g/i;
	my $auth = $dir;
	$auth =~ s/^$docs_prefix\/([^\/]+).*$/$1/;
	die "Autor necunoscut: ".Dumper($file) if $auth =~ m/^\s*$/;
	my $authors = get_authors($auth);
	$auth = "";
	foreach my $i (keys %$authors){
	    $auth .= "$i&" if $authors->{$i} eq "nume prenume";
	}
	$auth =~ s/(&$)//g;
	my ($ver, $series, $series_no, $coperta);
	$coperta = "$dir/$book.jpg" if -f "$dir/$book.jpg";
	($ver, $book) = get_version($book);
	($series, $series_no, $book) = get_series($book);
	die "Book already exists: $auth$url_sep$book ($file)\n".Dumper($files_to_import->{"$auth$url_sep$book"}) if defined $files_to_import->{"$auth$url_sep$book"};
	$files_to_import->{"$auth$url_sep$book"}->{"type"} = "$suffix";
	$files_to_import->{"$auth$url_sep$book"}->{"coperta"} = "$coperta" if defined $coperta;
	$files_to_import->{"$auth$url_sep$book"}->{"file"} = "$file";
	$files_to_import->{"$auth$url_sep$book"}->{"title"} = "$book";
# 	$files_to_import->{"$auth$url_sep$book"}->{"md5"} = "1";
	$files_to_import->{"$auth$url_sep$book"}->{"md5"} = Common::get_file_md5($file);
	$files_to_import->{"$auth$url_sep$book"}->{"auth"} = $auth;
	$files_to_import->{"$auth$url_sep$book"}->{"ver"} = $ver;
	$files_to_import->{"$auth$url_sep$book"}->{"seria"} = $series;
	$files_to_import->{"$auth$url_sep$book"}->{"seria_no"} = $series_no;
    }
    print "Get all files.\n";
    find ({wanted => sub { add_document ($File::Find::name) if -f },},"$docs_prefix") if -d "$docs_prefix";
    return $files_to_import;
}

sub convert_images {
    my ($images, $work_dir) = @_;
    my $orig_images = $images;
    $images = ();
    foreach (sort keys %$orig_images) {
	my $orig_name = $_;
	my $new_name = $orig_images->{$_};
	if (! -f "$work_dir/$orig_name") {
	    print "Missing image $work_dir/$orig_name.\n";
	    next;
	}
	print "\tConverting file $orig_name to $new_name.\n";
	system("convert", "$work_dir/$orig_name", "-background", "white", "-flatten", "$work_dir/$new_name") == 0 or die "error runnig convert: $!.\n";

	push @$images, "$work_dir/$new_name";
	unlink "$work_dir/$orig_name";
    }
    return $images;
}

sub clean_html_from_wiki {
    my ($html, $work_dir) = @_;
    my $images = ();
    my $tree = HtmlClean::get_tree($html);
    $tree = HtmlClean::wiki_tree_clean_script($tree, $work_dir);
    $tree = HtmlClean::doc_tree_clean_color($tree);
    $tree = HtmlClean::wiki_tree_clean_css($tree, $work_dir);
    $tree = HtmlClean::wiki_tree_clean_wiki($tree);
    ($tree, $images) = HtmlClean::wiki_tree_fix_links($tree, $wiki_site);
    $html = $tree->as_HTML('<>&', "\t");
    $tree = $tree->delete;
    return ($html, $images);
}

sub clean_html_from_ms {
    my $html = shift;
    my $images = ();
    my $tree = HtmlClean::get_tree($html);
    ($tree, $images) = HtmlClean::wiki_tree_fix_links($tree, $wiki_site);
    $html = $tree->as_HTML('<>&', "\t");
    $tree = $tree->delete;
    return ($html, $images);
}

#     ($tree, $images) = HtmlClean::doc_tree_fix_links_for_wiki($tree, $no_links);
#     $tree = HtmlClean::wiki_tree_clean_script($tree, "/dev/null");
sub clean_html_from_oo {
    my ($html, $work_dir) = @_;
    my $images = ();
    my $no_links = 0;
# my $i = 1;
# Common::write_file("/home/cristi/programe/carti/work_wiki/".$i++." html.html", $html);
    ## this should be minus?
    $html =~ s/\x{1e}/-/gsi;
    $html =~ s/\x{2}//gsi;
    my $tree = HtmlClean::get_tree($html);
    my $enc = HtmlClean::doc_tree_find_encoding($tree);
    ## start with fucking removing colors
    $tree = HtmlClean::doc_tree_clean_color($tree) if $colors !~ m/^yes$/i;
# Common::write_file("/home/cristi/programe/carti/work_wiki/".$i++." html.html", $tree->as_HTML('<>&', "\t"));
    $tree = HtmlClean::doc_tree_clean_font($tree);
    $tree = HtmlClean::doc_tree_remove_empty_font($tree);
    $tree = HtmlClean::doc_tree_clean_span($tree);
    $tree = HtmlClean::doc_tree_remove_empty_span($tree);
    $tree = HtmlClean::doc_tree_clean_defs($tree);
    $tree = HtmlClean::doc_tree_remove_TOC($tree);
    ($tree, $images) = HtmlClean::doc_tree_fix_links_from_oo($tree, $no_links);
    $tree = HtmlClean::doc_tree_clean_h($tree, 0);
# Common::write_file("/home/cristi/programe/carti/work_wiki/".$i++." html.html", $tree->as_HTML('<>&', "\t"));
    $tree = HtmlClean::doc_tree_clean_div($tree);
    $tree = HtmlClean::doc_tree_clean_multicol($tree);
    $tree = HtmlClean::doc_tree_clean_b_i($tree);
    $tree = HtmlClean::doc_tree_remove_empty_list($tree);
    $tree = HtmlClean::doc_tree_clean_tables($tree);
# Common::write_file("/home/cristi/programe/carti/work_wiki/".$i++." html.html", $tree->as_HTML('<>&', "\t"));
    $tree = HtmlClean::doc_tree_fix_center($tree);
    $tree = HtmlClean::wiki_tree_clean_body($tree);
    $tree = HtmlClean::doc_tree_fix_paragraph($tree);
    $tree = HtmlClean::doc_tree_clean_css_from_oo($tree, $work_dir);
    $tree = HtmlClean::doc_tree_clean_sub($tree);
# Common::write_file("./".$i++." html.html", $tree->as_HTML('<>&', "\t"));
#     $tree = HtmlClean::doc_tree_clean_pre($tree);
    $tree = HtmlClean::doc_tree_fix_paragraphs_start($tree);
    $tree = HtmlClean::doc_find_unknown_elements($tree);
    $html = $tree->as_HTML('<>&', "\t");
    $tree = $tree->delete;
# Common::write_file("/home/cristi/programe/carti/work_wiki//cleaned.html", $html);
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
# Common::write_file("$work_dir/$title 0.wiki", Encode::decode('utf8', $wiki));
    $wiki = WikiTxtClean::wiki_fix_chars($wiki);
# Common::write_file("$work_dir/$title 1.wiki", Encode::decode('utf8', $wiki));
    $wiki = WikiTxtClean::wiki_fix_empty_center($wiki);
# Common::write_file("$work_dir/$title 2.wiki", Encode::decode('utf8', $wiki));
    $wiki = WikiTxtClean::wiki_fix_small_issues($wiki);
# Common::write_file("$work_dir/$title 3.wiki", Encode::decode('utf8', $wiki));
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

sub libreoffice_to_epub {
    my ($book, $mode) = @_;
    return if defined $book->{"epub"} && $book->{"epub"} eq "done";
    my ($file, $title) =($book->{"file"}, $book->{"title"});
    my ($name,$dir,$ext) = fileparse(Common::normalize_text($file), qr/\.[^.]*/);
    my $work_dir = "$script_dir/$work_prefix/".($book->{"auth"})."$url_sep$title";
    my $working_file = "$work_dir/$name$ext";
    my $html_file = "$work_dir/$name.html";
    my $html_file_orig = "$work_dir/$name"."_orig.html";
    my $html_file_clean = "$work_dir/$name"."_clean.html";
    my $work;
    print "****************** Working $mode for $title.\n";

    $work = 0;
    eval{
    if (($mode eq "html") && !(defined $book->{"libreoffice"} && $book->{"libreoffice"} eq "done")) {
	print "Doing the doc to html conversion.\n";
	remove_tree("$work_dir") || die "Can't remove dir $work_dir: $!.\n" if -d "$work_dir";
	Common::makedir($work_dir);
	copy("$file", $working_file) or die "Copy failed $working_file: $!\n";
	if (defined $book->{'coperta'}){copy($book->{'coperta'}, $work_dir) or die "Copy failed ".$book->{'coperta'}.": $!\n"};
	my $res = doc_to_html_macro("$working_file");
	if ($res || ! -s $html_file) {print "Can't generate html.\n"; return;};
	move("$html_file", "$html_file_orig") || die "can't move file $html_file.\n";
	my $zip_file = "$work_dir/$title.zip";
	Common::add_file_to_zip("$zip_file", "$file");
	unlink $working_file || die "Can't remove file $working_file: $!\n";
	$book->{"libreoffice"} = "done";
	$work++;
    }};
    if ($@) {print Dumper($@). "error: $?.\n"; return;};
    $DataQueue->enqueue($book) if ($mode eq "html") ;
    Common::hash_to_xmlfile($book, "$work_dir/$control_file") if $work;
    return if $mode eq "html";

    $work = 0;
    eval {
    if (($mode eq "epub") && !(defined $book->{"html_clean"} && $book->{"html_clean"} eq "done"  && -s $html_file_clean)) {
	print "Doing the html cleanup.\n";
	my ($html, $images) = clean_html_from_oo(Common::read_file("$html_file_orig"), $work_dir);
	$images = convert_images ($images, $work_dir);
	$book->{'scurte'} = 1 if (length($html) <= 35000);
	$book->{'medii'} = 1 if (length($html) >= 30000 && length($html) <= 450000);
	$book->{'lungi'} = 1 if (length($html) >= 400000);
	Common::write_file("$html_file_clean", HtmlClean::html_tidy($html));
	unlink "$html_file_orig" || die "Can't remove file $html_file_orig: $!\n";
	$book->{"html_clean"} = "done";
	$work++;
    }};
    if ($@) {print Dumper($@). "error: $?.\n"; return;};
    Common::hash_to_xmlfile($book, "$work_dir/$control_file") if $work;

    $work = 0;
    eval {
    if ($mode eq "epub" && -s $html_file_clean) {
	print "Doing the epub.\n";
	opendir(DIR, "$work_dir");
	my @images = grep(/\.jpg$/,readdir(DIR));
	closedir(DIR);
	html_to_epub("$html_file_clean", $book);
	$book->{"epub"} = "done";
	unlink "$work_dir/$_" foreach (@images);
	unlink "$html_file_clean" || die "Can't remove file $html_file_clean: $!\n";
	$work++;
    }};
    if ($@) {print Dumper($@). "error: $?.\n"; return;};
    Common::hash_to_xmlfile($book, "$work_dir/$control_file") if $work;
}

sub import_html_to_wiki {
    my ($html, $images, $book) = @_;
    my ($author, $file, $title) =($book->{"auth"}, $book->{"file"}, $book->{"title"});
    my $work_dir = "$script_dir/$work_prefix/$title";
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

sub html_to_epub {
    my ($html_file, $book) = @_;
    my ($name, $dir, $ext) = fileparse($book->{"file"}, qr/\.[^.]*/);
    my $authors = $book->{'auth'};
    $name =  "$authors$url_sep$name";

    $dir = "$script_dir/AAA___epubs";
    Common::makedir("$dir");
    my $coperta = $book->{"coperta"} if defined $book->{"coperta"};
    my @tags = ();
    push @tags, "scurte" if defined $book->{'scurte'};
    push @tags, "medii" if defined $book->{'medii'};
    push @tags, "lungi" if defined $book->{'lungi'};
    push @tags, "ver=".$book->{'ver'} if defined $book->{'ver'};

    $book->{'title'} =~ s/\"/\\"/g;
    my ($name_fix, $html_file_fix) = ($name, $html_file);
    $name_fix =~ s/\"/\\"/g;
    $html_file_fix =~ s/\"/\\"/g;

    my $epub_command = "$extra_tools_dir/calibre/ebook-convert";
    my $epub_parameters = "--disable-font-rescaling --minimum-line-height=0 --toc-threshold=0 --smarten-punctuation --chapter=\"//*[(name()='h1' or name()='h2' or name()='h3' or name()='h4' or name()='h5')]\" --input-profile=default --output-profile=sony300 --max-toc-links=0 --language=ro --authors=\"$authors\" --title=\"".$book->{'title'}."\"";
    $epub_parameters .= " --tags=\"".(join ',', @tags)."\"" if scalar @tags;
    $epub_parameters .= " --series=\"".$book->{'seria'}."\" --series-index=\".$book->{'seria_no'}"."\"" if defined $book->{'seria'} && defined $book->{'seria_no'};
    $epub_parameters .= " --cover=\"$coperta\"" if defined $coperta;

    my ($out_file, $out_file_fix, $in_file, $output);
    ### normal epub
    print "Converting to epub.\n";
    $in_file = "$html_file_fix";
    $out_file_fix = "$dir/normal/$name_fix.epub";
    $out_file = "$dir/normal/$name.epub";
    Common::makedir("$dir/normal/");
#     $output = `$epub_command \"$in_file\" \"$out_file_fix\" $epub_parameters --no-default-epub-cover`;
#     die "file $out_file not created.\n".Dumper($in_file, $out_file, $output) if ! -s $out_file;

    $in_file = "$out_file_fix";
    ### epub with external font
    print "Converting to epub with external font.\n";
    $out_file_fix = "$dir/external/$name_fix.epub";
    $out_file = "$dir/external/$name.epub";
    Common::makedir("$dir/external/");
    $output = `$epub_command \"$in_file\" \"$out_file_fix\" $epub_parameters --no-default-epub-cover --extra-css=\"$script_dir/tools/external_font.css\"`;
    die "file $out_file not created.\n".Dumper($in_file, $out_file, $output) if ! -s $out_file;

    ### epub with embedded font
    print "Converting to epub with embedded font.\n";
    $out_file = "$dir/internal/$name.epub";
    $out_file_fix = "$dir/internal/$name_fix.epub";
    Common::makedir("$dir/internal/");
#     $output = `$epub_command \"$in_file\" \"$out_file_fix\" $epub_parameters --no-default-epub-cover --extra-css=\"$script_dir/tools/internal_font.css\"`;
#     Common::add_file_to_zip($out_file, "$script_dir/tools/$font");
#     die "file $out_file not created.\n".Dumper($in_file, $out_file, $output) if ! -s $out_file;

    ### epub with ascii chars
    print "Converting to ascii epub.\n";
    $out_file = "$dir/ascii/".Common::normalize_text("$name.epub");
    $out_file_fix = "$dir/ascii/".Common::normalize_text("$name_fix.epub");
    Common::makedir("$dir/ascii/");
#     $output = `$epub_command \"$in_file\" \"$out_file_fix\" $epub_parameters --no-default-epub-cover --asciiize`;
#     die "file $out_file not created.\n".Dumper($in_file, $out_file, $output) if ! -s $out_file;

    ### normal mobi
    print "Converting to mobi.\n";
    $out_file = "$dir/mobi/$name.mobi";
    $out_file_fix = "$dir/mobi/$name_fix.mobi";
    Common::makedir("$dir/mobi/");
    $output = `$epub_command \"$in_file\" \"$out_file_fix\" $epub_parameters`;
    die "file $out_file not created.\n".Dumper($in_file, $out_file, $output) if ! -s $out_file;

#     ### mobi with ascii chars
#     print "Converting to ascii mobi.\n";
#     $out_file = Common::normalize_text("$dir/ascii_mobi/$name.mobi");
#     Common::makedir("$dir/ascii_mobi/");
#     $output = `$epub_command \"$in_file\" \"$out_file\" --asciiize $epub_parameters`;
#     die "file $out_file not created.\n" if ! -s $out_file;

#     ### normal fb2
#     print "Converting to fb2.\n";
#     $out_file = "$dir/fb2/$name.fb2";
#     Common::makedir("$dir/fb2/");
#     `$epub_command \"$in_file\" \"$out_file\" $epub_parameters`;
    unlink $html_file;
}
#  -   --rating=between 1 and 5

sub synchronize_files {
#     my $files_to_import = get_new_documents;
    my ($files_already_imported, $files_to_import) = get_existing_documents (get_new_documents);
    print "\tDone.\n";
    my @arr1 = (keys %$files_already_imported);
    my @arr2 = (keys %$files_to_import);
    my ($only_in1, $only_in2, $common) = Common::array_diff(\@arr1, \@arr2);
    ## should delete $only_in1
    remove_tree("$script_dir/$work_prefix/$_") foreach (@$only_in1);
    return $files_to_import;
}

sub clean_files {
    my ($good_files, $new_files, $new_bad_files, $old_bad_files) = {};
    my $bad_file = "$script_dir/bad_files";
    my $new_file = "$script_dir/new_files";
    my $good_file = "$script_dir/good_files";

    if (-f $bad_file && ! -f "$bad_file.zip") {
	$old_bad_files = Common::xmlfile_to_hash("$bad_file");
    } elsif (! -f $bad_file && -f "$bad_file.zip") {
	$old_bad_files = Common::xmlfile_to_hash(Common::read_file_from_zip("$bad_file.zip", "bad_files"));
    } else {
	die "Error deciding between $bad_file and $bad_file.zip\n";
    }

    $good_files = get_files_from_dir($good_files_dir);
    Common::hash_to_xmlfile( $good_files, $good_file );
    $new_files = get_files_from_dir($new_files_dir);
    Common::hash_to_xmlfile( $new_files, $new_file );
    $new_bad_files = get_files_from_dir($bad_files_dir);
    Common::hash_to_xmlfile( $new_bad_files, "$bad_file.new" );

#     $good_files = Common::xmlfile_to_hash($good_file) if -f $good_file;
#     $new_files = Common::xmlfile_to_hash($new_file) if -f $new_file;
#     $new_bad_files = Common::xmlfile_to_hash("$bad_file.new");

    ## compare new bad files with old bad files
    my (@tmp1, @tmp2) = ();
    @tmp1 = (keys %$old_bad_files);
    @tmp2 = (keys %$new_bad_files);
    my ($only_in1, $only_in2, $common) = Common::array_diff(\@tmp1, \@tmp2);
    $old_bad_files->{$_} = $new_bad_files->{$_} foreach (@$only_in2);
    Common::hash_to_xmlfile( $old_bad_files, $bad_file );
    unlink ("$bad_file.zip");
    Common::add_file_to_zip("$bad_file.zip", $bad_file);
    unlink ($bad_file);
    ### all bad files are duplicate files
    $duplicate_files->{$new_bad_files->{$_}} = 1 foreach (@$common);
    $duplicate_files->{$new_bad_files->{$_}} = 1 foreach (@$only_in2);

    ## compare new files with bad files
    @tmp1 = (keys %$new_files);
    @tmp2 = (keys %$old_bad_files);
    ($only_in1, $only_in2, $common) = Common::array_diff(\@tmp1, \@tmp2);
    $duplicate_files->{$new_files->{$_}} = 1 foreach (@$common);

    ## compare new files with good files
    @tmp1 = (keys %$good_files);
    @tmp2 = (keys %$new_files);
    ($only_in1, $only_in2, $common) = Common::array_diff(\@tmp1, \@tmp2);
    $duplicate_files->{$new_files->{$_}} = 1 foreach (@$common);

    Common::hash_to_xmlfile( $duplicate_files, $duplicate_file );
    foreach my $key (keys %$duplicate_files) {
	my $file = decode_utf8($key);
	next, die "Dissapeared: $key\n" if ! -f $key;
	my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
	Common::makedir("$docs_prefix/duplicate/$dir/");
	move("$key", "$docs_prefix/duplicate/$dir/") || die "can't move duplicate file\n\t$key.\n";
	print Dumper("duplicate ".$file);
    }
}

sub wiki_site_to_epub {
    foreach my $book (sort @{$our_wiki->wiki_get_all_pages}) {
	my $work_dir = "$script_dir/$work_prefix/$book";
	next if -d "$work_dir";
	print "Start working for ".Encode::encode('utf8', $book).".\n";
	Common::makedir($work_dir);
	my $html_file = get_html_from_wikisite($book, $work_dir);
	my ($html, $images) = clean_html_wiki($html_file);
	Common::write_file(encode_utf8("$html_file"), HtmlClean::html_tidy($html));
	html_to_epub($html_file);
    }
}

sub ri_html_to_epub {
#     use Encode;
    my $html_file = $docs_prefix;
    my $html = Common::read_file("$html_file");
    my $images = ();
    $html = Encode::decode("iso-8859-1", $html);

    ($html, $images) = clean_html_ms ($html);
    print Dumper($images);
    Common::write_file(encode_utf8("__"."$html_file"), HtmlClean::html_tidy($html));
}

sub slave_threading {
    my $threads;
    my $running_thrd = 0;
    my $total_threads = 0;
    print "Starting threads for html clean and epub.\n";
    while (1) {
	my $DataElement = $DataQueue->peek;
	last if defined $DataElement && $DataElement eq 'undef';
	if (defined $DataElement && $running_thrd < $max_html_parse_threads){
	    $total_threads++;
	    $DataQueue->dequeue;
	    my $name = $DataElement->{'title'};
	    print "\t\t$total_threads ===starting thread $name\n";
	    my $t = threads->new(\&libreoffice_to_epub, $DataElement, "epub");
	    $running_thrd++;
	    $threads->{$name} = $t;
	    print "\t\t$total_threads ***running threads $running_thrd\n";
	} else {
	    usleep(300000);
	}
	foreach my $thr (keys %$threads) {
	    if ($threads->{$thr}->is_joinable()) {
		$threads->{$thr}->join();
		delete $threads->{$thr};
		$running_thrd--;
		print "\t\t$total_threads ---done with $thr\n";
	    }
	}
    }
    print "Done, waiting for last threads.\n";
    foreach my $thr (keys %$threads) {
	my $num = $threads->{$thr}->join();
	print "\t\t$total_threads ---done with $thr\n";
    }
    print "FIN ($running_thrd)*******************.\n";
}

sub transformer {
    my $files_to_import = synchronize_files;
    my $total = scalar (keys %$files_to_import);
    my $crt = 1;
    my $t = threads->new(\&slave_threading);

    foreach my $file (sort keys %$files_to_import) {
	my $type = $files_to_import->{$file}->{"type"};
	if ($type =~ m/\.docx?$/i || $type =~ m/\.odt$/i || $type =~ m/\.rtf$/i) {
	    print "start working for book $file: $crt out of $total.\n";
	    my ($html, $images) = libreoffice_to_epub($files_to_import->{$file}, "html");
# 	    import_html_to_wiki($html, $images, $files_to_import->{$file});
# 	} elsif ($type =~ m/\.html?$/i) {
	} elsif ($type =~ m/\.pdf$/i) {
# 	} elsif ($type =~ m/\.epub$/i) {
# 	} elsif ($type =~ m/\.zip$/i) {
	} else {
	    print Dumper($files_to_import->{$file})."\nUnknown file type: $type.\n";
	}
	$crt++;
    }
    $t->join();
}

if ($workign_mode eq "-ri") {
    ri_html_to_epub();
} elsif ($workign_mode eq "-clean") {
    clean_files();
} elsif ($workign_mode eq "-html" || $workign_mode eq "-epub") {
    transformer();
}


#######   epub to big html
#~/programe/calibre/ebook-convert Odiseea\ marţiană\ -\ maeştrii\ anticipaţiei\ clasice.epub Odiseea\ marţiană\ -\ maeştrii\ anticipaţiei\ clasice.htmlz
#######   run macro on doc
# rm -rf ~/.libreoffice/
# libreoffice -headless -invisible -nodefault -nologo -nofirststartwizard -norestore -convert-to swriter /dev/null
# cp /home/cristi/programe/scripts/carti/tools/libreoffice/Standard/* ~/.libreoffice/3/user/basic/Standard/
# libreoffice --headless --invisible --nocrashreport --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.embedImagesInWriter(/home/cristi/programe/scripts/carti/qq/index.html)"
# http://user.services.openoffice.org/en/forum/viewtopic.php?f=20&t=23909
#######   html to doc
# libreoffice -infilter="HTML (StarWriter)" -convert-to "ODF Text Document" ./q/Poul\ Anderson/index.html
