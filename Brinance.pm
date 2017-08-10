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


package Brinance;
require Exporter;

our @ISA = ("Exporter");
our $VERSION = "1.00";
our @EXPORT_OK = qw($current_acct $now);

our $current_acct = 0;
our $now;

$account_dir .= "$ENV{HOME}/.brinance/";

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

	if ($top =~ "^#NAME: ")
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
		if (/^#/) # doesn't affect calculation
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

	$_[0] *= 1; # to make sure its numeric

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
   1 - success
   0 - account already exists, no change
  -1 - too few arguments, needs 2
=cut
sub create {
	my $worked;

	if ( 2 > @_ )
	{
		return -1;
	}

	my $acct_name = $_[0];
	my $acct_num = $_[1];

	if (-e ("$account_dir" . "account" . $acct_num))
	{
		$worked = 0;
	}
	else
	{
		open (ACCOUNT, (">$account_dir" . "account" . $acct_num)) or die "couldn't create account file\n";
		open (FUTURE, (">$account_dir" . "future" . $acct_num)) or die "couldn't create future file\n";

		print ACCOUNT "#NAME: $acct_name\n";
		print FUTURE "#NAME: $acct_name\n";

		close ACCOUNT;
		close FUTURE;

		$worked = 1;
	}
	return $worked;
}

=pod
sub futurebalance: determines balance at given future time
  usage: &Brinance::futurebalance ( $futureDate )
  return values:
  x - too few arguments, needs 1
  else - the future balance
=cut
sub futurebalance {
	if ( 1 > @_ )
	{
		return "x";
	}

	open (FUTURE, ($account_dir . "future" . $current_acct)) or return "x";

	# date request can only be in 12-digit format

	my $rdate = $_[0];

	my $total = &Brinance::balance ();
	my $grabnext = 0;

	while (<FUTURE>)
	{
		if (/^#\d{12}$/)
		{
			my (undef, $cdate) = split (/#/, $_);
			chomp $cdate;
			if ($cdate < $rdate)
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

	close FUTURE;
	return $total;
}

=pod
sub futuretrans: applies a transaction at specified future time
  usage: &Brinance::futuretrans ( &futureDate, $amount, $comment )
  return values:
   0 - success
  -1 - too few arguments, needs three
  -2 - zero-value transaction
  -3 - time specified is not in the future
=cut
sub futuretrans {
	&renow ();

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
	elsif ( $now >= $_[0] )
	{ 
		# needs to actually be in the future
		close FUTURE;
		return -3;
	}
	else
	{
		open (FUTURE, (">>$account_dir" . "future" . $current_acct)) or die "ERROR: Cannot open file " . $account_dir . "future" . $current_acct;

		my $date = $_[0];
		my $amount = $_[1];
		my $comment = $_[2];

		#and roll..

		print FUTURE "#$date\n";
		print FUTURE "#$comment\n";
		print FUTURE "$amount\n";
	}

	close FUTURE;
	return 0;
}

=pod
sub update_future: called before working with an account to apply future transactions if they are now passed
=cut
sub update_future {
	&renow ();

	open (FUTURE, ($account_dir . "future" . $current_acct)) or die "ERROR: update_future: Cannot open file " . $account_dir . "future" . $current_acct;
	open (ACCOUNT, (">>$account_dir" . "account" . $current_acct)) or die "ERROR: update_future: Cannot open file " . $account_dir . "account" . $current_acct;
	open (NEWFUTURE, (">$account_dir" . "newfuture" . $current_acct)) or die "ERROR: update_future: Cannot open file " . $account_dir . "newfuture" . $current_acct;

	my @futures = {}; #we'll build this out of transactions from the ~future~
	my $futures_i = 0;
	my $grab = 0;

	# These are to build the new future file, minus the now-past transactions
	my @nfutures = {};
	my $nfutures_i = 0;
	my $ngrab;

	for (<FUTURE>)
	{
		chomp;

		if ($grab)
		{
			$futures[$futures_i++] = $_;
			$grab--;
			next;
		}

		if ($ngrab)
		{
			$nfutures[$nfutures_i++] = $_;
			$ngrab--;
			next;
		}

		if (/^#\d{12}$/) # our standard date stamp
		{
			my (undef, $date) = split(/#/, $_);

			if ($date <= $now)
			{
				$futures[$futures_i++] = $_;
				$grab = 2; # grab next two lines
			}
			else
			{
				$nfutures[$nfutures_i++] = $_;
				$ngrab = 2;
			}
		}
		elsif (/^#NAME: /)
		{
			$nfutures[$nfutures_i++] = $_;
		}
	}

	for (my $i = 0; $i < $futures_i; $i++) 
	{
		print ACCOUNT "$futures[$i]\n";
	}

	for (my $i = 0; $i < $nfutures_i; $i++)
	{
		print NEWFUTURE "$nfutures[$i]\n";
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
   1 - safe to switch, success
   0 - created account0; won't auto-create any other account
  -1 - account doesn't exist, unsafe
=cut
sub switch_acct {
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

			return 0;
		}
		else
		{
			# error out
			return -1;
		}
	}
	else
	{
		return 1;
	}
}

