#!/usr/bin/perl
use strict;
use warnings;

use URI;
use Web::Scraper;
use Data::Dumper::Perltidy;
use Data::TreeDumper;


$| = 1;

my %site;
my $res;
my $i;
my $x;
my $scrape;
my ($date, $url, $src, $at, $ath, $tmp, @row);
my $dumpMode=1;  #0->dump 1->dumpTree


$site{'url'}    = "http://www.arkivverket.no/arkivverket/Digitalarkivet/Om-Digitalarkivet/Nyhetsarkiv/Siste-100";
$site{'name'}   = "Siste-100";

open CSV, ">$site{'name'}.csv" or die $!;
my $seperator = ";";

$scrape = scraper {
    process 'div.oneCol > ol.numberList > li',
    'data[]' => scraper {
        process 'li > a', 'url' => '@href';
        process 'li > a', 'src' => 'TEXT';
    };
    process 'div.oneCol > ol.numberList > li','txt[]' => 'TEXT';
};

#scraper structure
# X->data[]{url}  # a-href
# X->data[]{src}  # a-text
# X->txt[]        # li-text

$res = $scrape->scrape( URI->new( $site{'url'} ) );
print CSV join( $seperator, "date", "url", "source", "at", "author"). "\n";
for $i ( 0 .. $#{$res->{data}} ) {
    $url  = $res->{data}[$i]->{url};
    $src  = $res->{data}[$i]->{src};
    $tmp  = $res->{txt}[$i];
    $tmp =~ s/\Q$src\E/''/ge; # \Q \E Enables to treat string as chars
    ($date, $at, $ath) = split (/\s+/,$tmp,3); #split into 3 bits on space
    @row   = ( $date, $url, $src, $at, $ath );
    print "$date\t$url\t$src\t$at\t$ath\n";
    print CSV join( $seperator, @row );
    print CSV "\n";
}

close CSV;
print "\n";
print "--------------------------------\n";
print "---         Dump data        ---\n";
print "--------------------------------\n";
print Dumper($res) unless $dumpMode;
print DumpTree ($res, 'Page') if $dumpMode;
print "\n";
print "--------------------------------\n";
print "---            End           ---\n";
print "--------------------------------\n";

1;
