#!/usr/bin/perl

use warnings;
use strict;

$SIG{__WARN__} = sub { die @_ };

use Cwd 'abs_path','chdir';
use File::Basename;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Find;

my $docs_prefix = shift;
$docs_prefix = "./" if ! defined $docs_prefix;
my $fonts_dir = "./Fonts";
my $css_file = "./Styles/style.css";
my $saved_dir = "./Modificate";
remove_tree($saved_dir);
make_path ("$fonts_dir");
make_path ("$saved_dir");
$fonts_dir = abs_path($fonts_dir);
$saved_dir = abs_path($saved_dir);
my $all_files;

sub find_epubs {
    sub add_files {
	my $file = shift;
# 	$file = Cwd::_perl_abs_path("../myepub/".$file);
	my ($name, $dir, $ext) = fileparse($file, qr/\.[^.]*/);
	$all_files->{$file} = 1 if $ext =~ m/\.epub/i;
    }
    find ({wanted => sub { add_files ($File::Find::name) if -f },}, "$docs_prefix") if -d "$docs_prefix";
}

find_epubs;

foreach my $file (sort keys %$all_files) {
    print "$file\n";
    $file = abs_path($file);
    next if ! -f $file;
    my ($name, $dir, $ext) = fileparse($file, qr/\.[^.]*/);
    my $zip = Archive::Zip->new();
    die 'read error' if $zip->read( $file ) != AZ_OK ;

    my $zip_font_dirs;
    my $zip_css_files;
    my $zip_html_files;
    my $existting_files;
    my $zip_opf_files;
    foreach my $zip_file ($zip->memberNames){
      my ($zip_name, $zip_dir, $zip_ext) = fileparse($zip_file, qr/\.[^.]*/);
      $zip->removeMember($zip_file) if defined $existting_files->{$zip_file};
      $existting_files->{$zip_file} = 1;
      $zip_css_files->{$zip_file} = 1 if $zip_ext =~ m/^\.css$/i;
      $zip_opf_files = $zip_file if $zip_ext =~ m/^\.opf$/i;
      $zip_html_files->{$zip_file} = 1 if $zip_ext =~ m/^\.x?html?$/i;
      if ( $zip_ext =~ m/^\.ttf$/i) {
	$zip->removeMember($zip_file);
	$zip_font_dirs->{$zip_dir} = 1;
      }
    }

    opendir(my $dh, $fonts_dir) || die "Can't read dir $fonts_dir\n";
    my @fonts;
    while(readdir $dh) {push @fonts, "$fonts_dir/$_" if -f "$fonts_dir/$_"};
    closedir $dh;

    my $zip_font_dir;
    if (defined $zip_font_dirs) {
      die "Too many font direcories in epub: $file.\n" if scalar keys %$zip_font_dirs > 1;
      $zip_font_dir = (keys %$zip_font_dirs)[0];
      $zip_font_dir =~ s/\.?(\/|\\)*$//;
      $zip_font_dir = "Fonts" if $zip_font_dir eq "";
    } else {
      $zip_font_dir = "Fonts";
    }

    my $opf_font_lines = {};
    foreach my $font (@fonts) {
      my ($font_name, $font_dir, $font_ext) = fileparse($font, qr/\.[^.]*/);
      $zip->addFile( $font, "$zip_font_dir/$font_name$font_ext") or die "Error adding font $font to zip.\n";
      $opf_font_lines->{"$font_name$font_ext"} = 1;
    }

    if (defined $zip_opf_files) {
      my ($opf_name, $opf_dir, $opf_ext) = fileparse($zip_opf_files, qr/\.[^.]*/);
      my $opf_txt = $zip->memberNamed( $zip_opf_files )->contents();
      $opf_dir =~ s/\.?(\/|\\)$//;
      my $depth = split(/\//,$opf_dir);
#       my $depth_fonts = split(/\//,$zip_font_dir);
#       $depth = 0 if $depth < 2;
      my $tmp = ("../" x $depth);
      my $new_opf_txt = "";
      foreach my $key (sort keys %$opf_font_lines) {
	$new_opf_txt .= '<item href="'."$tmp$zip_font_dir/$key".'" id="'."$key".'" media-type="application/x-font-ttf" />'."\n";
      }
print Dumper($opf_dir,$depth);
      $opf_txt =~ s/.*(application\/x-font-ttf).*//g;
      $opf_txt =~ s/(<manifest>\s*\n)/$1$new_opf_txt/;
      $zip->memberNamed( $zip_opf_files )->contents($opf_txt);
    }

    foreach my $html_file (sort keys %$zip_html_files) {
      my ($html_name, $html_dir, $html_ext) = fileparse($html_file, qr/\.[^.]*/);
      my $string = $zip->memberNamed( $html_file )->contents();
      $string =~ s/\@font-face\s*\{.*?\}//gms;
      $zip->memberNamed( $html_file )->contents($string);
    }

    my $my_css_txt;
    {
      local $/=undef;
      open FILE, "$css_file" or die "Couldn't open file $my_css_txt: $!";
      binmode FILE;
      $my_css_txt = <FILE>;
      close FILE;
    }

    my $font_family;
    while ($my_css_txt =~ m/font-family:(.*?)(,|;)/igm) {
	$font_family = $1;
    }

    foreach my $css_file (sort keys %$zip_css_files) {
      my ($css_name, $css_dir, $css_ext) = fileparse($css_file, qr/\.[^.]*/);
      my $css_txt = $zip->memberNamed( $css_file )->contents();
      $css_dir =~ s/\/$//;
      $css_txt =~ s/font-family: ".*?"(,|;)/font-family: $font_family$1/gm;
      my $depth = split(/\//,$css_dir);
      $depth = $depth - 1 if $depth < 2;
      $zip_font_dir = ("../" x $depth) .$zip_font_dir;
      $my_css_txt =~ s/(\@font-face\s*\{.*?src:url\()(.*\/)(.*)?(\)\})/$1$zip_font_dir\/$3$4/gm;
      $css_txt =~ s/\@font-face\s*\{.*?\}//gms;
      $css_txt .= "\n$my_css_txt\n";
      $zip->memberNamed( $css_file )->contents($css_txt);
    }

    unlink "$saved_dir/$name$ext" if -f "$saved_dir/$name$ext";
    die "Write error for zip file.\n" if $zip->writeToFileNamed( "$saved_dir/$name$ext" ) != AZ_OK;
}
