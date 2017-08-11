# Brinance.pm: Perl module for lightweight financial planner/tracker
#
# This software released under the terms of the GNU General Public License 2.0
#
# Copyright (C) 2003,2004 Brian M. Kelly locoburger@netscape.net http://www.locoburger.org/
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, version 2.0.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# brinance - Perl UNIX personal finance planner/tracker
#
#     tabstop = 3    (These two lines should line up)
#		tabstop = 3		(These two lines should line up)

use strict;
use warnings;

package Brinance;
require Exporter;

our @ISA = ("Exporter");
our $VERSION = "3.92";
our @EXPORT_OK = qw($current_acct $now $account_dir
							&getName &balance &trans &create
							&update_future &version &datedtrans
							&datedbalance &switch_acct);

our $current_acct = 0;
our $now;
our $account_dir = "$ENV{HOME}/.brinance";

=pod
sub renow: re-initialize $now, used before any time-dependant functions
=cut
sub renow () {
	my (undef, $min, $hour, $mday, $mon, $year, undef, undef, undef) = localtime(time);

	$year += 1900;
	$mon += 1;

	if ($mon < 10) { $mon = "0" . $mon; }
	if ($mday < 10) { $mday = "0" . $mday; }
	if ($hour < 10) { $hour = "0" . $hour; }
	if ($min < 10) { $min = "0" . $min; }

	$now = $year . $mon . $mday . $hour . $min;
}

=pod
sub version: returns current version of Briance module
=cut
sub version () {
	return $VERSION;
}

=pod
sub getName: returns the name of the current account, or undefined if there is no valid name
=cut
sub getName () {
	open (ACCOUNT, "$account_dir/accounts") or die "ERROR: Cannot open file $account_dir/accounts";

	my $title = undef;
	while (<ACCOUNT>) {
		if (/^ACCOUNT $current_acct: (.+)$/)
		{
			$title = $1;
			last;
		}
	}
	close ACCOUNT;

	return $title;
}

=pod
sub balance: returns the balance of the current account
=cut
sub balance () {
	&renow;
	open (ACCOUNT, ("$account_dir/accounts")) or die "ERROR: Cannot open file $account_dir/accounts";

	my $date_req;
	if ($_[0] and ($_[0] =~ /^\d{12}$/)) {
		$date_req = $_[0];
	} else {
		$date_req = $now;
	}

	my $total = 0;
	for (<ACCOUNT>)
	{
		if (/^(\d{12})\s+$current_acct\s+([-0-9\.]+).+$/)
		{
			if ( $1 <= $date_req ) {
				$total += $2;
			}
		}
	}

	close ACCOUNT;
	return $total;
}

=pod
sub trans: applies a transaction to the current account, either credit or debit
  usage: &Brinance::trans ( $amount, $comment, <$date> )
  return values:
   0 - success
  -1 - too few arguments (needs two)
  -2 - zero value transaction, which could mean a non-number was specified as the transaction amount
  -3 - invalid date specified
=cut
sub trans () {
	&renow;

	if ( 2 > @_ ) # too few arguments
	{
		return -1;
	}

	$_[0] += 0; # to make sure its numeric

	if ( 0 == $_[0] ) # zero value transacrion
	{
		return -2;
	}

	my $req_date;
	if ( $_[2] ) # was a date specified?
	{
		unless ($_[2] =~ /^\d{12}$/) # invalid date format
		{
			return -3;
		}
		$req_date = $_[2];
	}
	else
	{
		$req_date = $now;
	}

	# yup, do it.. the guts
	open (ACCOUNT, ">>$account_dir/accounts") or die "ERROR: Cannot open file $account_dir/accounts";

	my $amount = $_[0];
	my $comment = $_[1];

	print ACCOUNT "$req_date\t$current_acct\t$amount\t$comment\n";

	close ACCOUNT;
	return 0;
}

=pod
sub create: create a new account
  usage: &Brinance::create ( $accountName, $accountNumber )
  return values:
   1 - account already exists, no change
   0 - success
  -1 - too few arguments, needs 2
=cut
sub create () {
	if ( 2 > @_ )
	{
		return -1;
	}

	my $acct_name = $_[0];
	my $acct_num = 0 + $_[1]; #Make it numeric

	open (RACCOUNT, "$account_dir/accounts") or die "ERROR: Cannot open file $account_dir/accounts for reading";

	# check to see if account already exists
	my @oldacct;
	while (<RACCOUNT>) {
		chomp;
		unless (/^ACCOUNT $acct_num:?/) {
			push (@oldacct, $_);
		}	else {
			close RACCOUNT;
			return 1;
		}
	}
	close RACCOUNT;

	open (WACCOUNT, ">$account_dir/accounts") or die "ERROR: Cannot open file $account_dir/accounts for writing";

	if ($acct_name) {
		print WACCOUNT "ACCOUNT $acct_num: $acct_name\n"
	} else {
		print WACCOUNT "ACCOUNT $acct_num\n";
	}

	foreach (@oldacct) {
		print WACCOUNT "$_\n";
	}
	close WACCOUNT;

	open (RFUTURE, "$account_dir/futures") or die "ERROR: Cannot open file $account_dir/futures for reading";

	my $exists;
	my @oldfut;
	while (<RFUTURE>) {
		chomp;
		unless (/^ACCOUNT\s+$acct_num:/) {
			push (@oldfut, $_);
		} else {
			$exists = $_; # account already listed in futures file
		}
	}
	close RFUTURE;

	open (WFUTURE, ">$account_dir/futures") or die "ERROR: Cannot open file $account_dir/futures for writing";
	print WFUTURE "ACCOUNT $acct_num: $now\n";
	foreach (@oldfut) {
		print WFUTURE "$_\n";
	}
	close WFUTURE;

	return 0;
}

=pod
sub datedbalance: determines balance at given future time
  usage: &Brinance::datedbalance ( $date )
  return balance at $date
=cut
sub datedbalance () { # deprecated
	return &balance (@_);
}

=pod
sub datedtrans: applies a transaction at specified future time
  usage: &Brinance::datedtrans ( &date, $amount, $comment )
  return values:
   0 - success
  -1 - too few arguments, needs three
  -2 - zero-value transaction
=cut
sub datedtrans () { # deprecated
	if ( $_[0] and $_[1] and $_[2] ) {
		# trans takes the date last, datedtrans takes it first, so we need to switch things around
		return &trans ( $_[1], $_[2], $_[0] );
	} else {
		return -1;
	}
}

=pod
sub update_future: called before working with an account to apply future transactions if they are now in the past
=cut
sub update_future () {
#FIXME: this will check time patterns in futures file to see if there's an transaction to apply since our last run
# last run on each account is in futures file
	&renow;

	unless (-e "$account_dir/futures") {
		# create futures file
		open (FUTURES, ">$account_dir/futures") or die "ERROR: cannot create futures file";
		open (ACCOUNTS, "$account_dir/accounts") or die "ERROR: cannot read accounts file";

		my @accounts;
		while (<ACCOUNTS>) {
			if (/^ACCOUNT (\d+)/) {
				push (@accounts, $1);
			}
		}
		close ACCOUNTS;

		foreach (@accounts) {
			print FUTURES "ACCOUNT $_: $now\n";
		}
		close FUTURES;

		return;
	}

	# calculate now-past recurring transactions based upon last run-time in last_update
	open (RFUTURES, "$account_dir/futures") or die "ERROR: could not open futures file";

	my @futures; # load this up so we can update last dates, and then get down to business
	my $last_update;
	foreach (<RFUTURES>) {
		chomp;
		push (@futures, $_);

		if (/^\s*#/) { # ignore comments
			next;
		} elsif (/^\s*$/) { # ignore blank lines
			next;
		} elsif (/^ACCOUNT\s+$current_acct:\s+(\d{12})$/) { # get the last update time on the current account
			$last_update = $1;
		} elsif (/^\s*(\S+)\s+(\S+)\s+(\S+)\s+([|&]?)\s*(\S+)\s+(\S+)\s+(\S+)\s+:(\S*):\s+$current_acct\s+(.+)\s*$/) {
			# woo.. there's an ugly regex..
			$5 = $5 ? $5 : "|";
			my @dates;
			if ($last_update) {
				@dates = &calc_future_patterns ($1, $2, $3, $4, $5, $6, $7, $8, $last_update);
			} else {
				# silently fail, we'll post a last_update in just a sec
			}

			if (@dates) {
				open (ACCOUNTS, ">>$account_dir/accounts") or die "ERROR: Could not open accounts file to apply now-past transactions";
				my ($amount, $comment) = split ($9, /\s/, 2);
				foreach (@dates) {
					print ACCOUNTS "$_\t$current_acct\t$amount\t$comment\n";
#print STDOUT "$_\t$current_acct\t$amount\t$comment\n";
				}
				close ACCOUNTS;
			}
		}
	}
	close RFUTURES;

	# update last update info for this account in futures
	open (WFUTURES, ">$account_dir/futures") or die "ERROR: could not open last_update file";
	foreach (@futures) {
		if (/^ACCOUNT\s+$current_acct:/) {
			print WFUTURES "ACCOUNT $current_acct: $now\n";
		}
		else {
			print WFUTURES "$_\n";
		}
	}
	close WFUTURES;

	return;
}

=pod
sub switch_acct: safety for switching account, give a failure if the account isn't initialized
  return values:
   1 - created account0; won't auto-create any other account
   0 - safe to switch, success
  -1 - account doesn't exist, unsafe
=cut
sub switch_acct () {
	if ( @_ )
	{
		$current_acct = $_[0];
	}
	else
	{
		$current_acct = 0;
	}

	# check to see the account file exists, else create empty
	if (-e "$account_dir/accounts")
	{ # need to check that there is a ACCOUNT line for this account
		open (ACCOUNT, "$account_dir/accounts") or die "ERROR: Cannot open file $account_dir/accounts";

		while (<ACCOUNT>) {
			if (/^ACCOUNT $current_acct/) {
				close ACCOUNT;
				return 0;
			}
		}
		# didn't find it
		return -1;
	}
	else
	{ # create file, with account 0 named "default"
		open (ACCOUNT, ">$account_dir/accounts") or die "ERROR: Cannot create file $account_dir/accounts";
		print ACCOUNT "ACCOUNT 0: default\n";
		close ACCOUNT;

		return 1;
	}
}

=pod
INTERNAL
sub calc_future_patterns: processes patterns lines in futures file between last_update and now
=cut
#FIXME: want this to take a requested date argument, so we can calculate for future dates, for future balances
sub calc_future_patterns () {
#($year, $month, $day, $day_logic, $dayow, $hour, $min, $origin, $last_update)
	unless (9 == @_) {
		return ();
	}

	my ($year, $month, $day, $day_logic, $dayow, $hour, $min, $origin, $last_update) = @_;

	&renow;
	$now =~ /^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)$/;
	my ($year_now, $month_now, $day_now, $hour_now, $min_now) = ($1, $2, $3, $4, $5);
	my $dayow_now = &get_dayow($year_now, $month_now, $day_now);

	$last_update =~ /^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)$/;
	my ($year_last, $month_last, $day_last, $hour_last, $min_last) = ($1, $2, $3, $4, $5);
	my $dayow_last = &get_dayow($year_last, $month_last, $day_last);

	unless ($day_logic) { $day_logic = "|"; }

	$month =~ s/jan/1/i;
	$month =~ s/feb/2/i;
	$month =~ s/mar/3/i;
	$month =~ s/apr/4/i;
	$month =~ s/may/5/i;
	$month =~ s/jun/6/i;
	$month =~ s/jul/7/i;
	$month =~ s/aug/8/i;
	$month =~ s/sep/9/i;
	$month =~ s/oct/10/i;
	$month =~ s/nov/11/i;
	$month =~ s/dec/12/i;

	$dayow =~ s/sun/0/i;
	$dayow =~ s/mon/1/i;
	$dayow =~ s/tue/2/i;
	$dayow =~ s/wed/3/i;
	$dayow =~ s/thu/4/i;
	$dayow =~ s/fri/5/i;
	$dayow =~ s/sat/6/i;
	$dayow =~ s/7/0/;

	# we'll only calculate to a day's granularity, tack on the hour and min as the time, but it doesn't affect the calculation
	my %years = &gen_list ($year);
	my %months = &gen_list ($month);
	my %days = &gen_list ($day);
	my %dayows = &gen_list ($dayow);

#FIXME: still not triggering quite right..
	my @return_dates = ();
	foreach ( ($year_last . $month_last . $day_last) .. ($year_now . $month_now . $day_now) ) {
		unless (/^(\d{4})(\d\d)(\d\d)$/) {
#print "didn't like $_\n";
			next;
		}
		my ($year_req, $month_req, $day_req, $hour_req, $min_req, $dayow_req)= ($1, $2, $3, $hour, $min, &get_dayow($_));
#print "liked $_\n";

		my $curr = 1; # whether this date is a go
		if (%years) {
			unless  ($years{$year_req}) { $curr = 0; }
		}
		if (%months) {
			unless  ($months{$month_req}) { $curr = 0; }
		}
		# do the days and dayows
		if ( $day_logic eq "|" ) {
			if (%days) {
				if (%dayows) {
					unless ($days{$day_req} or $dayows{$dayow_req}) { $curr = 0; }
				}
				else {
					unless ($days{$day_req}) { $curr = 0; }
				}
			} elsif (%dayows) {
				unless ($dayows{$dayow_req}) { $curr = 0; }
			}
		}
		elsif ( $day_logic eq "&" ) {
			if (%days) {
				unless ($days{$day_req}) { $curr = 0; }
			}
			if (%dayows) {
				unless ($dayows{$dayow_req}) { $curr = 0; }
			}
		}
		else {
			return ();
		}

#print  "\$curr = $curr\n";
		if ($curr and (($hour_now . $min_now) > ($hour_req . $min_req))) { push (@return_dates, ($year_req . $month_req . $day_req . $hour_req . $min_req)); }
	}
	return @return_dates;
}

=pod
INTERNAL
sub get_dayow returns numeric day-of-week (0-6) based on 8-digit date
=cut
sub get_dayow () {
	my $ypart = ($1 % 100) + int((($1 % 100) / 4));
	my @mpart = (6,2,2,5,0,3,5,1,4,6,2,4);
	my $dpart = $3;
	my $total = $ypart + $mpart[$2-1] + $dpart;
	if (int($1/100) == 19) { $total += 1; }
	if (($1 % 4) == 0) {
	    if (($2 == 1) or ($2 == 2)) { $total -= 1; }
	}

	while ($total > 6) { $total -= 7; }

	return $total;
}

=pod
INTERNAL
sub gen_list takes a string of comma seperated, dash-indicated ranges and retuns all the valid values in a hash
 i.e. "2-5,7,8,12-15" returns hash of 2,3,4,5,7,8,12,13,14,15 all set to 1
=cut
sub gen_list () {
	my %items = ();
	my $item = $_[0];

	unless ($item eq "*") # leave %items uninitialized if so
	{
		my @holder = split (/,/, $item);
		foreach (@holder)
		{
			unless (/-/) {
				$items{$_} = 1;
			}
			else {
				my ($start, $end) = split (/-/);
				if ($start < $end) {
					while ($start <= $end) {
						$items{$start++} = 1;
					}
				}
				else {
					die "ERROR: item \$start:$start not before \$end:$end";
				}
			}
		}
	}
	return %items;
}
