#!/bin/sh
#
# Output daily CSV reports from Nagios RRD data
# Last updated 2013-02-04 by Peter Mc Aulay
#

# The string used to find(1) the relevant service checks
REGEX=$1

if [ "x$REGEX" = "x" ]; then
	echo "Usage: `basename $0` find-expression"
	exit 1
fi

# RRD files are here
INPUTDIR=/data/opsview/nagios/var/rrd
# CSV files go here
REPORTDIR=/data/opsview/reports
# Report this many seconds worth of data
INTERVAL=86400
# Path to rrd2csv.pl
RRD2CSV=/data/scripts/nagios/rrd2csv_new.pl

# Prepare output directory
OUTDIR=$REPORTDIR/csv/$(date +'%Y-%m-%d')
mkdir -p $OUTDIR || (echo "Cannot create $OUTDIR: $!"; exit 1)

# Compute timestamps
EPOCH=$(date +%s)
START=$(($EPOCH - $INTERVAL))

# Find service checks
for d in `find $INPUTDIR -type d -name $REGEX`; do
	# Build human-readable file name components
	HOST=`echo "$d"|awk -F/ '{ print $(NF-1) }'`
	SERVICE=`echo "$d"|sed 's/%../_/g;s/\/.*\///g;s/\-/_/g'`
	FILENAMES=""
	HEADERS=""
	echo "Found: $HOST - $SERVICE"

	# Find attributes
	for i in `find $d -type d`; do
		if [ -f $i/value.rrd ]; then
			# Get file name component
			ATTR=`echo "$i"|sed 's/%../_/g;s/\/.*\///g'`
			echo "  Found $ATTR"
			# Add RRD file to list of files to process
			FILENAMES="$FILENAMES -f $i/value.rrd"
			HEADERS="$HEADERS -l \"$ATTR\""
			# Alerting thresholds are stored in a separate file
			if [ -f "$i/thresholds.rrd" ]; then
				echo "  Adding thresholds"
				FILENAMES="$FILENAMES -f $i/thresholds.rrd"
				HEADERS="$HEADERS -l \"${ATTR}_warning\" -l \"${ATTR}_critical\""
			fi
		fi
	done

	# Process the RRD files, converting them to broken non-US Excel CSV format
	$RRD2CSV --separator=';' -s $START -e now $FILENAMES $HEADERS > $OUTDIR/${HOST}-${SERVICE}.csv 2>&1
	if [ $? -gt 0 ]; then
		echo "  Failed!"
	fi
	echo
done
