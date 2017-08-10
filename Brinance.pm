# Brinance.pm: Perl module for lightweight financial planner/tracker
#
# This software released under the terms of the GNU General Public License 2.0
#
# Copyright (C) 2003 Brian M. Kelly locoburger@netscape.net http://www.locoburger.org/
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
our $VERSION = "1.12";
our @EXPORT_OK = qw($current_acct $now $account_dir);

our $current_acct = 0;
our $now;
our $account_dir = "$ENV{HOME}/.brinance/";

=pod
sub renow: re-initialize $now, used before any time-dependant functions
=cut
sub renow {
	$now = `date +%C%y%m%d%H%M`;
	chomp $now;
}

=pod
sub version: returns current version of module
=cut
sub version {
	return $VERSION;
}

=pod
sub getName: returns the name of the current account, or undefined if there is no valid name
=cut
sub getName {
	open (ACCOUNT, ($account_dir . "account" . $current_acct)) or die "ERROR: Cannot open file " . $account_dir . "account" . $current_acct;

	#only look for it on the first line
	my $top = <ACCOUNT>;
	my $title = undef;

	if ($top =~ /^#NAME: /)
	{
		(undef, $title) = split(/: /, $top);
		chomp $title;
	}

	close ACCOUNT;
	return $title;
}

=pod
sub balance: returns the balance of the current account
=cut
sub balance {
	open (ACCOUNT, ($account_dir . "account" . $current_acct)) or die "ERROR: Cannot open file " . $account_dir . "account" . $current_acct;

	my $total = 0;
	for (<ACCOUNT>)
	{
		if (/^#/)
		{
			#commented line
		}
		else
		{
			$total += $_;
		}
	}

	close ACCOUNT;
	return $total;
}

=pod
sub trans: applies a transaction to the current account, either credit or debit
  usage: &Brinance::trans ( $amount, $comment )
  return values:
   0 - success
  -1 - too few arguments (needs two)
  -2 - zero value transaction, which could mean a non-number was specified as the transaction amount
=cut
sub trans () {
	&renow ();

	open (ACCOUNT, (">>$account_dir" . "account" . $current_acct)) or die "ERROR: Cannot open file " . $account_dir . "account" . $current_acct;

	if ( 2 > @_ ) # too few arguments
	{
		close ACCOUNT;
		return -1;
	}

	$_[0] += 0; # to make sure its numeric

	if ( 0 == $_[0] ) # zero value transacrion
	{
		close ACCOUNT;
		return -2;
	}
	else
	{
		# yup, do it.. the guts
		print ACCOUNT "#$now\n"; # timestamp
		print ACCOUNT "#$_[1]\n"; # comment
		print ACCOUNT "$_[0]\n"; # amount
	}

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
	my $acct_num = 1 * $_[1]; #Make it numeric

	if (-e ("$account_dir" . "account" . $acct_num))
	{
		return 1;
	}
	else
	{
		open (ACCOUNT, (">$account_dir" . "account" . $acct_num)) or die "couldn't create account file\n";
		open (FUTURE, (">$account_dir" . "future" . $acct_num)) or die "couldn't create future file\n";

		print ACCOUNT "#NAME: $acct_name\n";
		print FUTURE "#NAME: $acct_name\n";

		close ACCOUNT;
		close FUTURE;

		return 0;
	}
}

=pod
sub datedbalance: determines balance at given future time
  usage: &Brinance::datedbalance ( $date )
  return balance at $date:
=cut
sub datedbalance {
	if ( 1 > @_ )
	{
		return undef;
	}

	my $requestd_date = $_[0];
	my $total;
	my $file; # Which file to open, depending on next if
	if ( $now >= $requestd_date )
	{
		$file = "account";
		$total = 0;
	}
	else
	{
		$file = "future";
		$total = &balance ();
	}

	open (FILE, ($account_dir . $file . $current_acct)) or die "Could not open $file file\n";
	my $grabnext = 0;

	while (<FILE>)
	{
		if (/^#(\d{12})$/)
		{
			if ($1 <= $requestd_date)
			{
				$grabnext = 1; # take the next value to come up
			}
		}
		elsif (/^#/)
		{
			# other commented line, ignore it
		}
		elsif ($grabnext) # it's not a comment, and we've been told to take next value
		{
			$total += $_;
			$grabnext = 0;
		}
	}

	close FILE;
	return $total;
}

=pod
sub datedtrans: applies a transaction at specified future time
  usage: &Brinance::datedtrans ( &date, $amount, $comment )
  return values:
   0 - success
  -1 - too few arguments, needs three
  -2 - zero-value transaction
=cut
sub datedtrans {
	&renow ();
	my $file = "future";

	if ( 3 > @_ )
	{
		# too few arguments
		return -1;
	}
	elsif ( 0 == $_[1] )
	{
		# 0-value transaction
		return -2;
	}
	elsif ( $now > $_[0] )
	{ 
		$file = "account";
	}

	open (FILE, (">>$account_dir" . $file . $current_acct)) or die "ERROR: Cannot open file " . $account_dir . $file . $current_acct;

	# for readability
	my $date = $_[0];
	my $amount = $_[1];
	my $comment = $_[2];

	#and roll..

	print FILE "#$date\n";
	print FILE "#$comment\n";
	print FILE "$amount\n";

	close FILE;
	return 0;
}

=pod
sub update_future: called before working with an account to apply future transactions if they are now in the past
=cut
sub update_future {
	&renow ();

	open (FUTURE, ($account_dir . "future" . $current_acct)) or die "ERROR: update_future: Cannot open file " . $account_dir . "future" . $current_acct;
	open (ACCOUNT, (">>$account_dir" . "account" . $current_acct)) or die "ERROR: update_future: Cannot open file " . $account_dir . "account" . $current_acct;
	open (NEWFUTURE, (">$account_dir" . "newfuture" . $current_acct)) or die "ERROR: update_future: Cannot open file " . $account_dir . "newfuture" . $current_acct;

	my @futures = (); #we'll build this out of transactions from the ~future~
	my $grab = 0;

	# These are to build the new future file, minus the now-past transactions
	my @nfutures = ();
	my $ngrab = 0;

	for (<FUTURE>)
	{
		chomp;

		if ($grab)
		{
			push (@futures, $_ );
			$grab--;
			next;
		}

		if ($ngrab)
		{
			push (@nfutures, $_);
			$ngrab--;
			next;
		}

		if (/^#\d{12}$/) # our standard date stamp
		{
			my (undef, $date) = split(/^#/, $_);

			if ($date <= $now)
			{
				push (@futures, $_ );
				$grab = 2; # grab next two lines
			}
			else
			{
				push (@nfutures, $_);
				$ngrab = 2;
			}
		}
		elsif (/^#NAME: /)
		{
			push (@nfutures, $_);
		}
	}

	foreach (@futures)
	{
		print ACCOUNT "$_\n";
	}

	foreach (@nfutures)
	{
		print NEWFUTURE "$_\n";
	}

	close ACCOUNT;
	close FUTURE;
	close NEWFUTURE;

	my $src = ($account_dir . "newfuture" . $current_acct);
	my $trg = ($account_dir . "future" . $current_acct);

	system ("mv -f $src $trg");
}

=pod
sub switch_acct: safety for switching account, give a failure if the account isn't initialized
  return values:
   1 - created account0; won't auto-create any other account
   0 - safe to switch, success
  -1 - account doesn't exist, unsafe
=cut
sub switch_acct {
	if ( @_ )
	{
		$current_acct = $_[0];
	}
	else
	{
		$current_acct = 0;
	}

	# check to see this account exists, else fail
	if (!-e ($account_dir . "account" . $current_acct)) # doesn't exist
	{
		# if 0 doesn't exist, create it, calling it default;
		if ( 0 == $current_acct )
		{
			open (ACCOUNT, (">$account_dir" . "account0")) or die "couldn't create account file\n";
			open (FUTURE, (">$account_dir" . "future0")) or die "couldn't create future file\n";

			print ACCOUNT "#NAME: default\n";
			print FUTURE "#NAME: default\n";

			close ACCOUNT;
			close FUTURE;

			# created the initial account
			return 1;
		}
		else
		{
			# error out
			return -1;
		}
	}
	else
	{
		# safe to work with this account
		return 0;
	}
}

