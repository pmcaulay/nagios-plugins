#!/usr/bin/perl -w
#
# Script to check the age of files in a directory and return an alert
# if any are older than a given age.
#
# Last updated 2013-02-18 by Peter Mc Aulay
#

use strict;
use Getopt::Long;
use utils qw($TIMEOUT %ERRORS);
# Standalone Windows version
#my (%ERRORS) = ( OK => 0, WARNING => 1, CRITICAL => 2, UNKNOWN => 3, WARN => 1, CRIT => 2 );

my ($debug, $help);
my ($file, $dir, $warning, $critical, $onlyfiles);
my $oldest_time = 0;
my $oldest_file;
my @files;

# Get command line options
GetOptions (
	"debug"	 => \$debug,
	"h|help"	=> \$help,
	"f|file=s"      => \$file,
	"onlyfiles"     => \$onlyfiles,
	"d|directory=s" => \$dir,
	"w|warning=s"   => \$warning,
	"c|critical=s"  => \$critical,
);

# Usage info
sub print_help () {
	print "Usage: $0 [-d directory] [-f filename] [--onlyfiles] -w warning -c critical\n";
	print "Thresholds are expressed in minutes.\n";
	exit $ERRORS{'UNKNOWN'};
}

# Error handler
sub print_error {
	my $msg = $_[0];
	print "$msg\n" if $msg;
	exit $ERRORS{'CRITICAL'};
}

# Input validation
!($help) || print_help();
($warning) || print_error("No warning threshold specified");
($critical) || print_error("No critical threshold specified");

# Build file list
if ($file) {
	# Both directory and filespec
	if ($dir) {
		-d "$dir" || print_error("$dir not found or not readable");
		@files = <$dir/$file>;
	# Otherwise, just the one file
	} else {
		-f "$file" || print_error("$file not found or not readable");
		@files = ($file);
	}
} else {
	# By default, all files in the directory are considered
	-d "$dir" || print_error("$dir not found or not readable");
	@files = <$dir/*>;
}

# Check timestamp on every file, keep the oldest
for my $f (@files) {
	next if -d $f && ($onlyfiles);

	my $timestamp = (stat("$f"))[9];
	my $mtime = time - $timestamp;

	# Sanity check: ignore files dated 01/01/1970
	# Many file transfer applications create temp files with blank timestamps
	print "Bogus timestamp: $timestamp\n" if ($debug && $timestamp < 86400);
	$mtime = 0 if $timestamp < 86400;

	print "$f last modified $mtime seconds ago\n" if $debug;
	if ($mtime > $oldest_time) {
		$oldest_time = $mtime;
		$oldest_file = $f;
	}
}

print "Oldest file: $oldest_file, last modified $oldest_time s ago\n" if ($debug && $oldest_file);

# Thresholds are in minutes
$oldest_time = $oldest_time / 60;

# Compare oldest file against thresholds
if ($oldest_time >= $warning && $oldest_time < $critical) {
	print "WARNING: ", $file ? "matching " : "" , "files older than $warning minutes: $oldest_file ($oldest_time min)\n";
	exit $ERRORS{'WARNING'};
} elsif ($oldest_time >= $critical) {
	print "CRITICAL: ", $file ? "matching " : "" , "files older than $critical minutes: $oldest_file ($oldest_time min)\n";
	exit $ERRORS{'CRITICAL'};
} else {
	print "OK - No ", $file ? "matching " : "" , "files older than $warning minutes\n";
	exit $ERRORS{'OK'};
}
