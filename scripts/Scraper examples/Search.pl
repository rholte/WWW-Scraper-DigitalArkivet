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
my $index;
my $mode=1; #0->dump 1->dumpTree


# New  kb !!!!
#kirkebok
$site{'url'}    = "https://media.digitalarkivet.no/kb/contents/11448";
$site{'name'}   = "kb_contents-11448";
&DA_kb_contents($site{'url'}, $site{'name'});

#tinglyst
#https://media.digitalarkivet.no/view/63061
#folketelling
# https://media.digitalarkivet.no/ft/contents/38049

## Old kb !!!!!
$site{'url'}    = "http://www.arkivverket.no/URN:kb_read?idx_id=11448";
$site{'name'}   = "kb_read-11448";
&DA_kb_read($site{'url'}, $site{'name'});

#http://www.arkivverket.no/URN:db_read/ft/38105
#http://www.arkivverket.no/URN:db_read/db/42182

#skannet
$site{'url'}    = "http://www.arkivverket.no/URN:db_read/ft/38049";
$site{'name'}   = "db_read-38049";
&DA_db_read($site{'url'}, $site{'name'});

#
$site{'url'}    = "http://www.arkivverket.no/URN:db_read/db/42182";
$site{'name'}   = "db_read-42182";
&DA_db_read($site{'url'}, $site{'name'});

#NA
#$site{'url'}    = "http://www.arkivverket.no/URN:tl_read?idx_id=63061";
#$site{'name'}   = "tl_read-63061;
#&DA_tl_read($site{'url'}, $site{'name'});

#$site{'url'}    = "";
#$site{'name'}   = "_read-;
#&DA_read($site{'url'}, $site{'name'});

sub DA_kb_contents {
    my $site_url  = shift;
    my $site_name = shift;

        # main scraper object
        $index = scraper {
            process 'div.searchresult','page' => scraper {
                #process 'h3', 'h3[]' => 'TEXT';
                #process 'h4', 'h4[]' => 'TEXT';
                process 'h5', 'h5[]' => 'TEXT';
                process 'table > tr', 'row[]' => scraper {
                    process 'td.w10', 'span' => 'TEXT';
                    process 'td > a', 'pages[]' => 'TEXT', 'url[]'  => '@href';
                }; # search redundant?

            };
            process 'div.source-info','source' => scraper {
                process 'h3.clipboard-meta', 'source-h3[]' => 'TEXT';
                process 'span.clipboard-tab', 'source-span[]' => 'TEXT';
            };
            result 'page'; # res == page
        };
        $res = $index->scrape( URI->new( $site_url ) );
        &printDump($res);
};

sub DA_db_read {
    my $site_url  = shift;
    my $site_name = shift;

        # main scraper object
        $index = scraper {
            process 'div.genericBody','page' => scraper {
                process 'h2', 'h2[]' => 'TEXT';
                process 'table > tr', 'row[]' => scraper {
                    process 'td', 'p[]' => 'TEXT';
                    process 'a', 'page' => 'TEXT', 'url'  => '@href';
                }; # search redundant?

            };
            result 'page'; # res == page
        };
        $res = $index->scrape( URI->new( $site_url ) );
        &printDump($res);
};

sub DA_kb_read {
    my $site_url  = shift;
    my $site_name = shift;

        # main scraper object
    $index = scraper {
            process 'table > tr','row[]' => scraper {
                process 'td', 'type' => 'TEXT';
                process 'td > a', 'yearPage[]' => 'TEXT','url[]'  => '@href';
            };
            #result 'row'; # res == row
    };
    $res = $index->scrape( URI->new( $site_url ) );
    &printDump($res);
};

sub printDump {
    print "\n";
    print "--------------------------------\n";
    print "---         Dump data        ---\n";
    print "--------------------------------\n";
    print Dumper($_[0]) unless $mode;
    print DumpTree ($_[0], 'Page') if $mode;
    print "\n";
    print "--------------------------------\n";
    print "---            End           ---\n";
    print "--------------------------------\n";
}


1;
