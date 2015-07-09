#!/usr/bin/perl -w
#
# Script to test whether an IP address belongs to a given list of IP ranges
# Based on http://www.theunixtips.com/perl-find-if-ip-address-is-in-network-range
# Last updated 2013-07-08 by Peter Mc Aulay
#
use strict;
use NetAddr::IP;

my $ipAddr  = $ARGV[0];
my $ipRanges = $ARGV[1];
my $verbose = $ARGV[2];

die("Usage: check_ip_range.pl 1.2.3.4 ranges.txt [verbose]") unless $ipAddr and $ipRanges;

open RANGE, $ipRanges or die("Cannot open range list $ipRanges");
while (<RANGE>) {
	my $netAddr = $_;
	my $network  = NetAddr::IP->new($netAddr);
	my $ip = NetAddr::IP->new($ipAddr);
	if ($ip->within($network)) {
		print $ip->addr() . " is in range $network\n";
	} else {
		print $ip->addr() . " not in $network\n" if $verbose;
	}
}

