use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
	'NAME' => 'Brinance',
	'VERSION_FROM' => 'lib/Brinance.pm',
	'EXE_FILES' => [
		'bin/brinance',
	],
	'PREREQ_PM' => {
		'Date::Calc' => '5.4',
		'IO::Prompt::Tiny' => '0.003',
	},
	'PREREQ_PRINT' => 1,
);
