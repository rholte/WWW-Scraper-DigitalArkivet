# -*- perl -*-

# t/002_load.t - check module loading and create testing directory

use Test::More tests => 2;

BEGIN { use_ok( 'WWW::Scraper::DigitalArkivet::Database' ); }

my $object = WWW::Scraper::DigitalArkivet::Database->new ();
isa_ok ($object, 'WWW::Scraper::DigitalArkivet::Database');


