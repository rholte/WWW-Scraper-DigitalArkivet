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


# NEW !!!!
$site{'url'}    = "https://media.digitalarkivet.no/kb/contents/11448";
$site{'name'}   = "Index-11448";
&DAindex($site{'url'}, $site{'name'});

## OLD !!!!!
$site{'url'}    = "http://www.arkivverket.no/URN:kb_read?idx_id=11448";
$site{'name'}   = "Index-old-11448";
&DAindexOLD($site{'url'}, $site{'name'});


sub DAindex {
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
        print "\n";
        print "--------------------------------\n";
        print "---       Dump data       ---\n";
        print "--------------------------------\n";
        #print Dumper(\$res);
        print DumpTree ($res, 'Page');
        print "\n";
        print "--------------------------------\n";
        print "---            End           ---\n";
        print "--------------------------------\n";

};

sub DAindexOLD {
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
    print "\n";
    print "--------------------------------\n";
    print "---       Dump OLD data       ---\n";
    print "--------------------------------\n";
    #print Dumper(\$res);
    print DumpTree ($res, 'Row');
    print "\n";
    print "--------------------------------\n";
    print "---            End           ---\n";
    print "--------------------------------\n";
};





1;
