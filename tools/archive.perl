#!/usr/opt/bin/perl -wT
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
# This is free software; you can redistribute it and/or modify it
#   under the same terms as Perl itself.
# $Id$
# $URL$

use strict;
use IO::File;
use Time::Local;
use Template;
use File::chdir;
use File::Copy;
use File::Path;
use File::Find;

sub search_RCStag {
    my $file = shift;
    my $search_tags = shift;

    my $fh = IO::File->new($file, 'r');
    if (defined $fh) {
	my %tags;

	foreach my $line (<$fh>) {
	    foreach my $tag (@$search_tags) {
		if ($line =~ /\$\Q$tag:\E (.+?) \$/) {
		    $tags{$tag} = $1;
		}
	    }
	}
	foreach my $tag (keys %tags) {
	    @$search_tags =
		grep {
		    $tag ne $_;
		} @$search_tags;
	}
	return \%tags, $search_tags;
    }
    return {}, $search_tags;
}

##
# timeglobal($S, $M, $H, $d, $m, $y)
sub timeglobal{
    my $times = eval(timegm(@_));

    # leapsecond 対策。
    $times += $_[0] - (gmtime($times))[0];

    return 0 if($times <= 0);
    return $times;
}

sub untaint {
    my $data = shift;

    $data =~ s/^([^\0]*)\0.*$/$1/s;
    $data =~ /^(.+)$/;
    return $1;
}

sub main {
    my @args = @_;

    my $BASE_PATH = do {
	use File::Basename;
	use File::Spec;

	# clean-up
	File::Spec->rel2abs(File::Spec->catdir(dirname($0),'../..')) =~ /^(.+)$/;
	$1;
    };
    # PATH clean-up (maybe ok)
    $ENV{PATH} =~ /^(.+)$/;
    $ENV{PATH} = $1;
    my $MASTER_PATH = "$BASE_PATH/vendor/cvs/master";
    my $ARCHIVE_PATH = "$BASE_PATH/trunk/web/archive";
    my @COMPRESS_ARCHIVE_FORMATS = qw(zip);
    my @ARCHIVE_FORMATS = qw(tar);
    my @OUTPUT_FORMATS = qw(patch tar.gz tar.bz2 zip);
    my $ARCHIVE_NAME = 'tiarra-';
    my $REMOTE_HOST = "sakura.angelicalice.net";
    my $REMOTE_PATH = "clovery.jp/www/tiarra";
    my $REMOTE_URI = "$REMOTE_HOST:$REMOTE_PATH";
    my $ARCHIVE_URI = "http://www.clovery.jp/tiarra/";
    my $ARCHIVELIST_FILENAME = 'archives.list';
    my $do_uploading = 1;

    my @archive_files = ();
    my @compress_files = ();
    my %upload_files;
    my ($tags, $notfound_tags) = search_RCStag("$MASTER_PATH/ChangeLog",
					       [qw(Date Revision Id Author)]);
    if (@$notfound_tags) {
	print STDERR "ERROR: can't find tags...\n";
	print STDERR join("\n", @$notfound_tags);
	print STDERR "\n";
	return 1;
    }

    $tags->{Date} =~ m|(\d{4})/(\d{2})/(\d{2})|;
    my $date = $1.$2.$3;
    my $version = '0';
    my $revision = $tags->{Revision};
    my $suffix = '';
    my $archive = $ARCHIVE_NAME.$date.$suffix;
    my $dir = substr($date, 0, 4).'/'.substr($date, 4, 2);
    print "start creating archive...\n";
    print "\tDate    : $tags->{Date}\n";
    print "\tVersion : $version\n";
    print "\tRevision: $revision\n";
    print "\tId      : $tags->{Id}\n";
    print "\tAuthor  : $tags->{Author}\n";
    print "\tArchive : $archive\n";

    # make archive
    $CWD = $ARCHIVE_PATH;
    umask(022);
    system("ezpack tiarra ".
	       join(',',@ARCHIVE_FORMATS, @COMPRESS_ARCHIVE_FORMATS)." $date$suffix");
    push(@archive_files, map {"$archive.$_";} @COMPRESS_ARCHIVE_FORMATS);
    push(@compress_files, map {"$archive.$_";} @ARCHIVE_FORMATS);

    # update archives list
    my @archives = ();
    my $save_number = 5;

    do {
	my $filename = $ARCHIVELIST_FILENAME;
	push(@{$upload_files{archive}}, $filename);
	print STDERR "update archives list...\n";
	-e $filename && move($filename, "$filename.bak");
	my $write = IO::File->new("> $filename");
	if (defined $write) {
	    push(@archives,
		 "$archive\t$dir\t$version\t$revision\t$tags->{Date}\n");
	    $write->syswrite($archives[0]);
	    my $read = IO::File->new("< $filename.bak");
	    if (defined $read) {
		my $line;
		while ($line = $read->getline) {
		    next if substr($line, 0, length($archive)) eq $archive;
		    push(@archives, $line) if $save_number > @archives;
		    $write->syswrite($line);
		}
		$read->close;
	    } else {
		print STDERR "can't read!\n";
		print STDERR "but continue...\n";
	    }
	    $write->close;
	} else {
	    print STDERR "can't write!\n";
	    -e "$filename.bak" && move("$filename.bak", $filename);
	    return 1;
	}
    };

    # generate patch
    do {
	print STDERR "generate patch...\n";
	my $work_dir = "$ARCHIVE_PATH/temp";
	my $archive_extract_command = 'tar xf';
	my $archive_ext = '.tar';
	my @archive_datas = map {
	    /^(.+)$/;
	    (split(/\t/, $1))[0];
	} @archives[1, 0];
	my $filename = $archive_datas[1];

	mkpath $work_dir;
	local $CWD = $work_dir;

	# extract
	foreach my $archive (@archive_datas) {
	    system("$archive_extract_command ../$archive$archive_ext");
	}

	# make_patch
	system("diff -urN " . join(' ', @archive_datas)
		   . " > ../$filename.patch");
	push(@archive_files, "$filename.patch");

	system("diff -u " . join(' ', map { "$_/NEWS" } @archive_datas)
		   . " > ../$filename.changelog.patch");
	system("diff -u " . join(' ', map { "$_/sample.conf" } @archive_datas)
		   . " >> ../$filename.changelog.patch");
	system("diff -u " . join(' ', map { "$_/ChangeLog" } @archive_datas)
		   . " >> ../$filename.changelog.patch");
	push(@archive_files, "$filename.changelog.patch");

	rmtree $work_dir;
    };

    # compress
    do {
	print STDERR "do compress...\n";
	my %compress = (
	    '.gz' => 'gzip -9',
	    '.bz2' => 'bzip2 -9',
	   );

	foreach my $filename (@compress_files) {
	    map {
		system("cat $filename | $compress{$_} > $filename$_");
		push(@archive_files, "$filename$_");
	    } keys %compress;
	}
    };

    # make digest
    do {
	print STDERR "make digest...\n";
	my $filename;
	my $digest_filename;
	push(@archive_files, map {
	    $filename = $_;
	    $digest_filename = "$filename.digests";
	    system("gpg --print-mds $filename > $digest_filename");
	    $digest_filename;
	} @archive_files);
    };

    print STDERR "generate indecies...\n";
    map {
	print STDERR "    $_";
    } @archives;

    my $generator = sub {
	my ($title, $filename) = @_;
	print STDERR "  generate $title...\n";
	push(@{$upload_files{'.'}}, $filename);
	-e $filename && move($filename, "$filename.bak");

	my $read = IO::File->new("< $filename.tmpl");
	my $write = IO::File->new("> $filename");
	if (defined $read && defined $write) {
	    my %vars = (
		formats => [@OUTPUT_FORMATS],
	       );

	    foreach (@archives) {
		my @labels = qw(archive dir version revision date);
		my %var;
		my $archive = $_;
		chomp $archive;
		map {
		    $var{shift(@labels)} = $_;
		} split(/\t/, $archive);
		$var{date} =~ m|(\d{4})/(\d{2})/(\d{2}) (\d{2}):(\d{2}):(\d{2})|;
		$var{date_pretty} = "$1/$2/$3";
		$var{date_rfc} = "$1-$2-$3";
		$var{datetime_rfc} = "$1-$2-$3T$4:$5:$6Z";
		push (@{$vars{releases}}, \%var);
	    }
	    map {
		$vars{$_} = $vars{releases}[0]{$_};
	    } qw(archive dir version revision date date_pretty date_rfc datetime_rfc);
	    $vars{uri} = $ARCHIVE_URI;

	    my $tt = Template->new({
		START_TAG => '<tt:tmpl',
		END_TAG => '/>',
		POST_CHOMP => 1,
	    }) || die $Template::ERROR;

	    $tt->process($read, \%vars, $write) || die $Template::ERROR;
	    $write->close;
	} else {
	    if (!defined $read) {
		print STDERR "can't open read stream for $title\n";
	    }
	    if (!defined $write) {
		print STDERR "can't open write stream for $title\n";
	    }
	}
    };

    $generator->('html', '../index.html.ja.utf8');
    $generator->('rss', '../index.rdf.ja.utf8');

    # generate documentation directory
    do {
	print STDERR "generate documentation directory...\n";
	my $work_dir = "$ARCHIVE_PATH/temp";
	my $archive_extract_command = 'tar xf';
	my $archive_ext = '.tar';
	$archives[0] =~ /^(.+)$/;
	my $archive = (split(/\t/, $1))[0];
	rmtree ['../doc', $work_dir];
	mkpath $work_dir;
	local $CWD = $work_dir;
	system("$archive_extract_command ../$archive$archive_ext $archive/doc");
	move("$archive/doc", "../../doc");
	rmtree $work_dir;
    };

    # set last-modified time, and permission
    do {
	print STDERR "set modified time, and permission...\n";
	$tags->{Date} =~ m|(\d{4})/(\d{2})/(\d{2}) (\d{2}):(\d{2}):(\d{2})|;
	my $time = timeglobal($6, $5, $4, $3, $2 - 1, $1 - 1900);
	my $mode = 0644; # -wr-r--r--
	my @files_to_change = (
	    @archive_files,
	    map {
		@$_;
	    } values(%upload_files),
	   );
	find({
	    wanted => sub {
		/^(.+)$/;
		-f $1 && push @files_to_change, $1;
	    },
	    no_chdir => 1,
	}, '../doc');

	utime($time, $time, @files_to_change);
	chmod($mode, @files_to_change);
	#print STDERR "file to change...\n";
	#print STDERR join('', map {
	#    "\t$_\n";
	#} @files_to_change);
    };

    if ($do_uploading) {
	print STDERR "file uploading...\n";
	system("ssh $REMOTE_HOST mkdir -p $REMOTE_PATH/archive/$dir");
	system("scp -p -C ".join(' ',@archive_files)." $REMOTE_URI/archive/$dir");
	foreach my $key (keys %upload_files) {
	    system("scp -p -C ".join(' ',@{$upload_files{$key}})." $REMOTE_URI/$key");
	}
	system("scp -p -r -C ../doc $REMOTE_URI");
	system("svn commit -m '* upload archive.' $ARCHIVELIST_FILENAME");
    }
    return 0;
}

exit main(@ARGV);
