#!/usr/bin/perl
use strict;
use warnings;

use URI;
use Web::Scraper;
use Data::Dumper::Simple;

$| = 1;

my %site;
my @res;
my $i;
my $j;
my $label_for;
my @scrape;
my ($name,$text, $value,$id, $type, @row);


#$site{'siteID'} = 1;
$site{'url'}    = "http://digitalarkivet.arkivverket.no/finn_kilde";
$site{'name'}   = "finn_kilde";

open CSV, ">$site{'name'}.dat" or die $!;
my $seperator = ";";

$scrape[0] = scraper {
    process 'div.listGroup.open > ul.grouped > li.expandable',
      'data[]' => scraper {
        process 'input',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
        process 'label',              'label_for' => '@for';
        process 'span.listExpander ', 'text'      => 'TEXT';
      };
};

$scrape[1] = scraper {
    process 'ul.sublist1 > li', 'data[]' => scraper {
        process 'input',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
        process 'label', 'label_for' => '@for';
        process 'span',  'text'      => 'TEXT';
    }
};

$scrape[2] = scraper {
    process 'ul.sublist2 > li', 'data[]' => scraper {
        process 'input',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
        process 'label', 'label_for' => '@for';
        process 'span',  'text'      => 'TEXT';
    }
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
    sleep(2);
}
close CSV;
print "\n";
print "--------------------------------\n";
print "---       Dump av data       ---\n";
print "--------------------------------\n";
print Dumper(\@res);

1;
