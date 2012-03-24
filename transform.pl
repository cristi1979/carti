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
use POSIX ":sys_wait_h";
use DBI;

use Carti::HtmlClean;
use Carti::Common;

my $script_dir = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
my $extra_tools_dir = "$script_dir/tools";

my $workign_mode = shift;
# my $docs_prefix = shift;
# my $docs_prefix = "/media/carti/aaa_aaa/";
# my $docs_prefix = "/media/ceva1/Audio/Carti/aaa_aaa/";
# my $docs_prefix = "/media/wiki_rem/media/share/Documentation/cfalcas/q/carti/www";
my $docs_prefix = "/media/ceva1/Audio/Carti/";
$docs_prefix = abs_path($docs_prefix);

my $good_files_dir = "$docs_prefix/aaa_aaa/";
my $bad_files_dir = "$docs_prefix/ab_aaa - RAU/";
my $new_files_dir = "$docs_prefix/ac_noi/";
our $duplicate_files = {};
my $duplicate_file = "$script_dir/duplicate_files";

my $control_file = "doc_info_file.xml";
# my $work_prefix = "/media/carti/work";
my $work_prefix = "/media/ceva2/downloads/work";
# my $work_prefix = "./work";
$work_prefix = abs_path($work_prefix);
Common::makedir($work_prefix);
my $path_to_db_file = "/dev/shm/sqlitedb.sqlite";

my $debug = 1;
my $retry_on_fail = 0;
my $extract_cover = 0;
my $url_sep = " -- ";
my $font = "BookmanOS.ttf";
my $Xdisplay = ":12345";

my $table_work_name = "WORK";
my $table_work_def = "
    XML_FILE TEXT UNIQUE,
    WORKER_NAME TEXT,
    STATUS TEXT,
    PID INTEGR";
my $table_info_name = "INFO";
my $table_info_def = "
    LIBREOFFICE INTEGER,
    CLEAN INTEGER,
    EBOOK INTEGER,
    LIBREOFFICE_RUNNING INTEGER,
    CLEAN_RUNNING INTEGER,
    EBOOK_RUNNING INTEGER,
    LIBREOFFICE_DONE INTEGER,
    CLEAN_DONE INTEGER,
    EBOOK_DONE INTEGER,
    ALL_DONE INTEGER,
    SINGLE_MODE TEXT";

sub dbi_error_handler {
    my( $message, $handle, $first_value ) = @_;
    die "Caught: \n".Dumper($message, $handle, $first_value);
}

sub connect_sqlite {
    my ($dbh, $db_name) = @_;
    $dbh = DBI->connect("dbi:SQLite:dbname=$db_name","","",
	    { RaiseError => 1,
	      AutoCommit => 1,
	      sqlite_use_immediate_transaction => 1,
	      PrintError         => 1,
	      ShowErrorStatement => 1,
	      HandleError        => \&dbi_error_handler,
	    }) || die "Cannot connect: $DBI::errstr";
    $dbh->do("PRAGMA synchronous  = ON");
    $dbh->do("PRAGMA temp_store  = MEMORY");
    $dbh->do("PRAGMA cache_size  = 4000000");
    return $dbh;
}

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
	$tmp =~ s/(^\s+|\s+$)//g;
	my @tmp1 = split /\s/, $tmp;
	my $tmp1 = (pop @tmp1).", ". join " ", @tmp1;
	$tmp1 =~ s/(^\s+|\s+$)//g;
	$authors->{$tmp} = "nume prenume";
	$authors->{$tmp1} = "prenume, nume";
    }
    return $authors;
}

sub get_version {
    my $file = shift;
    my $ver;
    $ver = $2 if ($file =~ m/(\s\[([0-9]+(\.[0-9]+)+)\])$/i);
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
# my $libreoo_home = $ENV{'HOME'}."/.config/libreoffice/";
my $libreoo_home = $ENV{'HOME'}."/.libreoffice/";
sub doc_to_html_macro {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    Common::my_print "Start generating html file.\n";
    my $status;
    `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}') &>/dev/null`;
    if (! -f "$libreoo_home/3/user/basic/Standard/" || -s "$libreoo_home/3/user/basic/Standard/" < 500) {
	Common::my_print "Doing initial config for libreoffice.\n";
	if (-d $libreoo_home){remove_tree("$libreoo_home") || die "Can't remove dir $libreoo_home: $!.\n"};
	system("$libreoo_path", "--headless", "--invisible", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", "swriter", "/dev/null") == 0 or die "creating initial libreoffice failed ($?): $!.\n";
	copy("$extra_tools_dir/libreoffice/Standard/Module1.xba", "$libreoo_home/3/user/basic/Standard/") or die "Copy failed libreoffice macros: $!\n";
    }
    eval {
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 600;
# 	system("Xvfb $Xdisplay -screen 0 1024x768x16 &");
# 	system("$libreoo_path", "--display", "$Xdisplay", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "macro:///Standard.Module1.ReplaceNBHyphenHTML($doc_file)") == 0 or die "libreoffice failed: $?";
	Common::my_print "Launching libreoffice for $name.\n";
	system("$libreoo_path", "--headless", "--invisible", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "macro:///Standard.Module1.ReplaceNBHyphenHTML($doc_file)") == 0 or die "libreoffice failed: $?";
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
	    system("$libreoo_path", "--display", "$Xdisplay", "--unnaccept=all", "--invisible", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", "html:HTML (StarWriter)", "--outdir", "$dir", "$doc_file") == 0 or die "libreoffice failed: $?";
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

if ($file !~ m/^([&a-z\.\/_ \-0-9\(\)\[\],:'!"\?@;]|\x{c4}\x{83}|\x{c5}\x{9e}|\x{c5}\x{9f}|\x{c3}\x{a2}|\x{c3}\x{a8}|\x{c3}\x{a9}|\x{c3}\x{a4}|\x{c8}\x{9b}|\x{c8}\x{99}|\x{c5}\x{a2}|\x{c3}\x{8e}|\x{c3}\x{a5}|\x{c3}\x{85}|\x{c3}\x{bc}|\x{e2}\x{82}\x{ac}|\x{e2}\x{80}\x{99}|\x{c3}\x{a1}|\x{c3}\x{ba}|\x{c5}\x{a1}|\x{c5}\x{a0}|\x{c3}\x{a0}|\x{c3}\x{ae}|\x{e2}\x{80}\x{a6})+$/i){
print "$file\n";
$file=~ s/[&a-z\.\/_ \-0-9\(\)\[\],:'!"\?@;]|\x{c4}\x{83}|\x{c5}\x{9e}|\x{c5}\x{9f}|\x{c3}\x{a2}|\x{c3}\x{a8}|\x{c3}\x{a9}|\x{c3}\x{a4}|\x{c8}\x{9b}|\x{c8}\x{99}|\x{c5}\x{a2}|\x{c3}\x{8e}|\x{c3}\x{a5}|\x{c3}\x{85}|\x{c3}\x{bc}|\x{e2}\x{82}\x{ac}|\x{e2}\x{80}\x{99}|\x{c3}\x{a1}|\x{c3}\x{ba}|\x{c5}\x{a1}|\x{c5}\x{a0}|\x{c3}\x{a0}|\x{c3}\x{ae}|\x{e2}\x{80}\x{a6}//gi;
die "\nERROR WWW\n_$file\_\n";
};

	print "$count\r" if ++$count % 10 == 0;
	$file = abs_path($file);
	my ($name, $dir, $suffix) = fileparse($file, qr/\.[^.]*/);
	die "$dir\n" if $dir =~ m/(^\s+|\s+$|\s{2,})/g;
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
	return if $suffix =~ m/^\.jpg$/i;
	my $file_no_path = $file; $file_no_path =~ s/^$docs_prefix\/*//;
	my $book->{'doc_file'} = $file_no_path;
	$book->{'name'} = $name;
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
	$book->{'xml_version'} = 1;
	$book->{'coperta'} = $coperta || 0;
	$book->{'title'} = $name;
	$book->{'auth'} = $auth;
	$book->{'ver'} = $ver || 0;
	$book->{'seria'} = $series || 0;
	$book->{'seria_no'} = $series_no || 0;
	$book->{'scurte'} = 0;
	$book->{'medii'} = 0;
	$book->{'lungi'} = 0;

	my $fixed_file = "$auth$url_sep$name/$name";
	$fixed_file =~ s/[:,"]//g;
	$fixed_file = Common::normalize_text($fixed_file);
	my ($name_x,$dir_x,$suffix_x) = fileparse($fixed_file, qr/\.[^.]*/);
	$book->{'file_info'}->{'safe_name'} = $name_x;
	$book->{'file_info'}->{'workingdir'} = $dir_x;
	$book->{'file_info'}->{'doc_filename_fixed'} = "$name_x$suffix";
	$book->{'file_info'}->{'filesize'} = -s $file;
	$book->{'file_info'}->{'type'} = $suffix;
	$book->{'file_info'}->{'filedate'} = stat($file)->mtime;
	$book->{'result'}->{'libreoffice'} = "";
	$book->{'result'}->{'html_clean'} = "";
	$book->{'result'}->{'epub_normal'} = "";
	$book->{'result'}->{'epub_font_included'} = "";
	$book->{'result'}->{'epub_font_external'} = "";
	$book->{'result'}->{'mobi'} = "";
	$book->{'result'}->{'ebook'} = "";
	$book->{'out'}->{'html_file'} = "$dir_x/$name_x.html";
	$book->{'out'}->{'html_file_orig'} = "$dir_x/$name_x\_orig.html";
	$book->{'out'}->{'html_file_clean'} = "$dir_x/$name_x\_clean.html";
	$book->{'out'}->{'epub_normal'} = "$dir_x/$name_x\_normal.epub";
	$book->{'out'}->{'epub_font_included'} = "$dir_x/$name_x\_internal.epub";
	$book->{'out'}->{'epub_font_external'} = "$dir_x/$name_x\_external.epub";
	$book->{'out'}->{'mobi'} = "$dir_x/$name_x.mobi";

	my $key = $dir_x;
	$key =~ s/\///g;;
	die "Book already exists: $key ($file)\n".Dumper($files_to_import->{$key}) if defined $files_to_import->{$key};
	if (defined $files_already_imported->{$key}) {
	    my $book_from_file = Common::xmlfile_to_hash($files_already_imported->{$key});
	    if ($book->{'file_info'}->{'filesize'} eq $book_from_file->{'file_info'}->{'filesize'} &&
		    $book->{'file_info'}->{'filedate'} eq $book_from_file->{'file_info'}->{'filedate'}) {
		$book->{'file_info'}->{'md5'} = $book_from_file->{'file_info'}->{'md5'};
		$book->{'result'} = $book_from_file->{'result'};
	    } else {
		print "Delete deprecated dir: $book->{'file_info'}->{'workingdir'}.\n";
		remove_tree($book->{'file_info'}->{'workingdir'});
		$book->{'file_info'}->{'md5'} = Common::get_file_md5("$file");
	    }
	} else {
	    $book->{'file_info'}->{'md5'} = Common::get_file_md5("$file");
	}
	$files_to_import->{$key} = $book;
    }
    print "Get all files.\n";
    find ({wanted => sub { add_document ($File::Find::name) if -f },},"$docs_prefix") if -d "$docs_prefix";
    print "Got all files: $count.\n";
    return $files_to_import;
}

sub get_existing_documents {
    our $files_already_imported = {};
    die "Working dir $work_prefix is a file.\n" if -f $work_prefix;
    return if ! -d $work_prefix;
    print "Get already done files from $work_prefix.\n";
    opendir(DIR, "$work_prefix") || die("Cannot open directory $work_prefix.\n");
    my @alldirs = grep { (!/^\.\.?$/) && -d "$work_prefix/$_" } readdir(DIR);
    closedir(DIR);
    my $count = 0;
    foreach my $dir (sort @alldirs) {
	if (! -f "$work_prefix/$dir/$control_file"){
	    print "Remove wrong dir $work_prefix/$dir.\n";
	    remove_tree("$work_prefix/$dir") || die "Can't remove dir $work_prefix/$dir: $!.\n";
	    next;
	}
	print "$count\r" if ++$count % 10 == 0;
# 	$files_already_imported->{$dir} = Common::xmlfile_to_hash("$work_prefix/$dir/$control_file");
	$files_already_imported->{$dir} = "$work_prefix/$dir/$control_file";
    }
# print Dumper($files_already_imported);exit 1;
    print "Got already done files from $work_prefix: $count.\n";
    return $files_already_imported;
}

sub synchronize_files {
    my $files_already_imported = get_existing_documents;
    my $files_to_import = get_documents($files_already_imported);
# my $q=0;
# foreach (sort keys %$files_already_imported){
# print Dumper($files_already_imported->{$_});
# last if $q++>1;
# }
# $q=0;
# foreach (sort keys %$files_to_import){
# print Dumper($files_to_import->{$_});
# last if $q++>1;
# }
# exit 1;
    print "\tDone.\n";
    my @arr1 = (keys %$files_already_imported);
    my @arr2 = (keys %$files_to_import);
    my ($only_in1, $only_in2, $common) = Common::array_diff(\@arr1, \@arr2);
#     ## should delete $only_in1
    remove_tree("$work_prefix/$_") foreach (@$only_in1);
    return $files_to_import;
}

sub convert_images {
    my ($images, $work_dir) = @_;
    my $cover = "";
    foreach my $key (sort keys %$images) {
	my $orig_name = $key;
	my $new_name = $images->{$key}->{'name'};
	if (! -f "$work_dir/$orig_name") {
	    die "Missing image $work_dir/$orig_name.\n";
	    next;
	}
	Common::my_print "\tConverting file $orig_name to $new_name.\n";
	system("convert", "$work_dir/$orig_name", "-background", "white", "-flatten", "$work_dir/$new_name") == 0 or die "error runnig convert: $!.\n";
# copy("$work_dir/$orig_name", "$work_dir/$new_name");
	$cover = "$work_dir/$new_name" if $images->{$key}->{'nr'} == 0;
	unlink "$work_dir/$orig_name";
    }
    return $extract_cover?$cover:"";
}


sub libreoffice_to_html {
    my $xml_book = shift;
    my $book = Common::xmlfile_to_hash($xml_book);
    my ($work_dir, $title, $html_file) =("$work_prefix/$book->{'file_info'}->{'workingdir'}", $book->{'title'}, "$work_prefix/$book->{'out'}->{'html_file'}");

    my $working_file = "$work_dir/$book->{'file_info'}->{'doc_filename_fixed'}";
    eval{
    if (! (($book->{'result'}->{'libreoffice'} eq "failed" && !$retry_on_fail) ||
	  ($book->{'result'}->{'libreoffice'} eq "done" && -s "$work_prefix/$book->{'out'}->{'html_file_orig'}"))) {
	$book->{'result'}->{'libreoffice'} = "failed";
	Common::my_print "Doing the doc to html conversion for $title.\n";
	Common::makedir($work_dir);
	copy("$docs_prefix/$book->{'doc_file'}", $working_file) or die "Copy failed \n\$docs_prefix/$book->{'doc_file'}\n\t$working_file:\n$!\n";
	my $res = doc_to_html_macro($working_file);
	die "Can't generate html $html_file.\n" if ($res || ! -s $html_file);
	move($html_file, "$work_prefix/$book->{'out'}->{'html_file_orig'}") || die "can't move file $html_file.\n";
	my $zip_file = "$work_dir/$book->{'file_info'}->{'safe_name'}.zip";
	Common::add_file_to_zip($zip_file, "$docs_prefix/$book->{'doc_file'}");
# use IO::Compress::Zip qw(:all);
# zip [ $working_file ] => $zip_file or die "Cannot create zip file: $ZipError" ;
# 	system("zip", "-j", "$zip_file", "$docs_prefix/$book->{'doc_file'}") == 0 or die "creating zip file failed ($?): $!.\n";
die "SPARTAAAA!!!!\n" if ! -f $zip_file;
	unlink $working_file || die "Can't remove file $working_file: $!\n";
	$book->{'result'}->{'libreoffice'} = "done";
    }};
    Common::hash_to_xmlfile($book, "$xml_book");
    print "XXXX LO ERROR\n".Dumper($title, $@). "error: $?.\n" if ($@);
    return ($@)?1:0;
}

sub libreoffice_html_clean {
    my $xml_book = shift;
    my $book = Common::xmlfile_to_hash($xml_book);
    my ($work_dir, $title, $html_file_orig) =("$work_prefix/$book->{'file_info'}->{'workingdir'}", $book->{'title'}, "$work_prefix/$book->{'out'}->{'html_file_orig'}");
    my $file_max_size_single_thread = 30000000;
    my $dbh;$dbh = connect_sqlite($dbh, $path_to_db_file);
    my $sth = $dbh->prepare( "select libreoffice_running+clean_running+ebook_running from $table_info_name");
    if (-f $html_file_orig && -s $html_file_orig > $file_max_size_single_thread) {
	## wait for others to finish:
	Common::my_print "\t\t************ Single for $title.************\n";
	do {usleep(100000);$sth->execute()}while (@{$sth->fetch}[0]>1);
    } else {
	update_proc($dbh, "UPDATE $table_info_name set single_mode=NULL where single_mode=".$dbh->quote($xml_book."/clean"));
    }

    eval{
    if (! (($book->{'result'}->{'html_clean'} eq "failed" && !$retry_on_fail) ||
	  ($book->{'result'}->{'html_clean'} eq "done" && -s "$work_prefix/$book->{'out'}->{'html_file_clean'}")) ) {
	$book->{'result'}->{'html_clean'} = "failed";
	Common::my_print "Doing the html cleanup for $title.\n";
	my ($html, $images) = HtmlClean::clean_html_from_oo(Common::read_file($html_file_orig), $title, $work_dir);
	my $cover = convert_images ($images, $work_dir);
	Common::write_file("$work_prefix/$book->{'out'}->{'html_file_clean'}", $html);
	$book->{'scurte'} = 1 if (length($html) <= 35000);
	$book->{'medii'} = 1 if (length($html) >= 30000 && length($html) <= 450000);
	$book->{'lungi'} = 1 if (length($html) >= 400000);
	if (! $book->{'coperta'} && defined $cover){
	    my ($name_b,$dir_b,$suffix_b) = fileparse(decode_utf8("$docs_prefix/$book->{'doc_file'}"), qr/\.[^.]*/);
	    my ($name_c,$dir_c,$suffix_c) = fileparse($cover, qr/\.[^.]*/);
	    copy("$cover", "$dir_b/$name_b$suffix_c") or die "Copy cover failed \n\t$cover\n\t$dir_b/$name_b$suffix_c:\n$!\n";
	    $book->{'coperta'} = "$dir_b/$name_b$suffix_c";
	}
	unlink "$html_file_orig" || die "Can't remove file $html_file_orig: $!\n";
	$book->{'result'}->{'html_clean'} = "done";
    }};
    Common::hash_to_xmlfile($book, "$xml_book");
    print "YYYY clean ERROR\n".Dumper($title, $@). "error: $?.\n" if ($@);
    return ($@)?1:0;
}

sub libreoffice_html_to_epub {
    my $xml_book = shift;
    my $book = Common::xmlfile_to_hash($xml_book);
    my ($work_dir, $title, $html_file_clean) = ("$work_prefix/$book->{'file_info'}->{'workingdir'}", $book->{'title'}, "$work_prefix/$book->{'out'}->{'html_file_clean'}");

    eval{
    if (! (($book->{'result'}->{'ebook'} eq "failed" && !$retry_on_fail) ||
	  ($book->{'result'}->{'ebook'} eq "done" && -s "$work_prefix/$book->{'out'}->{'epub_font_external'}")) ) {
	$book->{'result'}->{'ebook'} = "failed";
	Common::my_print "Doing epubs for $title.\n";
	opendir(DIR, "$work_dir");
	my @images = grep(/\.jpg$/,readdir(DIR));
	closedir(DIR);
	html_to_epub($book, $xml_book);
	unlink "$work_dir/$_" foreach (@images);
	unlink "$html_file_clean" || die "Can't remove file $html_file_clean: $!\n";
	$book->{'result'}->{'ebook'} = "done";
    }};
    Common::hash_to_xmlfile($book, "$xml_book");
    print "ZZZZ ebook ERROR\n".Dumper($title, $@). "error: $?.\n" if ($@);
    return ($@)?1:0;
}

sub make_ebook {
    my ($book, $type, $epub_command, $epub_parameters) = @_;
    my $in_file = "$work_prefix/$book->{'out'}->{'html_file_clean'}";
    my $out_file = "$work_prefix/$book->{'out'}->{$type}";
    my $cmd = "$epub_command \"$in_file\" \"$out_file\" $epub_parameters";

    if ($book->{'result'}->{$type} ne "done"){
      Common::my_print "Converting $type start.\n";
      my $output = `$cmd`;
      die "file $out_file not created.\n".Dumper($in_file, $out_file, $output)."CMD:\n$cmd\n\n" if ! -s $out_file;
      $book->{'result'}->{$type} = "done";
      Common::my_print "Converting $type done.\n";
    }
}

sub html_to_epub {
    my ($book, $xml_book) = @_;
    my ($name, $authors, $dir, $title) = ($book->{'file_info'}->{'safe_name'}, $book->{'auth'}, "$work_prefix/$book->{'file_info'}->{'workingdir'}", $book->{'title'});
    my @tags = ();
    push @tags, "scurte" if $book->{'scurte'};
    push @tags, "medii" if $book->{'medii'};
    push @tags, "lungi" if $book->{'lungi'};
    push @tags, "ver=".$book->{'ver'} if $book->{'ver'};

    my $epub_command = "$extra_tools_dir/calibre/ebook-convert";
    my $epub_parameters = "--disable-font-rescaling --minimum-line-height=0 --toc-threshold=0 --smarten-punctuation --chapter=\"//*[(name()='h1' or name()='h2' or name()='h3' or name()='h4' or name()='h5')]\" --input-profile=default --output-profile=sony300 --max-toc-links=0 --language=ro --authors=\"".(decode_utf8($authors))."\" --title=\"".(decode_utf8($title))."\"";
# --keep-ligatures --rating=between 1 and 5
    $epub_parameters .= " --tags=\"".(join ',', @tags)."\"" if scalar @tags;
    $epub_parameters .= " --series=\"".(decode_utf8($book->{'seria'}))."\" --series-index=\".$book->{'seria_no'}"."\"" if $book->{'seria'} && $book->{'seria_no'};
    if ($book->{'coperta'}) {
	my $cover = "$book->{'coperta'}";
	$epub_parameters .= " --cover=\"".(decode_utf8($cover))."\"";
    }

    my $in_file = "$work_prefix/$book->{'out'}->{'html_file_clean'}";
    my ($out_file, $output, $type);

    ### normal epub
#     make_ebook($book, "epub_normal", $epub_command,  "$epub_parameters --no-default-epub-cover");
#     Common::hash_to_xmlfile($book, $xml_book);

    ### epub with external font
    make_ebook($book, "epub_font_external", $epub_command,  "$epub_parameters --no-default-epub-cover --extra-css=\"$script_dir/tools/external_font.css\"");
    Common::hash_to_xmlfile($book, $xml_book);

    ### epub with embedded font
#     make_ebook($book, "epub_font_included", $epub_command,  "$epub_parameters --no-default-epub-cover --extra-css=\"$script_dir/tools/internal_font.css\"");
#     Common::hash_to_xmlfile($book, $xml_book);

    ### normal mobi
#     make_ebook($book, "mobi", $epub_command,  "$epub_parameters");
#     Common::hash_to_xmlfile($book, $xml_book);
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

sub update_proc {
    my ($dbh, $txt, $dontcare) = @_;
    my $res = $dbh->do($txt);
    if (! defined $dontcare && $res eq "0E0"){
	die "Mortii matii:\n$txt\n" ;
	$txt =~ s/UPDATE/SELECT \* /;
	$txt =~ s/( set .* where )/ where /;
	print Dumper($dbh->selectall_arrayref("$txt"));
    }
# print "$txt\n$res\n" if $res eq "0E0";
    return $res ne "0E0"?1:0;
}

sub reap_children {
    my ($dbh, $running, $crt_worker, $next_worker) = @_;
    my $thread_nr;
    my $pid = waitpid(-1, WNOHANG);
    if ($pid > 0) {
	my $exit_status = $?;
	die "Unknown pid: $pid.\n".Dumper($running) if ! defined $running->{$pid};
	my $xml_file = $running->{$pid}->{'xml_file'};
	$thread_nr = $running->{$pid}->{'thread_nr'};
	if (defined $next_worker) {
	    my $new_status = $exit_status?'failed':'start';
	    update_proc($dbh, "UPDATE $table_work_name set worker_name='$next_worker', status='$new_status', PID=0 where status='working' and worker_name='$crt_worker' and xml_file=".$dbh->quote($xml_file));
	} else {
	    my $new_status = $exit_status?'failed':'done';
	    update_proc($dbh, "UPDATE $table_work_name set worker_name='$crt_worker', status='done', pid=0 where status='working' and worker_name='$crt_worker' and xml_file=".$dbh->quote($xml_file));
	}
	print "\t\t$crt_worker ($pid) $running->{$pid}->{'name'} reapead.\n";
	delete $running->{$pid};
	update_proc($dbh, "UPDATE $table_info_name set $crt_worker\_running=".(scalar keys %$running));
	update_proc($dbh, "UPDATE $table_info_name set single_mode=NULL where single_mode=".$dbh->quote($xml_file."/$crt_worker"), 1);
	die "Thread number should be positive.\n" if $thread_nr < 1;
	return $thread_nr;
    }
    return undef;
}

#status: start -> collected (in launcher) -> working (after forked launcher) start (reaper) -> done (last reaper)
# LIBREOFFICE CLEAN EBOOK LIBREOFFICE_RUNNING CLEAN_RUNNING EBOOK_RUNNING LIBREOFFICE_DONE CLEAN_DONE EBOOK_DONE SINGLE_MODE
sub focker_launcher {
    my ($function, $crt_worker, $next_worker) = @_;
    print "starting forker process $crt_worker.\n";
    my ($running, $sth, $dbh, @queue);
    $dbh = connect_sqlite($dbh, $path_to_db_file);
    my @thread = (1..20);
    while (1) {
	my ($max_procs, $worker_done) = @{shift @{$dbh->selectall_arrayref( "SELECT $crt_worker, $crt_worker\_done FROM $table_info_name")}};
	my $data = $dbh->selectall_arrayref("SELECT xml_file FROM $table_work_name where WORKER_NAME = '$crt_worker' and STATUS='start'");
	foreach (@$data){
	    my $xml_file = shift @$_;
	    push @queue, $xml_file;
	    update_proc($dbh, "UPDATE $table_work_name set status='collected' where status='start' and worker_name='$crt_worker' and xml_file=".$dbh->quote($xml_file));
	}
	last if $worker_done && ! scalar @queue;

	my $xml_file = shift @queue;
	if ((scalar keys %$running) < $max_procs && defined $xml_file &&
		update_proc($dbh, "UPDATE $table_info_name set single_mode=".$dbh->quote($xml_file."/".$crt_worker)." where single_mode is null", 1)){
	    my $name = (split /$url_sep/, ((split /\/+/, $xml_file)[-2]))[-1];
	    my $crt = shift @thread;
	    die "We should always have something.\n" if ! defined $crt;
	    my $pid = fork();
	    if (! defined ($pid)){
		die "Can't fork $crt_worker $name.\n";
	    } elsif($pid==0) {
		Common::my_print_prepand("\t$crt_worker $crt $name ");
		exit $function->($xml_file);
# 		exit (0);
	    }
	    die "Seems we want to add the same process twice.\n" if defined $running->{$pid};
	    $running->{$pid}->{'thread_nr'} = $crt;
	    $running->{$pid}->{'xml_file'} = $xml_file;
	    $running->{$pid}->{'name'} = $name;
	    update_proc($dbh, "UPDATE $table_info_name set single_mode=NULL where single_mode=".$dbh->quote($xml_file."/$crt_worker")) if $crt_worker ne "clean";
	    update_proc($dbh, "UPDATE $table_work_name set status='working', pid=$pid where status='collected' and worker_name='$crt_worker' and xml_file=".$dbh->quote($xml_file));
	    update_proc($dbh, "UPDATE $table_info_name set $crt_worker\_running=".(scalar keys %$running));
	    print "\t\t$crt_worker ($pid) $name started (out of ".(scalar @queue).").\n" if $pid > 0;
	} else {
	    push @queue, $xml_file if defined $xml_file;
	}

	my $thread_nr;
	do {
	    $thread_nr = reap_children($dbh, $running, $crt_worker, $next_worker);
	    push @thread, $thread_nr if defined $thread_nr;
	} while (defined $thread_nr);
	usleep(100000);
# 	sleep 1;
    }

    do {
	my $thread_nr = reap_children($dbh, $running, $crt_worker, $next_worker);
	push @thread, $thread_nr;
	usleep(100000);
    } while (scalar keys %$running);

    if (defined $next_worker) {
	update_proc($dbh, "UPDATE $table_info_name set $next_worker=$next_worker+$crt_worker, $next_worker\_done=1");
    } else {
	update_proc($dbh, "UPDATE $table_info_name set ALL_DONE=1");
    }

    print "($crt_worker). FIN *******************.\n";
}

sub periodic_checks {
    my $main_proc = shift;
    print "Starting checks process.\n";
    my ($dbh, $sth, $sth_work, $sth_info, $row);
    $dbh = connect_sqlite($dbh, $path_to_db_file);
    $sth = $dbh->prepare("SELECT ALL_DONE FROM $table_info_name");
    $sth_work = $dbh->prepare("SELECT worker_name, pid, xml_file FROM $table_work_name where pid>0");
    $sth_info = $dbh->prepare("SELECT libreoffice, clean, ebook, libreoffice_running, clean_running, ebook_running, ifnull(single_mode,'none') FROM $table_info_name");
    my $parents->{$main_proc} = "main";
    do {
	my $string = "";
	$sth_work->execute();
	while ($row = $sth_work->fetch){
	    open( STAT , "</proc/@$row[1]/stat" ) or next;
	    my @stat = split /\s+/ , <STAT>;
	    close( STAT );
# 	    my $name = (split /$url_sep/, ((split /\/+/, @$row[2])[-2]))[-1];
	    my $name = (split /\/+/, @$row[2])[-2];
	    $string .= "** worker pid = @$row[1], VmSize = ".(sprintf "%.0f", $stat[22]/1024/1024)."MB, VmRSS =".(sprintf "%.0f", $stat[23] * 4/1024)."MB, daddy = $stat[3], name = @$row[0] $name\n";
	    $parents->{$stat[3]} = @$row[0];
	}
	my @all_procs = grep /PPid:\s+$main_proc/, `grep PPid /proc/*/status`;
	foreach my $pid (@all_procs, $main_proc){
	    $pid =~ s/(\/status:PPid:.+\n$)|(^\/proc\/)//g;
	    open( STAT , "</proc/$pid/stat" ) or next;
	    my @stat = split /\s+/ , <STAT>;
	    close( STAT );
	    my $name_real = "";
	    $name_real = $parents->{$pid} if defined $parents->{$pid};
	    $name_real = "checker" if $pid == $$;
	    $string .= "** forked pid = $pid, VmSize = ".(sprintf "%.0f", $stat[22]/1024/1024)."MB, VmRSS =".(sprintf "%.0f", $stat[23] * 4/1024)."MB, daddy = $stat[3], name = $name_real$stat[1]\n";
	}
	$sth_info->execute();
	while ($row = $sth_info->fetch){
	    $string .= "** LO_procs = @$row[3] (@$row[0]), clean_procs = @$row[4] (@$row[1]), ebook_procs = @$row[5] (@$row[2])\n** single_mode = @$row[6]\n";
	}
	sleep 1;
	$sth->execute();
	print "**************************************************\n$string**************************************************\n";
    } while (! @{$sth->fetch}[0]);
    print "(checks). FIN *******************.\n";
}

sub main_process_worker {
    print "starting main thread\n";
    my $main_pid = $$;
    my ($dbh, $sth);
    $dbh = connect_sqlite($dbh, $path_to_db_file);
    eval { $sth = $dbh->selectall_arrayref( "SELECT 1 from $table_work_name;");};
    $dbh->do("DROP TABLE $table_work_name;") if defined $sth;
    eval { $sth = $dbh->selectall_arrayref( "SELECT 1 from $table_info_name;");};
    $dbh->do("DROP TABLE $table_info_name;") if defined $sth;
    $dbh->do("CREATE TABLE $table_work_name ($table_work_def);");
    $dbh->do("CREATE TABLE $table_info_name ($table_info_def);");
    do { eval{$dbh->selectall_arrayref( "SELECT * FROM work")}} until (! $@);
# LIBREOFFICE CLEAN EBOOK LIBREOFFICE_RUNNING CLEAN_RUNNING EBOOK_RUNNING LIBREOFFICE_DONE CLEAN_DONE EBOOK_DONE SINGLE_MODE
    $dbh->do( "INSERT INTO $table_info_name VALUES (1, 10, 10, 0, 0, 0, 0, 0, 0, 0, NULL)");

    my ($forks, $pid);
    $pid = fork();
    if (!$pid) {focker_launcher(\&libreoffice_to_html, "libreoffice", "clean"); exit 0;};
    $forks->{$pid} = "libreoffice";
    $pid = fork();
    if (!$pid) {focker_launcher(\&libreoffice_html_clean, "clean", "ebook"); exit 0;};
    $forks->{$pid} = "clean";
    $pid = fork();
    if (!$pid) {focker_launcher(\&libreoffice_html_to_epub, "ebook"); exit 0;};
    $forks->{$pid} = "epub";
#     $pid = fork();
#     if (!$pid) {periodic_checks($main_pid); exit 0;};
#     $forks->{$pid} = "checks";
    print Dumper($forks);

    my $files_to_import = synchronize_files;
    my $crt = 1;
    foreach my $file (sort keys %$files_to_import) {
	my $type = $files_to_import->{$file}->{'file_info'}->{'type'};
	my $xml_file = "$work_prefix/$files_to_import->{$file}->{'file_info'}->{'workingdir'}/$control_file";
	if ($type =~ m/\.docx?$/i || $type =~ m/\.odt$/i || $type =~ m/\.rtf$/i) {
	    Common::hash_to_xmlfile($files_to_import->{$file}, $xml_file);
	    $dbh->do( "INSERT INTO $table_work_name VALUES (".$dbh->quote($xml_file).", 'libreoffice', 'start', 0)");
	} elsif ($type =~ m/\.pdf$/i) {
	} elsif ($type =~ m/\.epub$/i) {
	} else {
	    print Dumper($files_to_import->{$file})."\nUnknown file type: $type.\n";
	}
	$crt++;
# last if $xml_file =~ m/Navi-Gand-ind/;
# last if $crt>10;
    }
    update_proc($dbh, "UPDATE $table_info_name set libreoffice_done=1");
    while (scalar keys %$forks) {
	$pid = waitpid(-1, WNOHANG);
	if ($pid > 0) {
	    next, print "strange pid: $pid\n" if ! defined  $forks->{$pid};
	    delete $forks->{$pid};
	    print "reaped $pid\n";
	}
	usleep(100000);
    }
    print "FIN *******************.\n";
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
# libreoffice --headless --invisible --nodefault --nologo --nofirststartwizard --norestore "macro:///Standard.Module1.embedImagesInWriter(/home/cristi/programe/scripts/carti/qq/index.html)"
# http://user.services.openoffice.org/en/forum/viewtopic.php?f=20&t=23909
#######   html to doc
# libreoffice -infilter="HTML (StarWriter)" -convert-to "ODF Text Document" ./q/Poul\ Anderson/index.html
