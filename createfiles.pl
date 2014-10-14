#!/usr/bin/perl

use threads;
require "imagemagick.pl";

$config_file = "sitevariables.pl"; #default config fie
$sizes = "640";
$count=0;
$count_images=0;
$count_thumbnails=0;
$count_ignored_directories =0;
$count_directories=0;
$count_new_directories=0;
$count_new_thumbnail_directories=0;
$count_new_thumbnails=0;
$verbosity = 0;

foreach $arg (@ARGV){
	print "processing $arg\n";
	if($arg =~ /^-c$/){ # new config file
		$config_file = $ARGV[$count+1];
		unless($config_file){die("usage (option -c requires an argument): -c config_file\n");}
		(-r "$config_file")||die("config file could not be opened for reading.  Attempted to use $config_file.\n");
	} elsif($arg =~ /^-b$/){ # batchmode mode
		$batchmode = "yes";	
	} elsif($arg =~ /^-v$/){ # verbosity mode
		$verbosity++;	
	} elsif($arg =~ /^-s$/){ # specify sizes
		$sizes = $ARGV[$count+1];
		unless($sizes){print("WARNING: usage (option -s requires an argument): -c size,size,size\nWARNING: making only thumbnails\n");}
	} elsif($arg =~ /^-t$/){ # force thumbnail regenerate
		$forceThumbs = "yes";
	} elsif($arg =~ /^-r$/){ # force RAW file regenerate
		$forceRAW = "yes";
	} else { # do help
		print "
##########################################################
# Thumbnail, Directory, and Data Accessory script for
# My Photo Gallery
#
# NOTE: My Photo Gallery will work just fine without this
# script.  This script will create all of the thumbnails
# and directories needed for the script so that they do
# not have to be done on the fly.  This may help speed
# things up for your visitors after a fresh upload of
# many pictures.  You may also want to consider having this
# placed in cron to run in the middle of the night
# however often you update your galleries.  The default
# opperation (without -s) is to create only thumbnails
# and the 640 size.  Use -s to specify more sizes
# separated by commas.
#
# -c config_file	specifies a config file (sitevariables.pl)
# -b			for cronjobs ..doesnt ask questions
# -s 320,640,800,1024   specify just a few sizes to make
#                       default is just thumbnails,640
# -t      force regeneration of thumbnails
# -r      force regerenation of RAW image reduction
# -v more debugging (supply more to increase level)
#
##########################################################
";
		exit;

	}
	$count++;
}

unless($batchmode) { print "using $config_file as the configuration file (sitevariables.pl)\n"; }
require "sitevariables.pl";

unless($resize_quality){$resize_quality=95;}

# if we have watermarking turned on
if($watermark_file){
	unless($watermark_file =~ /\.(jpg|png|gif)$/i){die("ERROR: $watermark usage (option -w requires an argument: picture)\n");}
	unless(-e $watermark_file){die("ERROR: $watermark does not exist. $!\n");}
	print("WARNING: watermarking images will attempt to modify the original images!");
}

unless($batchmode){
	print "Is this the correct directory to read pictures from?\n$photoroot [y/n]\n";
	$answer = <STDIN>;
	unless($answer =~ /^y/i){
		die("ABORT: Please check $config_file for accuracy.");
	}
	print "Is this the correct directory to write thumbnails, descriptions, and other data to?\n$dataroot [y/n]\n";
	$answer = <STDIN>;
	unless($answer =~ /^y/i){
		die("ABORT: Please check $config_file for accuracy.");
	}

}
if($watermark_file){
	if(open(WATERMARK_LOG,"<watermark.log")){
		flock(2,WATERMARK_LOG);
		while(<WATERMARK_LOG>){
			chomp;
			push(@watermarked_pictures,$_);
		}
		flock(8,WATERMARK_LOG);
		close(WATERMARK_LOG);
	}
}
unless($verbosity < 1) {
	print "\n\nreading from $photoroot\nwriting to $dataroot\n";
	print "making thumbnails and $sizes\n";
}
&process_directory($photoroot,1); # Set this to 1 to make it multi-threaded

foreach my $thr (threads->list) {
	# don't join main thread or ourselves
	if($thr->tid && !threads::equal($thr,threads->self)) { $thr->join(); }
}

print"
Summary
------------------------
images found:        \t$count_images (.jpg, .png, .gif)
directories ignored: \t$count_ignored_directories (probably old thumbnail or resized dirs)
directories created: \t$count_new_directories for $count_directories total picture dirs (others already existed) 
thumbnails created:  \t$count_new_thumbnails/$count_images
";

sub process_directory($$){
	my $directory = $_[0];
	my $doFork = $_[1];
	my $file;
	my $path;
	my $filename;
	my @files;

	$glob_directory = $directory;
	$glob_directory =~ s/ /\\ /g;
	unless($verbosity < 1) { print "Processing $directory\n"; }

	@files = glob("$glob_directory/*");
	foreach $file (@files){
		#print "$file\n";
		if(-d "$file"){
			if(
				($file =~ /\/thumbnails$/)||
				($file =~ /\/site-images$/)||
				($file =~ /\/descriptions$/)||
				($file =~ /\/comments$/)||
				($file =~ /\/320$/)||
				($file =~ /\/640$/)||
				($file =~ /\/800$/)||
				($file =~ /\/1024$/)
				){
				$count_ignored_directories++;
			}else{
				print check_data_directories($file);
				if($doFork) {
					threads->new(\&process_directory,$file,0);
				} else {
					&process_directory($file,0);
				}
				$count_directories++;
			}
		}
		if(($file =~ /\.MOV$/i) || ($file =~ /\.MP4$/i)) {
			# Added by FAK
			if(!-e $file.".gif") {
#				system("ffmpeg -i \"$file\" -deinterlace -an -ss 3 -f mjpeg -t 1 -r 1 -y -s '320x240' -v 0 \"$file".".jpg\" >/dev/null 2>&1");
				unless($verbosity < 1) { print "Creating gif of $file...\n"; }
				$filename = (split(/\//,$file))[-1];
				system("ffmpeg -i \"$file\" -r 1 /tmp/$filename\_%05d.gif >/dev/null 2>&1");
				if($? == 0) {
				 	system("convert -delay 1x5 -loop 0 /tmp/$filename\_*.gif \"$file\.gif\" && rm -f /tmp/$filename\_*");
					if($? != 0) { print "Error creating $file.gif\n"; }
					else { $file = $file.".gif"; }
				} else { print "Failed to create $file.gif\n"; }
			} else { $file = $file.".gif"; }
		} elsif($file =~ /\.cr2$/i) {
			# Added by FAK
			my $fileJPG = $file;
			my $fileCR2 = $file;
			$fileJPG =~ s/\.CR2/.jpg/i;
			if(defined($forceRAW) || (!-e $fileJPG)) {
				system("ufraw-batch --wb=camera --black-point=auto --overwrite --color-smoothing --silent --rotate=camera --auto-crop --out-type=jpg \"$file\"");
				$file = $fileJPG;
			}
			# delete files older than 2 months
			my @stats = stat($fileCR2);
			if(time() - $stats[9] > 60*60*24*30*2) {
#				system("rm -f \"$fileCR2\"");
			}
		}
		if(($file =~ /\.jpg$/i)||($file =~ /\.gif$/i)||($file =~ /\.png$/i)){
			#get the image name
			$filename=$file;
			$filename=~ s/.*\///;
			# get the path to the image
			$path=$file;
			$path=~ s/$photoroot\/(.*)\/.*/$1/i;

			$count_images++;
			unless($verbosity < 2) { print "\t$filename "; }

			if($watermark_file){
				open(WATERMARK_LOG,">>watermark.log")||die("could not create watermark.log to store information about which pictures have already been watermarked.");
				flock(2,WATERMARK_LOG);

				#watermark($file);
				# see if we've watermarked this before
				$already_watermarked = 0;
				foreach $watermarked_picture (@watermarked_pictures){
					if($watermarked_picture eq $file) { $already_watermarked = 1; }
				}
				unless($already_watermarked == 1){
					if(-w $file){
						overlay($file,$file,$watermark_file);
						unless($verbosity < 2) { print(" -watermarked- "); }
						print WATERMARK_LOG "$file\n";
					} else{ print "ERROR:  Could not watermark $file: $!\n"; }
				}
				flock(2,WATERMARK_LOG);
				close(WATERMARK_LOG);
			} else { $already_watermarked = 1; } # prevent forced creation of already existing sizes

			#check for thumbnail
			if((defined($forceThumbs)) || !(-e "$dataroot/$path/thumbnails/$filename") || ($already_watermarked == 0)){
				#print "[NOT FOUND]\n";
				#print "processing $file=>$dataroot/$path/thumbnails/$filename\n";
				unless(-e "$dataroot/site-images/mag.png"){
					die("ERROR:  You must copy the site-images/ directory to your dataroot/ directory (in your case it is $dataroot.  $!");
				}
				print resize("$file","$dataroot/$path/thumbnails/$filename",$previewWidth,$resize_quality);
				if($mag_on_thumbnails =~ /yes/i){
					print overlay("$dataroot/$path/thumbnails/$filename","$dataroot/$path/thumbnails/$filename","$dataroot/site-images/mag.png");
				}
				unless($verbosity < 2) { print " -thumbnailed- "; }
				$count_new_thumbnails++;
			}
			make_picture_size($file,"$dataroot/$path/320/$filename",320);
			make_picture_size($file,"$dataroot/$path/640/$filename",640);
			make_picture_size($file,"$dataroot/$path/800/$filename",800);
			make_picture_size($file,"$dataroot/$path/1024/$filename",1024);
			unless($verbosity < 2) { print "\n"; }
		}
	}
}

sub make_picture_size($$$){
	my $original_file= $_[0];
	my $new_file = $_[1];
	my $size = $_[2];
	
	#check for size
	if((-e "$new_file")){
		if($already_watermarked == 0){
			print resize("$original_file","$new_file",$size,$resize_quality);
			unless($verbosity < 2) { print " -$size- "; }
			$count_new_thumbnails++;
		}
	}elsif($sizes =~ /$size/){
		print resize("$original_file","$new_file",$size,$resize_quality);
		unless($verbosity < 2) { print " -$size- "; }
		$count_new_thumbnails++;
	}
}

################################################################
# takes the selected album and makes sure that we have all of
# the directories that we need up to that point
###############################################################
sub check_data_directories($){
	my $directory = $_[0];
	my $return;
	my @steps;
	my $step;
	my $sofar;

	$directory =~ s/^$photoroot\///i;
	@steps = split (/\//,"$directory");
	#$return .= "checking data directories for $directory<br>";
	foreach $step (@steps){
		$step =~ s/\///gi;
		if($sofar){
			$sofar = "$sofar/$step";
		}else{
			$sofar = "$dataroot/$step";
		}
		unless(-e "$sofar"){
			$return .= "creating $sofar with 755 permissions\n";
			mkdir("$sofar",0755)||die("Could not create data directory! $!");
			$count_new_directories++;
		}
	}
	unless(-e "$sofar/thumbnails"){
		mkdir("$sofar/thumbnails",0755)||die("Could not create thumbnails directory! $!");
		$count_new_directories++;
	}
	unless(-e "$sofar/comments"){
		mkdir("$sofar/comments",0755)||die("Could not create thumbnails directory! $!");
		$count_new_directories++;
	}
	unless(-e "$sofar/descriptions"){
		mkdir("$sofar/descriptions",0755)||die("Could not create thumbnails directory! $!");
		$count_new_directories++;
	}
	unless(-e "$sofar/320"){
		mkdir("$sofar/320",0755)||die("Could not create thumbnails directory! $!");
		$count_new_directories++;
	}
	unless(-e "$sofar/640"){
		mkdir("$sofar/640",0755)||die("Could not create thumbnails directory! $!");
		$count_new_directories++;
	}
	unless(-e "$sofar/800"){
		mkdir("$sofar/800",0755)||die("Could not create thumbnails directory! $!");
		$count_new_directories++;
	}
	unless(-e "$sofar/1024"){
		mkdir("$sofar/1024",0755)||die("Could not create thumbnails directory! $!");
		$count_new_directories++;
	}
	return $return;
}


