#!perl

use Test::More tests => 1;

BEGIN {
    use_ok('Brinance');
}

diag( "Testing Brinance $Brinance::VERSION, Perl $], $^X" );
