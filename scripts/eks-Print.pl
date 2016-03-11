#!/usr/bin/perl
use strict;
use warnings;

use URI;
use Web::Scraper;
use Data::Dumper::Simple;

$| = 1;

my %site;
my $res;
my $print;
#my ($date, $url, $src, $at, $ath, $tmp, @row);

$site{'url'}    = "http://digitalarkivet.arkivverket.no/kilde/11448";
$site{'name'}   = "Print-11448";
&DAprint($site{'url'}, $site{'name'});

$site{'url'}    = "http://digitalarkivet.arkivverket.no/kilde/11755";
$site{'name'}   = "Print-11755";
&DAprint($site{'url'}, $site{'name'});

sub DAprint {
    my $site_url  = shift;
    my $site_name = shift;

        # sub container object
        my $tableData = scraper {
                process 'td:nth-child(1)', 'label1' => 'TEXT';
                process 'td:nth-child(2)', 'value1' => 'TEXT';
                process 'td:nth-child(3)', 'label2' => 'TEXT';
                process 'td:nth-child(4)', 'value2' => 'TEXT';
        };
        # main scraper object
        $print = scraper {
            process 'div.contentContainer','page' => scraper {
                process 'ul > li > ul > li', 'search[]' => scraper {
                    process 'a', 'link' => 'TEXT', 'url'  => '@href';
                }; # search redundant?
                process 'ul > li > a', 'link[]' => 'TEXT', 'url[]'  => '@href';
                process 'h4', 'h4[]' => 'TEXT';
                process 'h3', 'h3[]' => 'TEXT';
                process 'div.contentHeader > h1', 'title' => 'TEXT';
                process 'table.infotable', 'data[]'  => scraper {
                    process 'tr', 'table[]' => $tableData;
                };
            };
            result 'page'; # res == page
        };

    #scraper structure
    # X->data[]{url}  # a-href
    # X->data[]{src}  # a-text
    # X->txt[]        # li-text

    $res = $print->scrape( URI->new( $site_url ) );

    print "\n";
    print "--------------------------------\n";
    print "---       Dump av data       ---\n";
    print "--------------------------------\n";
    print Dumper(\$res);
    print "\n";
    print "--------------------------------\n";
    print "---            End           ---\n";
    print "--------------------------------\n";
}

1;
