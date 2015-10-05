#!/usr/bin/perl -w
# nagios: -epn

=pod

=head1 SYNOPSIS

check_log3.pl is a regular expression based log file parser plugin for Nagios and Nagios-like monitoring systems.

Tested on Linux, Windows, AIX and Solaris.

Usage:

  check_log3.pl --help
  perldoc check_log3.pl

=head1 CREDITS

Originally written by Aaron Bostick (abostick@mydoconline.com)
Rewritten by Peter Mc Aulay and Tom Wuyts
The --output-all feature was contributed by Ian Gibbs 
The --and feature was contributed by Wesley Moore
Released under the terms of the GNU General Public Licence v2.0

Last updated 2015-10-01 by Peter Mc Aulay <peter@zeron.be>

Thanks and acknowledgements to Ethan Galstad for Nagios and the check_log
plugin this is modeled after.


=head1 DESCRIPTION

This plugin will scan arbitrary text files looking for regular expression
matches.

The search pattern can be any Perl regular expression.  It will be passed
verbatim to the B<m///> operator (see B<man perlop>).  The search patterns can
be read from a file, one per line; the lines will be concatenated into a
single regexp of the form B<'line1|line2|line3|...'>.  If you specify the -p
option multiple times, the patterns will be concatenated in the same manner.
You can use either -p or -P, but not both.  If you specify both, -P will
take precedence.  If you specify the --and parameter the patterns will be
ANDed instead of OR'ed, i.e. all patterns must appear on a line to count as
a successful match (the order does not matter).

An ignore (whitelist) pattern can be specified using the -n option, causing
the plugin to ignore all lines matching it, even if they match the search
pattern.  This is for badly behaved applications that produce lots of error
messages when running "normally" (certain Java apps come to mind).  The list
of ignore patterns can be read from a file, one regexp per line, like the -P
option.  If you specify -n multiple times the patterns will be concatenated
in the same manner.  You can use either -n or -f, but not both.  If both are
specified, -f will take precedence.

Pattern matching can be either case sensitive or case insensitive.  The -i
option controls case sensitivity for both search and ignore patterns.

A temporary file is used to store the seek byte position of the last scan.
Specifying this file is optional, if you don't specify a filename it will be
auto-generated.  To read the entire file each run, use the null device (NUL
on Win32, /dev/null on Unix) as the seek file.  If you specify a directory,
the seek file will be written to that directory instead of in /tmp.

To monitor files with a dynamic component in the filename, such as rotated
or time stamped fike names, use -l to specify only the fixed part of the
path and filename, and the -m option to specify the variable part, using a
glob expression (see B<man 7 glob>).  If this combination pattern of -l and
-m matches more than one file, you can use the -t option to further narrow
down the selection to the most recently modified file, the first match
(sorted alphabetically) or the last match (this is the default).  You can
also use macro's similar to the Unix B<date(1)> format string syntax, and you
can use the --timestamp option to tell the script to look for files with
timestamps in the past (the default is the current date).

When using -m, do not specify a seek file; it will be ignored unless it is
/dev/null or a directory.  Also note that glob patterns are not the same as
regular expressions (please let me know if you want support for that).

If the -l option points to a directory, B<-m '*'> is assumed.

The -w and -c options control the WARNING and CRITICAL state thresholds; if
if none are provided, the plugin will return a WARNING state if at least one
match was found (equivalent to B<-w 1>).

If the thresholds are expressed as percentages, they are taken to mean the
percentage of lines in the input that match (match / total * 100).  When
using the -e or -E options, the percentage of matched lines that also match
the parsing condition is taken, rather than the total number of lines in the
input.

You can only specify each threshold once (if you specify one multiple times
the last one on the command line wins).  You can specify a percentage for
one threshold and an absolute number for another.

To invert the result of the pattern matching, use the "--negate" option.
This will return an alert if NOT at least X matches were found, with X
being the value of the -w and/or -c thresholds.  If you specify a warning
threshold higher than the critical threshold (and both > 0) then --negate
will be assumed.  Explicitly specifying --negate will have no additional
effect (you can't negate an implied negation, to avoid the urge of the next
maintainer of your installation to hunt you down and beat you with a stick).

Note that a bad regexp might case an infinite loop, so set a reasonable
plugin time-out in Nagios.  This goes double if you use custom eval code.

This plugin will set an internal time-out alarm based on the $TIMEOUT
setting found in utils.pm.  You can use the --timeout option to change this
behaviour.

It is also possible to raise a warning or critical alert if the log file was
not written to since the last check, using -d or -D.  This can be used as a
kind of "heartbeat" monitor.  You can use these options either by themselves
or in combination with pattern matching.  This is useful only if you can
guarantee that the frequency of log writes will always be higher than the
service check interval.  If no search pattern was specified but only -d or
-D, the -w and -c options control the number of expected new lines before an
alert is triggered.  In that case the -D option is equivalent to B<-d -c 1>.

Optionally the plugin can execute a block of Perl code on each matched line,
to further affect the output (using -e or -E).  The code should usually be
enclosed in curly brackets (for performance if nothing else) and probably
quoted.  This function allows for the performing of additional tests, output
reformatting, data extraction and other processing (possibly of lines other
than the current match, if you also use --context) of log file content.
You can use either -e or -E, but not both.  If you do, -E takes precedence.

This custom code is executed as a Perl 'eval' block and the matched line is
passed to it as $_.   (See "perldoc -f eval" for details).  You can modify
$parse_out to save a custom string for this match (the default is the input
line itself).  When using --context, you must modify @line_buffer instead of
$parse_out.  You can also modify $perfdata to return custom performance data
to Nagios (e.g. based on content extracted from the log file).  See the
Nagios plugin development guidelines for the proper format of performance
data metrics, as no validation is done by this plugin.  

If you want to parse every line in the log using the custom code, you must
use -p to specify a search pattern that matches every line (e.g. B<-p '.*'>).

Expected return codes of the eval block:

=over

=item *

If the code returns non-zero, it is counted towards the alert threshold.

=item *

If the code returns 0, the line is not counted against the threshold.  (It's still counted as a match, but for informational purposes only.)

=back

B<Note:> using custom eval code is an advanced feature and can potentially
have unintended side effects.  The eval code has full access to the plugin's
internal variables, so bugs in your code may lead to unpredictable plugin
behaviour and incorrect monitoring results.  If you don't know at least a
little Perl, do not attempt to use this feature.


=head1 EXIT CODES

This plugin returns OK when a file is successfully scanned and no lines
matching the search pattern(s) are found, or not enough to exceed the
alerting thresholds.

It returns WARNING or CRITICAL if any matches were found that are not also
whitelisted; the -w and -c options determine how many lines must match before
an alert is raised.  If an eval block is defined (via -e or -E) a line is
only counted if it both matches the search pattern B<and> the custom code
returns a non-zero result for that line.

By default, the plugin returns WARNING if one match was found.

Note that it is not possible to generate WARNING alerts for one pattern and
CRITICAL alerts for another in the same run.  If you want that, you need to
define two service checks (using different seek files!) or use another
plugin.

The plugin returns WARNING if the -d option is used, and the log file hasn't
grown since the last run.  Likewise, if -D is used, it will return CRITICAL
instead.  Take care that the time between service checks is less than the
minimum amount of time your application writes to the log file when you use
these options.  If you specify only these options and no search pattern,
you can use the -w and -c options to control how many new lines minimum
there should be in the log since the last check before returning an alert.

If the log file is missing (or the multiple file selection options don't
return any matches) the plugin will return CRITICAL unless overridden by
the --missing option.  You can specify a custom error message using the
--missing-msg option.

If the --ok option is used, the plugin will always return OK unless an error
occurs and will ignore any thresholds.  This can be useful if you use this
plugin only for its log parsing functionality, not for alerting (e.g. to
just plot a graph of values extracted from the log file).  Specifying a zero
value for both -w and -c has the same effect.

The plugin always returns CRITICAL if an error occurs, such as if a file
is not found (except when using --missing) or in case of a permissions
problem or I/O error.


=head1 OUTPUT

The line of the last pattern matched is returned in the output along with
the service state, the line and pattern count and the thresholds used (not
if you used --no-header).  If you use the --quiet option the output will
always be "No matches found" if the thresholds were not reached.

Use the -a option to output all matching lines instead of just the last
matching one.  Note that Nagios will only read the first 4 KB of data that
a plugin returns, and that the NRPE daemon even has a 1KB output limit.

The --report-first-only option will cause the plugin to output the first
matching line instead of the last one.  This option is ignored if -a is
also specified.  This is useful when you are mainly interested in when a
problem first occurred, rather than the last occurrence.

The --stop-first-match option will not only cause the plugin to report the
first match, but also stop processing at that point, so that every single
match is reported (eventually; one match gets reported per service check).
This option overrides -a.  Note that this means that such a service check
may continue to report errors long after the original problem is solved.

If you use both --report-first-only and --stop-first-match together, then
--report-first-only takes precedence.

Use the -C option to return some lines of context before and/or after the
match, like "grep -C".  Prefix the number with - to return extra lines only
before the matched line, with + to return extra lines only after the matched
line, or with nothing to return extra lines both before and after the match.

If you use -a and -C together, the plugin will output "---" between blocks
of matched lines and their context.

If custom Perl code is run on matched lines using -e, the number of matches
for which the custom code returned true is also returned.  You may modify
the output via $parse_out (for best results, do not produce output directly
using 'print' or related functions).

B<Note:> lines returned as context are not parsed automatically with -e or -E,
nor is context preserved if you modify $parse_out.  If you want to return
custom output while also preserving context, modify @line_buffer instead to
change the content of the read-back buffer.  You cannot modify lines after
the match this way (but you can read ahead using the read_next function, if
you must.  Try not to modify the LOG_FILE file handle directly).

Use --debug to see what the plugin is doing behind the scenes.


=head1 PERFORMANCE DATA

The number of matching lines is returned as performance data (label "lines").
If -e is used, the number of lines for which the eval code returned 1 is
also returned (label "parsed").  The eval code can change the perfdata output
by modifying the value of the $perfdata variable, e.g. for when you want to
graph the actual figures appearing in the log file.  In that case the line
and match counts are not returned.

You can suppress the plugin's standard "lines" and "parsed" perfdata counters
using the --no-perfdata option.


=head1 NAGIOS SERVICE CHECK CONFIGURATION NOTES

Please be aware of the following things when configuring service checks
using this plugin:

=over

=item 1.

The maximum check attempts value for the service should always be 1, to
prevent Nagios from retrying the service check (the next time the check
is run it will not produce the same results).  Otherwise you will not
receive a notification for every match.

=item 2.

The notification options for the service should be set to not notify you
of recoveries for the check.  Since pattern matches in the log file will
normally only be reported once, "recoveries" don't really apply.  (An
exception might be if you are reading the whole file each time.)

=item 3.

If you have more than one service check reading the same log file, you
must explicitly supply a seek file name using the -s option.  If you use
the -s option explicitly you must always use a different seek file for
each service check.  Otherwise one service check may start reading where
another left off, which is likely not what you want (especially since
the order in which they are run by Nagios is unpredictable).

=back

Also note that many NRPE agents restrict the characters that they accept,
which includes those commonly used in regular expressions.


=head1 CHARACTER SET SUPPORT

This plugin supports any character set and encodings your local system and
Perl installation support.  However, the plugin does not itself care about
or try to guess input file encodings, so if you're reading files with multi-
byte or non-ASCII characters you will need to tell the plugin about it using
the --input-enc option.  (UTF-8 is always handled correctly as it's the Perl
native format.)

On Windows systems in particular UTF-16 and Windows-1252 are common, so you
may need to use "--input-enc=utf-16" or "input-enc=win-1252" to correctly
find non-ASCII strings in such files.

The plugin outputs UTF-8 by default, but you can change this using the
--output-enc option.  You may need to do this if your service check output
looks wrong in Nagios, e.g. "--output-enc=latin1".

The --input-enc option affects the interpretation of log files and search
pattern files, but not seek files or custom parsing scripts (for which it's
either not necessary or which take care of their own internal encoding).

Note that the encoding of the patterns passed from the command line by the
shell (from Nagios, an NRPE agent, or by you while testing manually) must
match the encoding specified by --input-enc.  You may have to use pattern
files if this is not the case (such as parsing Windows UTF-16 files on a
Linux system, whose shells normally uses UTF-8).

Please note that the quality of Unicode support varies somewhat between Perl
versions.  Use at least Perl 5.8.1 and preferably 5.14 or higher if you need
these features.


=head1 EXAMPLES

Return WARNING if errors occur in the system log, but ignore the ones from
the NRPE agent itself:

  check_log3.pl -l /var/log/messages -p '[Ee]rror' -n nrpe

Return WARNING if 10 or more logon failures have been logged since the last
check, or CRITICAL if there are 50 or more:

  check_log3.pl -l /var/log/auth.log -p 'Invalid user' -w 10 -c 50

Return WARNING if half or more of all new lines logged contain errors, and
CRITICAL if the application stops logging altogether:

  check_log3.pl -l /var/log/heartbeat.log -p ERROR -w 50% -D

Return WARNING if there are error messages in a rotated log file (so we're
actually looking for /var/log/messages* and want the most recent one):

  check_log3.pl -l /var/log/messages -m '*' -p Error -t most_recent

Return WARNING if there are error messages in a log whose name contains a
time stamp, so we're really reading access.YYMMDD.log:

  check_log3.pl -l /data/logs/httpd/access -m '.%Y%m%d.log' -p Error

Return CRITICAL if not at least one MARK was written to the syslog since the
last check:

  check_log3.pl -l /var/log/messages -p MARK --negate -c 1

Return WARNING if there are lines containing any combination of the strings
'sudo', 'root' and 'baduser' in /var/log/messages, and list them all:

  check_log3.pl -l /var/log/messages -p sudo -p root -p baduser --all -a

Return WARNING and print a custom message if there are 50 or more lines
in a CSV formatted log file where column 7 contains a value over 4000:

  check_log3.pl -l processing.log -p ',' -w 50 -e \
   '{
       my @fields = split(/,/);
       if ($fields[6] > 4000) {
	       $parse_out = "Processing time for $fields[0] exceeded: $fields[6]\n";
	       return 1
       }
   }'

Note: in nrpe.cfg this will all have to be put on one line.  It will be more
readable if you put the parser code in a separate file and use -E.


=cut

# Load modules
require 5.004;
use strict;
use lib "/usr/lib/nagios/plugins";    # Debian
use lib "/usr/lib64/nagios/plugins";  # 64 bit
use lib "/usr/local/libexec/nagios";  # (Free)BSD
use lib "/usr/local/nagios/libexec";  # Other
use utils qw($TIMEOUT %ERRORS &print_revision &support);
use Getopt::Long qw(:config no_ignore_case);
use File::Spec;
use File::Glob ':glob';

# These are here so PAR-Packer's pp will compile them into the standalone Win32 EXE
# (CJK modules not included for size reasons)
use Encode qw(:all);
use Encode::Byte;
use Encode::Unicode;

# Plugin version
my $plugin_revision = '3.11d';

# Predeclare subroutines
sub print_usage ();
sub print_version ();
sub print_help ();
sub print_encodings ();
sub ioerror;
sub add_to_buffer;
sub read_next;

# Initialise variables and defaults
my $tmpdir = File::Spec->tmpdir();
my $devnull = File::Spec->devnull();
my $log_file = '';
my $log_pattern;
my $timestamp = time;
my $size;
my $log_select = 'last_match';
my @logfiles;
my $seek_file = '';
my $warning = '1';
my $critical = '0';
my $diff_warn = '';
my $diff_crit = '';
my @patterns;
my @negpatterns;
my $re_pattern = '';
my $pattern_file = '';
my $negpatternfile = '';
my $case_insensitive = '';
my $pattern_count = 0;
my $pattern_line = '';
my $parse_pattern = '';
my $parse_file = '';
my $parse_line = '';
my $parse_count = 0;
my $parse_out = '';
my $output_all = 0;
my $total = 0;
my $stop_first_match;
my $report_first_only;
my $always_ok;
my $missing;
my $missing_ok;
my $missing_msg = "No log file found";
my @line_buffer;
my $read_ahead = 0;
my $read_back = 0;
my $no_timeout;
my $timeout;
my $output;
my $context;
my $negate;
my $perfdata;
my $quiet;
my $noheader;
my $noperfdata;
my $version;
my $help;
my $debug;
my $and;
my $mode;
my $enc_in;
my $enc_out;
my $list_enc;
my $crlf;

# If invoked with a path, strip the path from our name
my ($prog_vol, $prog_dir, $prog_name) = File::Spec->splitpath($0);

# Grab options from command line
GetOptions (
	"l|logfile=s"		=> \$log_file,
	"m|log-pattern=s"	=> \$log_pattern,
	"t|log-select=s"	=> \$log_select,
	"s|seekfile=s"		=> \$seek_file,
	"p|pattern=s"		=> \@patterns,
	"P|patternfile=s"       => \$pattern_file,
	"n|negpattern=s"	=> \@negpatterns,
	"f|negpatternfile=s"	=> \$negpatternfile,
	"w|warning=s"		=> \$warning,
	"c|critical=s"		=> \$critical,
	"i|case-insensitive"	=> \$case_insensitive,
	"d|nodiff-warn"		=> \$diff_warn,
	"D|nodiff-crit"		=> \$diff_crit,
	"e|parse=s"		=> \$parse_pattern,
	"E|parsefile=s"		=> \$parse_file,
	"a|output-all"		=> \$output_all,
	"C|context=s"		=> \$context,
	"1|stop-first-match"	=> \$stop_first_match,
	"report-first-only"	=> \$report_first_only,
	"negate"		=> \$negate,
	"ok"			=> \$always_ok,
	"missing=s"		=> \$missing,
	"missing-ok"		=> \$missing_ok,
	"missing-msg=s"		=> \$missing_msg,
	"timeout=i"		=> \$timeout,
	"no-timeout"		=> \$no_timeout,
	"timestamp=s"		=> \$timestamp,
	"q|quiet"		=> \$quiet,
	"Q|no-header"		=> \$noheader,
	"no-perfdata"		=> \$noperfdata,
	"A|and"			=> \$and,
	"input-enc|encoding=s"	=> \$enc_in,
	"output-enc=s"		=> \$enc_out,
	"list-encodings"	=> \$list_enc,
	"crlf"			=> \$crlf,
	"v|V|version"		=> \$version,
	"h|help"		=> \$help,
	"debug"			=> \$debug,
);

# Set output encoding before we output anything
if ($enc_out) {
	binmode STDOUT, ":encoding($enc_out)" if $enc_out;
	print "debug: using $enc_out output encoding\n" if $debug;
} else {
	# Safe default
	binmode STDOUT, ":encoding(UTF-8)";
}

print "debug: check_log3.pl version $plugin_revision starting\n" if $debug;
print "debug: warning=$warning, critical=$critical\n" if $debug;

#
# Parse input
#

($version) && print_version ();
($help) && print_help ();
($list_enc) && print_encodings ();

# These options are mandatory
($log_file) || usage("Log file not specified.\n");
(@patterns) || usage("Regular expression not specified.\n") unless ($pattern_file || $diff_warn || $diff_crit);

# Validate --missing option if present (otherwise $missing remains false)
usage("Invalid state: $missing\n") if ($missing && uc($missing) !~ /OK|WARNING|CRITICAL|UNKNOWN/);
$missing = 'OK' if $missing_ok;

# Just in case of problems, let's not hang Nagios
$timeout = $TIMEOUT if not defined $timeout;
$timeout = 0 if $no_timeout;
unless ($timeout) {
	$SIG{'ALRM'} = sub {
		print "Plug-in error: time out after $timeout seconds\n";
		exit $ERRORS{'UNKNOWN'};
	};
	alarm($timeout);
}
print "debug: plugin timeout set to $timeout seconds\n" if $debug;

# Determine line buffer characteristics
if ($context && $context =~ /\+(\d+)/) {
	$read_ahead = $1;
} elsif ($context && $context =~ /\-(\d+)/) {
	$read_back = $1 + 1;
} elsif ($context && $context =~ /(\d+)/) {
	$read_ahead = $1;
	$read_back = $1 + 1;
}
print "debug: using line buffer: $read_back back, $read_ahead ahead\n" if $debug;

# PerlIO encoding layer to use when reading input files - logs and pattern files
# Not applied to seek files or Perl scripts (custom eval code)
if ($enc_in) {
	print "debug: using $enc_in input encoding\n" if $debug;
	$mode = "<:encoding($enc_in)";
} else {
	# Use system default
	$mode = "<";
}

# Translate CR/LF (MS-DOS line endings) to Unix newlines
# Not the default for performance reasons
if ($crlf) {
	print "debug: translating CRLF line endings\n" if $debug;
	$mode .= ":crlf" 
}

# If we have a pattern file, read it and construct a pattern of the form 'line1|line2|line3|...'
if ($pattern_file) {
	print "debug: using pattern file '$pattern_file'\n" if $debug;
	open (PATFILE, $mode, "$pattern_file") || ioerror("Unable to open '$pattern_file': $!");
	chomp(@patterns = <PATFILE>);
	close(PATFILE);
}

# Combine multiple patterns (from a file or the command line) into one expression
if ($and) {
	$re_pattern = '(?=.*' . join(')(?=.*', @patterns) . ')';
} else {
	$re_pattern = join('|', @patterns);
}
($re_pattern) || usage("Regular expression not specified.\n") unless ($diff_warn || $diff_crit);
print "debug: looking for '$re_pattern'\n" if $debug;

# If we have an ignore/whitelist file, read it
if ($negpatternfile) {
	print "debug: using negpattern file '$negpatternfile'\n" if $debug;
	open (PATFILE, $mode, "$negpatternfile") || ioerror("Unable to open '$negpatternfile': $!");
	chomp(@negpatterns = <PATFILE>);
	close(PATFILE);
}

# If we have a custom code file, read it
# Note that since this is Perl code we don't force an encoding on it
if ($parse_file) {
	print "debug: using parse file '$parse_file'\n" if $debug;
	open (EVALFILE, "$parse_file") || ioerror("Unable to open '$parse_file': $!");
	while (<EVALFILE>) {
		$parse_pattern .= $_;
	}
	close(EVALFILE);
}

# If -s points to a directory we take that as the new $tmpdir and auto-generate the seek filename
if (-d "$seek_file") {
	$tmpdir = $seek_file;
	print "debug: using seek dir '$tmpdir'\n" if $debug;
	# We'll auto-generate this later
	undef $seek_file;
}

# This is not fatal but we should warn the user about it
print "Warning: '$tmpdir' not writable, seek position will not be saved\n" if not -w "$tmpdir";

# Seek files are always auto-generated for dynamic log files
if ($log_pattern) {
	print "debug: overriding seek file for dynamic filenames\n" if $debug;
	undef $seek_file unless $seek_file eq $devnull;
}

#
# Find and open the files
#

# Match log filenames against glob patterns (rotated, time stamped, etc)
# Note that if nothing matches $log_pattern this will select just $log_file
if ($log_pattern) {
	# Timestamped filenames support
	if ($log_pattern =~ /%/) {
		print "debug: enabling timestamp substitutions\n" if $debug;

		# Timestamp can be expressed as 'X months|weeks|days|hours|minutes|seconds ... [ago]'
		# or as seconds after the epoch (note, this is not validated for correctness)
		if ($timestamp =~ /\D/) {
			# Safe fall-back
			if ($timestamp !~ /(sec|min|hour|day|week|mon|now|yesterday)/i) {
				print "debug: timestamp '$timestamp' not valid, using 'now'\n" if $debug;
				$timestamp = time;
			} else {
				my $newtimestamp;
				if ($timestamp =~ /now/i) { $newtimestamp = time; }
				if ($timestamp =~ /yesterday/i) { $newtimestamp = time - 86400; }
				if (my ($t) = ($timestamp =~ /(\d+) mon/i)) { $newtimestamp = time - ($t * 2592000); }
				if (my ($t) = ($timestamp =~ /(\d+) week/i)) { $newtimestamp = time - ($t * 604800); }
				if (my ($t) = ($timestamp =~ /(\d+) day/i)) { $newtimestamp = time - ($t * 86400); }
				if (my ($t) = ($timestamp =~ /(\d+) hour/i)) { $newtimestamp = time - ($t * 3600); }
				if (my ($t) = ($timestamp =~ /(\d+) min/i)) { $newtimestamp = time - ($t * 60); }
				if (my ($t) = ($timestamp =~ /(\d+) sec/i)) { $newtimestamp = time - $t; }
				print "debug: new reference timestamp: " . localtime($newtimestamp) . "\n" if $debug;
				$timestamp = $newtimestamp;
			}
		}

		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($timestamp);
		# Adjust some values for user-friendliness
		$year += 1900;
		$mon += 1;
		my $yr = sprintf("%02d", $year % 100);
		# Add padding zeros
		$yday = sprintf("%03d", $yday);
		foreach my $t (($sec, $min, $hour, $mday, $mon)) {
			$t = sprintf("%02d", $t);
		}

		# Emulate some common date(1) format options
		$log_pattern =~ s/%Y/$year/g;
		$log_pattern =~ s/%y/$yr/g;
		$log_pattern =~ s/%m/$mon/g;
		$log_pattern =~ s/%d/$mday/g;
		$log_pattern =~ s/%H/$hour/g;
		$log_pattern =~ s/%M/$min/g;
		# Less common
		$log_pattern =~ s/%S/$sec/g;
		$log_pattern =~ s/%w/$wday/g;
		$log_pattern =~ s/%j/$yday/g;
	}

	# Normalise path
	my ($vol, $dir, $file) = File::Spec->splitpath($log_file);
	my $logprefix = File::Spec->catpath($vol, $dir, $file);
	print "debug: looking for files matching '$log_file$log_pattern'\n" if $debug;
	@logfiles = bsd_glob("$log_file$log_pattern");

# Only if not using -m
} elsif (-d "$log_file") {
	# Normalise path
	my ($vol, $dir, $file) = File::Spec->splitpath($log_file, 1);
	my $tmplogpath = File::Spec->catpath($vol, $dir, '*');
	print "debug: log_file is a directory, assuming '$tmplogpath'\n" if $debug;
	@logfiles = bsd_glob("$tmplogpath");
}

# If selecting multiple files
if (@logfiles) {
	# Filter out anything that is not a file
	foreach my $f (@logfiles) {
		shift @logfiles unless -f "$f";
	}

	# Refine further with -t if there is more than one match
	if (scalar(@logfiles) gt 1) {
		if ($debug) {
			print "debug: found " . scalar(@logfiles) . " files matching selection:\n";
			foreach (@logfiles) {
				print "debug:     $_\n";
			}
		}

		# Trivial cases: first and last match (the default)
		my @sorted = sort(@logfiles);
		$log_select = "last_match" if not $log_select;
		if ($log_select =~ /last_match/i) {
			print "debug: picking last match\n" if $debug;
			$log_file = pop(@sorted);
		} elsif ($log_select =~ /first_match/i) {
			print "debug: picking first match\n" if $debug;
			$log_file = $sorted[0];
		# By mtime: stat each file and keep the most recent one
		} elsif ($log_select =~ /most_recent/i) {
			print "debug: picking most recent match\n" if $debug;
			my $latest_mtime = 0;
			foreach my $f (@sorted) {
				my $timestamp = (stat("$f"))[9];
				print "debug: considering '$f' ($timestamp)\n" if $debug;
				if ($timestamp >= $latest_mtime) {
					$latest_mtime = $timestamp;
					$log_file = $f;
				}
			}
			print "debug: '$log_file' is most recent\n" if $debug;
		# Safe fall-back
		} else {
			print "debug: '$log_select' not supported, using default\n" if $debug;
			$log_file = pop(@sorted);
		}

	} elsif (scalar(@logfiles) == 1) {
		# Exact match
		print "debug: only one matching file\n" if $debug;
		$log_file = $logfiles[0];
	} else {
		# Set contained objects, but none of them are files
		print "debug: no matching files found, trying just '$log_file'\n" if $debug;
	}

} else {
	# Glob returned nothing
	print "debug: no multiple match or set is empty, trying just '$log_file'\n" if $debug;
}

# Open the log file - only here can errors be fatal
print "debug: using log file '$log_file'\n" if $debug;
if (! -f "$log_file") {
	if ($missing) {
		# Custom error message & state
		print "$missing_msg\n";
		exit $ERRORS{uc($missing)};
	} else {
		# Standard error message
		my $errstr = "Cannot read '$log_file'";
		$errstr = "Cannot read '$log_file$log_pattern' or '$log_file'" if $log_pattern;
		ioerror($errstr);
	}
}
open (LOG_FILE, $mode, "$log_file") || ioerror("Unable to open '$log_file': $!");

# Auto-generate seek file name if necessary
if (not $seek_file) {
	my ($log_vol, $log_dir, $basename) = File::Spec->splitpath($log_file);
	$seek_file = File::Spec->catfile($tmpdir, $basename . '.seek');
}
print "debug: using seek file '$seek_file'\n" if $debug;

# Get size of log file
my @stat = stat(LOG_FILE);
$size = $stat[7];

# Try to open seek file.  If open fails, we seek from beginning of file by default.
if (open(SEEK_FILE, "$seek_file")) {
	chomp(my @seek_pos = <SEEK_FILE>);
	close(SEEK_FILE);

	# If file is empty, no need to seek
	if ($seek_pos[0] && $seek_pos[0] != 0) {
		# Compare seek position to actual file size.  If file size is smaller,
		# then we just start from beginning i.e. the log was rotated.
		print "debug: seek from $seek_pos[0] (eof = $size)\n" if $debug;

		# If the file hasn't grown since last time and a nodiff option was specified, stop here.
		$diff_crit = 1 if ($diff_warn && $critical);
		if ($seek_pos[0] == $size && $diff_crit) {
			print "CRITICAL: Log file not written to since last check\n";
			exit $ERRORS{'CRITICAL'};
		} elsif ($seek_pos[0] == $size && $diff_warn) {
			print "WARNING: Log file not written to since last check\n";
			exit $ERRORS{'WARNING'};
		}

		# Seek to where we stopped reading before
		if ($seek_pos[0] <= $size) {
			seek(LOG_FILE, $seek_pos[0], 0);
		}
	}
} else {
	print "debug: cannot open seek file, first time reading this file\n" if $debug;
}

#
# Process the log file
#

# Loop through every line of log file and check for pattern matches.
# Count the number of pattern matches and save the output.
print "debug: reading file...\n" if $debug;
while (<LOG_FILE>) {
	my $line = $_;
	my $negmatch = 0;

	# Count total number of lines
	$total++;

	# Add current line to buffer, if required
	add_to_buffer($line, $read_back) if $read_back;

	# Try if the line matches the pattern
	if (/$re_pattern/i) {
		# If not case insensitive, skip if not an exact match
		unless ($case_insensitive) {
			next unless /$re_pattern/;
		}

		# And if it also matches the ignore list
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

		# OK, line matched!
		if ($negmatch == 0) {
			# Increment final count
			$pattern_count += 1;

			# Save the line matched and optionally some lines of context before and/or after
			if ($output_all) {
				$pattern_line .= join('', @line_buffer) if $read_back;
				$pattern_line .= "($pattern_count) $line" if not $read_back;
				$pattern_line .= read_next(*LOG_FILE, $read_ahead) if $read_ahead;
				$pattern_line .= "---\n" if $context;
			} else {
				$pattern_line = join('', @line_buffer) if $read_back;
				$pattern_line = $line if not $read_back;
				$pattern_line .= read_next(*LOG_FILE, $read_ahead) if $read_ahead;
			}

			# Optionally execute custom code
			if ($parse_pattern) {
				my $res = eval $parse_pattern;
				warn $@ if $@;
				# Save the result if non-zero
				if ($res > 0) {
					$parse_count += 1;
					# If the eval block set $parse_out, save that instead
					# Note: in this case we don't save any context
					if ($parse_out) {
						if ($output_all) {
							$parse_line .= "($parse_count) $parse_out";
						} else {
							$parse_line = $parse_out;
						}
					# Otherwise save the current line as before
					} else {
						if ($output_all) {
							$parse_line .= join('', @line_buffer) if $read_back;
							$parse_line .= "($parse_count) $line" if not $read_back;
							$parse_line .= read_next(*LOG_FILE, $read_ahead) if $read_ahead;
							$parse_line .= "---\n" if $context;
						} else {
							$parse_line = join('', @line_buffer) if $read_back;
							$parse_line = $line if not $read_back;
							$parse_line .= read_next(*LOG_FILE, $read_ahead) if $read_ahead;
						}
					}
				}
			}
		}
		# Stop here?
		last if $stop_first_match or $report_first_only;
	}
}

# Overwrite log seek file and print the byte position we have seeked to.
open(SEEK_FILE, ">$seek_file") || ioerror("Unable to open '$seek_file' for writing: $!");
if ($report_first_only) {
	# Ignore rest of file up to EOF
	print SEEK_FILE $size;
} else {
	print SEEK_FILE tell(LOG_FILE);
}

# Close files
close(SEEK_FILE);
close(LOG_FILE);

print "debug: found $pattern_count maches, total lines $total, parse count $parse_count, limits: warn $warning crit $critical\n" if $debug;

#
# Compute exit code, terminate if no thresholds were exceeded
# Count parse matches if applicable, or else just count the matches.
#

# If this was a nodiff check we just count the lines and stop
if (!$re_pattern) {
	if ($diff_crit && $total lt $critical) {
		print "CRITICAL: Only $total lines written since last check (expected at least $critical)\n";
		exit $ERRORS{'CRITICAL'};
	} elsif ($diff_warn && $total lt $warning) {
		print "WARNING: Only $total lines written since last check (expected at least $warning)\n";
		exit $ERRORS{'WARNING'};
	} elsif ($diff_warn or $diff_crit) {
		print "OK: $total lines written since last check\n";
		exit $ERRORS{'OK'};
	}
}

# Pattern matching requires a little more work
my $state = "UNKNOWN";
my $endresult = $ERRORS{'UNKNOWN'};

# Thresholds may be expressed as percentages
my ($warnpct, $critpct);
if ($warning =~ /%/) {
	if ($parse_pattern) {
		# Ratio of parsed lines to matched lines
		$warnpct = ($parse_count / $pattern_count) * 100 if $pattern_count;
	} else {
		# Ratio of matched lines to total lines
		$warnpct = ($pattern_count / $total) * 100 if $total;
	}
	# Normalise threshold value so we can compare
	$warning =~ s/%//g;
}

# We do this twice because one threshold may be a percentage but not the other
if ($critical =~ /%/) {
	if ($parse_pattern) {
		# Ratio of parsed lines to matched lines
		$critpct = ($parse_count / $pattern_count) * 100 if $pattern_count;
	} else {
		# Ratio of matched lines to total lines
		$critpct = ($pattern_count / $total) * 100 if $total;
	}
	# Normalise threshold value so we can compare
	$critical =~ s/%//g;
}

print "debug: ", $warnpct ? "warnpct = $warnpct " : " ", $critpct ? "critpct = $critpct\n" : "\n" if ($debug && ($warnpct || $critpct));

# Inverting the thresolds implies --negate
print "debug: thresholds inverted, assuming --negate\n" if ($debug && (($warning && $critical) && $warning > $critical));
$negate = 1 if ($warning && $critical) && $warning > $critical;

# --negate inverts the compare op
my $cmp = '>=';
$cmp = '<' if $negate;
print "debug: inverting result due to --negate\n" if ($debug && $negate);

# Warning?
if ($warning > 0) {
	# By percentage (either matched or parsed)
	if ($warnpct) {
		if (eval "$warnpct $cmp $warning") {
			$endresult = $ERRORS{'WARNING'};
			print "debug: warnpct $cmp warning\n" if $debug;
		} else {
			$endresult = $ERRORS{'OK'};
		}
	# Absolute count after custom parsing
	} elsif ($parse_pattern) {
		if (eval "$parse_count $cmp $warning") {
			$endresult = $ERRORS{'WARNING'};
			print "debug: parse_count $cmp warning\n" if $debug;
		} else {
			$endresult = $ERRORS{'OK'};
		}
	# Plain pattern matching
	} elsif (eval "$pattern_count $cmp $warning") {
			$endresult = $ERRORS{'WARNING'};
			print "debug: pattern_count $cmp warning\n" if $debug;
	# No thresholds reached = OK
	} else {
		$endresult = $ERRORS{'OK'};
	}
}

# Critical?
if ($critical > 0) {
	# By percentage (either matched or parsed)
	if ($critpct) {
		if (eval "$critpct $cmp $critical") {
			$endresult = $ERRORS{'CRITICAL'};
			print "debug: critpct $cmp critical\n" if $debug;
		} else {
			$endresult = $ERRORS{'OK'} unless $endresult == $ERRORS{'WARNING'};
		}
	# Absolute count after custom parsing
	} elsif ($parse_pattern) {
		if (eval "$parse_count $cmp $critical") {
			$endresult = $ERRORS{'CRITICAL'};
			print "debug: parse_count $cmp critical\n" if $debug;
		} else {
			$endresult = $ERRORS{'OK'} unless $endresult == $ERRORS{'WARNING'};
		}
	# Plain pattern matching
	} elsif (eval "$pattern_count $cmp $critical") {
			$endresult = $ERRORS{'CRITICAL'};
			print "debug: pattern_count $cmp critical\n" if $debug;
	# No thresholds reached = OK (but don't downgrade Warnings)
	} else {
		$endresult = $ERRORS{'OK'} unless $endresult == $ERRORS{'WARNING'};
	}
}

# Another way of saying --ok
$endresult = $ERRORS{'OK'} if ($warning == 0 && $critical == 0);
$endresult = $ERRORS{'OK'} if $always_ok;

print "debug: end result: $endresult\n"  if $debug;

#
# Generate output
#

# If matches were found, print the last line matched, or all lines if -a was specified.
# Note that there is a limit to how much data can be returned to Nagios: 4 KB if run locally, 1 KB if run via NRPE.
# If -e was used, print the last line parsed with a non-zero result, if any (possibly something else if the code modified $parse_out).
# Output total line and match counts as performance data (unless custom code modified $perfdata).
$parse_line = "No matches found." if not $parse_line;
if ($parse_pattern) {
	$output = "Parsed output ($parse_count matched): " unless $noheader;
	$output .= $parse_line;
	$perfdata = "lines=$pattern_count parsed=$parse_count" unless $perfdata;
} else {
	$output = $pattern_line;
	$perfdata = "lines=$pattern_count" unless $noperfdata;
}

# Prepare output, or terminate if nothing to do
if ($endresult == $ERRORS{'CRITICAL'}) {
	$state = "CRITICAL";
} elsif ($endresult == $ERRORS{'WARNING'}) {
	$state = "WARNING";
} elsif ($endresult == $ERRORS{'OK'}) {
	$state = "OK";
	# We still output if there are any matches but the thresholds were not reached
	$output = "No matches found." if not $output;
	# Suppress all output (default pre-3.9 behaviour)
	$output = "No matches found." if $quiet;
}

#
# Print output and exit
#

# Reinstate percentage suffix if appropriate
$warning .= '%' if $warnpct;
$critical .= '%' if $critpct;

# Filter any pipes from the output, as that is the Nagios output/perfdata separator
$output =~ s/\|/\!/g;
chomp($output);
print "$state: " unless $noheader;
print "Found $pattern_count lines (limit=$warning/$critical): " unless $noheader;
# Context is not saved if $parse_out was set (or nothing was found, obviously)
print "\n" if ($context and not ($parse_out || $endresult == $ERRORS{'OK'}));
print "$output";
print "|$perfdata" if $perfdata;
print "\n";

exit $ERRORS{'OK'} if $always_ok;
exit $endresult;


#
# Main programme ends
#
###

#
# Subroutines
#

# Print all supported charset encodings
sub print_encodings () {
	use Encode;
	print "$prog_name version $plugin_revision\n\n";
	print "This plugin supports the following encodings:\n\n";
	print join(", ", Encode->encodings(":all"));
	print "\n\n";
	print qq|See "man Encode::Supported" for more details.\n\n|;
	exit $ERRORS{'OK'};

}

# Die with error message and Nagios error code, for system errors
sub ioerror() {
	print @_;
	print "\n";
	exit $ERRORS{'CRITICAL'};
}

# Die with usage info, for improper invocation
sub usage {
	my $format=shift;
	printf($format,@_);
	print "\n";
	print_usage();
	exit $ERRORS{'UNKNOWN'};
}

# Print version number
sub print_version () {
	print "$prog_name version $plugin_revision\n";
	exit $ERRORS{'OK'};
}

# Add a line to the read-back buffer, a FIFO queue with max length $c
sub add_to_buffer {
	my ($l, $c) = @_;
	push(@line_buffer, $l);
	shift(@line_buffer) if @line_buffer > $c;
}

# Get next $n lines from current file position of file $fh
# The current seek position is preserved
sub read_next {
	my ($fh, $n) = @_;
	my $lines;
	my $i = 1;

	# Save current position
	my $oldpos = tell($fh);

	# Read next $i lines (if possible)
	while (<$fh>) {
		last if not $_;
		last if $i > $n;
		$lines .= $_;
		$i++;
	}

	# Restore seek position and return
	seek ($fh, $oldpos, 0);
	return $lines;
}

# Short usage info
sub print_usage () {
	print "This is $prog_name version $plugin_revision\n\n";
	print "Usage: $prog_name [ -h | --help ]\n";
	print "Usage: $prog_name [ -v | --version ]\n";
	print "Usage: $prog_name [ -v | --list-encodings ]\n";
	print "Usage: $prog_name -l log_file|log_directory (-p pattern [-p pattern ...])|-P patternfile)
	[-i] [-n negpattern|-f negpatternfile ] [-s seek_file|seek_base_dir]
	([-m glob-pattern] [-t most_recent|first_match|last_match] [--timestamp=time-spec])
	[-d] [-D] [-1] [-a] [-C {-|+}n] [-q] [-Q] [-e '{ eval block }'|-E script_file]
	[--ok]|([-w warn_count] [-c crit_count] [--negate])
	[--input-enc=encoding] [--output-enc=encoding] [--crlf]
	[--missing=STATE [--missing-msg=message]]
	
Full manual: perldoc check_log3.pl

\n";
}

# Long usage info
sub print_help () {
################################################################################
	print_usage();
	print "
This plugin scans arbitrary text files for regular expression matches.

Log file control:

-l, --logfile=<logfile|dir>
    The log file to be scanned, or the fixed path component if -m is in use.
    If this is a directory, -t and -m '*' is assumed.
-s, --seekfile=<seekfile|base_dir>
    The temporary file to store the seek position of the last scan.  If not
    specified, it will be automatically generated in $tmpdir, based on the
    log file's base name.  If this is a directory, the seek file will be auto-
    generated there instead of in $tmpdir.
    If you specify the system's null device ($devnull), the entire log file
    will be read every time.
-m, --logfile-pattern=<expression>
    A glob(7) expression, used together with the -l option for selecting log
    files whose name is variable, such as time stamped or rotated logs.
    If you use this option, the -s option will be ignored unless it points to
    either a directory or to the null device ($devnull).
    For selecting time stamped logs, you can use the following date(1)-like
    expressions, which by default refer to the current date and time:
	\%Y = year
	\%y = last 2 digits of year
	\%m = month (01-12)
	\%d = day of month (01-31)
    	\%H = hour (00-23)
	\%M = minute (00-59)
	\%S = second (00-60)
	\%w = week day (0-6), 0 is Sunday
	\%j = day of year (000-365)
    Use the --timestamp option to refer to timestamps in the past.
-t, --logfile-select=most_recent|first_match|last_match
    How to further select amongst multiple files when using -m:
     - most_recent: select the most recently modified file
     - first_match: select the first match (sorting alphabetically)
     - last_match: select the last match (this is the default)
--timestamp='(X months|weeks|days|hours|minutes|seconds)... [ago]'
    Use this option to make the time stamp macro's in the -m expression refer
    to a time in the past, e.g. '1 day, 6 hours ago'.  The shortcuts 'now' and
    'yesterday' are also recognised.  The default is 'now'.
    If this expression is purely numerical it will be interpreted as seconds
    since 1970-01-01 00:00:00 UTC.

Search pattern control:

-p, --pattern=<pattern>
    The regular expression to scan for in the log file.  If specified more
    than once, the patterns will be combined into an expression of the form
    'pattern1|pattern2|pattern3|...' (but also see the -A option).
-P, --patternfile=<filename>
    File containing regular expressions, one per line, which will be combined
    into an expression of the form 'line1|line2|line3|...' (but also see -A).
-A, --and
    Use AND instead of OR to combine multiple patterns specified via the -p or
    -P options.  A line must match all patterns to be counted as a match.
    This is equivalent to '(?=.*pattern1)(?=.*pattern2)(?=.*pattern3)...'.
-n, --negpattern=<negpattern>
    The regular expression to skip in the log file.  Can be specified multiple
    times, in which case they will be combined as 'pat1|pat2|pat3|...'.
-f, --negpatternfile=<negpatternfile>
    Specifies a file with regular expressions which will all be skipped.
-i, --case-insensitive
    Do a case insensitive scan.

Character set control:

--encoding=<encoding>, --input-enc=<encoding>
    Force a particular encoding on the log file and pattern files (but not
    custom eval scripts), such as utf-16, iso-8859-15, cp1252, koi8-r, etc.
    For example, to read Windows Unicode files you probably need \"utf16le\".
    Run the script with --list-encodings to see which encodings are supported.
    Warning: if you use this option and the patterns specified on the command
    line (with -p and -n) are not themselves in this encoding, you *must* use
    pattern files!  Also note that using this option is bad for performance.
--output-enc=<encoding>
    Force a particular character encoding of the plugin output, as above.
    The plugin's default output encoding is UTF-8.
--list-encodings
    Show which character set encodings this plugin supports, and exits.
--crlf
    Translate CRLF line endings to Unix newlines; use this if you are reading
    logs generate on DOS/Windows PCs on a Unix machine and are getting '^M'
    characters in the output.  This option is also bad for performance.

Alerting control:

-w, --warning=<number>
    Return WARNING if at least this many matches found.  The default is 1.
-c, --critical=<number>
    Return CRITICAL if at least this many matches found.  The default is 0,
    i.e. don't return critical alerts unless specified explicitly.
-d, --nodiff, --nodiff-warn
    Return an alert if the log file was not written to since the last scan.
    By default this will result in a WARNING if not at least one line was
    written.  If no search pattern was specified, the -w and -c options can
    be used to control the number of expected lines.
-D, --nodiff-crit
    Return CRITICAL if the log was not written to since the last scan.  If no
    search pattern was specified this is equivalent to '-d -c 1'.
--missing=STATE [ --missing-msg=\"message\" ]
    Return STATE instead of CRITICAL when no log file could be found, and
    optionally output a custom message (by default \"$missing_msg\").
    STATE must be one of OK, WARNING, CRITICAL or UNKNOWN.
    Note, if --missing is not specified, --missing-msg is ignored, and a
    standard error message is returned.
--missing-ok
    Equivalent to --missing=OK (for backwards compatibility).
--ok
    Always return an OK status to Nagios.
--negate
    Inverts the meaning of the -w and -c options, i.e. returns an alert if not
    at least this many matches are found.  (Note: this option is not useful in
    combination with --ok.)

Output control:

-1, --stop-first-match
    Stop at the first line matched, instead of the last one.  It will make the
    plugin report every single match (and implies an alerting threshold of 1).
--report-first-only
    Stop at the first line matched, but also skip the remainder of the file
    (by moving the seek pointer to the end of the log file, as determined at
    the moment it was opened for reading).  Use this option only when you are
    expecting many identical (or very similar) matches but only want to see
    the first one, and to ignore all subsequent matches until the next service
    check.  (Note, this option takes precedence over --stop-first-match.)
-a, --output-all
    Output all matching lines instead of just the last one.  Note that the
    plugin output may be truncated if it exceeds 4KB (1KB when using NRPE).
-C, --context=[-|+]<number>
    Output <number> lines of context before or after matched line; use -N for
    N lines before the match, +N for N lines after the match (if possible) or
    an unqualified number to get N lines before and after the match.
-e, --parse=<code>
-E, --parse-file=<filename>
    Custom Perl code block to parse each matched line with, or an external
    script.  If specified directly with -e the code should probably be in
    curly brackets and quoted.  It will be executed as a Perl 'eval' block.
    If the return code of the custom code is non-zero the line is counted
    against the threshold, otherwise it isn't and it will be as if the line
    did not match the pattern after all (though it is counted as perfdata).
    The current matching line will be passed to the eval code in \$_.
    Set \$parse_out to generate custom output instead of the matching line.
    Set \$perfdata to generate custom performance data instead of the number of
    matching lines.  Note: if you set \$parse_out, no context will be output,
    but you can parse it, and indeed you must use -C if you want to parse a
    line other than the current matching one.  In that case you should parse
    \@line_buffer instead of \$_.
-q, --quiet
    Suppress output of matched line(s) if state is OK.
-Q, --no-header
    Suppress leading state and statistics info from output.
--no-perfdata
    Suppress the standard performance data output from the plugin.  Use this
    if your are using custom parsing code and generate your own perfdata.
--timeout=<seconds>
    Override the plugin time-out timer (by default $TIMEOUT seconds).  The plugin
    will return UNKNOWN if the plugin runs for more than this many seconds.
--no-timeout
    Equivalent to --timeout=0.

Support information:

Send email to pmcaulay\@evilgeek.net if you have questions regarding use of this
software, or to submit patches or suggest improvements.  Please include version
information with all correspondence (the output of the --version option).

This Nagios plugin comes with ABSOLUTELY NO WARRANTY. You may redistribute
copies of the plugins under the terms of the GNU General Public License.
For more information about these matters, see the file named COPYING.

";
	exit $ERRORS{'OK'};
}

