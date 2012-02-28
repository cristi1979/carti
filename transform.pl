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

# my $os = $^O;
# $os = "windows" if $^O eq "MSWin32";
use File::Find;
use File::Copy;
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";
use Devel::Size qw(size);

use HTML::WikiConverter;
use File::Path qw(make_path remove_tree);
use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use URI::Escape;
use Time::HiRes qw(usleep nanosleep);
use File::stat;

use threads;
use threads::shared;
use Thread::Semaphore;
use Thread::Queue;

use Carti::WikiWork;
use Carti::HtmlClean;
use Carti::Common;
use Carti::WikiTxtClean;

my $DataQueue_html_clean = Thread::Queue->new();
my $DataQueue_calibre_epub = Thread::Queue->new();
my $sema = Thread::Semaphore->new();

my $script_dir = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
my $extra_tools_dir = "$script_dir/tools";
my $wiki_site = "http://192.168.0.163/wiki";
my ($wiki_user, $wiki_pass, $wiki_original_files) = ("admin", "qwaszx", "$wiki_site/fisiere_originale");
my $our_wiki;

my $workign_mode = shift;
my $docs_prefix = shift;
$docs_prefix = abs_path($docs_prefix);
my $good_files_dir = "$docs_prefix/aaa_aaa/";
my $bad_files_dir = "$docs_prefix/ab_aaa - RAU/";
my $new_files_dir = "$docs_prefix/ac_noi/";
our $duplicate_files = {};
my $duplicate_file = "$script_dir/duplicate_files";

my $control_file = "doc_info_file.xml";
my $work_prefix = "/media/carti/work";
my $epub_dir = "$work_prefix/../AAA___epubs";

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
# my $libreoo_path = "/opt/libreoffice3.5/program/soffice";
my $libreoo_path = "soffice";
# my $libreoo_home = $ENV{"HOME"}."/.config/libreoffice/";
my $libreoo_home = $ENV{"HOME"}."/.libreoffice/";
sub doc_to_html_macro {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    Common::my_print "\tStart generating html file.\n";
    my $status;
    if ($first_time == 0) {
	`kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
	remove_tree("$libreoo_home") || die "Can't remove dir $libreoo_home: $!.\n" if -d "$libreoo_home";
	system("$libreoo_path", "--headless", "--invisible", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", "swriter", "/dev/null") == 0 or die "libreoffice failed: $?";
	copy("$extra_tools_dir/libreoffice/Standard/Module1.xba", "$libreoo_home/3/user/basic/Standard/") or die "Copy failed libreoffice macros: $!\n";
	$first_time++;
    }
    `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
#     system("Xvfb $Xdisplay -screen 0 1024x768x16 &");
    eval {
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 600;
# 	system("$libreoo_path", "--display", "$Xdisplay", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "macro:///Standard.Module1.ReplaceNBHyphenHTML($doc_file)") == 0 or die "libreoffice failed: $?";
	system("$libreoo_path", "--headless", "--invisible", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "macro:///Standard.Module1.ReplaceNBHyphenHTML($doc_file)") == 0 or die "libreoffice failed: $?";
	alarm 0;
    };
    $status = $?;
    if ($status) {
	printf "Error: Timed out: $status. Child exited with value %d\n", $status >> 8;
        `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
    } else {
	Common::my_print "\tFinished with status: $status.\n";
    }
    Common::my_print "\tStop generating html file.\n";
    return 0;
}

sub doc_to_html {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    print "\t-Generating html file from $doc_file.\n";
    my $status;
    `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
    eval {
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
	    system("Xvfb $Xdisplay -screen 0 1024x768x16 &> /dev/null &");
	    system("$libreoo_path", "--display", "$Xdisplay", "--unnaccept=all", "--invisible", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", "html:HTML (StarWriter)", "--outdir", "$dir", "$doc_file") == 0 or die "libreoffice failed: $?";
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

sub get_documents {
    our $files_already_imported = shift;
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
	my $key = "$auth$url_sep$book";
	die "Book already exists: $key ($file)\n".Dumper($files_to_import->{"$key"}) if defined $files_to_import->{"$key"};
	$files_to_import->{"$key"}->{"file"} = "$file";
	$files_to_import->{"$key"}->{"filesize"} = -s "$file";
	$files_to_import->{"$key"}->{"filedate"} = stat($file)->mtime;
	$files_to_import->{"$key"}->{"type"} = "$suffix";
	$files_to_import->{"$key"}->{"coperta"} = "$coperta" if defined $coperta;
	$files_to_import->{"$key"}->{"title"} = "$book";
	$files_to_import->{"$key"}->{"md5"} = (defined $files_already_imported->{$key} &&
	      $files_already_imported->{$key}->{"filesize"} eq $files_to_import->{"$key"}->{"filesize"} &&
	      $files_already_imported->{$key}->{"filedate"} eq $files_to_import->{"$key"}->{"filedate"})
		    ? $files_already_imported->{"$key"}->{"md5"} : Common::get_file_md5("$file");
	$files_to_import->{"$key"}->{"auth"} = $auth;
	$files_to_import->{"$key"}->{"ver"} = $ver;
	$files_to_import->{"$key"}->{"seria"} = $series;
	$files_to_import->{"$key"}->{"seria_no"} = $series_no;
# 	my ($name,$dir,$ext) = (Common::normalize_text($file), qr/\.[^.]*/);
	my $work_dir = "$work_prefix/$key";
	$work_dir =~ s/[:,]//g;
	$files_to_import->{"$key"}->{"workdir"} = Common::normalize_text("$work_dir");

	my $working_file = "$work_dir/$book";
	$working_file =~ s/[:,]//g;
	$files_to_import->{"$key"}->{"workingfile"} = Common::normalize_text("$working_file")."$suffix";
	$files_to_import->{"$key"}->{"html_file"} = Common::normalize_text("$working_file").".html";
	$files_to_import->{"$key"}->{"html_file_orig"} = Common::normalize_text("$working_file")."_orig.html";
	$files_to_import->{"$key"}->{"html_file_clean"} = Common::normalize_text("$working_file")."_clean.html";

	if (defined $files_already_imported->{$key}) {
	    my $crt_file = $files_already_imported->{$key};
	    foreach my $akey (keys %$crt_file){
		$files_to_import->{"$key"}->{$akey} = $crt_file->{$akey} if ! defined $files_to_import->{"$key"}->{$akey};
	    }
	}
    }
    print "Get all files.\n";
    find ({wanted => sub { add_document ($File::Find::name) if -f },},"$docs_prefix") if -d "$docs_prefix";
    return $files_to_import;
}

sub get_existing_documents {
#     my $documents_to_import = shift;
    our $files_already_imported = {};
    my $work_dir = "$work_prefix/";
    die "Working dir $work_dir is a file.\n" if -f $work_dir;
    return if ! -d $work_dir;
    print "Get already done files from $work_dir.\n";
#     Common::makedir($work_dir);
    $work_dir = abs_path("$work_prefix/");
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
	$files_already_imported->{$title} = Common::xmlfile_to_hash("$dir/$control_file");
    }
    return ($files_already_imported);
}

sub synchronize_files {
    my $files_already_imported = get_existing_documents;
    my $files_to_import = get_documents($files_already_imported);
    print "\tDone.\n";
#     my @arr1 = (keys %$files_already_imported);
#     my @arr2 = (keys %$files_to_import);
#     my ($only_in1, $only_in2, $common) = Common::array_diff(\@arr1, \@arr2);
#     ## should delete $only_in1
#     remove_tree("$work_prefix/$_") foreach (@$only_in1);
    return $files_to_import;
}

sub convert_images {
    my ($images, $work_dir) = @_;
    my $cover = ();
    foreach my $key (sort keys %$images) {
	my $orig_name = $key;
	my $new_name = $images->{$key}->{"name"};
	if (! -f "$work_dir/$orig_name") {
	    die "Missing image $work_dir/$orig_name.\n";
	    next;
	}
	Common::my_print "\tConverting file $orig_name to $new_name.\n";
	system("convert", "$work_dir/$orig_name", "-background", "white", "-flatten", "$work_dir/$new_name") == 0 or die "error runnig convert: $!.\n";
# copy("$work_dir/$orig_name", "$work_dir/$new_name");
	$cover = "$work_dir/$new_name" if $images->{$key}->{"nr"} == 0;
	unlink "$work_dir/$orig_name";
    }
    return $cover;
}

sub libreoffice_to_html {
    my $book = shift;
    my ($file, $working_file, $work_dir, $title, $html_file, $html_file_orig) =($book->{"file"}, $book->{"workingfile"}, $book->{"workdir"}, $book->{"title"}, $book->{"html_file"}, $book->{"html_file_orig"});

    my $work = 0;
    eval{
    if (!(defined $book->{"libreoffice"} && $book->{"libreoffice"} eq "done")) {
	Common::my_print "Doing the doc to html conversion for $title.\n";
	remove_tree("$work_dir") || die "Can't remove dir $work_dir: $!.\n" if -d "$work_dir";
	Common::makedir($work_dir);
	copy("$file", $working_file) or die "Copy failed $working_file: $!\n";
	my $res = doc_to_html_macro("$working_file");
	die "Can't generate html $html_file.\n" if ($res || ! -s $html_file);# {; return $crt_thread;};
	move("$html_file", "$html_file_orig") || die "can't move file $html_file.\n";
	my $zip_file = "$work_dir/$title.zip";
	Common::add_file_to_zip("$zip_file", "$file");
	unlink $working_file || die "Can't remove file $working_file: $!\n";
	$book->{"libreoffice"} = "done";
	$work++;
    }};
    if ($@) {print "XXXX ERROR\n".Dumper($title, $@). "error: $?.\n"; return;}
    $DataQueue_html_clean->enqueue($book);
    Common::hash_to_xmlfile($book, "$work_dir/$control_file") if $work;
}

my %waiters :shared;
sub libreoffice_html_clean {
    my ($book, $crt_thread) = @_;
    my $file_max_size_single_thread = 5000000;
# return $crt_thread;
    my ($file, $working_file, $work_dir, $title, $html_file_clean, $html_file_orig) =($book->{"file"}, $book->{"workingfile"}, $book->{"workdir"}, $book->{"title"}, $book->{"html_file_clean"}, $book->{"html_file_orig"});

    my $work = 0;
    my $html_file_orig_size = (-s "$html_file_orig");
    return $crt_thread if ! defined $html_file_orig_size;
    $waiters{$title} = $crt_thread;
    $sema->down;
#     while (! $sema->down_nb){usleep(300000); Common::my_print "Waiting for lock in \n\t$title \nfrom :\n\t$latest_locker.\n";
    if ($html_file_orig_size < $file_max_size_single_thread){
	$sema->up;
    } else {
	while (1) {
	    my $max = 0;
	    my $worker = "";
	    foreach (sort keys %waiters){
		$max = $waiters{$_} if $max < $waiters{$_};
		$worker .= "$_;" if $waiters{$_} > 100;
	    };
	    last if $max<100;
	    my $str = "";
	    $str .= "\t\t$_: $waiters{$_}.\n" foreach (sort keys %waiters);
	    Common::my_print "Waiting in $title. Working: $worker. Others : \n$str\n";
	    sleep 1;
	}
    }
    $waiters{$title} = $crt_thread*100;

    eval {
    if (!(defined $book->{"html_clean"} && $book->{"html_clean"} eq "done")  && -s $html_file_orig) {
	Common::my_print "Doing the html cleanup for $title.\n";
	my $obj = new HtmlClean;
	my ($html, $images) = $obj->clean_html_from_oo(Common::read_file($html_file_orig));
# 	my $html = Common::read_file("$html_file_orig"); my $images;
	Common::write_file("$html_file_clean", $html);
	$book->{'scurte'} = 1 if (length($html) <= 35000);
	$book->{'medii'} = 1 if (length($html) >= 30000 && length($html) <= 450000);
	$book->{'lungi'} = 1 if (length($html) >= 400000);
	unlink "$html_file_orig" || die "Can't remove file $html_file_orig: $!\n";
	my $cover = convert_images ($images, $work_dir);
	$book->{'coperta'} = $cover if ! defined $book->{'coperta'} && defined $cover;
	$book->{"html_clean"} = "done";
	$work++;
	undef $obj;
    }};
    delete $waiters{$title};
    $sema->up if !($html_file_orig_size < $file_max_size_single_thread);
    if ($@) {print Dumper($title, $@). "error: $?.\n"; return $crt_thread;};
    $DataQueue_calibre_epub->enqueue($book);
    Common::hash_to_xmlfile($book, "$work_dir/$control_file") if $work;

    return $crt_thread;
}

sub libreoffice_html_to_epub {
    my ($book, $crt_thread) = @_;
    my ($work_dir, $title, $html_file_clean) =($book->{"workdir"}, $book->{"title"}, $book->{"html_file_clean"});
    my $work = 0;
    return $crt_thread if ! defined $html_file_clean;
    eval {
    if (-s $html_file_clean) {
	Common::my_print "Doing epubs for $title.\n";
	opendir(DIR, "$work_dir");
	my @images = grep(/\.jpg$/,readdir(DIR));
	closedir(DIR);
	$book = html_to_epub("$html_file_clean", $book);
	$book->{"epub"} = "done";
	unlink "$work_dir/$_" foreach (@images);
	unlink "$html_file_clean" || die "Can't remove file $html_file_clean: $!\n";
	$work++;
    }};
    if ($@) {print Dumper($title, $@). "error: $?.\n"; return $crt_thread;};
    Common::hash_to_xmlfile($book, "$work_dir/$control_file") if $work;
    return $crt_thread;
}

sub html_to_epub {
    my ($html_file, $book) = @_;
    my ($name, $dir, $ext) = fileparse($book->{"file"}, qr/\.[^.]*/);
    my $authors = $book->{'auth'};
    $name =  "$authors$url_sep$name";

    $dir = "$epub_dir";
    Common::makedir("$dir");
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
# --keep-ligatures --rating=between 1 and 5
    $epub_parameters .= " --tags=\"".(join ',', @tags)."\"" if scalar @tags;
    $epub_parameters .= " --series=\"".$book->{'seria'}."\" --series-index=\".$book->{'seria_no'}"."\"" if defined $book->{'seria'} && defined $book->{'seria_no'};
    $epub_parameters .= " --cover=\"$book->{'coperta'}\"" if defined $book->{'coperta'};

    my ($out_file, $out_file_fix, $in_file, $output);
    $in_file = "$html_file_fix";

    ### normal epub
#     $out_file = "$dir/normal/$name.epub";
#     $out_file_fix = "$dir/normal/$name_fix.epub";
#     if (! (defined $book->{'epub_normal'} && -s $out_file_fix)){
#     Common::my_print "Converting to epub.\n";
#     Common::makedir("$dir/normal/");
#     $output = `$epub_command \"$in_file\" \"$out_file_fix\" $epub_parameters --no-default-epub-cover`;
#     die "file $out_file not created.\n".Dumper($in_file, $out_file, $output) if ! -s $out_file;
#     }
#     $book->{'epub_normal'} = "$out_file";

#     $in_file = "$out_file_fix";
    ### epub with external font
    $out_file = "$dir/external/$name.epub";
    $out_file_fix = "$dir/external/$name_fix.epub";
    if (! (defined $book->{'epub_external'} && -s $out_file_fix)){
    Common::my_print "Converting to epub with external font.\n";
    Common::makedir("$dir/external/");
    $output = `$epub_command \"$in_file\" \"$out_file_fix\" $epub_parameters --no-default-epub-cover --extra-css=\"$script_dir/tools/external_font.css\"`;
    die "file $out_file not created.\n".Dumper($in_file, $out_file, $output) if ! -s $out_file;
    }
    $book->{'epub_external'} = "$out_file";

    ### epub with embedded font
    $out_file = "$dir/internal/$name.epub";
    $out_file_fix = "$dir/internal/$name_fix.epub";
    if (! (defined $book->{'epub_embedded'} && -s $out_file_fix)){
    Common::my_print "Converting to epub with embedded font.\n";
    Common::makedir("$dir/internal/");
    $output = `$epub_command \"$in_file\" \"$out_file_fix\" $epub_parameters --no-default-epub-cover --extra-css=\"$script_dir/tools/internal_font.css\"`;
    Common::add_file_to_zip($out_file, "$script_dir/tools/$font");
    die "file $out_file not created.\n".Dumper($in_file, $out_file, $output) if ! -s $out_file;
    }
    $book->{'epub_embedded'} = "$out_file";

    ### normal mobi
    $out_file = "$dir/mobi/$name.mobi";
    $out_file_fix = "$dir/mobi/$name_fix.mobi";
    if (! (defined $book->{'epub_mobi'}  && -s $out_file_fix)){
    Common::my_print "Converting to mobi.\n";
    Common::makedir("$dir/mobi/");
    $output = `$epub_command \"$in_file\" \"$out_file_fix\" $epub_parameters`;
    die "file $out_file not created.\n".Dumper($in_file, $out_file, $output) if ! -s $out_file;
    }
    $book->{'epub_mobi'} = "$out_file";

    return $book;
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

sub threading_my_shit {
    my ($function, $queue, $max_html_parse_threads, $str_prepand) = @_;
    my @thread = (1..$max_html_parse_threads);
    my $running_threads = {};

    print "Starting $max_html_parse_threads threads for $str_prepand.\n";
    while (1) {
	my $DataElement = $queue->peek;
	last if defined $DataElement && $DataElement eq 'undef';
	if (defined $DataElement && (scalar keys %$running_threads) < $max_html_parse_threads){
	    $queue->dequeue;
	    my $name = $DataElement->{'title'};
	    my $crt_thread = shift @thread;
	    Common::my_print_prepand("$crt_thread ($str_prepand). $name ");
	    my $t = threads->create($function, $DataElement, $crt_thread);
	    $running_threads->{$name} = $t;
	    Common::my_print "New thread launched. Running threads: ".(scalar threads->list)." (pending: ".$queue->pending().") \n\t\t".(join ";\n\t\t",(sort keys %$running_threads))."\n";
	} else {
	    usleep(300000);
	}
	foreach my $name (keys %$running_threads) {
	    if ($running_threads->{$name} > 0 && $running_threads->{$name}->is_joinable()) {
		my $crt_thread = $running_threads->{$name}->join();
		delete $running_threads->{$name};
		print "x ($str_prepand). Done with thread $crt_thread: $name\n";
		push @thread, $crt_thread;
	    }
	}
    }
    print "Done, waiting for last threads.\n";
    foreach my $name (keys %$running_threads) {
	my $crt_thread = $running_threads->{$name}->join();
	print "x ($str_prepand). Done with thread $crt_thread: $name\n";
    }
    print "z ($str_prepand). FIN *******************.\n";
}

sub transformer {
    my $t = threads->new(\&threading_my_shit, \&libreoffice_html_clean, $DataQueue_html_clean, 2, "  clean");
    my $w = threads->new(\&threading_my_shit, \&libreoffice_html_to_epub, $DataQueue_calibre_epub, 3, "   epub");
    my $files_to_import = synchronize_files;
    my $total = scalar (keys %$files_to_import);
    my $crt = 1;

    foreach my $file (sort keys %$files_to_import) {
	my $type = $files_to_import->{$file}->{"type"};
	if ($type =~ m/\.docx?$/i || $type =~ m/\.odt$/i || $type =~ m/\.rtf$/i) {
	    Common::my_print_prepand("0 (loffice). $files_to_import->{$file}->{'title'} ");
	    my ($html, $images) = libreoffice_to_html($files_to_import->{$file});
# 	    import_html_to_wiki($html, $images, $files_to_import->{$file});
	} elsif ($type =~ m/\.pdf$/i) {
	} else {
	    print Dumper($files_to_import->{$file})."\nUnknown file type: $type.\n";
	}
	$crt++;
    }
    $DataQueue_html_clean->enqueue('undef');
    $DataQueue_calibre_epub->enqueue('undef');
    $t->join();
    $w->join();
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
