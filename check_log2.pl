#!/usr/bin/perl
#
# Log file regular expression based parser plugin for Nagios.
#
# Written by Aaron Bostick (abostick@mydoconline.com)
# Rewritten by Peter Mc Aulay and Tom Wuyts
# Released under the terms of the GNU General Public Licence v2.0
#
# Last updated 2012-07-26 by Peter Mc Aulay <peter@zeron.be>
#
# Thanks and acknowledgements to Ethan Galstad for Nagios and the check_log
# plugin this is modeled after.
#
# Usage: check_log2.pl --help
#
#
# Description:
#
# This plugin will scan arbitrary text files looking for regular expression 
# matches.  A temporary file used to store the seek byte position of the last
# scan.  This file will be created automatically.
#
# The search pattern can be any RE pattern that perl's s/// syntax accepts.
# A negation pattern can be specified, causing the plugin to ignore lines
# matching it.  Alternatively, the ignore patterns can be read from a file
# (one regexp per line).  This is for badly behaved applications that produce
# lots of error messages when running "normally" (certain Java apps come to
# mind).  You can use either -n or -f, but not both.  If both are specified,
# -f will take precedence.
#
# Patterns can be either case sensitive or case insensitive.  The -i option
# controls case sensitivity for both search and ignore patterns.
#
# It is also possible to just raise an alert if the log file was not written
# to since the last check (using -d).
#
# Note that a bad regexp might case an infinite loop, so set a reasonable
# plugin time-out in Nagios.
#
# Optionally the plugin can execute a block of Perl code on each matched line,
# to further affect the output (using -e).  The code should be enclosed in
# brackets.  This allows for complex parsing rules of log files based on their
# actual content.  The matched line will be passed as $_.
#
# Modify $parse_out to make the plugin save a custom string for this match
# (the default is the input line itself).
#
# Return code control:
# - If the block returns a non-zero exit code, it is considered to be a match
#   and is counted towards the alert threshold.
# - If the block returns zero, the line is not counted even though it matches
#   the search pattern.
# - If the return code is > 1, a critical alert is raised (if the threshold
#   is reached).  This overrides the absence of the -C switch.
#
# Note: -e is an experimental feature and potentially dangerous!
#
#
# Return codes:
#
# This plugin returns OK when a file is successfully scanned and no pattern
# matches are found.  It returns either WARNING or CRITICAL (depending on the
# presence of the -C switch) if 1 or more patterns are found.  The -c option
# can be used to raise the alert threshold, so that an alert is triggered only
# if this many or more matches are found.
#
# If an eval block is run (-e) it may further affect the return code.
#
# The plugin returns UNKNOWN if the -d option is used, and the log file hasn't
# grown since the last run, unless --critical has been specified, in which case
# CRITICAL is returned instead.  Take care that the time between service checks
# is less than the minimum amount of time your application writes to the log
# file.
#
# The plugin always returns CRITICAL if an error occurs, such as if a file is
# not found or in case of a permissions problem or I/O error.
#
#
# Output:
#
# The line of the last pattern matched is returned in the output along with
# the pattern count.  If custom Perl code is run on matched lines using -e,
# it may modify the output via $parse_out.
#
#
# Nagios service check configuration notes:
#
# 1. The "max_attempts" value for the service should be 1, to prevent Nagios
#    from retrying the service check (the next time the check is run it will
#    not produce the same results).
#
# 2. The "notify_recovery" value for the service should be 0, so that Nagios
#    does not notify you of "recoveries" for the check.  Since pattern matches
#    in the log file will only be reported once, recoveries don't really apply
#    to this type of check.
#
# 3. You must supply a different seek file for each service check that you
#    define - even if the different checks are reading the same log file.
#
#
# Simple examples:
#
# Return WARNING if errors occur in the system log, but ignore the ones from
# the NRPE agent itself:
#   check_log.pl -l /var/log/messages -s /tmp/log_messages.seek -p '[Ee]rror' -n nrpe
#
# Return CRITICAL if the application stops writing to a log file:
#   check_log.pl -l heartbeat.log -s heartbeat.seek -d -C
#
# Return WARNING if more than 10 logon failures logged since last check:
#   check_log.pl -l /var/log/auth.log -s /tmp/auth.seek -p 'Invalid user' -c 10
#
#
# Advanced example:
#
# Return WARNING and print a custom message if more than 50 files took more
# than 4000ms to process since the last check, where the file name is logged
# in the first column of a semi-column separated file, and the processing time
# is logged in the 7th column:
#
# check_log2.pl -l processing.log -s processing.seek -p 'ERROR' -c 50 -e \
# '{
#	my @fields = split(/;/);
#	if ($fields[6] > 4000) { 
#		$parse_out = "Processing time for $fields[0] exceeded: $fields[6]\n";
#		return 1
#	}
# }'
#
#
####

require 5.004;

use strict;
use utils qw($TIMEOUT %ERRORS &print_revision &support &usage);
use Getopt::Long qw(:config no_ignore_case);

# Predeclare subroutines
sub print_usage ();
sub print_version ();
sub print_help ();
sub cond_match;

# Initialise variables
my $plugin_revision = '$Revision: 3.0 $ ';
my $log_file = '';
my $seek_file = '';
my $critical = '';
my $difference = '';
my $re_pattern = '';
my $case_insensitive = '';
my $neg_re_pattern = '';
my $negpatternfile = '';
my $pattern_count = 0;
my $count_threshold = 1;
my $pattern_line = '';
my $parse_pattern = '';
my $parse_line = '';
my $parse_count = 0;
my $parse_result = 0;
my $parse_out = "";
my $output;
my $version;
my $help;

# Grab options from command line
GetOptions (
	"l|logfile=s"		=> \$log_file,
	"s|seekfile=s"		=> \$seek_file,
	"p|pattern=s"		=> \$re_pattern,
	"n|negpattern=s"	=> \$neg_re_pattern,
	"f|filenegpattern=s"	=> \$negpatternfile,
	"C|critical"		=> \$critical,
	"i|case-insensitive"	=> \$case_insensitive,
	"d|difference"		=> \$difference,
	"c|count=i"		=> \$count_threshold,
	"e|parse=s"		=> \$parse_pattern,
	"v|version"		=> \$version,
	"h|help"		=> \$help,
);

!($version) || print_version ();
!($help) || print_help ();

# These options are mandatory
($log_file) || usage("Log file not specified.\n");
($seek_file) || usage("Seek file not specified.\n");
($re_pattern) || usage("Regular expression not specified.\n");

# Open log file
open (LOG_FILE, $log_file) || die "Unable to open log file $log_file: $!";

# Try to open log seek file.  If open fails, we seek from beginning of file by default.
if (open(SEEK_FILE, $seek_file)) {
	chomp(my @seek_pos = <SEEK_FILE>);
	close(SEEK_FILE);

	#  If file is empty, no need to seek...
	if ($seek_pos[0] != 0) {
            
		# Compare seek position to actual file size.  If file size is smaller,
		# then we just start from beginning i.e. file was rotated, etc.
		my @stat = stat(LOG_FILE);
		my $size = $stat[7];

		# If the file hasn't grown since last time and --difference was specified, stop here.
		if ($seek_pos[0] eq $size && $difference) {
			if ($critical) {
				print "CRITICAL: Log file not written to since last check\n";
				exit $ERRORS{'CRITICAL'};
			} else {
				print "WARNING: Log file not written to since last check\n";
				exit $ERRORS{'UNKNOWN'};
			}
		}

		if ($seek_pos[0] <= $size) {
			seek(LOG_FILE, $seek_pos[0], 0);
		}
	}
}

# If we have an exclusion pattern file, read it first
my @negpatterns;
if ($negpatternfile) {
	open (PATFILE, $negpatternfile) || die "Unable to open pattern file $negpatternfile: $!";
	chomp(@negpatterns = <PATFILE>);
	close(PATFILE);
} else {
	@negpatterns = ($neg_re_pattern);
}

# Loop through every line of log file and check for pattern matches.
# Count the number of pattern matches and remember the full line of 
# the most recent match.
while (<LOG_FILE>) {
	my $line = $_;
	my $negmatch = 0;

	# Try if the line matches the pattern
	if (/$re_pattern/i) {
		# If not case insensitive, skip if not an exact match
		unless ($case_insensitive) {
			next unless /$re_pattern/;
		}

		# And if it also matches the exclude list
		foreach (@negpatterns) {
			next if ($_ eq '');
			if ($line =~ /$_/i) {
				# As case sensitive as the first match
				unless ($case_insensitive) {
					next unless $line =~ /$_/;
				}
				$negmatch = 1;
				last;
			}
		}

		# OK, line matched
		if ($negmatch == 0) {
			# Increment final count
			$pattern_count += 1;
			# Save last matched line
			$pattern_line = $line;
			# Optionally execute custom code
			if ($parse_pattern) {
				my $res = eval $parse_pattern;
				warn $@ if $@;
				# Save the result if non-zero
				if ($res > 0) {
					$parse_count += 1;
					$parse_result = $res;
					# Force a critical alert if the return code is higher than 1
					$critical = 1 if $res > 1;
					# If the eval block set $parse_out, save that instead
					if ($parse_out && $parse_out ne "") {
						$parse_line = $parse_out;
					} else {
						$parse_line = $line;
					}
				}
			}
		}
	}
}

# Overwrite log seek file and print the byte position we have seeked to.
open(SEEK_FILE, "> $seek_file") || die "Unable to open seek count file $seek_file: $!";
print SEEK_FILE tell(LOG_FILE);

# Close files
close(SEEK_FILE);
close(LOG_FILE);

# Print result and return exit code.
#
# An alert is raised if either the number of lines matched, or if custom code was run,
# the number of lines where the eval block returned non-zero, exceeded the count threshold.
if (($parse_count >= $count_threshold) || ($parse_result = 0 && $pattern_count >= $count_threshold)) {
	if ($critical) { 
		print "CRITICAL: ";
	} else {
		print "WARNING: ";
	}

	# Output last line parsed with non-zero result, or output last match if no parsing was done
	if ($parse_result > 0) {
		$output = "Parsed output ($parse_count not OK): $parse_line";
	} else {
		$output = $pattern_line;
	}

	# Filter out any pipes in the output (as that is the Nagios output/perfdata separator)
	$output =~ s/\|/\!/g;

	print "Found $pattern_count lines (limit=$count_threshold): $output";

	# Exit with the appropriate Nagios status code
	if ($critical) { 
		exit $ERRORS{'CRITICAL'}; 
	} else {
		exit $ERRORS{'WARNING'}; 
	}
} else {
	print "OK - No matches found.\n";
	exit $ERRORS{'OK'};
}

#
# Subroutines
#

# If invoked with a path, strip the path from our name
my $prog_dir;
my $prog_name = $0;
if ($0 =~ s/^(.*?)[\/\\]([^\/\\]+)$//) {
	$prog_dir = $1;
	$prog_name = $2;
}

# Short usage info
sub print_usage () {
    print "Usage: $prog_name -l <log_file> -s <log_seek_file> -p <pattern> [-n <negpattern>|-f <negpatternfile>] [-c <count>] [-C] [-d] [-i] [-e '{ eval block}']\n";
    print "Usage: $prog_name [ -v | --version ]\n";
    print "Usage: $prog_name [ -h | --help ]\n";
}

# Version number
sub print_version () {
    print_revision($prog_name, $plugin_revision);
    exit $ERRORS{'OK'};
}

# Long usage info
sub print_help () {
    print_revision($prog_name, $plugin_revision);
    print "\n";
    print "Scan arbitrary log files for regular expression matches.\n";
    print "\n";
    print_usage();
    print "\n";
    print "-l, --logfile=<logfile>\n";
    print "    The log file to be scanned\n";
    print "-s, --seekfile=<seekfile>\n";
    print "    The temporary file to store the seek position of the last scan\n";
    print "-p, --pattern=<pattern>\n";
    print "    The regular expression to scan for in the log file\n";
    print "-i, --case-insensitive\n";
    print "    Do a case insensitive scan\n";
    print "-n, --negpattern=<negpattern>\n";
    print "    The regular expression to skip in the log file\n";
    print "-f, --negpatternfile=<negpatternfile>\n";
    print "    Specifies a file with regular expressions which all will be skipped\n";
    print "-c, --count=<number>\n";
    print "    Return an alert only if at least this many matches found\n";
    print "-C, --critical\n";
    print "    Return CRITICAL instead of WARNING\n";
    print "-d, --difference\n";
    print "    Return an alert if the log file was not written to since the last scan\n";
    print "-e, --parse\n";
    print "    Perl 'eval' block to parse each matched line with (EXPERIMENTAL)\n";
    print "    The code should be in curly brackets and quoted.\n";
    print "    The return code of the block of code influences the final result:\n";
    print "    - A return code of zero means OK\n";
    print "    - A non-zero return code means WARNING\n";
    print "    - If -C is also used, a non-zero return code means CRITICAL\n";
    print "    For the final check status, a result obtained by parsing takes precedence\n";
    print "    over a result obtained by just counting matches.\n";
    print "\n";
    support();
    exit $ERRORS{'OK'};
}

