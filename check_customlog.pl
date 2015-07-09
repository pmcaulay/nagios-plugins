#!/usr/bin/perl -w
#
# Wrapper script for custom log file checks which allows the thresholds to be
# set from an external parameter file.
#
# Usage: check_customlog -f conffile -l log -p parameter
# Where:
# - conffile is the path to a configuration file,
# - log is a keyword reference to a file or path, defined in conffile
# - parameter is a parameter block defined in conffile
#
# Patterns, thresholds, custom code are all taken from conffile.
#
# Last updated 2013-03-28 by Peter Mc Aulay
#
use strict;
use utils qw($TIMEOUT %ERRORS &print_revision);
use Getopt::Long;

my $plugin_revision = "1.01";

# Path to Nagios log check plugin
my $check_log = '/usr/lib/nagios/plugins/check_log3.pl';

# Some variables
my ($help, $debug, $version, $conffile, %config, $log, $param, $logfile, $seekfile, $cmdexec, $args, $err);

# Grab options from command line
GetOptions (
	"f|file=s"	=> \$conffile,
	"l|log=s"	=> \$log,
	"p|param=s"	=> \$param,
	"h|help"	=> \$help,
	"d|debug"	=> \$debug,
	"v|version"	=> \$version,
);

# Input validation
($help) && print_help();
($version) && print_version();

($conffile) || print_error("Configuration file missing");
-f "$conffile" || print_error("Configuration file not found");
($log) || print_error("Log file reference missing");
($param) || print_error("Parameter to check missing");

# Read configuration file, build parameter hash
%config = readconfig($conffile);

# Check for mandatory parameters
($config{'configuration'}{$log}) || print_error("Log identifier \'$log\' not found in $conffile");
print_error("$param not defined") if not defined $config{$param};

# Only one threshold is actually mandatory
$config{$param}{'warn'} = $config{$param}{'crit'} if not $config{$param}{'warn'};
$config{$param}{'crit'} = $config{$param}{'warn'} if not $config{$param}{'crit'};

# If custom is defined, it is assumed it will replace the built-in threshold
# check, and the only options passed to check_log3.pl will be pattern, warn,
# crit and custom (warn and crit are optional).
#
# Otherwise, col, threshold and at least one of warn and crit are mandatory.
unless (defined $config{$param}{'custom'}) {
	if (defined $config{$param}{'col'}) {
		($config{$param}{'threshold'}) || print_error("Threshold missing for \'$param\'");
		print_error("Column number not a number for \'$param\'") unless $config{$param}{'col'} =~ /^(\d+\.?\d*|\.\d+)$/;
		print_error("Threshold for \'$param\' not a number") unless $config{$param}{'threshold'} =~ /^(\d+\.?\d*|\.\d+)$/;
		# In the conffile, column numbers are 1-based for user-friendliness
		--$config{$param}{'col'};
	} else {
		# If no column number is defined, warn and crit apply to the total number of
		# lines that match the pattern, and the threshold value is ignored.  In this
		# case the pattern is not optional.
		($config{$param}{'pattern'}) || print_error("Pattern is mandatory if no column defined for \'$param\'");
	}
	# At least one of warn or crit must be defined
	print_error("At least one of warn or crit must be defined") unless defined $config{$param}{'crit'};
}

# Defaults
$config{$param}{'pattern'} = ';' if not defined $config{$param}{'pattern'};
$config{$param}{'desc'} = $param unless $config{$param}{'desc'};

# Find log file and generate seek file filename
$logfile = $config{'configuration'}{$log};
$seekfile = "/tmp/log-$log-$param.seek";

# If the log is rotated and timestamped we need to do some globbing
if ($config{'configuration'}{'timestamp'}) {
	$logfile .= '`date +' . $config{'configuration'}{'timestamp'} . '`*' if $config{'configuration'}{'timestamp'};
	my @files = `ls -1 $logfile`;
	(@files) || print_ok("No log file found for $log today");
	chomp @files;
	# Use the last match found
	$logfile = $files[$#files];
}

# Uncomment for debugging the hashes
#use Data::Dumper;
#print Data::Dumper->Dump([\%config]);

#
# Generate command line options
#

$args .= " -l $logfile -s $seekfile -p '$config{$param}{'pattern'}'";
$args .= " -w $config{$param}{'warn'} -c $config{$param}{'crit'}" if defined $config{$param}{'crit'};

# Build the eval block
$args .= " $config{$param}{'custom'} " if $config{$param}{'custom'};
$args .= q| -e '{ my @fields = split(/;/); if ($fields[| . $config{$param}{'col'} . q|] > | . $config{$param}{'threshold'} . q|) { $parse_out = "| . $config{$param}{'desc'} . q|\n"; return 1 }}'| if defined $config{$param}{'col'};
$args .= " --debug" if $debug;

#
# Execute plugin, capture output and return code, and exit
#

$cmdexec = "$check_log $args";
print "DEBUG: $cmdexec\n" if $debug;
print `$cmdexec 2>&1`;
$err = $?;

# Note, $? is not just the child's exit code, it's a 16 bit binary value where the first 8 bits are the result
# of calling system() itself - if not 0 (i.e. if any bits are set), bits 0-7 are the signal that caused the child
# to end, bit 8 is whether core was dumped - and the upper 8 bits are the child process's actual exit code.
if ($err == -1 || ($err >> 8) == 127) {
	print "Plugin failed to execute\n";
	exit $ERRORS{'UNKNOWN'};
} elsif ($err & 127) {
	printf "Plugin died with signal %d, %s coredump\n", ($err & 127), ($err & 128) ? 'with' : 'no';
	exit $ERRORS{'UNKNOWN'};
} else {
	# Pass on the plugin's return code to Nagios
	$err = $err >> 8;
	exit $err;
}


#
# Subroutines
#

# Error handler for anything that causes input validation to fail
sub print_error {
	my $msg = $_[0];
	print "$msg\n" if $msg;
	exit $ERRORS{'UNKNOWN'};
}

# Error handler for when we terminate because there is nothing to do
sub print_ok {
	my $msg = $_[0];
	print "$msg\n" if $msg;
	exit $ERRORS{'OK'};
}

# Command line help
sub print_help {
	print "Usage: check_customlog -f conffile -l log_keyword -p parameter\n";
	exit $ERRORS{'OK'};
}

# Print version
sub print_version {
	print "check_customlog version $plugin_revision\n";
	exit $ERRORS{'OK'};
}

# Reads configuration data from a file and returns a hash.
# Parameter: filename
#
# Format:
#
# [configuration]
# keyword = log path (prefix)
# timestamp = date(1) format string (optional)
#
# [parameter]
# desc = free text describing the parameter
# pattern = regexp pattern filter applied before parsing
# col = column number of this parameter (mandatory)
# warn = warning threshold 
# crit = critical threshold
# threshold = value to compare against what is in col
# custom = literally to check_log3.pl
#
sub readconfig {
	my $configfile = $_[0];
	my $sublevel = undef;
	my ($key, $value);
	my %hash = ();

	open(FILE, $configfile) || print_error("Error opening $configfile: $!");
	while(<FILE>) {
		chomp;
		my $line = $_;

		# Skip comments and empty lines
		next if $line =~ /^\s*#/;
		next if $line =~ /^$/;

		my ($key, $value) = split(/=/, $line, 2);

		# Parse [headings]
		if ($line =~ /^\[(.*)\]$/) {
			$sublevel = $1;
		}

		# Strip leading and trailing whitespace from keys
		$key =~ s/^\s*//g;
		$key =~ s/\s*$//g;
		# And from values
		$value =~ s/^\s*//g if $value;
		$value =~ s/\s*$//g if $value;

		# Stuff everything into %hash
		if ($sublevel) {
			next unless (defined($value) && $value);
			$hash{$sublevel}{$key} = $value;
		} else {
			$hash{$key} = $value unless (defined($value) && $value);
		}
	}
	close FILE;
	return %hash;
}

