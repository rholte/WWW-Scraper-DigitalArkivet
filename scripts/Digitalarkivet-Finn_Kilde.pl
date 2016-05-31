#!/usr/bin/perl -w
#-----------------------------------------------------------------------------
use strict;
use warnings;
no warnings 'redefine';

use constant { true => 1, false => 0 };
use Carp qw( croak );
use Config::Simple;
use Data::Dumper::Simple;
use Fcntl qw(:flock);
use Getopt::Std;
use Log::Log4perl qw(get_logger :levels);
use Pod::Usage;
use WWW::Scraper::DigitalArkivet  qw/&buildCSVparamList  &processParamList &isNew &getRunID &doDBIrunStart &doDBIrunStat &DBIloadCSVdaParms &s2hms/; # &buildCSVparamList  &processParamList   &getRunID &doDBIrunStart

$| = 1; # autoflush buffer

# END's are evaluated last... therefore it gives execution time in hours, minutes and seconds
END { my $a=time-$^T; my $hms = s2hms($a);  warn sprintf "Runtime %s -- %d min %d s -- %d s \n", $hms,$a/60,$a%60,$a}

#Log::Log4perl->init_and_watch("l4p.conf", 900); #checks reloads log4perl config every 900 sec (15 min)
#Log::Log4perl->init("l4p.conf"); #checks reloads log4perl config every 900 sec (15 min)
#my $log = Log::Log4perl->get_logger(); # root
# use file locking to prevent script from running twice
#open my $self, '<', $0 or $log->logdie("Couldn't open self: $!");
#flock $self, LOCK_EX | LOCK_NB or $log->logdie("This script is already running");
open my $self, '<', $0 or die("Couldn't open self: $!");
flock $self, LOCK_EX | LOCK_NB or die("This script is already running");

our (%Option, %cfg, $config);
our (%site, $href);

# command line options
getopt('abhmrsx:', \%Option);
# options (actions) for script
my $gAll   = exists  $Option{a} ? $Option{a} : false; # a - all    # use -a [1]/0
my $gBuild = exists  $Option{b} ? $Option{b} : false; # b - build  # use -b [1]/0
my $gHelp  = exists  $Option{h} ? $Option{h} : false; # h - help   # use -h [1]/0
my $gMan   = exists  $Option{m} ? $Option{m} : false; # m - manual # use -m [1]/0
my $gReset = exists  $Option{r} ? $Option{r} : false; # r - reset  # use -r [1]/0
my $gSkip  = exists  $Option{s} ? $Option{s} : false; # s - skip   # use -s [1]/0
my $gX     = defined $Option{x} ? $Option{x} : undef; # x - x      # use -x [1]/0

pod2usage(-verbose => 1)  if (($gHelp) || (!%Option)); #need at least 1 option
pod2usage(-verbose => 1)  if ($gHelp);
pod2usage(-verbose => 2)  if ($gMan);

if ($gAll) {
    $gBuild=true;
    $gSkip=false;
    $gReset=true;
}
#$gBuild=0 if ($gReset); # Can't build when resetting (?? unless All ??? Must think about that)

# import configuration from file into hash %cfg:
$config = Config::Simple->import_from( 'DigitalArkivet.cfg', \%cfg ) or die Config::Simple->error();
$href   = defined $cfg{'Site.finn_kilde'} ? $cfg{'Site.finn_kilde'}   : {};
%site   = @$href;

my $gDebug   = defined $cfg{'Debug.debug'}   ? $cfg{'Debug.debug'}   : 0; # 1 turns debugging on
my $doStat   = defined $cfg{'Option.doStat'} ? $cfg{'Option.doStat'} : 0;
my $siteID   = defined $site{'siteID'}       ? $site{'siteID'}       : 1;
my $path     = defined $site{'path'}         ? $site{'path'}         : '';
my $daParm   = defined $site{'daParm'}       ? $site{'daParm'}       : 'da__parms.csv';

#my $runID    = defined $cfg{'ID.Run'}        ? $site{'ID.Run'}       : 1;
my $runID;

isNew('parmsID',0); #reset resultID
$runID=doDBIrunStart(\%Option) if ($doStat && !$gBuild);

#ToDO
#&resetParamList($siteID,$gSkip) if ($gReset);
  # .... UPDATE da__parms set set checked = false;
  # .... UPDATE da__parms set skip=false WHERE skip=true and checked = false;

my $base = $site{'url'}.'?s=&fra=&til=';
my $csvFile  = $path.$daParm;
my ($db_handle,$built) = buildCSVparamList($siteID,$base,$csvFile) if ($gBuild || $gAll);

#    # To be able to continue after error we need to store CSV (load) into database
my ($handle,$rows)=&DBIloadCSVdaParms($csvFile) if ($gBuild || $gAll);

# TODO save csv to db (only when not build (b=0) or?? / and ?? not All (a=0) )
my $processed = processParamList($siteID,$gSkip) unless ($gBuild || $gAll); #skip default false
# UPDATE da__parms set skip=true WHERE hits=0; ??
my $r = doDBIrunStat(0) if ($doStat);

1;
#--------   subs   ------------------------------------------------------------
# no subs

__END__

#-----------------------------------------------------------------------------
=pod

=head1 NAME

B<DigitalArkivet-finn_kilde.pl> - script for harvesting metadata at Digitalarkivet


=head1 VERSION

  0.005 - 19.09.2015 Log4perl, filelocking


=head1 SYNOPSIS

  DigitalArkivet-finnkilde.pl [options]

In order to work script table form must contain data to fill table da__parms
using build option. Normal usage then is to fill resultlist

It is not possible possible to do all data collection in one pass. At some point
communication will fail, another concern is memory usage. Script is only ment to
process a small chuck of data in one 'run'.

Note! script needs working database filled with data from "Stage 1"

    options/switches:
        -a 1/0 - all        all (reset skip=false & build)
        -b 1/0 - build      builds database
        -h 1/0 - help       brief help message
        -m 1/0 - manual     full documentation
        -r 1/0 - reset      reset must be used with skip
        -s 1/0 - skip       skip, must be combined with reset
        -x 0...n - x

All options except x are boolean, without any number after them they
default to 1 there is no need for a space between option and number

B<I<NOTE needs at least one option to run, otherwise it displays help text>>

    Normal usage:
        -b1 (build mode: constructs csv file and stores it into database (no scraping))
        -b0 (web scraping mode:  hence not building csv, just scraping based upon `da__parms` )

    [toDo] Reset: (set checked = false for either skip=false or skip=true)
        (skip=true ) Not all urls had data to colloect on last run, if this is expected on rerun, don't waste time checking this run (skip)
            -r1,-s1
        (skip=false) Expecting or looking for new hits amoung previous (0 hits) We don't skip.
            -r1,-s0
    [/toDo]

    Help: (print doc & die)
        -h

The script should be run as cron or using windows scheduler (as task). Thus restarting
over and over. For windows example look at RunDigitalArkivetfinnKilde.txt and
RunDigitalArkivetfinnKilde.cmd.

B<I<NOTE Don't run as task if you don't need it to. The script will normally run
    for at least 10 days until completed. Do not test just for fun, site is
    crucial for a lot of people. webscraping can degrade a sites performance if
    bombarded with requests.

    takes approx 5 mins to fill da__parms, and 14 days for resultlist !!>>


=head1 TODO

  ??(-d database.... -> file)??
  all
  reset

=head1 DESCRIPTION

"Finn kilde" (Norwegian) or "select source" let's you find sources.
This script harvests metadata on these sources from the Digital Archives
of Norway, also known as DigitalArkivet.

The script executes Stage 2, and depends on DigitalArkivet-GetForm.pl beeing run
first to complete stage 1. This 2 step is time-consuming, most likly fail at
some point. Thus, it is designed to pick up where it failed, and continue.
If setup run for the first time as cron/task it will take at least 10 days before
completion. Script reads from database and traverses all combo's of form-inputs

Main objective of script is to either fill table `da__parms` with data or
process it and fill table 'da__list' (with data). da__parms contains parameters
which define webpages that might/might not have data to be scraped at later stage.
Each possible page is checked, if "we" hit a page with data, it's recorded into
resultlist.

=head1 CONFIGURATION AND ENVIRONMENT

Tested on win7, no known ties to this platform should work for other platforms.
    see config file - B<DigitalArkivet.cfg>


=head1 DEPENDENCIES

Requires modules
 Getopt::Std, Pod::Usage, WWW::Scraper::DigitalArkivet, WWW::Scraper::DigitalArkivet::Database

Databasestructure as of DigitalArkivet-webscraper.mwb v.0.1


=head1 AUTHOR

Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>
Member of DIS-Norge, The Genealogy Society of Norway-DIS

Please drop me an email if you use this in any project. It would be nice to
know if it's usable for others in any capacity. Any suggestions for improvement
are also appreciated.


=head1 REVISION HISTORY

 0.005 - 11.05.2016 - Subs renamed in WWW::Scraper::DigitalArkivet
 0.005 - 19.09.2015 - Log4perl, filelocking preventing mutilpe instances of script
 0.004 - 01.08.2015 - Moved "library" to module
 0.003 - 01.07.2015 - Added POD, options
 0.002 - 21.09.2014 -
 0.001 - 01.08.2014 - Created.


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2015 Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>

B<Artistic License (Perl)>
Author (Copyright Holder) wishes to maintain "artistic" control over the licensed
software and derivative works created from it.

This code is free software; you can redistribute it and/or modify it under the
terms of the Artistic License 2.0. The full text of the license can be found in the
LICENSE file included with this module, or L<http://cpansearch.perl.org/src/NWCLARK/perl-5.8.9/Artistic>


=head1  DISCLAIMER OF WARRANTY

This program is distributed in the hope that it will be
useful, but it is provided ?as is? and without any express
or implied warranties. For details, see the full text of
the license in the file LICENSE.

=cut
#-----------------------------------------------------------------------------
