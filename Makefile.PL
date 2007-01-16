require 5.004;
use ExtUtils::MakeMaker;

WriteMakefile(
	'NAME' => 'EasySession',
	'VERSION_FROM'	=>	'EasySession.pm',
	'PREREQ_PM'     => {
 	},
	dist		=>	{ COMPRESS => 'gzip -9f', SUFFIX => '.gz'}
);

