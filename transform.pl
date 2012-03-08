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

use File::Path qw(make_path remove_tree);
use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use URI::Escape;
use Time::HiRes qw(usleep nanosleep);
use File::stat;
use IO::Select;
use POSIX ":sys_wait_h";
# $SIG{CHLD} = 'IGNORE';

use Carti::HtmlClean;
use Carti::Common;
use Carti::WikiTxtClean;

my $script_dir = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
my $extra_tools_dir = "$script_dir/tools";

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
# my $work_prefix = "./work";
$work_prefix = abs_path($work_prefix);

my $debug = 1;
my $url_sep = " -- ";
my $font = "BookmanOS.ttf";
my $Xdisplay = ":12345";
# my $stdout = \*STDOUT;

use Devel::Size qw(size total_size);
# sub get_mem_info {
#     my @proc_mem = split /\s+/, Common::read_file("/proc/$$/stat");
#     my ($stat_threads, $stat_vsize, $stat_rss) = ($proc_mem[19], $proc_mem[22]/1024, $proc_mem[23]/1024);
#     my @system_mem = split /\n/, Common::read_file("/proc/meminfo");
#     s/(^[a-z]+:\s+)//i for(@system_mem);
#     s/(\s+[a-z]+$)//i for(@system_mem);
#     my ($sys_mem, $sys_mem_free, $sys_cache) = ($system_mem[0], $system_mem[1], $system_mem[3]);
#     print Dumper(
# "html queue ".total_size($DataQueue_html_clean),
# "calibre queue ".total_size($DataQueue_calibre_epub),
# "semaphore ".total_size($sema),
# );
#     return ($stat_threads, $stat_vsize, $stat_rss, $sys_mem, $sys_mem_free, $sys_cache);
# }

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

# my $libreoo_path = "/opt/libreoffice3.5/program/soffice";
my $libreoo_path = "soffice";
# my $libreoo_home = $ENV{"HOME"}."/.config/libreoffice/";
my $libreoo_home = $ENV{"HOME"}."/.libreoffice/";
sub doc_to_html_macro {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    Common::my_print "Start generating html file.\n";
    my $status;
    `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
    if (! -f "$libreoo_home/3/user/basic/Standard/" || -s "$libreoo_home/3/user/basic/Standard/" < 500) {
	Common::my_print "Doing initial config for libreoffice.\n";
	if (-d $libreoo_home){remove_tree("$libreoo_home") || die "Can't remove dir $libreoo_home: $!.\n"};
	system("$libreoo_path", "--headless", "--invisible", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", "swriter", "/dev/null") == 0 or die "creating initial libreoffice failed ($?): $!.\n";
	copy("$extra_tools_dir/libreoffice/Standard/Module1.xba", "$libreoo_home/3/user/basic/Standard/") or die "Copy failed libreoffice macros: $!\n";
    }
    eval {
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 600;
# 	system("Xvfb $Xdisplay -screen 0 1024x768x16 &");
# 	system("$libreoo_path", "--display", "$Xdisplay", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "macro:///Standard.Module1.ReplaceNBHyphenHTML($doc_file)") == 0 or die "libreoffice failed: $?";
	Common::my_print "Launching libreoffice.\n";
	system("$libreoo_path", "--headless", "--invisible", "--nocrashreport", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "macro:///Standard.Module1.ReplaceNBHyphenHTML($doc_file)") == 0 or die "libreoffice failed: $?";
	alarm 0;
    };
    $status = $?;
    if ($status) {
	printf "Error: Timed out: $status. Child exited with value %d\n", $status >> 8;
        `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
    } else {
	Common::my_print "Finished with status: $status.\n";
    }
    Common::my_print "Stop generating html file.\n";
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
	my ($name, $dir, $suffix) = fileparse($file, qr/\.[^.]*/);
	if ($name =~ m/(^\s+|\s+$|\s{2,})/ || $suffix ne lc($suffix)){
	    my $tmp1 = $name;
	    $tmp1 =~ s/(^\s+|\s+$)//i;
	    $tmp1 =~ s/\s+/ /ig;
	    my $tmp2 = $suffix;
	    $tmp2 = lc($suffix);
	    print "\"$name$suffix\" ==> \"$tmp1$tmp2\"\n";
	    move("$dir/$name$suffix", "$dir/$tmp1$tmp2") || die "can't move file $name$suffix.\n";
	    $file = "$dir/$tmp1$tmp2";
	    $name = $tmp1;
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
	$coperta = "$dir/$name.jpg" if -f "$dir/$name.jpg";
	($ver, $name) = get_version($name);
	($series, $series_no, $name) = get_series($name);
	my $key = "$auth$url_sep$name";
	die "Book already exists: $key ($file)\n".Dumper($files_to_import->{$key}) if defined $files_to_import->{$key};
	my $book->{"doc_file"} = "$file";
	$book->{"filesize"} = -s "$file";
	$book->{"filedate"} = stat($file)->mtime;
	$book->{"type"} = "$suffix";
	$book->{"coperta"} = "$coperta" if defined $coperta;
	$book->{"title"} = "$name";
	$book->{"md5"} = (defined $book &&
	      $book->{"filesize"} eq $book->{"filesize"} &&
	      $book->{"filedate"} eq $book->{"filedate"})
		    ? $book->{"md5"} : Common::get_file_md5("$file");
	$book->{"auth"} = $auth;
	$book->{"ver"} = $ver;
	$book->{"seria"} = $series;
	$book->{"seria_no"} = $series_no;

	my $working_file = "$work_prefix/$key/$name";
	$working_file =~ s/[:,]//g;
	$working_file = Common::normalize_text("$working_file");
	my ($name_x,$dir_x,$suffix_x) = fileparse($working_file, qr/\.[^.]*/);
	$book->{"safe_name"} = "$name_x";
	$book->{"workingdir"} = "$dir_x";
	$book->{"workingfile"} = "$name_x$suffix";
	$book->{"html_file"} = "$dir_x$name_x.html";
	$book->{"html_file_orig"} = "$dir_x$name_x\_orig.html";
	$book->{"html_file_clean"} = "$dir_x$name_x\_clean.html";

	$files_to_import->{$key} = $book;
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
    my $xml_book = shift;
    my $book = Common::xmlfile_to_hash("$xml_book");
    my ($file, $workingfile, $work_dir, $title, $html_file, $html_file_orig) =($book->{"doc_file"}, $book->{"workingfile"}, $book->{"workingdir"}, $book->{"title"}, $book->{"html_file"}, $book->{"html_file_orig"});

    my $working_file = "$work_dir/$workingfile";
    Common::my_print_prepand("\t ");
    eval{
    if (not defined $book->{"libreoffice"}) {
	print "Doing the doc to html conversion for $title.\n";
	Common::makedir($work_dir);
	copy($file, $working_file) or die "Copy failed \n\t$file\n\t$working_file: $!\n";
	my $res = doc_to_html_macro($working_file);
	die "Can't generate html $html_file.\n" if ($res || ! -s $html_file);
	move("$html_file", "$html_file_orig") || die "can't move file $html_file.\n";
	my $zip_file = "$work_dir/$title.zip";
	Common::add_file_to_zip("$zip_file", "$file");
	unlink $working_file || die "Can't remove file $working_file: $!\n";
	$book->{"libreoffice"} = "done";
	Common::hash_to_xmlfile($book, "$xml_book");
    }};
    print "XXXX ERROR\n".Dumper($title, $@). "error: $?.\n" if ($@);
}

sub libreoffice_html_clean {
    my $xml_book = shift;
    my $book = Common::xmlfile_to_hash("$xml_book");
    my $file_max_size_single_thread = 10000000;
    my ($work_dir, $title, $html_file_clean, $html_file_orig) =($book->{"workingdir"}, $book->{"title"}, $book->{"html_file_clean"}, $book->{"html_file_orig"});

    eval {
    if (! defined $book->{"html_clean"} && -s $html_file_orig) {
	print "Doing the html cleanup for $title.\n";
	my ($html, $images) = HtmlClean::clean_html_from_oo(Common::read_file($html_file_orig), $title);
	my $cover = convert_images ($images, $work_dir);
	Common::write_file($html_file_clean, $html);
	$book->{'scurte'} = 1 if (length($html) <= 35000);
	$book->{'medii'} = 1 if (length($html) >= 30000 && length($html) <= 450000);
	$book->{'lungi'} = 1 if (length($html) >= 400000);
	$book->{'coperta'} = $cover if ! defined $book->{'coperta'} && defined $cover;
	$book->{"html_clean"} = "done";
	unlink "$html_file_orig" || die "Can't remove file $html_file_orig: $!\n";
	Common::hash_to_xmlfile($book, $xml_book);
    }};
    print Dumper($title, $@). "error: $?.\n" if ($@);
}

sub libreoffice_html_to_epub {
    my $xml_book = shift;
    my $book = Common::xmlfile_to_hash("$xml_book");
    my ($work_dir, $title, $html_file_clean) = ($book->{"workingdir"}, $book->{"title"}, $book->{"html_file_clean"});

    eval {
    if (not defined $book->{"epub"} && -s $html_file_clean) {
	Common::my_print "Doing epubs for $title.\n";
	opendir(DIR, "$work_dir");
	my @images = grep(/\.jpg$/,readdir(DIR));
	closedir(DIR);
	$book = html_to_epub($book);
	$book->{"epub"} = "done";
	unlink "$work_dir/$_" foreach (@images);
	unlink "$html_file_clean" || die "Can't remove file $html_file_clean: $!\n";
	Common::hash_to_xmlfile($book, $xml_book);
    }};
    print Dumper($title, $@). "error: $?.\n" if ($@);
}

sub html_to_epub {
    my $book = shift;
    my ($name, $authors, $dir, $html_file, $title) = ($book->{'safe_name'}, $book->{'auth'}, $book->{'workingdir'}, $book->{"html_file_clean"}, $book->{'title'});
    my @tags = ();
    push @tags, "scurte" if defined $book->{'scurte'};
    push @tags, "medii" if defined $book->{'medii'};
    push @tags, "lungi" if defined $book->{'lungi'};
    push @tags, "ver=".$book->{'ver'} if defined $book->{'ver'};

    $title =~ s/\"/\\"/g;
    my ($name_fix, $html_file_fix) = ($name, $html_file);
    $name_fix =~ s/\"/\\"/g;
    $html_file_fix =~ s/\"/\\"/g;

    my $epub_command = "$extra_tools_dir/calibre/ebook-convert";
    my $epub_parameters = "--disable-font-rescaling --minimum-line-height=0 --toc-threshold=0 --smarten-punctuation --chapter=\"//*[(name()='h1' or name()='h2' or name()='h3' or name()='h4' or name()='h5')]\" --input-profile=default --output-profile=sony300 --max-toc-links=0 --language=ro --authors=\"$authors\" --title=\"$title\"";
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
    my $html_file = $docs_prefix;
    my $html = Common::read_file("$html_file");
    my $images = ();
    $html = Encode::decode("iso-8859-1", $html);

    ($html, $images) = clean_html_ms ($html);
    print Dumper($images);
    Common::write_file(encode_utf8("__"."$html_file"), HtmlClean::html_tidy($html));
}

sub focker_launcher {
    my ($function, $max_nr_threads, $str_prepand, $ref2fh) = @_;
    print "starting forker process $str_prepand\n";
    my @queue;
    my $running;
    my @thread = (1..$max_nr_threads);
    my $s = IO::Select->new();
    $s->add(\*STDIN);

    while (1) {
	my $DataElement = <STDIN> if ($s->can_read(.1));
	push @queue, $DataElement if defined $DataElement;
	if ((scalar keys %$running) < $max_nr_threads && scalar @queue){
	    die "Can't have this.\n".Dumper(@thread) if not scalar @thread;
	    $DataElement = shift @queue;
	    next if not defined $DataElement;
	    my $crt = shift @thread;
	    chomp $DataElement;
	    last if $DataElement eq 'undef';
	    my $name = (split /$url_sep/, ((split /\/+/, $DataElement)[-2]))[-1];
	    my $crt_thread = scalar @queue;
	    my $pid = fork();
	    if(defined ($pid) and $pid==0) {
		Common::my_print_prepand("$crt $str_prepand $name ");
		$function->("$DataElement", $crt);
		print $ref2fh "$DataElement\n" if defined $ref2fh;
# print Dumper($DataElement,$ref2fh);
		exit (0);
	    }
	    $running->{$pid}->{'thread_nr'} = $crt;
	    $running->{$pid}->{'xml_file'} = $DataElement;
	    $running->{$pid}->{'name'} = $name;
	}
	my $pid = -2;
	while ($pid && $pid != -1) {
# print "xxx $str_prepand $pid ".(scalar @queue).Dumper($DataElement);
	    $pid = waitpid(-1, WNOHANG);
	    if ($pid > 0) {
		print "$str_prepand reapead $running->{$pid}->{'name'}\n" if $pid > 0;
		push @thread, $running->{$pid}->{'thread_nr'};
# 		print $ref2fh $running->{$pid}->{'xml_file'}."\n" if defined $ref2fh;
		delete $running->{$pid};
	    }
	};
	usleep(100000);
    }
    my $pid = -2;
    while (scalar keys %$running) {
	$pid = waitpid(-1, WNOHANG);
	if ($pid > 0) {
		print "$str_prepand reapead $running->{$pid}->{'name'}\n" if $pid > 0;
		push @thread, $running->{$pid}->{'thread_nr'};
# 		print $ref2fh $running->{$pid}->{'xml_file'}."\n" if defined $ref2fh;
		delete $running->{$pid};
	}
    };
    print $ref2fh "undef\n" if defined $ref2fh;
}

sub epub_process_launcher {
# select STDOUT; $| = 1;
    print "starting epuber process\n";
    my $str_prepand = "  epub";
    focker_launcher(\&libreoffice_html_to_epub, 6, $str_prepand);
    print "(epuber). FIN *******************.\n";
}

sub cleaner_process_launcher {
    print "starting cleaner process\n";
    my $str_prepand = "   clean";
    my $pid_epub = open(EPUB, "|-");
    autoflush EPUB  1;
    die "cannot fork epuber\n" if ! defined $pid_epub;
    if (!$pid_epub){epub_process_launcher();exit 0;};
    focker_launcher(\&libreoffice_html_clean, 6, $str_prepand, \*EPUB);
    print "(cleaner). FIN *******************.\n";
    usleep(100000) while (! eof EPUB);
    close(EPUB);
    print "closed epub queue\n";
}

sub main_process_worker {
    print "starting main thread\n";
    my $pid_clean = open(CLEANER, "|-");
    autoflush CLEANER  1;
    die "cannot fork cleaner\n" if ! defined $pid_clean;
    if (!$pid_clean){cleaner_process_launcher();exit 0;};

    my $files_to_import = synchronize_files;
    my $crt = 1;
    foreach my $file (sort keys %$files_to_import) {
	my $type = $files_to_import->{$file}->{"type"};
	my $xml_file = "$files_to_import->{$file}->{'workingdir'}/$control_file";
	if ($type =~ m/\.docx?$/i || $type =~ m/\.odt$/i || $type =~ m/\.rtf$/i) {
	    Common::hash_to_xmlfile($files_to_import->{$file}, $xml_file);
	    libreoffice_to_html($xml_file);
	    print CLEANER "$xml_file\n";
	} elsif ($type =~ m/\.pdf$/i) {
	} else {
	    print Dumper($files_to_import->{$file})."\nUnknown file type: $type.\n";
	}
	$crt++;
# last if $crt>10;
    }
    print "0 (loffice). FIN *******************.\n";
    print CLEANER "undef\n";
    usleep(100000) while (! eof CLEANER);
    close(CLEANER);
    print "closed clean queue\n";
}

if ($workign_mode eq "-ri") {
    ri_html_to_epub();
} elsif ($workign_mode eq "-clean") {
    clean_files();
} elsif ($workign_mode eq "-epub") {
    main_process_worker();
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
