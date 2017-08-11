# Brinance.pm: Perl module for lightweight financial planner/tracker
#
# This software released under the terms of the GNU General Public License 2.0
#
# Copyright (C) 2003-2006 Brian M. Kelly locoburger@gmail.com http://locoburger.org/
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
#       tabstop = 4     (These two lines should line up)
#		tabstop = 4		(These two lines should line up)

use strict;
use warnings;

package Brinance;
require Exporter;

our @ISA = ('Exporter');
our $VERSION = '4.03';
our @EXPORT = qw(	$current_acct $now $account_dir
					&getName &balance &trans &get_accts
					&version &create &switch_acct);

our $current_acct = 0;
our $now;
our $account_dir = "$ENV{HOME}/.brinance";

my %accounts = (); # HoH of account names and last updates times indexed by account number
my %new_accounts = ();
my @transactions = (); # AoH representing all transactions
my @new_transactions = ();
my @futures = (); # AoH patterns and comments found in the futures file

INIT {
	&_setup;
}

END {
	&_writechanges;
}

=pod
sub version: returns current version of Briance module
=cut
sub version {
	return $VERSION;
}

=pod
sub getName: returns the name of the current account, or undef if there is no valid name
=cut
sub getName {
	if (defined $accounts{$current_acct}) {
		return $accounts{$current_acct}->{'name'} ne '' ? $accounts{$current_acct}->{'name'} : undef;
	} elsif (defined $new_accounts{$current_acct}) {
		return $new_accounts{$current_acct}->{'name'} ne '' ? $new_accounts{$current_acct}->{'name'} : undef;
	} else {
		return undef;
	}
}

=pod
sub balance: returns the balance of the current account
=cut
sub balance {
	my ($date_req) = @_;
	unless (defined $date_req and ($date_req =~ /^\d{12}$/)) {
		&_renow;
		$date_req = $now;
	}

	my $total = 0;
	foreach my $t (@transactions, @new_transactions) {
		$total += $t->{'amount'}
			if	$t->{'type'} eq 'transaction' and
				$t->{'account'} == $current_acct and
				$t->{'date'} <= $date_req;
	}

	if ($date_req > $now) {
		foreach my $fut (@futures) {
			my @dates = ();
			if (($fut->{'type'} eq 'pattern') and ($fut->{'account'} == $current_acct)) {
				@dates = &_calc_future_patterns ($fut->{'year'}, $fut->{'month'}, $fut->{'day'},
				$fut->{'day_logic'}, $fut->{'dayow'}, $fut->{'hour'}, $fut->{'min'}, $fut->{'origin'},
				$now, $date_req);

				foreach my $date (@dates) {
					$total += $fut->{'amount'};
				}
			}
		}
	}

	return $total;
}

=pod
sub trans: applies a transaction to the current account, either credit or debit
  usage: &Brinance::trans ( $amount, $comment, <$date> )
  return values:
   0 - success
  -1 - too few arguments (needs at least two)
  -2 - zero value transaction, which could mean a non-number was specified as the transaction amount
  -3 - invalid date specified
=cut
sub trans {
	if (2 > scalar @_) {
		return -1; # too few arguments
	}

	my ($amount, $comment, $req_date) = @_;

	$amount += 0; # to make sure its numeric
	if (0 == $amount) { # zero value transacrion
		return -2;
	}

	if ($req_date) { # was a date specified?
		unless ($req_date =~ /^\d{12}$/) { # invalid date format
			return -3;
		}
	} else {
		&_renow;
		$req_date = $now;
	}

	push @new_transactions,	{
		'date' => $req_date,
		'account' => $current_acct,
		'amount' => $amount,
		'comment' => $comment,
		'type' => 'transaction',
	};

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
sub create {
	if (2 > scalar @_) {
		return -1;
	}

	my ($acct_name, $acct_num) = @_;
	$acct_num += 0; #Make it numeric

	if (defined $accounts{$acct_num} or defined $new_accounts{$acct_num}) {
		return 1;
	} else {
		&_renow;
		$new_accounts{$acct_num}->{'name'} = $acct_name;
		$new_accounts{$acct_num}->{'updated'} = $now;
	}

	return 0;
}

=pod
sub switch_acct: safety for switching account, give a failure if the account isn't initialized
  return values:
   1 - created account 0; won't auto-create any other account
   0 - success
  -1 - failed, account doesn't exist
=cut
sub switch_acct {
	($current_acct) = @_;
	$current_acct += 0;

	if (defined $accounts{$current_acct} or defined $new_accounts{$current_acct}) {
		&_update_futures;
		return 0;
	} elsif ($current_acct == 0) { # create account 0 named "default"
		&_renow;
		$new_accounts{0}->{'name'} = 'default';
		$new_accounts{0}->{'updated'} = $now;
		&_update_futures;
		return 1;
	} else { # account not found
		return -1;
	}
}

=pod
sub get_accts: returns a list of numbers of all accounts
=cut
sub get_accts {
	my @list = sort {$a <=> $b} (keys %accounts, keys %new_accounts);
	return @list;
}

=pod
INTERNAL
sub _renow: re-initialize $now, used before any time-dependant functions
=cut
sub _renow {
	my ($min, $hour, $mday, $mon, $year) = (localtime(time))[1,2,3,4,5];

	$year += 1900;
	$mon += 1;

	if ($mon  < 10) { $mon  = '0' . $mon; }
	if ($mday < 10) { $mday = '0' . $mday; }
	if ($hour < 10) { $hour = '0' . $hour; }
	if ($min  < 10) { $min  = '0' . $min; }

	$now = $year . $mon . $mday . $hour . $min;
}

=pod
INTERNAL
sub _update_futures: called before working with an account to apply future transactions if they are now in the past
=cut
sub _update_futures {
	foreach my $fut (@futures) {
		my @dates = ();
		if ($fut->{'type'} eq 'pattern' and $fut->{'account'} == $current_acct) {
			&_renow;
			@dates = &_calc_future_patterns (
				$fut->{'year'},
				$fut->{'month'},
				$fut->{'day'},
				$fut->{'day_logic'},
				$fut->{'dayow'},
				$fut->{'hour'},
				$fut->{'min'},
				$fut->{'origin'},
				$accounts{$current_acct}->{'updated'},
				$now,
			);

			foreach my $date (@dates) {
				push @new_transactions,	{
					'date' => $date,
					'amount' => $fut->{'amount'},
					'account' => $fut->{'account'},
					'comment' => $fut->{'comment'},
					'type' => 'transaction',
				};
			}
		}
	}

	$accounts{$current_acct}->{'updated'} = $now;

	return;
}

=pod
INTERNAL
sub _calc_future_patterns: processes patterns lines in futures file between last_update and now
=cut
sub _calc_future_patterns {
	unless (10 == scalar @_) {
		return ();
	}

	my (
		$year,
		$month,
		$day,
		$day_logic,
		$dayow,
		$hour,
		$min,
		$origin,
		$from_date,
		$to_date,
	) = @_;

	$hour = (length $hour) eq 1 ? '0' . $hour : $hour;
	$min = (length $min) eq 1 ? '0' . $min : $min;

	$from_date =~ /^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)$/;
	my ($from_year, $from_month, $from_day, $from_hour, $from_min) = ($1, $2, $3, $4, $5);
	my $from_dayow = &_get_dayow($from_year, $from_month, $from_day);

	$to_date =~ /^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)$/;
	my ($to_year, $to_month, $to_day, $to_hour, $to_min) = ($1, $2, $3, $4, $5);
	my $to_dayow = &_get_dayow($to_year, $to_month, $to_day);

	$day_logic = '|' unless $day_logic;

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

	# we'll only calculate to a day's granularity;
		# tack on the hour and min as the time, but it doesn't affect the calculation
	my %years = &_gen_list ($year);
	my %months = &_gen_list ($month);
	my %days = &_gen_list ($day);
	my %dayows = &_gen_list ($dayow);

	my @return_dates = ();
	my $current_date = $from_year . $from_month . $from_day;
	while ($current_date <= $to_year . $to_month . $to_day) {
		unless ($current_date =~ /^(\d{4})(\d\d)(\d\d)$/) {
			next;
		}
		my ($year_req, $month_req, $day_req, $hour_req, $min_req, $dayow_req) =
			($1, $2, $3, $hour, $min, &_get_dayow($1, $2, $3));

		my $curr = 1; # whether this date is a go
		if (%years) {
			$curr = 0 unless $years{$year_req};
		}
		if (%months) {
			$curr = 0 unless $months{$month_req};
		}

		if ($day_logic eq '|') {
			if (%days) {
				if (%dayows) {
					$curr = 0 unless ($days{$day_req} or $dayows{$dayow_req});
				}
				else {
					$curr = 0 unless $days{$day_req};
				}
			} elsif (%dayows) {
				$curr = 0 unless $dayows{$dayow_req};
			}
		} elsif ($day_logic eq '&') {
			if (%days) {
				$curr = 0 unless $days{$day_req};
			}
			if (%dayows) {
				$curr = 0 unless $dayows{$dayow_req};
			}
		} else {
			# Invalid day logic
			return;
		}

		foreach (keys %dayows) {
			# *** if we have a periodic request ***
			if (/\d+\/(\d+)/) { # determine the divisor (x/<divisor>)
				my $divisor = $1;

				my $calc_period = 7 * $divisor; # determine the period (in the current units)
				# calc_period = period * divisor (in current units)
				#FIXME: only works for weeks right now.. maybe forever..
				# keep adding calc_period to origin until we hit requested date (leave curr alone)
					# or we go past (curr = 0)
				my $calc_date = $origin;
				while ($calc_date < $current_date) {
					$calc_date = &_add_date($calc_date, $calc_period);
				}

				if ($calc_date == $current_date) {
					$curr = 1;
				}
			}
		}

		if ($curr) {
			if ($to_year . $to_month . $to_day eq $year_req . $month_req . $day_req) {
				#FIXME: reset hour and min to zero if from is before req day
				# hmm.. not right.. seems to keep finding it in future balances
				if ($from_year . $from_month . $from_day < $year_req . $month_req . $day_req) {
					$from_hour = '00';
					$from_min = '00';
				}

				if (($from_hour . $from_min) <= ($hour_req . $min_req) and
						($to_hour . $to_min) >  ($hour_req . $min_req)) {
					push (@return_dates, ($year_req . $month_req . $day_req . $hour_req . $min_req));
				}
			} else {
				push (@return_dates, ($year_req . $month_req . $day_req . $hour_req . $min_req));
			}
		}
		$current_date = &_add_date($current_date, 1);
	}

	my @final_dates = ();
	foreach my $rd (@return_dates) {
		if ($rd > $from_date and $rd <= $to_date) {
			push @final_dates, $rd;
		} else {
			#FIXME: get an outside range error here..
			#warn "$rd outside of range: $from_date to $to_date";
		}
	}

	return @final_dates;
}

=pod
INTERNAL
sub _get_dayow returns numeric day-of-week (0-6) based on numeric year, month, and day
=cut
sub _get_dayow {
	my ($y,$m,$d) = @_;

	my $ypart = ($y % 100) + int((($y % 100) / 4));
	my @mpart = (0,6,2,2,5,0,3,5,1,4,6,2,4);
	my $dpart = $d;
	my $total = $ypart + $mpart[$m] + $dpart;
	if (int($y/100) == 19) { $total += 1; }
	if (($y % 4) == 0) {
	    if (($m == 1) or ($m == 2)) { $total -= 1; }
	}

	while ($total > 6) { $total -= 7; }

	return $total;
}

=pod
INTERNAL
sub _gen_list takes a string of comma seperated, dash-indicated ranges and returns all the valid values in a hash
 i.e. "2-5,7,8,12-15" returns hash of 2,3,4,5,7,8,12,13,14,15 all set to 1
=cut
sub _gen_list {
	my %items = ();
	my ($item) = @_;

	unless ($item eq '*') { # leave %items uninitialized if so
		my @holder = split (/,/, $item);
		foreach (@holder) {
			unless (/-/) {
				$items{$_} = 1;
			} else {
				my ($start, $end) = split (/-/);
				if ($start < $end) {
					while ($start <= $end) {
						$items{$start++} = 1;
					}
				} else {
					die "ERROR: item \$start:$start not before \$end:$end";
				}
			}
		}
	}
	return %items;
}

=pod
INTERNAL
sub _setup populates %accounts and @transactions
=cut
sub _setup {
	&_renow;

	unless (open (ACCOUNT, "$account_dir/accounts")) {
		&_initial_setup;
		return;
	} else {
		while (<ACCOUNT>) {
			chomp;
			if (/^ACCOUNT (\d+):?(.*)$/) {
				my ($num, $name) = ($1, $2);
				if (defined $name) {
					$name =~ s/^\s+//;
				} else {
					$name = '';
				}
				$accounts{$num} = {};
				$accounts{$num}->{'name'} = $name;
			} elsif (/^(\d{12})\s+(\d+)\s+([-\d\.]+)\s+(.*)$/) {
				my ($date, $account, $amount, $comment) = ($1, $2, $3, $4);
				push @transactions, {
					'date' => $date,
					'account' => $account,
					'amount' => $amount,
					'comment' => $comment,
					'type' => 'transaction',
				};
			} else {
				push @transactions, {
					'line' => $_,
					'type' => 'comment',
				};
			}
		}
		close ACCOUNT;

		open (FUTURE, "$account_dir/futures") or return;
		while (<FUTURE>) {
			chomp;
			if (/^ACCOUNT (\d+): (\d{12})$/) {
				if (defined $accounts{$1}) {
					$accounts{$1}->{'updated'} = $2;
				} else {
					die 'ERROR: account mismatch between accounts and futures for account ' . $1;
				}
			} elsif (/^
					(\S+)\s+	# year
					(\S+)\s+	# month
					(\S+)\s+	# day
					([|&]?)\s*	# day logic, or not, followed by space or not
					(\S+)\s+	# day of the week (dayow)
					(\S+)\s+	# hour
					(\S+)\s+	# minute
					:(\d*):\s+	# origin surrounded by colons
					(\d+)\s+	# account number
					(-?[\.\d]+)	# transaction amount
					\s+(.+)		# transaction comment
					$/x) {
				push @futures, {
					'line'		=> $_,
					'type'		=> 'pattern',
					'year'		=> $1,
					'month'		=> $2,
					'day'		=> $3,
					'day_logic'	=> $4 ? $4 : '|',
					'dayow'		=> $5,
					'hour'		=> $6 < 10 ? '0'.$6 : $6,
					'min'		=> $7 < 10 ? '0'.$7 : $7,
					'origin'	=> $8,
					'account'	=> $9,
					'amount'	=> $10,
					'comment'	=> $11,
				};
			} else {
				push @futures, {
					'line'		=> $_,
					'type'		=> 'comment',
				};
			}
		}
		close FUTURE;
	}
}

=pod
INTERNAL
sub _writechanges writes new accounts file if there's been a change
=cut
sub _writechanges {
	if (keys %new_accounts) {
		open (ACCOUNT, ">$account_dir/accounts") or
			die "ERROR: Cannot open file $account_dir/accounts for writing: $!";

		foreach (sort {$a <=> $b} (keys %accounts, keys %new_accounts)) {
			if (defined $accounts{$_}) {
				if ($accounts{$_}->{'name'} ne '') {
					print ACCOUNT "ACCOUNT $_: " . $accounts{$_}->{'name'} . "\n";
				} else {
					print ACCOUNT "ACCOUNT $_\n";
				}
			} elsif (defined $new_accounts{$_}) {
				if ($new_accounts{$_}->{'name'} ne '') {
					print ACCOUNT "ACCOUNT $_: " . $new_accounts{$_}->{'name'} . "\n";
				} else {
					print ACCOUNT "ACCOUNT $_\n";
				}
			}
		}

		foreach (@transactions, @new_transactions) {
			if ($_->{'type'} eq 'transaction') {
				print ACCOUNT $_->{'date'} ."\t". $_->{'account'} ."\t". $_->{'amount'} ."\t". $_->{'comment'} ."\n";
			} elsif ($_->{'type'} eq 'comment') {
				print ACCOUNT $_->{'line'} ."\n";
			}
		}
		close ACCOUNT;

	} elsif (@new_transactions) {
		open (ACCOUNT, ">>$account_dir/accounts") or
			die "ERROR: Cannot open file $account_dir/accounts for appending: $!";

		foreach (@new_transactions) {
			if ($_->{'type'} eq 'transaction') {
				print ACCOUNT $_->{'date'} ."\t". $_->{'account'} ."\t". $_->{'amount'} ."\t". $_->{'comment'} ."\n";
			} elsif ($_->{'type'} eq 'comment') {
				print ACCOUNT $_->{'line'} ."\n";
			}
		}

		close ACCOUNT;
	}

	# We will always have some futures updates, because we indicate the last time each account was accessed
	open (FUTURE, ">$account_dir/futures") or
		die "ERROR: Cannot open file $account_dir/futures for writing: $!";

	&_renow;

	foreach (sort {$a <=> $b} (keys %accounts, keys %new_accounts)) {
		if (defined $accounts{$_}) {
			$accounts{$_}->{'updated'} = $now unless $accounts{$_}->{'updated'};
			print FUTURE "ACCOUNT $_: " . $accounts{$_}->{'updated'} . "\n";
		} elsif (defined $new_accounts{$_}) {
			$accounts{$_}->{'updated'} = $now unless $accounts{$_}->{'updated'};
			print FUTURE "ACCOUNT $_: " . $new_accounts{$_}->{'updated'} . "\n";
		}
	}

	foreach (@futures) {
		print FUTURE $_->{'line'} . "\n";
	}
	close FUTURE;
}

=pod
INTERNAL
sub _initial_setup: called when accounts file doesn't exist (never been run before)
=cut
sub _initial_setup {
	&_renow;

	$new_accounts{0}->{'name'} = 'default';
	$new_accounts{0}->{'updated'} = $now;

	return;
}

=pod
INTERNAL
add days to the given date and return the new date
=cut
sub _add_date {
	my ($date, $added) = @_;

	$date =~ /^(\d{4})(\d\d)(\d\d)$/;

	my $year = $1;
	my $month = $2;
	my $day = $3;

	# Make sure it's all numeric so the hash below works and our comparisons are valid
	$day += $added;
	$month *= 1;

	# months are crazy go nuts..
	# I couldn't find a an easy-enough to use package to do this, so I wrote it myself, no doubt introducing numerous bugs..
	my %months = (
		1 => 31, 2 => 28, 3 => 31,
		4 => 30, 5 => 31, 6 => 30,
		7 => 31, 8 => 31, 9 => 30,
		10 => 31, 11 => 30, 12 => 31,
	);

	my $leap = 0;

	while ($day > $months{$month}) {
		if ($month == 2 && (($year % 4) == 0)) {
			if (29 == $day) {
				$leap = 1;
				$day = 28; # so we don't get stuck in the loop, we'll set it back to 29 later
			} else {
				$day -= 29;
				$month++;
			}
		} else {
			$day -= $months{$month};
			$month++;
		}

		while ($month > 12) {
			$month -= 12;
			$year++;
		}
	}

	if ($leap) {
		$day = 29;
		$leap = 0;
	}

	while ($month > 12) {
		$month -= 12;
		$year++;
	}

	if ($year > 9999) {
		print STDERR "WARNING: Calculated year is huge: $year\n";
		$year = 9999;
	}

	$month *= 1; $day *= 1;

	if ($month < 10) {
		$month = '0' . $month;
	}

	if ($day < 10) {
		$day = '0' . $day;
	}

	return $year . $month . $day;
}

=pod
DEPRECATED
sub datedbalance: determines balance at given future time
  usage: &Brinance::datedbalance ( $date )
  return balance at $date
=cut
sub datedbalance {
	return &balance (@_);
}

=pod
DEPRECATED
sub datedtrans: applies a transaction at specified future time
  usage: &Brinance::datedtrans ( &date, $amount, $comment )
  return values:
   0 - success
  -1 - too few arguments, needs three
  -2 - zero-value transaction
=cut
sub datedtrans {
	# trans takes the date last, datedtrans took it first, so we need to switch things around
	if (defined $_[0] and defined $_[1] and defined $_[2]) {
		return &trans ($_[1], $_[2], $_[0]);
	} else {
		return -1;
	}
}

=pod
DEPRECATED
sub update_futures: used to update accounts with future patterns from futures file
now this is done implicitly with switch_acct
=cut
sub update_futures {
	return;
}

1;
