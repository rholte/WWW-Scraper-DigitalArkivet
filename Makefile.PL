

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'WWW::Scraper::DigitalArkivet',
    VERSION_FROM => 'lib/WWW/Scraper/DigitalArkivet.pm', # finds \$VERSION
    AUTHOR       => 'Rolf B. Holte (rolfbh@disnorge.no)',
    ABSTRACT     => 'Library for routines to web scrape metadata',
    PREREQ_PM    => {
                     'Test::Simple' => 0.44,
                    },
);
