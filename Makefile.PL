

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

#WriteMakefile(
#    NAME         => 'WWW::Scraper::DigitalArkivet::Database',
#    VERSION_FROM => 'lib/WWW/Scraper/DigitalArkivet/Database.pm', # finds \$VERSION
#    AUTHOR       => 'Rolf B. Holte (rolfbh@disnorge.no)',
#    ABSTRACT     => 'Library for routines to web scrape DigitalArkivet',
#    PREREQ_PM    => {
#                     'Test::Simple' => 0.44,
#					 'Config::Simple'=> 4.58,
#					 'DBI' => 1.630
#					#''  => ,
#                    },
#);

WriteMakefile(
    NAME         => 'WWW::Scraper::DigitalArkivet',
    VERSION_FROM => 'lib/WWW/Scraper/DigitalArkivet.pm', # finds \$VERSION
    AUTHOR       => 'Rolf B. Holte (rolfbh@disnorge.no)',
    ABSTRACT     => 'Library for routines to web scrape DigitalArkivet',
    PREREQ_PM    => {
                     'Test::Simple' => 0.44,
					 'Web::Scraper' => 0.37,
					 'Text::Trim'  => 1.02,
					 'WWW::Scraper::DigitalArkivet::Database'  =>  0.00
					#''  => ,
                    },
);
