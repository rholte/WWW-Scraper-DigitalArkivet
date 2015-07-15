# -*- perl -*-

# t/001_load.t - check module loading and create testing directory

use Test::More tests => 2;

BEGIN { use_ok( 'WWW::Scraper::DigitalArkivet' ); }

my $object = WWW::Scraper::DigitalArkivet->new ();
isa_ok ($object, 'WWW::Scraper::DigitalArkivet');


