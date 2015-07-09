#!/usr/bin/perl -w
#
# RRD to CSV export tool
#
# Based on rrd2csv.pl by wrhoop r3 Oct 29, 2010
# Last modified by Peter Mc Aulay 2013-02-04
#

#use strict;
use POSIX qw(strftime);
use Getopt::Long;
use RRDs;
use lib '/usr/opt/rrdtool/';
use Data::Dumper;

# Pre-declare some variables
my ($csvname, $point_in_time, $offset, $names, $data, $error);
my ($val, $units);
my @results;
my @fetch;

#
# Programme version
#
my $revision = "3.0 PMA";
sub version() {
	print "rrd2csv $revision\n";
	exit 0;
}

#
# Parse options
#
my ($debug, $scale, $conversion, $start, $end, $now, $step, $sep, $help, $version, @rrdfiles, @headers) = '';
GetOptions (
	"debug"	 => \$debug,
	"a|autoscale"   => \$scale,
	"c|conversion"  => \$conversion,
	"l|label=s"     => \@headers,
	"s|start=s"     => \$start,
	"e|end=s"       => \$end,
	"i|step"	=> \$step,
	"n|now"	 => \$now,
	"separator=s"   => \$sep,
	"h|help"	=> \$help,
	"f|file=s"      => \@rrdfiles,
	"v|version"     => \$version,
	);

# Command line help
sub usage {
	print <<EOF;

Usage: rrd2csv.pl [args] -f file.rrd [-f file2.rrd...]

Where args is one or more of:
  -a	  autoscale DS values (also --autoscale)
  -c num      convert DS values by "num" (also --conversion)
  -e end      report ending at time "end" (also --end)
  -l label    label DS value column with "label" (also --label)
  -n	  only report values around now (--now)
  -s start    report starting at time "start" (also --start)
  -i step     specify step interval in seconds (also --step)
  --separator specify column separator (default ",")
  -h	  print this screen (also --help)
  -v	  print programme version (also --version)

The -s and -e options support the traditional "seconds since the Unix
epoch" and the AT-STYLE time specification (see man rrdfetch)

For multiple input files, the output will have multiple columns,
one per input DS.  You can specify the column headers with "-l".

EOF
	exit 1;
}

#
# Input validation
#
!($version) || version();
!($help) || usage();
(@rrdfiles) || usage();

foreach (@rrdfiles) {
	if (! -f "$_" ) {
		print "rrd2csv: can't find file: $_\n";
		$error = 1;
	}
	if ($error) {
		usage();
		exit 1;
	}
}

if ($conversion && $conversion !~ /^\d+$|^\d+\.\d+$|^\.\d+$/) {
	print "Bad conversion factor \"$conversion\"\n";
	usage();
	exit 1;
}

# rrdtool understands human-readable times
if ($now) {
	$start = $end = 'now';
}

# Make sure both start and end are initialised
if ($start && !$end) {
	$end = 'now';
}

if ($end && !$start) {
	if ($end =~ /^\d+$/) {
		$start = $end - 1;
	} else {
		# Time specified as text
		$start = "${end}-1sec";
	}
	$point_in_time = 1;
}

if (!$start && !$end) {
	$start = $end = 'now';
	$point_in_time = 1;
}

# Default step is 5 minutes
if (!$step) {
	$step = 300;
}

# Default separator is a comma
if (!$sep) {
	$sep = ',';
}

#
# Fetch data from files
#
foreach my $file (@rrdfiles) {
	my $qstep = $step;
	my ($qstart);
	undef @fetch;
	#
	# Get data around a single point in time
	#
	if ($point_in_time) {
		print "DEBUG: point-in-time fetch\n" if $debug;
		push @fetch, $file, '-s', $start, '-e', $end, 'AVERAGE';
		if (! $qstep) {
			# Fetch data from RRD file to determine step
			# Also rounds $start to nearest data point
			print "DEBUG: rrdtool fetch ", join(' ', @fetch), " (figuring out step)\n" if $debug;
			($start, $qstep, $names, $data) = RRDs::fetch @fetch;
			if ($error = RRDs::error) {
				print "rrd2csv: rrdtool fetch failed: \"$error\"\n";
				exit 1;
			}
		}

		# Fetch data from (point_in_time - step) to point_in_time
		# Go back two steps so we report values on either side of the point in time
		$offset = $qstep * 2;
		if ($end =~ /^\d+$/) {
			$start = $start - $offset;
		} else {
			$start = "${end}-${offset}sec";
		}

		# Start again now we know the step, with adjusted start and end times
		undef @fetch;
		push @fetch, $file, '-s', $start, '-e', $end, '-r', $qstep, 'AVERAGE';

		# Fetch data from RRD file
		print "DEBUG: rrdtool fetch ", join(' ', @fetch), " (getting data)\n" if $debug;
		($start, $qstep, $names, $data) = RRDs::fetch @fetch;
		if ($error = RRDs::error) {
			print "rrd2csv: rrdtool fetch failed: \"$error\"\n";
			exit 1;
		}

	#
	# Otherwise, retrieve the requested range
	#
	} else {
		push @fetch, $file;
		push @fetch, '-s', $start if $start;
		push @fetch, '-e', $end if $end;
		push @fetch, '-r', $qstep if $qstep;
		push @fetch, 'AVERAGE';

		print "DEBUG: rrdtool fetch ", join(' ', @fetch), "\n" if $debug;
		($qstart, $qstep, $names, $data) = RRDs::fetch @fetch;
		if ($error = RRDs::error) {
			print "rrd2csv: rrdtool fetch failed: \"$error\"\n";
			exit 1;
		}
		# Incidentally converts "AT-style" timestamps to Unix epoch
		$start = $qstart;
	}

	#print Dumper([$data]) if $debug;

	# Create a new column
	push(@results, $data);
}

#
# Print output
#

#print Dumper([\@results]) if $debug;

# Print DS names, or header labels in the order passed on the command line
$names = \@headers if @headers;
unshift @$names, "Timestamp";
print join($sep, @$names);
print "\n";

# Transpose the results matrix (swap columns and rows)
my @transposed = ();
for my $row (@results) {
	for my $column (0 .. $#{$row}) {
		push(@{$transposed[$column]}, $row->[$column]);
	}
}
@results = @transposed;

# Print results
for my $row (@results) {
	# Print timestamp
	print strftime("%m/%d/%Y %H:%M:%S", localtime($start));
	$start += $step;
	# Print rows and columns of data
	for my $col (@$row) {
		if ($col) {
			for my $val (@$col) {
				if ($val) {
					$val = $val * $conversion if $conversion;
					$val = $val * autoscale($val) if $scale;
					printf "$sep%4.2f", $val;
				} else {
					print $sep, "0.00";
				}
			}
		} else {
			print $sep, "0.00";

		}
	}
	print "\n";
}

# Done!
exit 0;


#
# Subroutines
#

# Function to auto-scale units
sub autoscale {
	my $value = @_;
	my ($floor, $magnitude, $index, $symbol, $new_value);
	# SI prefixes for the scaling factors (atto to exa)
	my %scale_symbols = qw( -18 a -15 f -12 p -9 n -6 u -3 m 3 k 6 M 9 G 12 T 15 P 18 E );

	# Strip null and invalid values from output
	if ($value =~ /^\s*[0]+\s*$/ ||
	    $value =~ /^\s*[0]+.[0]+\s*$/ ||
	    $value =~ /^\s*NaN\s*$/) {
		return $value, ' ';
	}

	# Round and scale where appropriate
	$floor = floor($value);
	$magnitude = int($floor/3);
	$index = $magnitude * 3;
	$symbol = $scale_symbols{$index};
	$new_value = $value / (10 ** $index);

	return $new_value, " $symbol";
}

# As the C floor(3) function
sub floor {
	my $value = $_;
	my $i = 0;

	if ($value > 1.0) {
		# scale downward...
		while ($value > 10.0) {
			$i++;
			$value /= 10.0;
		}
	} else {
		while ($value < 10.0) {
			$i--;
			$value *= 10.0;
		}
	}
	return $i;
}
