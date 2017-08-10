#!/usr/bin/perl -w
#
# The NEW and IMPROVED brinance!
#
# This softwre released under the terms of GNU General Public License 2.0
#
# Loaded with new features, and various bugs that will surely be ironed out soon..

use File::Basename;
use Number::Format;

# Parse agruments, which in turn, call subfunctions..
#
#	Accepted args:
#		b - show balance
#			$ brinance -b
#		B - future balance
#			$ brinance -B <12-digit date>
#		c - credit
#			$ brinance -c <amount> <comment>
#		C - future credit
#			$ brinance -C <12-digit date> <amount> <comment>
#		d - debit
#			$ brinance -d <amount> <comment>
#		D - future debit
#			$ brinance -D <12-digit date> <amount> <comment>
#		# - (as in, a number) all following arguments refer to this (numbered) account
#			$ brinance -2 <action>
#		n - get the name of the active account
#			$ brinance -4 -n
#		r - create a new account
#			$ brinance -C <description>
#		h - help
#			$ brinance -h
#		v - version
#			$ brinance -v

#FIXME: all modifications to $skipnext should be in main loop, not in subroutines
# fixed it, needs to be debugged

my $skipnext = 0;
my $current_acct = 0;
my $where = 0;
my $credit = 0; #1 is credit, 0 is debit, ignored otherwise

my $now = `date +%C%y%m%d%H%M`;
chomp $now;

# tougher than I thought to pick out a user's home dir..
my $account_dir = `echo \$HOME`;
chomp $account_dir;
$account_dir = $account_dir . "/.brinance/";

switch_acct (); # sets us up to use account0
update_future (); # sync with future transactions

if ( -1 == $#ARGV ) {
	print "Need arguments..\n";
	usage ();
}

# do it now!
main ();

=pod
sub main: process our arguments, and also drive execution
=cut
sub main {
foreach (@ARGV) {
	if ($skipnext) { $where++; $skipnext--; next; }

	elsif ($_ eq "-h" or $_ eq "--help") {
		usage ();
	}
	elsif ($_ eq "-v" or $_ eq "--version") {
		version ();
	}
	elsif ($_ eq "-n" or $_ eq "--name") {
		if ($out = getName ())
		{
			print "account$current_acct name: $out\n";
		}
		else
		{
			print "No name for account$current_acct\n";
		}
	}
	elsif (/^\-[0-9]+$/) {
		$current_acct = -1 * $_; # effectively strips the '-', and gracefully sets invalid values to 0
		if (-1 == switch_acct ())
		{
			print "ERROR: account$current_acct doesn't exist\ncreate first using -r\n";
			usage ();
		}
		update_future ();
		print "Now working with account$current_acct\n";
	}
	elsif ($_ eq "-b" or $_ eq "--balance") {
		print "Balance: " . Number::Format::round (balance ()) . "\n";;
	}
	elsif ($_ eq "-c" or $_ eq "--credit") {
		$credit = 1;
		$out = trans ();
		$bal = Number::Format::round (balance ());

		if ( 0 == $out )
		{
			print "Balance after credit: $bal\n";
			$skipnext = 2; # eat the next next two arguments
		}
		elsif ( -1 == $out )
		{
			print "ERROR: Too few arguments to trans()\n";
			usage ();
		}
		elsif ( -2 == $out )
		{
			print "Ignoring 0-value transaction: $ARGV[$where+2]\n";
		}
		else
		{
			print "ERROR: unrecognized error in trans()\n";
		}
	}
	elsif ($_ eq "-d" or $_ eq "--debit") {
		$credit = 0;
		$out = trans ();
		$bal = Number::Format::round (balance ());

		if (0 == $out)
		{
			# successful
			print "Balance after debit: $bal\n";
			$skipnext = 2; # eat the next next two arguments
		}
		elsif (-1 == $out)
		{
			print "ERROR: Too few arguments to trans()\n";
			usage ();
		}
		elsif (-2 == $out)
		{
			print "Ignoring 0-value transaction: $ARGV[$where+2]\n";
		}
		else
		{
			print "ERROR: unrecognized error in trans()\n";
		}
	}
	elsif ($_ eq "-r" or $_ eq "--create") {
		$out = create ();

		if (1 == $out)
		{
			print "account$ARGV[$where+2] created successfully\n";
			$skipnext = 2;
		}
		elsif (0 == $out)
		{
			print "ERROR: account$ARGV[$where+2] already exists\n";
		}
		elsif (-1 == $out)
		{
			print "ERROR: Too few arguments to create ()\n";
			usage ();
		}
	}
	elsif ($_ eq "-B" or $_ eq "--futurebalance") {
		$out = futurebalance ();

		if (-1 == $out)
		{
			print "ERROR: Too few arguments to futurebalance ()\n";
			usage ();
		}
		elsif (0 == $out)
		{
			print "ERROR: Unable to calculate future balance\n";
		}
		else
		{
			$out = Number::Format::round ($out);
			print "account$current_acct future balance: $out\n";
			$skipnext = 1;
		}
	}
	elsif ($_ eq "-C" or $_ eq "--futurecredit") {
		$credit = 1;
		$out = futuretrans ();

		if (0 == $out)
		{
			#success
			$skipnext = 3;
		}
		elsif (-1 == $out)
		{
			print "ERROR: Too few arguments to futuretrans ()\n";
			usage ();
		}
		elsif (-2 == $out)
		{
			print "Ignoring 0-value transaction: $ARGV[$where+3]\n";
		}
		elsif (-3 == $out)
		{
			print "ERROR: Must specify a *future* date in the format YYYYMMDDHHmm\n";
			print "It is now $now\n";
		}
	}
	elsif ($_ eq "-D" or $_ eq "--futuredebit") {
		$credit = 0;
		$out = futuretrans ();

		if (0 == $out)
		{
			#success
			$skipnext = 3;
		}
		elsif (-1 == $out)
		{
			print "ERROR: Too few arguments to futuretrans ()\n";
			usage ();
		}
		elsif (-2 == $out)
		{
			print "Ignoring 0-value transaction: $ARGV[$where+3]\n";
		}
		elsif (-3 == $out)
		{
			print "ERROR: Must specify a *future* date in the format YYYYMMDDHHmm\n";
			print "It is now $now\n";
		}
	}

	else {
		print "Unrecognized argument: $_\n";
		usage ();
	}

	$where++;
}
} # END main ()

=pod
sub usage: shows how to invoke the command-line program
=cut
sub usage {
	my $exec = basename ($0);

	print "Usage:\n
  \$ $exec <args>\n
  Accepted args:
     -b --balance -> show balance
        \$ $exec -b
     -B --futurebalance -> show future balance
        \$ $exec -B 200306271200
     -c --credit -> credit
        \$ $exec -c <amount> <comment>
     -C --futurecredit -> future credit
        \$ $exec -C 200306271200 <amount> <comment>
     -d --debit -> debit
        \$ $exec -d <amount> <comment>
     -D --futuredebit -> future debit
        \$ $exec -D 200306271200 <amount> <comment>
     -# -> (as in, a number) all following arguments refer to this account
        \$ $exec -2 <action>
     -n --name -> get the name of the active account
        \$ $exec -4 -n
     -r --create -> create a new account
        \$ $exec -r <account description> <account number>
     -h --help -> help
        \$ $exec -h
     -v --version -> version
        \$ $exec -v\n";

	exit (0);
}

=pod
sub version: prints current version of command line program
=cut
sub version {
	print "brinance version 2.0\n";
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
  return values:
   0 - success
  -1 - too few arguments (needs two)
  -2 - zero value transaction, which could mean a non-number was specified as the transaction amount
=cut
sub trans {
	open (ACCOUNT, (">>$account_dir" . "account" . $current_acct)) or die "ERROR: Cannot open file " . $account_dir . "account" . $current_acct;

	if ( ($where+2) > $#ARGV )
	{
		return -1;
	}

	if ($credit) # negate if it's a debit, which will also zero a non-number.. good..
	{
		$ARGV[$where+1] = 1 * $ARGV[$where+1];
	}
	else
	{
		$ARGV[$where+1] = -1 * $ARGV[$where+1];
	}

	if ( 0 == $ARGV[$where+1] )
	{
		return -2;
	}
	else
	{
		# yup, do it.. the guts
		my $amount = $ARGV[$where+1];
		my $comment = $ARGV[$where+2];

		print ACCOUNT "#$now\n";
		print ACCOUNT "#$comment\n";
		print ACCOUNT "$amount\n";
	}

	close ACCOUNT;
	return 0;
}

=pod
sub create: create a new account
  return values:
   1 - success
   0 - account already exists, no change
  -1 - too few arguments, needs 2
=cut
sub create {
	my $worked;

	if ( ($where+2) > $#ARGV )
	{
		return -1;
	}

	my $acct_name = $ARGV[$where+1];
	my $acct_num = $ARGV[$where+2];

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
  return values:
  -1 - too few arguments, needs 1
  else - the future balance
=cut
sub futurebalance {
#FIXME: What if the balance is -1?
	if ( ($where+1) > $#ARGV )
	{
		return -1;
	}

	open (FUTURE, ($account_dir . "future" . $current_acct)) or return 0;

	# date request can be one of two formats
	# either 12 number date or
	# +<days> in the future

	my $rdate;

	if ($ARGV[$where+1] =~ /^\+\d*/)
	{
		(undef, $plus_days) = split (/\+/, $ARGV[$where+1]);
		$rdate = $now + ($plus_days * 10000);
	}
	else
	{
		$rdate = $ARGV[$where+1];
	}

	my $total = balance ();

	while (<FUTURE>)
	{
		if (/^#\d\d\d\d\d\d\d\d\d\d\d\d$/)
		{
			my (undef, $cdate) = split (/#/, $_);
			if ($cdate < $rdate)
			{
				$grabnext = 1; # take the next value to comes up
			}
		}
		elsif (/^#/)
		{
			# must be a transaction comment, ignore it
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
  return values:
  -1 - too few arguments, needs three
  -2 - zero-value transaction
  -3 - time specified is not in the future
=cut
sub futuretrans {
	if ( ($where+3) > $#ARGV )
	{
		# too few arguments
		return -1;
	}

	if ($credit)
	{
		$ARGV[$where+2] = 1 * $ARGV[$where+2];
	}
	else
	{
		$ARGV[$where+2] = -1 * $ARGV[$where+2];
	}

	open (FUTURE, (">>$account_dir" . "future" . $current_acct)) or die "ERROR: Cannot open file " . $account_dir . "future" . $current_acct;

	if ( 0 == $ARGV[$where+2] )
	{
		# 0-value transaction
		return -2;
	}
	else
	{
		#may wax roll

		my $date;
		# support +<days> for specifying date
		if ($ARGV[$where+1] =~ /^\+\d*/)
		{
			(undef, $plus_days) = split (/\+/, $ARGV[$where+1]);
			$date = $now + ($plus_days * 10000);
		}
		else
		{
			$date = $ARGV[$where+1];
		}

		my $amount = $ARGV[$where+2];
		my $comment = $ARGV[$where+3];

		if ( $now >= $date )
		{
			# needs to actually be in the future
			return -3;
		}
		else
		{
			#and roll..

			print FUTURE "#$date\n";
			print FUTURE "#$comment\n";
			print FUTURE "$amount\n";
		}
	}

	close FUTURE;
	return 0;
}

=pod
sub update_future: called before working with an account to apply future transactions if they are now passed
=cut
sub update_future {
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

		if (/^#\d\d\d\d\d\d\d\d\d\d\d\d$/) # our standard date stamp
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

	for ($i = 0; $i < $futures_i; $i++) 
	{
		print ACCOUNT "$futures[$i]\n";
	}

	for ($i = 0; $i < $nfutures_i; $i++)
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