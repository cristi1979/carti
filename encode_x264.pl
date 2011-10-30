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
use Term::ANSIColor;


my $path_prefix = abs_path(shift);
my $arg = shift || "";
print Dumper($arg);
my $bkp_path = "/media/ceva1/Audio/aaa__de_sters/bkp";
# my $bkp_srt_path = "/media/ceva2/Video/bkp_srt";
# my $bkp_path = "./bkp";
my $bkp_srt_path = "$bkp_path/../bkp_srt";
my $movies = {};
my $force_subtitles = "no";
my $audio_only = "no";
my $video_only = "no";
if ($arg =~ m/\-m/i ) {
  # make mkv only
  $audio_only = "no";
  $video_only = "yes";
} elsif ($arg =~ m/\-a/i ) {
  # audio
  $audio_only = "yes";
  $video_only = "no";
} elsif ($arg =~ m/\-s/i ) {
  # subtitles
  $audio_only = "yes";
  $video_only = "yes";
} elsif ($arg =~ m/\-sn/i ) {
  # subtitles
  $audio_only = "yes";
  $video_only = "yes";
}

sub normalize_text {
    use Unicode::Normalize 'NFD','NFC','NFKD','NFKC';
    my $str = shift;
    ## from http://www.ahinea.com/en/tech/accented-translate.html
    for ( $str ) {  # the variable we work on
	##  convert to Unicode first
	##  if your data comes in Latin-1, then uncomment:
	$_ = Encode::decode( 'utf8', $_ );

	s/\xe4/ae/g;  ##  treat characters ä ñ ö ü ÿ
	s/\xf1/ny/g;  ##  this was wrong in previous version of this doc
	s/\xf6/oe/g;
	s/\xfc/ue/g;
	s/\xff/yu/g;
	## various apostrophes   http://www.mikezilla.com/exp0012.html
	s/\x{02B9}/\'/g;
	s/\x{2032}/\'/g;
	s/\x{0301}/\'/g;
	s/\x{02C8}/\'/g;
	s/\x{02BC}/\'/g;
	s/\x{2019}/\'/g;

	$_ = NFD( $_ );   ##  decompose (Unicode Normalization Form D)
	s/\pM//g;         ##  strip combining characters

	# additional normalizations:

	s/\x{00df}/ss/g;
	s/\x{00c6}/AE/g;
	s/\x{00e6}/ae/g;
	s/\x{0132}/IJ/g;
	s/\x{0133}/ij/g;
	s/\x{0152}/Oe/g;
	s/\x{0153}/oe/g;

	tr/\x{00d0}\x{0110}\x{00f0}\x{0111}\x{0126}\x{0127}/DDddHh/;
	tr/\x{0131}\x{0138}\x{013f}\x{0141}\x{0140}\x{0142}/ikLLll/;
	tr/\x{014a}\x{0149}\x{014b}\x{00d8}\x{00f8}\x{017f}/NnnOos/;
	tr/\x{00de}\x{0166}\x{00fe}\x{0167}/TTtt/;

	s/[^\0-\x80]//g;  ##  clear everything else; optional
    }
    return Encode::encode( 'utf8', $str );  ;
}

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

sub get_video_size {
    my ($info, $movie) = @_;
# print Dumper($info);
    my @extra_opts;
    my $w = $info->{ID_VIDEO_WIDTH};
    my $h = $info->{ID_VIDEO_HEIGHT};
    my $cropping = `HandBrakeCLI -i "$movie" -t 0 2>&1 | grep "+ autocrop:"`;
    print "Cropping failed: $?.\n".Dumper($cropping) if $?;
    $cropping =~ s/(^\s*\+ autocrop: |\s*$)//g;
    $cropping = "0/0/0/0" if $cropping eq "";
    my @crops = split /\//, $cropping;
    $w = $w - $crops[0] - $crops[1];
    $h = $h - $crops[2] - $crops[3];
    if ($w>1280 || $h>720 ){
	print "\twrong WxH: $w x $h.Downscalling to W=1280.\n";
	$h = 1280 * $h / $w;
	$w = 1280;
	push @extra_opts, ("-w", "1280");
    }

    return ($w, $h, $crops[1], @extra_opts);
}

sub work_on_subtitle {
    my ($movie, $info) = @_;
    my ($w, $h, $crop) = get_video_size($info, $movie);
    my $sub_file_name = $info->{ID_FILE_SUB_FILENAME} if exists $info->{ID_FILE_SUB_FILENAME};
    return "" if ! defined $sub_file_name;

    my $tmp = $sub_file_name;
    $tmp =~ s/(,|")//mgs;
    if ($tmp ne $movie) {
	move("$sub_file_name","$tmp") || die "mv srt 2: $!\n";
	$sub_file_name = $tmp;
    }

    my ($name,$dir,$suffix) = fileparse($sub_file_name, qr/\.[^.]*/);
    copy("$sub_file_name","$bkp_path/$name/") || die "cp srt1 ($sub_file_name to $bkp_path/$name): $!\n";

    my ($ass_file_name, $original_file_name) = ("$dir$name.ass", "$dir$name.original$suffix");
    copy("$sub_file_name", "$original_file_name") or die "Copy failed: $! ($sub_file_name to $original_file_name)\n";

    my $utf8_file_name = "$dir/$name.utf8$suffix";
    open(MYINPUTFILE, "<$sub_file_name"); # open for input
    my(@lines) = <MYINPUTFILE>; # read file into list
    close(MYINPUTFILE);

    $tmp = join "", @lines;
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
Style: Default,DejaVuSans,'.$fontsize.',&H00FFFFFF,&H0000FFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,2,2,5,5,'.(15+$crop).',0

[Events]
Format: Layer, Start, End, Style, Actor, MarginL, MarginR, MarginV, Effect, Text
';

    print color("green"), "\t\t*** Dropping subtitles with parameters $utf8_file_name, $movie.\n", color 'reset';
    `mplayer -sub "$utf8_file_name" -subcp utf8 -dumpsrtsub -vo null -ao null -frames 0 "$movie" 2>/dev/null`;
    die "Dropping subtitles failed.\n" if $?;

    if ($arg =~ m/\-sn/i ) {
	## normalize subtitle
	my $string;
	{  local $/=undef;
	  open FILE, "$dir/dumpsub.srt" or die "Couldn't open file: $!";
	  binmode FILE;
	  $string = <FILE>;
	  close FILE;
	}
	my $q = normalize_text($string);
	open MYFILE, ">$dir/$name.normalize$suffix";
	print MYFILE $q;
	close MYFILE;
    }

    unlink "$name.mplayer.srt" if -f "$name.mplayer.srt";
    copy("dumpsub.srt", "$name.mplayer.srt") or die "Copy failed: $!";
    push @to_move, "$dir/$name.original$suffix";
    push @to_move, "$utf8_file_name";
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

sub work_on_audio {
    my ($movie, $info) = @_;
    my ($name,$dir,$suffix) = fileparse($movie, qr/\.[^.]*/);
    my $audio_file = "$dir/_$name.aac";

    my $acodec = $info->{ID_AUDIO_CODEC};
    my $aformat = $info->{ID_AUDIO_FORMAT};
    my $arate = $info->{ID_AUDIO_RATE};
    my $anrchannels = $info->{ID_AUDIO_NCH};
    my $chapters = $info->{ID_CHAPTERS};
# return if ! defined $acodec;
# my $vcodec = $info->{ID_VIDEO_CODEC};
# my $vformat = $info->{ID_VIDEO_FORMAT};
# my $wsd="sunet_rau";
# open(BAD, ">>$path_prefix/$wsd");
# print "$vcodec\n$vformat\n$chapters\n$acodec\n$aformat\n$arate\n$anrchannels\n";
# print BAD "$movie ==> $vcodec $vformat n$chapters $acodec $aformat $arate $anrchannels\n" if !($acodec eq "faad" && $aformat eq "MP4A" && ($arate == 48000 || $arate == 44100 || $arate == 22050 || $arate == 32000) && $anrchannels > 3 && $chapters == 1) && ($vcodec eq "ffh264" && $info->{ID_VIDEO_FORMAT} eq 'H264');
# close BAD;
# return $audio_file;
    print color("green"), "\t\t*** Audio info: codec=$acodec, format=$aformat.\n", color 'reset';
    die "Unknown audio codec: $acodec $info->{ID_AUDIO_FORMAT}.\n" if defined $acodec && ($acodec ne "mp3" && $acodec ne "ffac3" && $acodec ne "alaw" && $acodec ne "ffdca" && $acodec ne "ffwmav2" && $acodec ne "pcm" && $acodec ne "ffadpcmimaqt" && ($acodec ne "faad" && $aformat eq "MP4A") && ($acodec ne "ffaac" && $aformat eq "MP4A"));
    return $audio_file if $video_only eq "yes";
    unlink $audio_file if -f $audio_file;

    if (1==0 && ($acodec eq "faad" || $acodec eq "ffaac") && $aformat eq "MP4A" && ($arate == 48000 || $arate == 44100 || $arate == 32000 || $arate == 22050)){
	print color("green"), "\t\t*** Copy audio with parameters $movie, $audio_file.\n", color 'reset';
# 	system("mplayer", "-dumpaudio", "-dumpfile", "$audio_file", "$movie") == 0 or die "audio encoding failed (copy): $!\n";
	system("ffmpeg", "-i", "$movie", "-acodec", "copy", "$audio_file") == 0 or die "audio encoding failed: $!\n";  ## for mp4
    } else {
	print color("green"), "\t\t*** Transcoding audio with parameters $movie, $audio_file.\n", color 'reset';
	system("bash", "-c", "mplayer -alang eng -srate 48000 -nocorrect-pts -ao pcm:fast:file=>\($script_dir/nero/neroAacEnc -if - -of \"$audio_file\" 2>/dev/null\) -vo null -vc null \"$movie\"") == 0 or die "audio encoding failed (transcode): $!. From $movie to $audio_file.\n".Dumper("bash", "-c", "mplayer -srate 48000 -nocorrect-pts -ao pcm:fast:file=>\($script_dir/nero/neroAacEnc -if - -of \"$audio_file\" 2>/dev/null\) -vo null -vc null \"$movie\"");
    }

    return $audio_file;
}

sub work_on_video {
    my ($movie, $info,$srt) = @_;
    my ($name,$dir,$suffix) = fileparse($movie, qr/\.[^.]*/);
    my $video_file = "$dir/_$name.mp4";

    my $demuxer = $info->{ID_DEMUXER};
    my $vcodec = $info->{ID_VIDEO_CODEC};
    die "Unknown video codec: $vcodec $info->{ID_VIDEO_FORMAT}.\n" if ($vcodec ne "ffwmv2" && $vcodec ne "ffodivx" && $vcodec ne "ffdivx" && $vcodec ne "ffmpeg1" && $vcodec ne "ffmpeg2" && $vcodec ne "ffmp41" && $vcodec ne "ffmp42" && $vcodec ne "ffcvid" && $vcodec ne "ffsvq3" && $vcodec ne "ffflv" && $vcodec ne "ffwmv3" && $vcodec ne "ffh264" && $vcodec ne "ffindeo5" && $vcodec ne "ffh263" && $vcodec ne "ffmjpeg");

    my @mkv_opts = ("mkvmerge", "-o", "$video_file.mkv", "$video_file");
    my ($w, $h, $crop, @HB_opts) = get_video_size($info, $movie);

    my $filetoencode = "$video_file";
    return $filetoencode if $audio_only eq "yes";

    if ($vcodec eq "ffh264" && $info->{ID_VIDEO_FORMAT} eq 'H264') {
	print color("green"), "\t\t*** Copy video with parameters $movie, $filetoencode.\n", color 'reset';
	if ($demuxer eq "avi") {
	    system("mencoder", "-idx", "-ovc", "copy", "-nosound", "$movie", "-o", "$filetoencode") == 0 or die "can't run mencoder:$?.\n";
	} else {
	    system("ffmpeg", "-f", "mp4", "-an", "-i", "$movie", "-vcodec", "copy", "$filetoencode") == 0 or die "can't run ffmpeg:$?.\n";
	}
	return $filetoencode;
    }


    print color("green"), "\t\t*** Dumping video with parameters $movie, $video_file.\n", color 'reset';
    system("mencoder", "-idx", "-ovc", "copy", "-nosound", "$movie", "-o", "$video_file") == 0 or die "can't run mencoder:$?.\n";

#     if ($suffix !~ m/flv/i && scalar @mkv_opts) {
    if ($srt ne ""){
	$filetoencode = "$video_file.mkv" ;
	print color("green"), "\t\t*** Making mkv with parameters $video_file.mkv, $video_file.\n", color 'reset';
	system(@mkv_opts, "$srt", "--attach-file", "$script_dir/DejaVuSans.ttf") == 0 or die "error running mkvmerge: $?.\n";
	die "mkvmerge failed: $!\n" if ( $? == -1 || ! -f "$filetoencode");
	push @HB_opts, ("-s", "1", "--subtitle-burn");
    } else {
	print "\tNo subtitles.\n";
	move($video_file, "$video_file.video");
	$filetoencode = "$video_file.video";
	die if $force_subtitles eq "yes";
    }

    if ($arg =~ m/\-m/i) {
	print "remove $video_file.\n";
	unlink $video_file || die "delete $video_file: $!\n" if -f $video_file;
	return;
    } elsif ($arg =~ m/\-s/i) {
	return;
    }
#     my @ultrafast_settings = ("-q", "25", "-x", "no-8x8dct=1:aq-mode=0:b-adapt=0:bframes=0:no-cabac=1:no-deblock=1:no-mbtree=1:me=dia:no-mixed-refs=1:partitions=none:ref=1:scenecut=0:subme=0:trellis=0:no-weightb=1:weightp=0");
#     my @slower_settings = ("-q", "17", "-x", "b-adapt=2:direct=auto:me=umh:rc-lookahead=60:ref=8:subme=9:partitions=all:trellis=2:psy-rd=1\|0.15:deblock=-1\|-1");
#     my @slow_settings = ("-q", "25", "-x", "b-adapt=2:rc-lookahead=50:direct=auto");
#     my @anim_settings = ("-9", "-q", "20", "-x", "b-adapt=2:analyse=all:me=umh:rc-lookahead=50:ref=5:subme=9:psy-rd=0.4\|0:deblock=1\|1:b-pyramid=1:no-dct-decimate=1:no-psnr=1:no-ssim=1:mixed-refs=1:no-fast-pskip=1:weightb=1:8x8dct=1:aq-strength=0.6");
#     my @gray_settings = ("-g");
    my @x264_settings = ("-q", "25", "-x", "b-adapt=2:direct=auto:me=umh:rc-lookahead=50:ref=5:subme=8:psy-rd=1\|0.15:deblock=-1\|-1:analyse=all:no-fast-pskip=1:no-dct-decimate=1");
#     , "--detelecine"
    print color("green"), "\t\t*** Transcoding video with parameters $filetoencode, $video_file.\n", color 'reset';
    my @handbrake = ("HandBrakeCLI", "--decomb", "--keep-display-aspect", "--loose-anamorphic","-f" ,"mp4", "-e", "x264", "-O", "-4", "-i", "$filetoencode", "-o", "$video_file", "--audio", "none", @HB_opts, @x264_settings);
    system(@handbrake) == 0 or die "error running handbrake: $?.\n";
    unlink "$filetoencode" || die "delete mkv: $!\n" if -f "$filetoencode";

    return $video_file;
}

sub work_on_file {
    my ($movie, $info) = @_;
    my $tmp = $movie;
    $tmp =~ s/(,|")//mgs;
    if ($tmp ne $movie) {
	die "Cleaned filename already exists: $tmp.\n" if -f $tmp;
	move("$movie","$tmp") || die "mv movie from \"$movie\" to \"$tmp\": $!\n";
	$movie = $tmp;
    }
    print "\tStart working.\n";
    my ($name,$dir,$suffix) = fileparse($movie, qr/\.[^.]*/);
    if (! -d "$bkp_path/$name") {mkpath("$bkp_path/$name") || die "mkdir $bkp_path/$name: $!\n";}
    if (! -d "$bkp_srt_path/$name") {mkpath("$bkp_srt_path/$name") || die "mkdir $bkp_srt_path/$name: $!\n";}

    return if $arg =~ m/\-m/i && -f "_$name.mp4.mkv";
# return;
    my $srt = work_on_subtitle($movie, $info);
    my $audio = work_on_audio($movie, $info);
    my $video = work_on_video($movie, $info, $srt);
    return if $arg =~ m/\-[m|s]/i;
#     ISO:
#     copy all VOBs
# mencoder dvd://10 -dvd-device /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.iso -oac copy -channels 6 -o audio -ovc frameno
## extract chapter
# mplayer dvd://43 -dvd-device /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.iso -chapter 4
#     cat 1.vob 2.vob ... > 0.vob
#     mkvmerge -o coco.mkv 0.vos sub.ssa
#     HandBrakeCLI -5 -e x264 -q 0.6 -f mp4 --rate 25 -O -4 -s 1 --subtitle-burn -2 -T -a 1 --aencoder copy:ac3  -i coco.mkv -o file.mp4

# FILE=some.iso
# lsdvd "$FILE" 	find all chapters (length > 1 min)
# mplayer -aid 135 dvd://43 -dvd-device /"$FILE" 	find the correct language (128 +)
# mencoder -aid 135 dvd://43 -dvd-device "$FILE" -idx -ovc copy -oac copy -o some.avi

#     flv:
#     NAME=Bare_Necessities
#     HandBrakeCLI -5 -e x264 -q 0.6 --rate 23.976 -i "$NAME.flv" -o "$NAME.mp4"

#     mencoder -ss 00:10:00 -endpos 00:01:00 -ovc copy -oac copy -o result.avi "$FILE"
#     mplayer -vo null -ao null -frames 0 -identify "$file" 2> /dev/null | grep "^ID_"

# mencoder dvd://10 -dvd-device /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.iso  -idx -ovc copy -nosound -o /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.avi
# /home/cristi/programe/scripts/nero/neroAacEnc -ignorelength -q 0.60 -if audiodump.wav -of audio.m4a & mplayer -vc null -vo null -ao pcm:fast dvd://10 -dvd-device /media/ceva2/downloads/torente/I\ Heart\ Huckabees/I\ Heart\ Huckabees.iso

# `ffmpeg -i "$file" -i "/media/Video3/__din nou/$name.audio" -map 0:0 -map 1:0 -acodec copy -vcodec copy "/media/Video1/Seriale/STNG/$name.mp4"`;


# **** MKV
# file="Pulp Fiction.mkv"
# i=1
# mkvextract tracks "$file" 1:$i""video.mp4 2:$i""audio.ac3 3:$i""subtitles_ro.srt 4:$i""subtitles.srt;
# mplayer -nocorrect-pts -ao pcm:fast:file=>(~/programe/encoding/nero/neroAacEnc -if - -of $i""audio.aac 2>/dev/null) -vo null -vc null $i""audio.ac3
# sleep 3
# ffmpeg -i $i""audio.aac -acodec copy -i $i""video.mp4 -vcodec copy "$file".mp4
#
# **** MP4
# file="Hitchhikers Guide to the Galaxy - 01.mp4"
# i=1
# ffmpeg -i "$file" -acodec copy $i""audio.ac3
# ffmpeg -f mp4 -an -i "$file" -acodec copy -vcodec copy $i""video.mp4
# mplayer -nocorrect-pts -ao pcm:fast:file=>(~/programe/encoding/nero/neroAacEnc -if - -of $i""audio.aac 2>/dev/null) -vo null -vc null $i""audio.ac3
# sleep 3
# ffmpeg -i $i""audio.aac -acodec copy -i $i""video.mp4 -vcodec copy "$file".mp4

# MP4Box -fps 25 -add output.264 -add audio.mp4 star-wars.mp4


#     my $offset = "00:00:0.400";
#     my $offset = "00:00:0"; , "-itsoffset", "$offset"
# return;
    move ($movie, "$movie.original");
    $movie = "$movie.original";
    sleep 25;
    die "no audio: $audio\n" if ! -f "$audio";
    die "no video: $video\n" if ! -f "$video";
    print color("green"), "\t\t*** Joining audio and video with parameters $audio, $video, $dir/$name.mp4.\n", color 'reset';
#     system("ffmpeg", "-i", "$audio", "-acodec", "copy", "-i", "$video", "-vcodec", "copy", "$dir/$name.mp4") == 0 or die "error running ffmpeg: $?.\n";
    my $output = `ffmpeg -i "$audio" -acodec copy -i "$video" -vcodec copy "$dir/$name.mp4" 2>&1`;
    if ( $? || $output =~ m/\[mov,mp4,m4a,3gp,3g2,mj2 @ (.*?)\] stream 0, offset (.*?): partial file/ ) {
	print "Joining failed:\n$output.\n";
	return;
    }

    my $audio_size = -s "$audio" || 0;
    my $video_size = -s "$video" || 0;
    my $final_size = -s "$dir/$name.mp4" || 0;
#     print color("green"), "\t\t*** Size of files: $audio_size + $video_size = ".($audio_size + $video_size)." final = $final_size.\nProcent:".($final_size*100/($audio_size + $video_size))."\n", color 'reset';
# exit 1;
    unlink "$audio" || die "delete audio: $!\n" if -f "$audio";
    unlink "$video" || die "delete video: $!\n" if -f "$video";
#     unlink "$movie";
    unlink "$srt";
#     move("$movie","$bkp_path/$name/") || die "mv avi: $!\n";
#     move("$srt","$bkp_path/$name/") || die "mv srt: $!\n"  if -f "$srt";
}

sub extract_mkv {
    my $file = shift;
    my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
    my $nr_tracks = `mkvinfo "$file" | grep "Track number:" | sort | tail -1 | sed "s/|  + Track number: //"`;
    my $tracks = "";
    for (my $i=1;$i<=$nr_tracks;$i++) {
	$tracks .= " $i:\"$file\".$i "
    }
    print "$tracks\n";
    `mkvextract tracks "$file" $tracks`;
}

sub add_document {
    my $file = shift;
    print "Adding $file.\n";
    my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);

    $file =~ s/"/\\"/g;
    my $out = `mplayer -vo null -ao null -frames 0 -identify "$file" 2> /dev/null | grep ^ID_`;
    die "Get info failed.\n" if $?;

    my @tmp = split "\n", $out;
    my $info = {};
    foreach my $val (@tmp) {
	my @tmp1 = split "=", $val;
	die "cocot: $file".Dumper(@tmp1) if scalar @tmp1 > 2;
	$info->{$tmp1[0]} = $tmp1[1];
    }

    $movies->{$info->{ID_FILENAME}} = $info;
    work_on_file($info->{ID_FILENAME}, $info);
#     extract_mkv($file) if $suffix =~ m/^\.mkv$/i;
}

find ({ wanted => sub { add_document ($File::Find::name) if -f && (/(\.avi|\.mpg|\.mpeg|\.flv|\.wmv|\.mov|\.3gp|\.ogm|\.divx|\.3gp|\.ogm|\._iso_|\._mp4_|\.mkv)$/i) }}, $path_prefix ) if  (-d "$path_prefix");
