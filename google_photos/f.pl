#!perl

use Image::Magick;
use Term::ReadKey;
use Win32::Console;
use Time::HiRes qw(time);
#use Sys::CpuAffinity;
use Image::ExifTool;
use Cwd;
use Graphics::Color::HSV;
use DateTime;
use Time::Local;
use Sys::Hostname;

use Whatsup;

use strict;

srand();


my $fh;
open($fh, '<', 'config.dat') || die 'cant open config.dat';
my %cfg = split(/[\r\n\t]+/, join('', grep(/^[^;#]/, <$fh>)));
close($fh);


my $gab = $cfg{gab}; die unless -d $gab;
my $exe = $cfg{exe}; die unless -x $exe; $exe =~ s!/!\\!g;


my $ext = 'jpg';
#Sys::CpuAffinity::setAffinity($$, [int(Sys::CpuAffinity::getNumCpus() * rand())]) || die 'cant change affinity';

my $con = new Win32::Console;
{ my $icon = 0; sub icon { $con->SetIcon('service'.($icon++ % 4).'.ico'); }; }

my $size = 0x0800;
my $bmp = "\x42\x4d\x36\x00\xc0\x00\x00\x00\x00\x00\x36\x00\x00\x00\x28\x00".
          "\x00\x00\x00\x08\x00\x00\x00\x08\x00\x00\x01\x00\x18\x00\x00\x00".
          "\x00\x00\x00\x00\x00\x00\xc4\x0e\x00\x00\xc4\x0e\x00\x00\x00\x00".
          "\x00\x00\x00\x00\x00\x00";
my $bmpo = length($bmp);
$bmp .= '123' x ($size*$size);



sub mkimg
{
  my ($fd, $base, $time, $now) = @_;

  my $err;
  my @c;
  my $color = Graphics::Color::HSV->new({
      hue         => $base % 360,
      saturation  => 1,
      value       => 1,
    });
  for(my $c = 0; $c < 50; $c++)
  {
    my $x = '';
    for(my $c2 = 0; $c2 < 8; $c2++)
    {
      $color->s(0.5+0.5*rand());
      $color->v(0.5+0.5*rand());
      my $rgb = $color->to_rgb();
      $x .= chr($rgb->r()*255).chr($rgb->g()*255).chr($rgb->b()*255);
    }
    push(@c, $x);
  }

  for(my $x = $bmpo; $x < $bmpo+$size*$size*3; $x += 3*int(8*rand()))
  {
    substr($bmp, $x, 3*8, $c[int(rand()*($#c+1))]);
  }


  #for(my $c = 0; $c < 100; $c++)
  #{
  #  my $x = '';
  #  $color->s(0.5+0.5*rand());
  #  $color->v(0.5+0.5*rand());
  #  my $rgb = $color->to_rgb();
  #  $x .= chr($rgb->r()*255).chr($rgb->g()*255).chr($rgb->b()*255);
  #  push(@c, $x);
  #}
  #
  #for(my $x = $bmpo; $x < $bmpo+$size*$size*3; $x += 3)
  #{
  #  substr($bmp, $x, 3, $c[int(rand()*($#c+1))]);
  #}


  my $i = Image::Magick->new(magick => 'bmp');
  $i->BlobToImage($bmp);

  #$err = $i->Write(filename => $fn.'.bmp', quality => 100);
  #$err = $i->Write(filename => $ext.':'.$fn, quality => 100);
  #warn($err) if($err);

  my $q = 100;
  $i->Set(magick => $ext);
  $i->Set(quality => $q);
  $i->Set(compress => 'LossLess');
  $i->Set('sampling-factor' => '1x1');
  ($$fd) = $i->ImageToBlob();

  open(my $fh, '>>', __FILE__.'/../logs/'.hostname().'.log');
  printf($fh "%d\t%d\t%d\t%s\t%s\n", $base % 360, $q, length($$fd), DateTime->from_epoch(epoch => $now)->iso8601(), DateTime->from_epoch(epoch => $time)->iso8601());
  close($fh);

  return $color->to_rgb()->as_css_hex();
}



my $gps;
sub geotag
{
  my ($fd, $loc, $time) = @_;

  my $dt = DateTime->from_epoch(epoch => $time);

  if(!$gps)
  {
    my $fh;
    open($fh, '<', 'cities1000.txt') || die 'cities1000.txt?';
    $gps = [ map { [(split(/\t/))[-15, -14]] } <$fh> ];
    close($fh);
  }
  my $exifTool = new Image::ExifTool();
  $exifTool->ExtractInfo($fd);
  my ($la, $lo) = @{$loc || $gps->[rand()*$#$gps]};
  $exifTool->SetNewValue(GPSLatitude => abs($la));
  $exifTool->SetNewValue(GPSLongitude => abs($lo));
  $exifTool->SetNewValue(GPSLatitudeRef => $la < 0 ? 'S' : 'N');
  $exifTool->SetNewValue(GPSLongitudeRef => $lo < 0 ? 'W' : 'E');
  $exifTool->SetNewValue(AllDates => $dt->ymd(':').' '.$dt->hms(':').'-04:00');
  $exifTool->SetNewValue(FileCreateDate => $dt->ymd(':').' '.$dt->hms(':').'-04:00', Protected => 1);
  $exifTool->SetNewValue(FileModifyDate => $dt->ymd(':').' '.$dt->hms(':').'-04:00', Protected => 1);

  #my @fill = qw/Artist HostComputer ProcessingSoftware Software DocumentName ImageDescription Copyright ImageHistory ImageID Make Model/;
  #my $pad = (10_000_000 - length($$fd)-305);
  #warn length $$fd;
  #foreach my $fill (@fill)
  #{
  #  my $c = 'xrmb_';
  #  #while($pad > 0)
  #  #{
  #  #  $c .= chr(97+int(rand()*26));
  #  #  $pad--;
  #  #}
  #  $exifTool->SetNewValue($fill => $c);
  #  $exifTool->WriteInfo($fd);
  #  warn length $$fd;
  #}

  if($exifTool->WriteInfo($fd))
  {
    #warn("geotagged to $lo/$la");
  }
  else
  {
    warn("geotag error $lo/$la");
  }
}



my $cmd = qq'start "title" "$exe"';
print("$cmd\n");
system($cmd);


my $path = $cfg{path} || 'pictures';
mkdir($path);
my $lfn;
my $fn;
my $time = time()-12345;
my $every = 15;
my $wait = -1;


my @of;
if(open(my $fh, '<', __FILE__.'/../logs/last.dat'))
{
  my $of = <$fh>;
  close($fh);
  if($of =~ /^\w+.jpg$/)
  {
    push(@of, $of);
  }
}


{
  opendir(my $dh, $path) || die;
  my ($of) = reverse sort grep { /$ext$/ } readdir($dh);
  closedir($dh);
  if($of =~ /^\w+.jpg$/)
  {
    push(@of, $of);
  }
}


if(open(my $log, '<', $gab.'network.log'))
{
  my $of;
  while(my $l = <$log>)
  {
    if(($l =~ m/Uploaded file \((\w+\.jpg),/ || $l =~ m/(\w+\.jpg)\s+: Media exists/) && $1 ge $of)
    {
      $of = $1;
    }
  }
  close($log);
  if($of) { push(@of, $of); }
}


if(open(my $fh, '<', __FILE__.'/../logs/'.hostname().'.log'))
{
  my $of;
  while(my $l = <$fh>)
  {
    my @l = split(/\s/, $l);
    if($l[3] && $l[3] ge $of)
    {
      $of = $l[3];
    }
  }
  close($fh);
  if($of) { $of =~ s/[\-:]//g; push(@of, $of); }
}


if(@of)
{
  my ($of) = reverse(sort(@of));
  printf("newest: %s\n", $of);
  my $dt = DateTime->new(year => substr($of, 0, 4), month => substr($of, 4, 2), day => substr($of, 6, 2),
                         hour => substr($of, 9, 2), minute => substr($of, 11, 2), second => substr($of, 13, 2), time_zone => '-0400');
  $time = $dt->epoch() + $every;
}
else
{
  die;
}


my $lastup;
MAIN: for(;;)
{
  my $start = Time::HiRes::time();
  my $actions = '';
  for(;;)
  {
    if(ReadKey($wait) || '' eq 'x') { last MAIN; }

    opendir(my $dh, $path);
    my $waiting = grep(/jpg$/, readdir($dh));
    closedir($dh);

    my $for = Time::HiRes::time()-$start;
    printf("%s\t%s\t%ds make lag\t%d uploads\t%.1fs work\n", scalar(localtime()), $fn, time()-$time, $waiting, $for);

    open(my $log, '<', $gab.'network.log') || warn('cant open log') && sleep(5) && next;
    my $size = -s $gab.'network.log';
    if($size > 10000) { seek($log, $size - 10000, 0) || warn('cant seek log') && sleep(5) && next; }
    my $done = 0;
    while(my $l = <$log>)
    {
      if(($l =~ m/Uploaded file \((\w+\.jpg),/ || $l =~ m/(\w+\.jpg)\s+: Media exists/) && "$path/$1" ne $fn && -f "$path/$1")
      {
        my $fn = $1;
        #print("unlink $path/$1\n");
        $lastup = DateTime->new(
            year      => substr($fn, 0, 4),
            month     => substr($fn, 4, 2),
            day       => substr($fn, 6, 2),
            hour      => substr($fn, 9, 2),
            minute    => substr($fn, 11, 2),
            second    => substr($fn, 13, 2),
            time_zone => '-0400'
          )->epoch();
        unlink("$path/$fn");
        $done++;

        if(open(my $fh, '>', __FILE__.'/../logs/last.dat'))
        {
          print($fh "$fn\n");
          close($fh);
        }
      }
    }
    close($log);
    if($done) { Whatsup->record(app => 'pushinglimits', google_photos => $done, lag => time()-$time); }

    if($waiting > 10)
    {
      ### restart myself ###
      if($for > 900 && $actions !~ /r/)
      {
        my $cmd = "start $0";
        print("$cmd\n");
        system($cmd);

        sleep(100);
        $actions .= 'r';
        exit;
      }

      ### restart backup ###
      if($for > 300 && $actions !~ /g/)
      {
        my $kill = $exe;
        $kill =~ s/^.*\\//;
        my $cmd = qq'pskill "$kill"';
        print("$cmd\n");
        system($cmd);

        unlink("$gab/db/$cfg{account}/files.dat");
        unlink("$gab/db/$cfg{account}/thumbindex.db");

        $cmd = qq'start "title" "$exe"';
        print("$cmd\n");
        system($cmd);

        $actions .= 'g';
      }

      ### cleanup oldest ###
      if($for > 600 && $actions !~ /c/)
      {
        opendir(my $dh, $path);
        my @f = sort grep { /\.jpg$/ } readdir($dh);
        closedir($dh);

        print("unlink $path/$f[0]\n");
        unlink("$path/$f[0]");

        $actions .= 'c';
      }

      sleep(5);
      next;
    }
    last;
  }



  while($lfn eq $fn || $fn && -f $fn)
  {
    if(ReadKey($wait) || '' eq 'x') { last MAIN; }
    my $dt = DateTime->from_epoch(epoch => $time, time_zone => '-0400');
    $dt->set(second => int($dt->second()/$every)*$every);
    $fn = sprintf('%s/%s_%s.%s', $path, $dt->ymd(''), $dt->hms(''), $ext);
    $con->Title($dt->ymd() .' '. $dt->hms());
    if($wait > 0) { icon(); }
    if($time < time()+10_000_000) { $time++; $wait = -1; } else { $wait = 1; }
  }
  $lfn = $fn;

  my $fd;
  icon();
  my $base = mkimg(\$fd, $time/$every, time(), $time);

  icon();
  geotag(\$fd, undef, $time);

  my $l = length($fd);
  if($l < 10000) { next; }

  $fd .= '_xrmb_';
  while(length($fd) < 10_000_000)
  {
    $fd .= chr(rand(256));
  }

  icon();
  open(my $fh, '>', $fn) || die;
  binmode($fh);
  print($fh $fd);
  close($fh);
}
