#!/usr/bin/perl
#-----------------------------------------------------------------------------
use constant { true => 1, false => 0 };
use strict;
use warnings;
use Benchmark;
use Config::Simple;
use Data::Dumper::Simple;
use Getopt::Std;
use Pod::Usage;
use URI;
use WWW::Scraper::DigitalArkivet  qw/&processFormInput/;
use WWW::Scraper::DigitalArkivet::Database qw/&DBIForm2DB/;
use 5.008001;
$| = 1;

my (@data, @input);
my (%cfg, %Option, %site);

# import into %cfg hash:
Config::Simple->import_from( 'DigitalArkivet.cfg', \%cfg );
#
my $gDebug = $cfg{'Debug.debug'};
my $seperator = $cfg{'Option.seperator'};
my $noDB = exists $cfg{'Option.NoDB'} ?  $cfg{'Option.NoDB'} : false;  #defaults to false -> store to database

# command line options
getopt('dhm', \%Option);
# options (actions) for script
my $gHelp     = exists $Option{h} ? $Option{h} : false; # h - help     # use -h [1]/0
my $gMan      = exists $Option{m} ? $Option{m} : false; # m - manual   # use -m [1]/0
my $dbStorage = exists $Option{d} ? $Option{d} : $noDB; # d - database # use -d [1]/0
pod2usage(-verbose => 1)  if ($gHelp);
pod2usage(-verbose => 2)  if ($gMan);
pod2usage("$0: No parameters given.")  if ((@ARGV == 0) && (-t STDIN));
pod2usage("$0: 3 parameters required") if ((@ARGV < 3)  && (-t STDIN));

my $aref = \@WWW::Scraper::DigitalArkivet::input; #get arrayRef to @input
@input = @{$aref};                                #arrayRef -> array

# ToDo(?) Don't use arguments?? -> DigitalArkivet.Site ??
$site{'siteID'} = shift; # eg. 2
$site{'url'}    = shift; # eg. http://digitalarkivet.arkivverket.no/sok/eiendom_avansert
$site{'name'}   = shift; # eg. eiendom_avansert

print "\n-----------------------------------------------";
print "\n  Processing site: $site{'name'}";
print "\n-----------------------------------------------";

# Create or open csv to store data
open my $fh, ">$site{'name'}.csv" or die $!;

# Stage 1a - Process each form input
# foreach @input (defined in WWW::Scraper::DigitalArkivet)
my $t0 = Benchmark->new;
for my $i ( 0 .. $#input ) {
    @data = @{processFormInput( $fh, $site{'siteID'}, $site{'url'}, $i, $input[$i], $seperator )};
}
my $t1 = Benchmark->new;
my $td = timediff($t1, $t0);
print "\n\n processFormInput:   ",timestr($td) if ($gDebug);

# Stage 1b - store data
DBIForm2DB( \@data ) if ($dbStorage);
close $fh;
my $t2 = Benchmark->new;
$td = timediff($t2, $t1);
print "\n DBIForm2DB:         ",timestr($td),"\n" if (($dbStorage)&&($gDebug));

if ($gDebug||!$dbStorage) {
    open DMP, ">$site{'name'}_dump.txt" or die $!;
    print DMP Dumper( \@data );
    close DMP;
}
print "\n----------------------------------------------";
print "\n-------------------  Done  -------------------";
print "\n----------------------------------------------\n";
1;

__END__

#-----------------------------------------------------------------------------

=pod

=head1 NAME

B<DigitalArkivet-GetForm.pl> - Get data from web form at Digitalarkivet

=head1 VERSION

 0.01 - 01.07.2015

=head1 SYNOPSIS

    DigitalArkivet-GetForm.pl [options] <siteID> <url> <name>

    options/switches:
    -d 1/0 - database   1 store to DB, 0 no storage
    -h 1/0 - help       brief help message (Synopsis)
    -m 1/0 - manual     full documentation (POD)
    Note: digit must follow last option, since SiteID otherwise would be parsed as option value
          -d1 and -d 1 are the same

    Required parameters:
    <siteID>    - identifying number (to site)
    <url>       - url of site
    <name>      - name of site

    eg.
        DigitalArkivet-GetForm.pl -d1 2 http://digitalarkivet.arkivverket.no/sok/eiendom_avansert eiendom_avansert

=head1 DESCRIPTION

The script gets form inputs on the given web page at Digitalarkivet. These are
needed to further scrape Digitalarkivet - The Digital Archives of Norway,
on later stages. The script executes all of B<Stage 1> for the given site.

Basic functionality:

What are the searchable options?
Look at the form, grab all data about inputs. Store data (to a database)

    1. Find inputs -> build @data
    2. Store data in CSV file
    3. [load CSV into a database]
    4. [dump @data to file]

Storing data in CSV to have better control over data, also storing a CSV
into a database with "load data" is faster than doing it incrementally.

NB! Use -d option switch to store @data in the database. If set, it uses the switch.
Not set, looks for noDB in config file noDB=1 means don't store to database.
Default setting for noDB is 0. A switch will override any option set in the config file.

Todo:

    1. Implment Slowly Changing Dimension (SCD)/ Change Data Capture (CDC) ?
    2. Drop indexes on the database before load, reinstate after load.
    3. Failsafe parameters - remove unwanted chars like " .
    4. Get hidden inputs (if needed ?? - currently doesn't seem to matter for later use).

=head1 CONFIGURATION AND ENVIRONMENT

Testet on win7, no known ties to this platform, should work for other plattforms.
    see config file - B<DigitalArkivet.cfg>

=head1 DEPENDENCIES

Config::Simple, Data::Dumper::Simple, Getopt::Std Web::Scraper, Pod::Usage
WWW::Scraper::DigitalArkivet, WWW::Scraper::DigitalArkivet::Database, URI

Databasestructure as of DigitalArkivet-webscraper.mwb v.1.0 or later

=head1 AUTHOR

Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>
Member of DIS-Norge, The Genealogy Society of Norway-DIS

Please drop me an email if you use this in any project. It would be nice to
know if it's usable for others in any capacity. Any suggestions for improvement
are also appreciated.

=head1 REVISION HISTORY

0.003 - 02.87.2015 - options,POD - Documented

0.001 - 01.08.2014 - Created.

=cut


=head1 SEE ALSO

I<WWW::Scraper::DigitalArkivet::Database>, I<WWW::Scraper::DigitalArkivet>, I<DigitalArkivet-finn_kilde.pl>, I<DigitalArkivet-eiendom_avansert.pl>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2015 Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>

B<Artistic License (Perl)>
Author (Copyright Holder) wishes to maintain "artistic" control over the licensed
software and derivative works created from it.

This code is free software; you can redistribute it and/or modify it under the
terms of the Artistic License 2.0.

The full text of the license can be found in the
LICENSE file included with this module, or "L<perlartistic>".


=head1  DISCLAIMER OF WARRANTY

This program is distributed in the hope that it will be
useful, but it is provided “as is” and without any express
or implied warranties. For details, see the full text of
the license in the file LICENSE.

=cut
