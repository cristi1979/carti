#!/usr/bin/perl

use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };
$|++;

use File::Find;
use File::Copy;
use File::Path;
use File::Basename;
use Cwd 'abs_path';
my $script_dir = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

my $path_prefix = abs_path(shift);
my $bkp_path = "/media/ceva2/Video/bkp";
my $bkp_srt_path = "/media/ceva2/Video/bkp_srt";
my $movies = {};
my $force_subtitles = "no";

sub get_encoding {
    my $txt = shift;
    use Encode::Guess;
    my $enc = guess_encoding($txt, qw/utf8 iso-8859-2/);
    return "utf8" if (!ref($enc));
    return $enc->name;
}

sub find_subtitles {
    my ($allfiles, $name) = @_;
    my $subtitle = "";

    foreach my $v (keys %$allfiles){
	if ($v =~ m/^$name\.(srt)|(sub)|(txt)|(ssa)$/i && $subtitle eq "") {
	    delete $allfiles->{"$v"};
	    $subtitle = $v;
	    next;
	} else {
	    die "$v\n$name\n";
	}
    }
    return $subtitle;
}

sub convert_subtitle {
    my ($sub_file_name, $movie, $w, $h) = @_;

    my ($name,$dir,$suffix) = fileparse($sub_file_name, qr/\.[^.]*/);

    my ($ass_file_name, $original_file_name) = ("$dir$name.ass", "$dir$name.original$suffix");
    copy("$sub_file_name", "$original_file_name") or die "Copy failed: $!";

    my $utf8_file_name = "$dir/$name.utf8$suffix";
    open(MYINPUTFILE, "<$sub_file_name"); # open for input
    my(@lines) = <MYINPUTFILE>; # read file into list
    close(MYINPUTFILE);
    my $tmp = join "", @lines;
    Encode::from_to($tmp, "cp1250", "utf8") if (get_encoding($tmp) ne "utf8" );
    open MYFILE, ">$utf8_file_name";
    print MYFILE $tmp;
    close MYFILE;

    my @to_move = ();
    my $fontsize = sprintf "%.0f", 4/100*sqrt($w*$w+$h*$h);
    my $header = '[Script Info]
; This script was created by subtitleeditor (0.38.0)
; http://home.gna.org/subtitleeditor/
ScriptType: V4.00+
PlayResX: '.$w.'
PlayResY: '.$h.'

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,DejaVuSans,'.$fontsize.',&H00FFFFFF,&H0000FFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,2,2,5,5,20,0

[Events]
Format: Layer, Start, End, Style, Actor, MarginL, MarginR, MarginV, Effect, Text
';

    `mplayer -sub "$utf8_file_name" -subcp utf8 -dumpsrtsub -vo null -ao null -frames 0 "$movie" 2>/dev/null`;
    copy("dumpsub.srt","$name.mplayer.srt") or die "Copy failed: $!";

    push @to_move, "$dir/$name.original$suffix";
    push @to_move, "$dir/$name.utf8$suffix";
    push @to_move, "$sub_file_name" if $sub_file_name ne $ass_file_name;
    push @to_move, "$dir/$name.mplayer.srt";

    rename("dumpsub.srt", "$ass_file_name");
    die "can't make srt.\n" if ! -s "$ass_file_name";
    my $txt = "";
    my $srt;
    open $srt, "<" . $ass_file_name;
    while(<$srt>) {
	my $line = $_;
	chomp $line;
	$txt .= "$line\n";
    }
    close $srt;

    my @arr = split /(?=(?:[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{1,} --> [0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{1,}))/m, $txt;
    shift @arr;
    $txt = "$header";
    foreach my $block (@arr){
	$block =~ s/\n\n[0-9]{1,}\n*$//msg;
	$block =~ s/\n*$//msg;
	my ($time1, $time2, $text) = ($1,$2, $3) if $block =~ m/^[0-9]([0-9]:[0-9]{2}:[0-9]{2},[0-9]{2})[0-9]? --> [0-9]([0-9]:[0-9]{2}:[0-9]{2},[0-9]{2})[0-9]?\n(.*)$/gms;
	die "Strange line: $block.\n".Dumper($time1, $time2, $text) if ! defined $time1 || ! defined $time2;
	$time1 =~ s/,/./;
	$time2 =~ s/,/./;
# 	$text = lc $text;
	$text =~ s/\n/\\N/mg;
	my $row = 'Dialogue: 0,'.$time1.','.$time2.',Default,,0000,0000,0000,,'.$text."\n";
	$txt .= "$row";
    }

    $txt =~ s/<i>/{\\i1}/mgi;
    $txt =~ s/<\/i>/{\\i0}/mgi;
    $txt =~ s/<b>/{\\b1}/mgi;
    $txt =~ s/<\/b>/{\\b0}/mgi;

    open MYFILE, ">$ass_file_name";
    print MYFILE $txt;
    close MYFILE;
    die "can't make srt.\n" if ! -s "$ass_file_name";

    foreach (@to_move) {
	move("$_","$bkp_srt_path/$name/") || die "mv srt 1 $_: $!\n";
    }
    return $ass_file_name;
}

sub work_on_file {
    my ($movie, $info) = @_;
    my $srt = "";
    $srt = $info->{ID_FILE_SUB_FILENAME} if exists $info->{ID_FILE_SUB_FILENAME};
    my ($tmp1, $tmp2) = ($movie, $srt);
    $tmp1 =~ s/(,|")//mgs;
    $tmp2 =~ s/(,|")//mgs;
    if ($tmp1 ne $movie) {
	die "Cleaned filename already exists: $tmp1.\n" if -f $tmp1;
	move("$movie","$tmp1") || die "mv movie: $!\n";
	if (-f "$srt") {move("$srt","$tmp2") || die "mv srt 2: $!\n";}
	$movie = $tmp1;
	$srt = $tmp2;
    }
    print "\tStart working.\n";
    my @extra_opts = ();
    my ($name,$dir,$suffix) = fileparse($movie, qr/\.[^.]*/);
    if (! -d "$bkp_path/$name") {mkpath("$bkp_path/$name") || die "mkdir $bkp_path/$name: $!\n";}
    if (! -d "$bkp_srt_path/$name") {mkpath("$bkp_srt_path/$name") || die "mkdir $bkp_srt_path/$name: $!\n";}

    my $w = $info->{ID_VIDEO_WIDTH};
    my $h = $info->{ID_VIDEO_HEIGHT};
    if ($w>1280 || $h>720 ){
	print "\twrong WxH: $w x $h.\n" if ! ($w>1280 && $h>720);
	print "\twrong WxH: $w x $h.Downscalling to W=1280.\n" ;
	$h = 1280 * $h / $w;
	$w = 1280;
	push @extra_opts, ("-w", "1280");
    }

    my $acodec = $info->{ID_AUDIO_CODEC};
    my $vcodec = $info->{ID_VIDEO_CODEC};
    die "Unknown audio codec: $acodec $info->{ID_AUDIO_FORMAT}.\n" if ($acodec ne "mp3" && $acodec ne "ffac3" && $acodec ne "alaw" && $acodec ne "ffdca" && $acodec ne "ffwmav2" && $acodec ne "pcm" && $acodec ne "ffadpcmimaqt" && ($acodec ne "faad" && $info->{ID_VIDEO_FORMAT} eq "MP4A"));
    die "Unknown video codec: $vcodec $info->{ID_VIDEO_FORMAT}.\n" if ($vcodec ne "ffwmv2" && $vcodec ne "ffodivx" && $vcodec ne "ffdivx" && $vcodec ne "ffmpeg1" && $vcodec ne "ffmpeg2" && $vcodec ne "ffmp41" && $vcodec ne "ffmp42" && $vcodec ne "ffcvid" && $vcodec ne "ffsvq3" && $vcodec ne "ffflv" && $vcodec ne "ffwmv3" && $vcodec ne "ffh264" && $vcodec ne "ffindeo5");

    my @mkv_opts = ("mkvmerge", "-o", "$dir/coco.mkv");

    if ($srt ne "") {
	copy("$srt","$bkp_path/$name/") || die "cp srt1: $!\n";
# 	copy("$srt","$bkp_srt_path/$name/") || die "cp srt2: $!\n";
# 	copy("$srt","$srt.ssa") || die "cp srt3: $!\n";
# 	$srt = "$srt.ssa";
	$srt = convert_subtitle($srt, $movie, $w, $h);

	push @mkv_opts, ("$srt");
	push @extra_opts, ("-s", "1", "--subtitle-burn");
    } else {
	print "\tNo subtitles.\n";
	die if $force_subtitles eq "yes";
    }

    system("mencoder", "-idx", "-ovc", "copy", "-nosound", "$movie", "-o", "$dir/$name.video") == 0 or die "can't run mencoder:$?.\n";
    if ($acodec eq "faad" && $info->{ID_VIDEO_FORMAT} eq "MP4A"){
	system("mplayer",  "-dumpaudio", "-dumpfile", "$dir/$name.audio", "$movie") == 0 or die "audio encoding failed: $!\n";
# 	push @mkv_opts, ("$movie");
    } else {
# 	my $out = "";
	system("bash", "-c", "mplayer -nocorrect-pts -ao pcm:fast:file=>\($script_dir/nero/neroAacEnc -if - -of \"$dir/$name.audio\" 2>/dev/null\) -vo null -vc null \"$movie\"") == 0 or die "audio encoding failed: $!\n";
    }
#     push @mkv_opts, ("$dir/$name.audio", "$dir/$name.video");
    push @mkv_opts, ("$dir/$name.video");
#     push @extra_opts, ("--aencoder", "copy");
    push @extra_opts, ("--audio", "none");

## convert subtitles to srt
# mplayer -sub example.ssa -dumpsrtsub Get\ Smart\ -\ S04E01\ -\ The\ Impossible\ Mission.avi -vo null -ao null -frames 0

#     mkfifo audiodump.wav
#     /home/cristi/programe/scripts/nero/neroAacEnc -ignorelength -2pass -if audiodump.wav -of audio.m4a & mplayer -vc null -vo null -ao pcm:fast "$FILE"
#     mencoder -idx -ovc copy -nosound input.avi -o outfile.avi
# 	    sau
# 	mplayer -nocorrect-pts -ao pcm:fast:file=>(/home/cristi/programe/scripts/nero/neroAacEnc -ignorelength -lc -q 0.6 -if - -of audio.mp4 2>nero.log) -vo null -vc null "/media/Video2/Filme desene animate/Disney Movies/2008 - Wall-E.mkv"

#     ISO:
#     copy all VOBs
# mencoder dvd://10 -dvd-device /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.iso -oac copy -channels 6 -o audio -ovc frameno
# lsdvd /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.iso
# mplayer dvd://1 -dvd-device /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.iso -chapter 4
#     cat 1.vob 2.vob ... > 0.vob
#     mkvmerge -o coco.mkv 0.vos sub.ssa
#     HandBrakeCLI -5 -e x264 -q 0.6 -f mp4 --rate 25 -O -4 -s 1 --subtitle-burn -2 -T -a 1 --aencoder copy:ac3  -i coco.mkv -o file.mp4

#     flv:
#     NAME=Bare_Necessities
#     HandBrakeCLI -5 -e x264 -q 0.6 --rate 23.976 -i "$NAME.flv" -o "$NAME.mp4"

#     mencoder -ss 00:10:00 -endpos 00:01:00 -ovc copy -oac copy -o result.avi "$FILE"
#     mplayer -vo null -ao null -frames 0 -identify "$FILE" 2> /dev/null | grep "^ID_"

# mplayer dvd://10 -dvd-device /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.iso  -idx -ovc copy -nosound -o /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.avi
# /home/cristi/programe/scripts/nero/neroAacEnc -ignorelength -q 0.60 -if audiodump.wav -of audio.m4a & mplayer -vc null -vo null -ao pcm:fast dvd://10 -dvd-device /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.iso


    my $filetoencode = "$movie";
    if ($suffix !~ m/flv/i && scalar @mkv_opts) {
	$filetoencode = "$dir/coco.mkv";
	system(@mkv_opts) == 0 or die "error running mkvmerge: $?.\n";
	if ( $? == -1 || ! -f "$filetoencode") {
	    print "mkvmerge failed: $!\n";
	    return;
	}
    }
#  "--detelecine",
    my @handbrake = ("HandBrakeCLI", "--decomb", "--keep-display-aspect", "--loose-anamorphic","-f" ,"mp4", "-e", "x264", "-O", "-4", "-i", "$filetoencode", "-o", "$dir/$name.mp4_video");

#     my @ultrafast_settings = ("-q", "25", "-x", "no-8x8dct=1:aq-mode=0:b-adapt=0:bframes=0:no-cabac=1:no-deblock=1:no-mbtree=1:me=dia:no-mixed-refs=1:partitions=none:ref=1:scenecut=0:subme=0:trellis=0:no-weightb=1:weightp=0");
#     my @slower_settings = ("-q", "17", "-x", "b-adapt=2:direct=auto:me=umh:rc-lookahead=60:ref=8:subme=9:partitions=all:trellis=2:psy-rd=1\|0.15:deblock=-1\|-1");
#     my @slow_settings = ("-q", "25", "-x", "b-adapt=2:rc-lookahead=50:direct=auto");
    my @slow_settings = ("-q", "25", "-x", "b-adapt=2:direct=auto:me=umh:rc-lookahead=50:ref=5:subme=8:psy-rd=1\|0.15:deblock=-1\|-1:analyse=all:no-fast-pskip=1:no-dct-decimate=1");
#     my @anim_settings = ("-9", "-q", "20", "-x", "b-adapt=2:analyse=all:me=umh:rc-lookahead=50:ref=5:subme=9:psy-rd=0.4\|0:deblock=1\|1:b-pyramid=1:no-dct-decimate=1:no-psnr=1:no-ssim=1:mixed-refs=1:no-fast-pskip=1:weightb=1:8x8dct=1:aq-strength=0.6");

    my @gray_settings = ("-g");

    push @handbrake, @extra_opts;
#     push @handbrake, @anim_settings;
    push @handbrake, @slow_settings;
#     push @handbrake, @gray_settings;
    if ($vcodec eq "ffh264" && $info->{ID_VIDEO_FORMAT} eq 'H264') {
	move("$dir/coco.mkv","$dir/$name.mkv") || die "mv avi: $!\n";
    } else {
	system(@handbrake) == 0 or die "error running handbrake: $?.\n";
	die "HandBrakeCLI failed: $!\n" if ( $? == -1 );
    }
    system("ffmpeg", "-i", "$dir/$name.audio", "-i", "$dir/$name.mp4_video", "-acodec", "copy", "-vcodec", "copy", "-y", "$dir/$name.mp4") == 0 or die "error running ffmpeg: $?.\n";
#     system("mencoder", "-ovc", "copy", "-audiofile", "$dir/$name.audio", "-oac", "copy", "$dir/$name.mp4_video", "-o", "$dir/$name.mp4") == 0 or die "error running mencoder: $?.\n";

    unlink "$dir/coco.mkv" || die "delete mkv: $!\n" if ($suffix !~ m/flv/i);
    unlink "$dir/$name.audio" || die "delete audio: $!\n" if -f "$dir/$name.audio";
    unlink "$dir/$name.video" || die "delete video: $!\n" if -f "$dir/$name.video";
    unlink "$dir/$name.mp4_video" || die "delete video: $!\n" if -f "$dir/$name.mp4_video";
    move("$movie","$bkp_path/$name/") || die "mv avi: $!\n";
    move("$srt","$bkp_path/$name/") || die "mv srt: $!\n"  if -f "$srt";
}

sub add_document {
    my $file = shift;
    print "Adding $file.\n";
    my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
    opendir(DIR, "$dir") || die("Cannot open directory $dir: $!\n");
    my @allfiles = grep { (!/^\.\.?$/) && -f "$dir/$_" } readdir(DIR);
    closedir(DIR);
    my %allfiles = map { $_ => 1 } @allfiles;
    delete $allfiles{"$name$suffix"};

    $file =~ s/"/\\"/g;
    my $out = `mplayer -vo null -ao null -frames 0 -identify "$file" 2> /dev/null | grep ^ID_`;
#    my $cropping = `HandBrakeCLI -i "$file" -t 0 2>&1 | grep "+ autocrop:" | sed s/\ \ +\ autocrop:\ //`;

    my @tmp = split "\n", $out;
    my $info = {};
    foreach my $val (@tmp) {
	my @tmp1 = split "=", $val;
	die "cocot: $file".Dumper(@tmp1) if scalar @tmp1 > 2;
	$info->{$tmp1[0]} = $tmp1[1];
    }

#     my $subtitle = find_subtitles(\%allfiles, $name);
#     die "$file:\n\t$dir$subtitle\n\t$info->{ID_FILE_SUB_FILENAME}\n" if exists $info->{ID_FILE_SUB_FILENAME} && "$dir$subtitle" ne $info->{ID_FILE_SUB_FILENAME} && $subtitle ne "" && $info->{ID_FILENAME} ne $file;
# print Dumper($info);
    $movies->{$info->{ID_FILENAME}} = $info;
    work_on_file($info->{ID_FILENAME}, $info);
}

find ({ wanted => sub { add_document ($File::Find::name) if -f && (/(\.avi)|(\.mpg)|(\.mpeg)|(\.flv)|(\.wmv)$|(\.mov)$|(\.3gp)$|(\.ogm)$/i) }}, $path_prefix ) if  (-d "$path_prefix");

