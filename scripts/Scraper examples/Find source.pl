#!/usr/bin/perl
use strict;
use warnings;

use URI;
use Web::Scraper;
#use Data::Dumper::Simple;
use Data::Dumper::Perltidy;
use Data::TreeDumper;

$| = 1;

my %site;
my @res;
my $i;
my $j;
my $label_for;
my @scrape;
my ($name,$text, $value,$id, $type, @row);
my $dumpMode=1;  #0->dump 1->dumpTree

#$site{'siteID'} = 1;
$site{'url'}    = "http://digitalarkivet.arkivverket.no/finn_kilde";
$site{'name'}   = "finn_kilde";

open CSV, ">$site{'name'}.dat" or die $!;
my $seperator = ";";

my $inputLabel = scraper {
        process 'input',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
        process 'label',              'label_for' => '@for';
        process 'span.listExpander ', 'text'      => 'TEXT';
      };

$scrape[0] = scraper {
    process 'div.listGroup.open > ul.grouped > li.expandable',
      'data[]' => $inputLabel;
};

$scrape[1] = scraper {
    process 'ul.sublist1 > li', 'data[]' => $inputLabel;
};

$scrape[2] = scraper {
    process 'ul.sublist2 > li', 'data[]' => $inputLabel;
};

for $i ( 0 .. $#scrape ) {
    $res[$i] = $scrape[$i]->scrape( URI->new( $site{'url'} ) );
    unless ($i) {
        print CSV
          join( $seperator, "label_for", "text", "name", "value", "id", "type" )
          . "\n";
    }
    for $j ( 0 .. $#{ $res[$i]->{data} } ) {
        if ( defined( $res[$i]->{data}[$j]->{label_for} ) ) {
            $label_for = $res[$i]->{data}[$j]->{label_for};
        }
        else {
            $label_for = "";
        }
        if ( length($label_for) > 0 ) {
            $name  = defined $res[$i]->{data}[$j]->{name}  ? $res[$i]->{data}[$j]->{name}  : '';
            $text  = defined $res[$i]->{data}[$j]->{text}  ? $res[$i]->{data}[$j]->{text}  : '';
            $value = defined $res[$i]->{data}[$j]->{value} ? $res[$i]->{data}[$j]->{value} : '';
            $id    = defined $res[$i]->{data}[$j]->{id}    ? $res[$i]->{data}[$j]->{id}    : '';
            $type  = defined $res[$i]->{data}[$j]->{type}  ? $res[$i]->{data}[$j]->{type}  : '';
            @row   = ( $label_for, $text, $name, $value, $id, $type );
            #if ( $i == 1 ) {
            #    print "$name\t$text\t$value\t$id\t$type\n";
            #}
            print CSV join( $seperator, @row );
            print CSV "\n";
        }
    }
    sleep(5);
}
close CSV;

print "\n";
print "--------------------------------\n";
print "---         Dump data        ---\n";
print "--------------------------------\n";
print Dumper(\@res) unless $dumpMode;
print DumpTree (\@res, 'Page') if $dumpMode;
print "\n";
print "--------------------------------\n";
print "---            End           ---\n";
print "--------------------------------\n";

1;
