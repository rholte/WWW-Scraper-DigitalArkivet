package WWW::Scraper::DigitalArkivet;
use strict;
use warnings;
no warnings 'redefine';

BEGIN {
    use Exporter ();
    use vars qw/$VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS/;
    $VERSION = sprintf "%d.%03d", q$Revision: 0.6 $ =~ /(\d+)/g;
    @ISA         = qw/Exporter/;
    @EXPORT      = qw//;
    @EXPORT_OK   = qw/&processFormInput &buildCSVparamList  &processParamList &labelFor
       &lastPage &s2hms &padZero &isNew &Connect2DB &Disconnect2DB &DBIresetDA
       &getRunID &DBIForm2DB &daResultparms &daGeography &daGeography2 &daSource
       &daListType &daTheme daFormat &daOrgan &DBIloadCSVresultparms &DBIloadFile
       &DBIresultParms2DB &DBIresultParms2DB &DBIresultUpdate &DBIresultList2DB
       &doDBIrunStart &doDBIrunStat &parseURI/;
    %EXPORT_TAGS = (ALL => [qw/&processFormInput &buildCSVparamList  &processParamList &labelFor
       &lastPage &s2hms &padZero &isNew &Connect2DB &Disconnect2DB &DBIresetDA
       &getRunID &DBIForm2DB &daResultparms &daGeography &daGeography2 &daSource
       &daListType &daTheme daFormat &daOrgan &DBIloadCSVresultparms &DBIloadFile
       &DBIresultParms2DB &DBIresultParms2DB &DBIresultUpdate &DBIresultList2DB
       &doDBIrunStart doDBIrunStat &parseURI/],
                    Stage1  => [qw/&processFormInput &DBIForm2DB/],
                    Stage2  => [qw/&buildParamList  &processParamList &getRunID &doDBIrunStart &doDBIrunStat/],
                    Stage5  => [qw/&parseURI/]
                    );
 }

#-----------------------------------------------------------------------------
=pod

=head1 NAME

B<WWW::Scraper::DigitalArkivet> - Routines for scraping Digitalarkivet


=head1 VERSION

 0.06 - 26.09.2015 - Module - Second stage complete ex.log4perl, (Fifth Stage completed)
 0.05 - 31.07.2015 - Module - First stage complete
 0.04 - 01.07.2015 - POD - Documented, minor bugfix'es
 0.03 - 01.10.2014 - Added proc resetDA
 0.02 - 21.09.2014 - Added Tables resultList, resultParms, resultBrowse.
                     Views: vgeography,vinput,vinputf,vinputformat,vinputk,
                            vinputka, vinputkt,vinputlt,vinputr,vinputtheme
 0.01 - 01.08.2014 - Created. Tables form, site, toscrape


=head1 SYNOPSIS

  use WWW::Scraper::DigitalArkivet;


=head1 DESCRIPTION

Library for routines to web scrape metadata of sources from the Digital Archives
of Norway also known as Digitalarkivet. Some of the routines are dependable on a
MySQL database (DBI::Mysql)

=head1 INSTALLING

You can create it now by using the command shown above from this directory.

At the very least you should be able to use this set of instructions
to install the module...

perl Makefile.PL
make
make test
make install

If you are on a windows box you should use 'nmake' rather than 'make'.

=head1 TODO

See TODO file (Stage 2 basicly completed except log4perl)



=head1 BUGS


=head1 SUPPORT


=head1 CONFIGURATION AND ENVIRONMENT

Tested on win7, no known ties to this platform. Should work for other platforms.
    Configuration see config file - B<DigitalArkivet.cfg>


=head1 DEPENDENCIES

Requires modules Web::Scraper, Text::Trim
Config::Simple and DBI (amd DBD::mysql)

Databasestructure as of DigitalArkivet-webscraper.mwb v.0. or newer


=head1 AUTHOR

    Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>
    Member of DIS-Norge, The Genealogy Society of Norway-DIS
    CPAN ID: RBH

Please drop me an email if you use this in any project. It would be nice to
know if it's usable for others in any capacity. Any suggestions for improvement
are also appreciated.


=head1 REVISION HISTORY

 0.04 - xx.08.2015 - Stage 2, Merged with WWW::Scraper::DigitalArkivet::Database
 0.03 - 31.07.2015 - Module
 0.02 - 01.05.2015 - POD - Documented
 0.01 - 01.08.2014 - Created.

=cut

#-----------------------------------------------------------------------------
use constant { true => 1, false => 0 };
use Config::Simple;
use Data::Dumper::Simple;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Text::CSV_XS qw( csv );
use Text::Trim;
#use Time::HiRes qw(sleep);
use URI;
use Web::Scraper;
use 5.008001;

our ($baseURL, $Connected, $config, $gDebug, $href, $runID, $resultID,
     $ResultList, $info, $resultListID, $recent);
our (%cfg, %old, %site, @input, @select, @radio, @rlist, @data);
our ($InG, $InS, $InL, $InT, $InF, $InO, $gLimit, $driver, $db, $host, $port, $res,
    $user, $pwd, $attr, $cfg_set, $gsState, $gsFact, $gsRand, $path, $pr, $maxHits,
    $doStat, $dbh );

$runID     = undef;
$resultID  = undef;
$Connected = undef; # only defined if connected to DB.
#
my $slept = 0;
my $c=0;
my $cc=0;
my $count=0;
%old = ();

_readCFG();
_defineScraper();

#Log::Log4perl->init_and_watch("l4p.conf", 900); #checks reloads log4perl config every 900 sec (15 min)
#Log::Log4perl->init("l4p.conf"); #checks reloads log4perl config every 900 sec (15 min)
#my $log = Log::Log4perl->get_logger('Digitalarkivet'); # root


#-----------------------------------------------------------------------------
##############################################################################
#-----------------------------------------------------------------------------
=pod

=head1 METHODS

Each subroutine/function (method) is documented. To avoid problems with timeout/
network errors and memory issues data should be gathered in chunks by re-runs,
each run should collect a given (not too large) amount of data until there is no
more to collect. Some sort of cron job needs to repeat these runs until the whole
site is scraped.

B<NOTE:>
Memory usage required to hold/store data temporarily in internal data structures
depend on chunk sizes. Stage 1 is neither large nor time comsuming. But afterwards
default chunk size could be larger memory wise, but are kept smaller due to user
experience on failure in communications. (Stage 2 may take 15 days to complete)
approx 450.000 entries 2.2 seconds foreach entry

=head3 B<Stage 1>

What are the searchable options?
Look at the form, compile list for later use

    a) grab all data about inputs.
    b) store data (to a database).

=head3 B<Stage 2>

Scrape URL's based upon options.
(For each option combo) save 'Result of search'.

=head3 B<Stage 3>

Result pages may contain identical search, browse, info pages. process only unique URL's!

    a. Search (What can be searched)
    b. Browse (Some sources have index to pages - grab index)
    c. Info. Details on each source
    d.

=head3 B<Stage 4>

    Try ID numbers - not published. Find info about (hidden?) sources

=head3 B<Stage 5>

    Last 100, scrape last 100 regularly and save to database table (recent)

=cut

#-----------------------------------------------------------------------------
################################ subroutines #################################
#-----------------------------------------------------------------------------
=pod

=head2 _readCFG

  Purpose  : Load configuration
  Returns  : <none>
  Argument : <none>

=cut

#-----------------------------------------------------------------------------
sub _readCFG {
    # import configuration into %cfg hash:
    $config = Config::Simple->import_from( 'DigitalArkivet.cfg', \%cfg );

    $gDebug = defined $cfg{'Debug.debug'}? $cfg{'Debug.debug'}: 1;

    # Configurations from file overrides defaults (on the left)
    $gLimit = defined $cfg{'DBI.limit'}  ? $cfg{'DBI.limit'}  : "10000";
    $driver = defined $cfg{'DBI.driver'} ? $cfg{'DBI.driver'} : "mysql";
    $db     = defined $cfg{'DBI.db'}     ? $cfg{'DBI.db'}     : "da";
    $host   = defined $cfg{'DBI.host'}   ? $cfg{'DBI.host'}   : "localhost";
    $port   = defined $cfg{'DBI.port'}   ? $cfg{'DBI.port'}   : "3306" ;
    $user   = defined $cfg{'DBI.user'}   ? $cfg{'DBI.user'}   : "dba" ;
    $pwd    = defined $cfg{'DBI.pwd'}    ? $cfg{'DBI.pwd'}    : "";
    $attr = {
                PrintError=>0,
                RaiseError=>1,       #Make database errors fatal to script
                mysql_enable_utf8=>1 #charset fix
           };
    # "boolean" vars that prevent SQL to be executed (IF clause).
    # sections can be configured not to 'execute' by having value set to 0
    # settings in configuration file if defined overides default values
    $InG    = defined $cfg{'Input.geo'}    ? $cfg{'Input.geo'}    : 1;
    $InS    = defined $cfg{'Input.src'}    ? $cfg{'Input.src'}    : 1;
    $InL    = defined $cfg{'Input.lt'}     ? $cfg{'Input.lt'}     : 0;
    $InT    = defined $cfg{'Input.theme'}  ? $cfg{'Input.theme'}  : 0;
    $InF    = defined $cfg{'Input.format'} ? $cfg{'Input.format'} : 0;
    $InO    = defined $cfg{'Input.organ'}  ? $cfg{'Input.organ'}  : 0;

    $gsState  = defined $cfg{'Sleep.state'}  ? $cfg{'Sleep.state'}  : 0;
    $gsFact   = defined $cfg{'Sleep.factor'} ? $cfg{'Sleep.factor'} : 23;    # used to generate random sleepfactor
    $gsRand   = defined $cfg{'Sleep.rand'}   ? $cfg{'Sleep.rand'}   : 13;      # used to generate random sleepfactor

    $path     = defined $cfg{'Option.path'}    ? $cfg{'Option.path'}    : "./";
    $pr       = defined $cfg{'Option.pr'}      ? $cfg{'Option.pr'}      : 250;
    $maxHits  = defined $cfg{'Option.maxHits'} ? $cfg{'Option.maxHits'} : 500;
    $doStat   = defined $cfg{'Option.doStat'}  ? $cfg{'Option.doStat'}  : 0;

    $cfg_set=1;

    # Site
    my $href = undef;
    $href = defined $cfg{'Site.finn_kilde'} ? $cfg{'Site.finn_kilde'} : undef;
    $site{'finn_kilde'} = $cfg{'Site.finn_kilde'} if $href;
    $href = defined $cfg{'Site.person_avansert'} ? $cfg{'Site.person_avansert'} : undef;
    $site{'person_avansert'} = $cfg{'Site.person_avansert'} if $href;
    $href = defined $cfg{'Site.eiendom_avansert'} ? $cfg{'Site.eiendom_avansert'} : undef;
    $site{'eiendom_avansert'} = $cfg{'Site.eiendom_avansert'} if $href;
    $baseURL= defined $cfg{'Site.baseURL'} ? $cfg{'Site.baseURL'} : 'http://digitalarkivet.arkivverket.no/';
}
#-----------------------------------------------------------------------------
=pod

=head2 _defineScraper()

  Purpose  : Define scraper objects
  Returns  :
  Argument : <none>
  Throws   : -
  Comment  : need to learn about scrapers? checkout/try
           :  http://www.perldesignpatterns.com/?WebScraper
           :  https://teusje.wordpress.com/2010/05/02/web-scraping-with-perl/

 See Also  : directory "scripts\Scraper examples" contains working scraper
           : samples.
=cut

#-----------------------------------------------------------------------------
sub _defineScraper {
        # ToDo? retrieve from da.toSrape
    # Define scraper objects - pattern to scrape/hold data
    my $inputLabel = scraper {
        # Default setup for input & label
            process 'input',
              'id'    => '@id',
              'value' => '@value',
              'type'  => '@type',
              'name'  => '@name';
            process 'label',
              'label_for' => '@for',
              'text'      => 'TEXT';
        };

    $input[0] = scraper {
        # Source category (Kildekategori)
        process 'div.listGroup > ul.grouped > li', 'data[]' => $inputLabel;
    };

    $input[1] = scraper {
        process 'ul.sublist1 > li', 'data[]' => $inputLabel;
    };

    $input[2] = scraper {
         # Geography (Geografi)
        process 'ul.sublist2 > li', 'data[]' => $inputLabel;
    };

    $input[3] = scraper {
        # Mainly text inputs
        # Personinformasjon, Hendelsesinformasjon / Eiendomsinformasjon
        process 'ol.form > li', 'data[]' => $inputLabel;
    };

    # Radio eiendom_avansert
    $radio[0] = scraper {
        process 'ul > li', 'data' => scraper {
            process 'input[]',
              'id'    => '@id',
              'value' => '@value',
              'type'  => '@type',
              'name'  => '@name';
            process 'label[]',
              'label_for' => '@for',
              'text'      => 'TEXT';
        };
    };

    # grab select
    $select[0] = scraper {
        process 'ol.form > li', 'data[]' => scraper {
            process 'select',
              'id'      => '@id',
              'name'    => '@name',
              'value[]' => scraper {
                process 'option',
                  'value' => '@value',
                  'text'  => 'TEXT';
              };
            process 'label',
              'label_for' => '@for',
              'text'      => 'TEXT';
        };
    };

    $rlist[0] = scraper {
        process 'div.listGroup > ul.grouped > li', 'data[]' => $inputLabel;
    };

    $ResultList = scraper {
         # Static info pr page
        process 'div.contentHeader > h1', 'header' => 'TEXT';
        process 'div.contentHeader > p.comment',
          'comment' => 'TEXT';            # Count of records in comment !
        process 'div.pageNavigator > div.pagination > strong',
          'page' => 'TEXT';               # Current page
                                          # pageNavigator
        process 'div.pageNavigator > div.pagination > a', 'pageurls[]' => '@href'
        ; # LAST PAGE: only need last page '>>' and it's page=X, but collect all..
        # Table data foreach (tr)row
        process 'table.resultList > tbody > tr', 'data[]' => scraper {
        process 'td.title',      'title'      => 'TEXT';
            process 'td.search',     'search'     => 'TEXT';
            process 'td.read',       'read'       => 'TEXT',;
            process 'td.browse',     'browse'     => 'TEXT',;
            process 'td.print',      'print'      => 'TEXT';
            process 'td.search > a', 'search_url' => '@href';
            process 'td.read   > a', 'read_url'   => '@href';
            process 'td.browse > a', 'browse_url' => '@href';
            process 'td.print  > a', 'print_url'  => '@href';
        };
    };

            #process 'td:nth-child(1)', 'label1' => 'TEXT';
            #process 'td:nth-child(2)', 'value1' => 'TEXT';
            #process 'td:nth-child(3)', 'label2' => 'TEXT';
            #process 'td:nth-child(4)', 'value2' => 'TEXT';
    $info = scraper {
        # Might have 2 tables, 4 coloumns .. label,value label value
        # First infotable
        process 'table.infotable:first-child > tbody > tr', 'about[]' => scraper {
            process 'td[position() mod 2 = 1 ]' => 'TEXT';
            process 'td[position() mod 2 = 0 ]' => 'TEXT';
        };
        # next infotable's
        process ' h4', 'section[]' ,'title'  => 'TEXT' => scraper {
            process 'h3', 'list[]' ,'title'  => 'TEXT' => scraper {
                process 'table.infotable[position() > 1] > tbody > tr', 'info[]' => scraper {
                    process 'td[position() mod 2 = 1 ]', 'label' => 'TEXT'; # odd
                    process 'td[position() mod 2 = 0 ]', 'value' => 'TEXT'; # even
                };
            };
        };
        process 'h1', 'title' => 'TEXT';
        process 'div#contentHeader > div > ul', 'link' => scraper {
            process 'li > ul > li', 'lists[]' => scraper { 'a', 'name' => 'TEXT', 'url'  => '@href' }
        };
        result 'title', 'about', 'section', 'link';
    };

    $recent = scraper {
        # recent 100 list
        process 'div.oneCol > ol.numberList > li',
        'data[]' => scraper {
             process 'li > a', 'url' => '@href';
             process 'li > a', 'src' => 'TEXT';
        };
        process 'div.oneCol > ol.numberList > li','txt[]' => 'TEXT';
    }
}


#-----------------------------------------------------------------------------
=pod

=head2 s2hms()

  Purpose  : Converts seconds into a string with hours, minutes and seconds
  Returns  : hh:mm:ss <string>
  Argument : (s) seconds <integer>
  Throws   : -
  Comment  : if seconds >  86400 wich is a day,
           : it will show days hours minutes seconds (dhms)

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub s2hms{
    my $s = shift;
    my $rtn = "";
    if ( $s =~ /^[0-9,.E]+$/ ) {
        my $d1 = $s/86400; #24*3600 s/day
        if (int($d1)>0){
            my $d  = int($d1);
            $s = ($d1-$d)*24;
            $rtn = $d."d ";
        }
        my $h1 = $s/3600;
        my $h  = int($h1);
        my $m1 = ($h1-$h)*60;
        my $m  = int($m1);
        $s = ($m1-$m)*60;
        $rtn .= padZero($h,2).":".padZero($m,2).":".padZero($s,2);
    }
    return $rtn;
}

#-----------------------------------------------------------------------------
=pod

=head2 padZero()

  Purpose  : Zero pad string  eg. 003 & 02
  Returns  : zero padded number <string>
  Argument : (num) number to pad
           : (len) maximum lenght
  Throws   : -
  Comment  : zero pad string to given length

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub padZero {
  my ($num, $len) = @_;
  #return '0' x ($len - length $num) . $num;
  return substr('0'x$len.$num, -$len);
}

#-----------------------------------------------------------------------------
=pod

=head2 Connect2DB()

  Purpose  : Establish and hold connection to a database
  Returns  : Database handle
  Argument : <none>
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Connects to a database, returns the handle to it for further use.

 See Also  : Disconnect2DB()

=cut

#-----------------------------------------------------------------------------
sub Connect2DB {
    _readCFG() if not($cfg_set);
    my $dsn = "dbi:$driver:$db:$host:$port";
    #our $dbh;
    #our $runID;

    #eval { $dbh = DBI->connect( $dsn, $user, $pwd, \%attr ); };
    eval { $dbh = DBI->connect( $dsn, $user, $pwd, $attr ); };
    if ( $DBI::err && $@ =~ /^(\S+) (\S+) failed: / ) {
        print "SQL error: $DBI::errstr ($DBI::err) $1 $2 - $@\n";
    }
    else {
        $Connected = 1;
        $runID     = &getRunID(); #process id, used as key
        $resultID  = &getResultatID();
    }
    return $dbh;
}

#-----------------------------------------------------------------------------
=pod

=head2 Disconnect2DB()

  Purpose  : Terminate database connection
  Returns  : <none>
  Argument : <none>
  Comment  : Disconnects MySQL handle, sets global $Conneccted to 0

 See Also  : Connect2DB()

=cut

#-----------------------------------------------------------------------------
sub Disconnect2DB {
    if ($Connected) {
        our $dbh->disconnect();
        $Connected = 0;
    }
}

#-----------------------------------------------------------------------------
=pod

=head2 DBIresetDA()

  Purpose  : Calls stored procedure to reset the database.
  Returns  : Ref to statement handle
  Argument : <none>
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Connect to a database, returns the handle to it for further use.
           : (via stored procedure)

=cut

#-----------------------------------------------------------------------------
sub DBIresetDA {
    our $dbh = &Connect2DB() if not($Connected);
    my $sql = qq{CALL resetDA()};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute();
    return (\$sth);
}

#-----------------------------------------------------------------------------
=pod

=head2 getRunID()

  Purpose  : Retrieve current RunID
  Returns  : (RunID) - integer - Last inserted RunID
  Argument : <none>
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Every 'Run' has a unique process (autoincrement) number.
           : Used to identify which data is collected during which run.
           : (via stored procedure)

=cut

#-----------------------------------------------------------------------------
sub getRunID {
    #our $dbh = &Connect2DB() if not($Connected);
    my $rtn = defined $cfg{'ID.Run'} ? $cfg{'ID.Run'} : 1; #failsafe value
    my $sql = qq{CALL getRunID()};
    #my $sql= qq{SELECT `runID` FROM `$db`.`run` ORDER BY `runID` DESC LIMIT 1};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute();
    ($runID) = $sth->fetchrow_array;
    if (defined $runID) {
        unless ($runID==$rtn) {
            $rtn = $runID; #database value used instead
            $config->param("ID.Run",$runID);
            $config->write();
        }
    return $rtn;
    }
}

#-----------------------------------------------------------------------------
=pod

=head2 getResultatID()

  Purpose  : Retrieve current getResultatID
  Returns  : (RunID) - integer - Last inserted getResultatID
  Argument : <none>
  Throws   : Die - on SQL error
  Comment  : MySQL
           : (autoincrement) number. (via stored procedure)

=cut

#-----------------------------------------------------------------------------
sub getResultatID {
    #our $dbh = &Connect2DB() if not($Connected);
    my $rtn = defined $cfg{'ID.Resultat'} ? $cfg{'ID.Resultat'} : 1; #failsafe value
    my $sql = qq{CALL getResultatID()};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute();
    ($resultID) = $sth->fetchrow_array;
    if (defined $resultID) {
        unless ($resultID==$rtn) {
            $rtn = $resultID; #database value used instead
            $config->param("ID.Resultat",$resultID);
            $config->write();
        }
    }
    return $rtn;
}

#-----------------------------------------------------------------------------
=pod

=head2 doDBIrunStart()

  Purpose  : Start data gathering
  Returns  : (RunID) - last insert id (mysql)
  Argument : action, hash ref to options
  Throws   : Die - on SQL error
  Comment  : MySQL
           : hashref pass as argument is converted into string of &key1=value1&key2=value2..
           : Invokes stored procedure `runStart` with 2 arguments
           : (Options) -string of options conveterd from hashref (options to "run" started)
           : (State) - sleep state
           : Marks beginning of data gathering enables logging of progress
           : "of run"/ harvesting of data (via stored procedure)

 See Also  : doDBIrunStat()

=cut

#-----------------------------------------------------------------------------
sub doDBIrunStart {
    use URI::Escape;
    my $href    = shift; # hashref
    my @ary;
    our $dbh = &Connect2DB() if not($Connected);
    my $pState = defined $cfg{'Sleep.state'} ? $cfg{'Sleep.state'} : 0;
    #build option string eg &opt1=x&opt2=y
    my $Options=join '&',map {uri_escape($_).'='.uri_escape($href->{$_})} grep {defined $href->{$_}} keys %$href;
    my $sql = qq/CALL `$cfg{'DBI.db'}`.`runStart`( ?, ? ) / ;
    our $sth = $dbh->prepare($sql)
            or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute($Options, $pState);
    @ary = $sth->fetchrow_array;
    $runID=$ary[0]; # set's new global runID
    return  $runID;
}

#-----------------------------------------------------------------------------
=pod

=head2 doDBIrunStat()

  Purpose  : log statistical data of harvesting
  Returns  : 1
  Argument : RunID
  Throws   : Die - on SQL error
  Comment  : MySQL
           : invokes stored procedure `runStat`
           : Used to track progress of run, also updates some statistical data
           : (via stored procedure)

 See Also  : doDBIrunStart()

=cut

#-----------------------------------------------------------------------------
sub doDBIrunStat {
    use URI::Escape;
    my $pID    = shift; # runID
    our $dbh = &Connect2DB() if not($Connected);
    my $sql = qq/CALL `$db`.`runStat`( ? ) / ;
    our $sth = $dbh->prepare($sql)
            or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    print "Can't execute SQL statement: ", $sth->errstr(), "\n" unless ($sth->execute($pID));
    return  1
}

#-----------------------------------------------------------------------------
=pod

=head2 doDBIfillSCD()

  Purpose  : fill SCD tables
  Returns  : 1
  Argument : SiteID
  Throws   : Die - on SQL error
  Comment  : MySQL
           : invokes stored procedure `fill_scd` to fill scd tables
           : (via stored procedure)

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub doDBIfillSCD {

    my $pID    = shift || 1 ; # siteID
    our $dbh = &Connect2DB() if not($Connected);
    my $sql = qq/CALL `$db`.`fill_scd`( ? ) / ;
    our $sth = $dbh->prepare($sql)
            or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    print "Can't execute SQL statement: ", $sth->errstr(), "\n" unless ($sth->execute($pID));
    return  1
}


#-----------------------------------------------------------------------------
#                            S T A G E  1
#-----------------------------------------------------------------------------
=pod

=head2 processFormInput()

  Stage    : 1

  Purpose  : Web scrape form inputs - process inputs from form
  Returns  : \@data - handle to array containing data
  Argument : $_[0] - (fh) filehandle
           : $_[1] - (siteID)
           : $_[2] - (url)
           : $_[3] - (level)
           : $_[4] - (scrape)
           : $_[5] - (tab) field seperator
  Throws   : -
  Comment  : webpage form shows searchable attributes for metadata on source

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub processFormInput {
    my $fh     = $_[0];
    my $siteID = $_[1];
    my $url    = $_[2];
    my $level  = $_[3];
    my $scrape = $_[4];
    my $tab    = $_[5];
    my $j      = 0;
    my $id;
    my $lf;
    my $name2;
    my $i;
    my $num;
    my @row = ( '', '', '', '', '', '' );

    $res = $scrape->scrape( URI->new( $url ) );
    $num = $#{ $res->{data} } + 1; #starts with 0 add 1 for actual number
    print "\n- - - - -    [$level]: $num elements - - - - -";
    # prints only first time when $level=0
    unless ($level) {
        print {$fh} join( $tab,
            "siteID", "level", "line", "label_for", "text",
            "name",   "value", "id",   "type",      "name2",
            "lf1",    "lf2",   "lf3" )
          . "\n";
    }
    for $i ( 0 .. $#{ $res->{data} } ) {
        my $label_for =
          $res->{data}[$i]->{label_for} ? $res->{data}[$i]->{label_for} : "";
        my $name = $res->{data}[$i]->{name} ? $res->{data}[$i]->{name} : "";
        #if ((length($label_for)>0) and ($name ne "ko[]") ){
        if ( length($label_for) > 0 ) {
            $j++;    # line
            my $text = $res->{data}[$i]->{text} ? $res->{data}[$i]->{text} : "";
            # remove potenial error : ',' -> comma in field fucks up list
            $text =~ s/, PA/ (PA)/g;    #quickfix for PA
            $text =~ s/, NY/ (NY)/g;    #quickfix for NY
            $text =~ s/, / - /g;        #quickfix for others
            $text =~ s/^\s+|\s+$//g;    #trim
            my $value =
              $res->{data}[$i]->{value} ? $res->{data}[$i]->{value} : "";
            my $id   = $res->{data}[$i]->{id}   ? $res->{data}[$i]->{id}   : "";
            my $type = $res->{data}[$i]->{type} ? $res->{data}[$i]->{type} : "";
            $name2 = $name;
            $name2 =~ s/\W//g;
            @row = (
                $siteID, $level, $j, $label_for, $text, $name, $value,$id, $type, $name2
            );
            #fix label for, split into 3 pieces
            my @LF = &labelFor( $label_for, $tab );
            foreach my $lf (@LF) {
                push( @row, $lf );
            }
            print {$fh} join( $tab, @row );
            print {$fh} "\n";
            push( @data, join( ',', @row ) );
        }
        else {
            my $text =
              $res->{data}[$i]->{text} ? trim( $res->{data}[$i]->{text} ) : "";
            my $value =
              $res->{data}[$i]->{value} ? $res->{data}[$i]->{value} : "";
            my $id   = $res->{data}[$i]->{id}   ? $res->{data}[$i]->{id}   : "";
            my $type = $res->{data}[$i]->{type} ? $res->{data}[$i]->{type} : "";
            print "\nFound !!\ttext: $text\tvalue: $value\tid: $id\ttype: $type\n" if ($gDebug);
        }
    }
    print "j: $j . . $num\n" if ($gDebug);
    #Time::HiRes::sleep(0.5); # Do not DDOS server - Sleep for 0.5 seconds

    return \@data;
}

#-----------------------------------------------------------------------------
=pod

=head2 labelFor()

  Stage    : 1

  Purpose  : Decode label attribute "for" eg ka14kt0
  Returns  : array of 3 strings
  Argument : $_[0] - (str) labelfor <string>
  Throws   : -
  Comment  : The label's for the attribute has a numbering system up to 3 levels.
           : break string into 3 parts, prefix/number and make an array of each
           : part. Pad with "null" if needed to make an array (of 3).
           : Used later to process hierarchal structures of the inputs.

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub labelFor {
    my $str = $_[0] ? $_[0] : undef;
    my @prefix;
    my @number;
    my @tmp;
    my $i;
    my $x;
    my @string;
    no warnings 'uninitialized';

    if ( length($str) > 0 ) {
        #non digits, split on digits
        @tmp = split /\d/, $str;
        for $i ( 0 .. $#tmp ) {
            push @prefix, $tmp[$i] if ($tmp[$i] ne '')
        }
        #digits, split on non digits
        @tmp = split /\D/, $str;
        for $i ( 0 .. $#tmp ) {
            push @number, $tmp[$i] if ($tmp[$i] ne '')
        }
        for $i ( 0 .. $#prefix ) {
            push @string, $prefix[$i] . $number[$i];
        }
        #pad
        $x = 3 - $#prefix;
        while ( $x > 1 ) {
            push @string, "null";
            $x--;
        }
        return @string; #normal return
    }
    else {
        return ("null","null","null"); # failsafe
    }
}

#-----------------------------------------------------------------------------
=pod

=head2 lastPage()

  Stage    : 1

  Purpose  : Actual page number of last page. (not url)
  Returns  : page number
  Argument : (pageurls) - array of urls
  Throws   : -
  Comment  : lastPage, of all "lastpages" scraped only last is relevant.
           : web scrape gets too many urls, this routine fixes last page.
           : (Thus need last page in scope)

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub lastPage {
    my $page     = shift;    # Remove the first member from @_.
    my @pageurls = @_;
    if (@pageurls) {
        my @page = split /page=/, $pageurls[-1];
        #last array has relevant data
        return $page[-1];
    }
    else {                   #return curent page
        #return $_[0];        # $page ? $_[0] possible error must debug
        return $page;
    }
}

#-----------------------------------------------------------------------------
=pod

=head2 DBIForm2DB()

  Stage    : 1

  Purpose  : Save form data to database. (Array from form into database).
  Returns  : Handle to execution of statement
  Argument : (data) Handle to array with data
  Throws   : Die - on SQL error
  Comment  : MySQL
           : All form's have a basic structure that is possible to save in tabular format.
           : Each input in the form is inspected, the hierarchical structure is preserved
           : along with wich site is was grabbed of. Each input has a hierarchical level,
           : Line is just an index. input(item) may have a label (label_for), a CSS name,
           : text, CSS id, and is of a certain type. Name2, lf1, lf2 and lf3 are just for
           : help in rebuilding hierarchy.

  Columns  : `siteID` `level` `line` `label_for` `text` `name` `value` `id` `type` `name2` `lf1` `lf2` `lf3`

=cut

#-----------------------------------------------------------------------------
sub DBIForm2DB {
    my @data = @{ $_[0] };
    our $dbh = &Connect2DB() if not($Connected);
    my $i=0;
    my @fields = (qw(`siteID` `level` `line` `label_for` `text` `name` `value` `id` `type` `name2` `lf1` `lf2` `lf3`));
    my $fieldlist = join ", ", @fields;
    my $field_placeholders = join ", ", map {'?'} @fields;
    my $sql = qq{REPLACE INTO `$db`.`form` ( $fieldlist ) VALUES( $field_placeholders )};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    foreach my $row (@data) {
        $_ = $row;
        my (
            $siteID, $level, $line, $label_for, $text,
            $name,   $value, $id,   $type,      $name2,
            $lf1,    $lf2,   $lf3
        ) = split /,/;
        if (
            $sth->execute(
                $siteID, $level, $line, $label_for, $text,
                $name,   $value, $id,   $type,      $name2,
                $lf1,    $lf2,   $lf3
            )
          )
        {
            #print "insert ok $row\n" if ($gDebug);
        }
        else {
            #or die
            print "Can't execute SQL statement: ", $sth->errstr(), "\n";
            print "NOT ok insert $row\n";
        }
    }
    #$dbh->disconnect();
    return ($sth);
}

#-----------------------------------------------------------------------------
#                            S T A G E  2
#-----------------------------------------------------------------------------
=pod

=head2 buildCSVparamList()

  Stage    : 2

  Purpose  : Build list of params - save to resultparms.csv
  Returns  : -
  Argument : $_[0] - (siteID)   - process this site
           : $_[1] - (base_url) - url
           : $_[2] - (csvFile)  - filename
  Throws   : Die on failure to close file
  Comment  : Build list to be traversed later.
           : List is saved to CSV.
           : Doesn't check theme & format for evry place, thus saving time
           : (Trick to reduce list, no need to check every permutation !)
           : NB  @organ is not traversed !!  on ToDo ??

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub buildCSVparamList {
    # pass = true, skip
    #$url = defined $site{url} ? $site{url} : ''; #reset url
    #our $resultID;
    my $siteID   = $site{'finn_kilde'}[1]; # -> 1 !!
    my $base_url = $site{'finn_kilde'}[3].'?s=&fra=&til=';
    my $csvFile  = $path."resultparms.csv";
    my $ref;

    $siteID   = shift;
    $base_url = shift;
    $csvFile  = shift;
    #my $runID  = shift;

    #@data = ($resultID, $siteID, $r, $f, $k, $ka, $kt, $lt, $format, $theme, $ok, $ko, $url, $skip);
    my (@data, @geo, @geo2, @src, @lt, @theme, @format, @organ );
    my ($c, $cc);

    # csv
    # header row
    open our $csvFH, ">:encoding(utf8)", $csvFile or die Text::CSV_XS->error_diag;
    my $csv = Text::CSV_XS->new ({ binary => 1, auto_diag => 1, allow_loose_quotes => 1 });
    $csv->eol ("\r\n");
    my @fields = (qw(`resultID` `siteID` `r` `f` `k` `ka` `kt` `lt` `format` `theme` `ok` `ko` `url` `skip` `runID`));
    $csv->print ($csvFH, \@fields) or $csv->error_diag;

    my %xtra;
    # build datastructures to traverse
    # fetch data into arrays of hashes, keep record of parms (by de-referencing subs)
    # if array is empty, check 'skip setting' under [Input] in config
    #$ref   = &daGeography($siteID);
    @geo    = @{&daGeography($siteID)}  if ($InG);  #i - 794 - r,f,k
    #$ref   = &daGeography2($siteID) ;
    @geo2   = @{&daGeography2($siteID)} if ($InG); #i -  47 - r,f (short list)
    #$ref   = &daSource($siteID);
    @src    = @{&daSource($siteID)}     if ($InS);     #j -     - ka,kt
    #$ref   = &daListType($siteID);
    @lt     = @{&daListType($siteID)}   if ($InL);   #l -     - lt
    #$ref   = &daTheme($siteID);
    @theme  = @{&daTheme($siteID)}      if ($InT);      #m -     -
    #$ref   = &daFormat($siteID);
    @format = @{&daFormat($siteID)}     if ($InF);     #n -     -
    #$ref   = &daOrgan($siteID);
    @organ  = @{&daOrgan($siteID)}      if ($InO);      #o -     - ok, ko

    # Only theme & Organ restrict data unless all...=1
    %xtra = ( all => 1, bit => '&allThemes=1' );
    push( @theme, \%xtra );
    %xtra = ( all => 1, bit => '&allOrgan=1' );
    push( @organ, \%xtra );

    # fix for all records, since empty 'bit' removes filtering constrains
    %xtra = ( all => 0, bit => '', ka => '', kt => '' );
    push( @src, \%xtra );
    %xtra = ( all => 0, bit => '', lt => '' );
    push( @lt, \%xtra );
    # following currwntly not need
    #%xtra = ( all => 0, bit => '', r => '', f => '', k => '' );
    #push( @geo, \%xtra );
    #%xtra = ( all => 0, bit => '', theme => '' );
    #push( @theme, \%xtra );
    #%xtra = ( all => 0, bit => '', format => '' );
    #push( @format, \%xtra );
    #%xtra = ( all => 0, bit => '', , ok => '', ko => '' );
    #push( @organ, \%xtra );
    undef %xtra;

    $resultID=getResultatID() if !(defined $resultID);

    print "\nBuilding CSV........ ";
    # toDo save to log, number parms to of each
    print "\n g:$#geo ($#geo2) s: $#src l: $#lt t: $#theme f: $#format o: $#organ\n" if ($gDebug);

    #
    ## main loop
    print "[csv id=src] $resultID" if ($gDebug);
    $c=&buildCSVsrc($siteID, $base_url, $csv, $csvFH,\@geo,\@src,\@lt);
    #print "#" if ($gDebug);
    $cc+=$c;
    print "\n[/csv id=src count= $c] $resultID\n" if ($gDebug);
    #
    ##each theme
    print "[csv id=theme] $resultID" if ($gDebug);
    $c=&buildCSVsimple($siteID, $base_url,'theme',$csv, $csvFH, \@geo2,\@theme);
    $cc+=$c;
    print "\n[/csv id=theme count= $c - $cc ] $resultID\n" if ($gDebug);
    #
    ##each format
    print "[csv id=format] $resultID" if ($gDebug);
    $c=&buildCSVsimple($siteID, $base_url,'format',$csv, $csvFH,\@geo2,\@format);
    $cc+=$c;
    print "\n[/csv id= format: $c - $cc ] $resultID\n" if ($gDebug);
    #
    ##each organ
    #print "[csv id=organ] $resultID" if ($gDebug);
    #$c=&buildCSVsimple($siteID, $base_url,'organ',$csv, $csvFH,\@geo2,\@organ);
    #$cc+=$c;
    #print "\n[/csv id= organ: $c - $cc ] $resultID\n" if ($gDebug);
    #

    close($csvFH)  or die "\n can't close $csvFile: $!"; #close csv file
    return $cc;
}

#-----------------------------------------------------------------------------
=pod

=head2 buildCSVsrc()

  Stage    : 2

  Purpose  : Build general list of params
  Returns  : -
  Argument : $_[0] - (siteID)   - process this site
           : $_[1] - (base_url) - url
           : $_[2] - (csv)      - filename
           : $_[3] - (FH)       - filhandle
           : $_[4] - (aref)     - arrayref (turned into array g)
           : $_[5] - (aref)     - arrayref (turned into array s)
           : $_[6] - (aref)     - arrayref (turned into array lt)
  Throws   : -
  Comment  : loop every kt[] & lt[] forearch geographic place
           : (->each daGeography  r,f,k)
           : Not nesting every available parameter, because there is some
           : logic to it all.  Short cut can be made, thus buildCSVsimple()
           : (Trick to reduce list, no need to check every permutation !)
           : NB  @organ is not traversed !!  on ToDo ??

 See Also  : buildCSVsimple()

=cut

#-----------------------------------------------------------------------------
sub buildCSVsrc(){
    #
    # build param string, save to csv
    # "list" is needed to restart from when script fail's before scraping is completed
    #  ->fault tolerant way to webscrape, recovery enabled
    #our $resultID;
    my ($r, $f, $k, $ka, $kt, $lt, $format, $theme, $ok, $ko, $skip, $bit, $url,  @data);
#    my $siteID   = $site{'finn_kilde'}->{'siteID'};
#    my $base_url = $site{'finn_kilde'}->{'url'}.'?s=&fra=&til=';
    #my $base_url = shift;
    my $siteID   = shift;
    my $base_url = shift;
    my $csv      = shift;
    my $FH       = shift;
    my $aref     = shift;
    my @g        = @{$aref};
    $aref        = shift;
    my @s        = @{$aref};
    $aref        = shift;
    my @lt       = @{$aref};
    #my $runID    = shift;
    my $allGeo   = '';
    my $bitGeo   = '';
    my $rows     = 0 ;

    $format   = '';
    $theme    = '';
    $ok       = '';
    $ko       = '';
    $skip     = 0 ; # skip = 0, (false) means not to skip later on
    for my $i ( 0 .. $#g ) {
        print "." if ($gDebug);
        $lt = '';
        $r = defined $g[$i]{r} ? $g[$i]{r} : '';
        $f = defined $g[$i]{f} ? $g[$i]{f} : '';
        $k = defined $g[$i]{k} ? $g[$i]{k} : '';
        $bitGeo = defined $g[$i]{bit} ? $g[$i]{bit} : '';
        # each kildetype kt[] (ka)
        my $bitSrc = '';
        for my $j ( 0 .. $#s ) {
            #our $allCat;  # not needed??
            $ka = defined $s[$j]{ka} ? $s[$j]{ka} : '';
            $kt = defined $s[$j]{kt} ? $s[$j]{kt} : '';
            $bitSrc = defined $s[$j]{bit} ? $s[$j]{bit} : '';
            if ( $ka eq '2' ) { # no need to loop @lt unless ka==2
                my $bitLt = '';
                for my $l ( 0 .. $#lt ) {
                    $lt = defined $lt[$l]{lt} ? $lt[$l]{lt} : '';
                    $bitLt = defined $lt[$l]{bit} ? $lt[$l]{bit} : '';
                    $url = $base_url.$bitGeo.$bitSrc.$bitLt . "&page=";
                    @data =($resultID, $siteID, $r, $f, $k, $ka, $kt, $lt, $format, $theme, $ok, $ko, $url, $skip);
                    $csv->print ($FH, \@data) or $csv->error_diag; #save to csv
                    $resultID++;
                    $rows++;
                }
            }
            else {
                $lt = ''; # not "liste type"
                $url = $base_url.$bitGeo.$bitSrc."&page=";
                @data = ($resultID, $siteID, $r, $f, $k, $ka, $kt, $lt, $format, $theme, $ok, $ko, $url, $skip);
                $csv->print ($FH, \@data) or $csv->error_diag; # save to csv
                $resultID++;
                $rows++;
            }
        }
    }
    return $rows;
}

#-----------------------------------------------------------------------------
=pod

=head2 buildCSVsimple()

  Stage    : 2

  Purpose  : Build simpler list of params
  Returns  : -
  Argument : $_[0] - (siteID)   - process this site
           : $_[1] - (base_url) - url
           : $_[2] - (key)      -
           : $_[3] - (csv)      - filename
           : $_[4] - (FH)       - filhandle
           : $_[5] - (aref)     - arrayref (turned into array g)
           : $_[6] - (aref)     - arrayref (turned into array d)
  Throws   : -
  Comment  : Since there is no need to permutate all options to find Theme/
           : format this is done countywise (fylkesvis). Expect to find same
           : source in buildCSVsrc -> search only countywise (fylkesvis)
           : (skip=1 needn't scrape)
           :
           : Trick to reduce list, no need to check every permutation !
           : NB  @organ is not traversed !!  on ToDo ??

 See Also  : buildCSVsrc()

=cut

#-----------------------------------------------------------------------------
sub buildCSVsimple {
    #our $resultID;
    my ($r, $f, $k, $ka, $kt, $lt, $format, $theme, $ok, $ko, $url, $skip,$bit,  @data);
    my $siteID   = shift;
    my $base_url = shift;
    my $key      = shift;
    my $csv      = shift;
    my $FH       = shift;
    my $aref     = shift;
    my @g        = @{$aref};
    $aref        = shift;
    my @d        = @{$aref};
    #my $runID    = shift;
    my $allGeo   = '';
    my $bitGeo   = '';
    my $rows     = 0;
    #my $siteID   = $site{'finn_kilde'}->{'siteID'};
    #my $base_url = $site{'finn_kilde'}->{'url'}.'?s=&fra=&til=';


    $format = '';
    $theme  = '';
    $ok     = '';
    $ko     = '';
    $skip   = 0 ; # skip = 0, (false) means not to skip later on
    $k      = '';
    $ka     = '';
    $kt     = '';
    $lt     = '';
    for my $i ( 0 .. $#g ) {
        print "." if ($gDebug);
        $r = defined $g[$i]{r} ? $g[$i]{r} : '';
        $f = defined $g[$i]{f} ? $g[$i]{f} : '';
        $bitGeo = defined $g[$i]{bit} ? $g[$i]{bit} : '';
        my $bitX  = '';
        for my $j ( 0 .. $#d ) {
            if ($key eq 'theme') {
                $theme = defined $d[$j]{theme} ? $d[$j]{theme} : '';
            } elsif ($key eq 'format') {
                $format = defined $d[$j]{format} ? $d[$j]{format} : '';
            } elsif ($key eq 'organ') {
                $format = defined $d[$j]{organ} ? $d[$j]{organ} : '';
            }
            $bitX = defined $d[$j]{bit} ? $d[$j]{bit} : '';
            $url = $base_url.$bitGeo.$bitX."&page=";
            @data = ($resultID, $siteID, $r, $f, $k, $ka, $kt, $lt, $format, $theme, $ok, $ko, $url, $skip);
            $csv->print ($FH, \@data) or $csv->error_diag; #save to csv
            $resultID++;
            $rows++;
        }
    } # for @g
    return $rows;
}


#-----------------------------------------------------------------------------
=pod

=head2 processParamList()


  Stage    : 2

  Purpose  : Read unprocessed urls into array (of hashes)
  Returns  :
  Argument : $_[0] - (siteID) - process this site
           : $_[1] - (skip)   - True/false (default false)
  Throws   : -
  Comment  : Loops thru database picks urls of unprocessed parameter items
           : Starts scraping these (actually scraping urls to scrape later)
           : (data retrieved is limited, globally set option)

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub processParamList {
    my $siteID = shift;
    my $skip   = shift || false;
    #my $runID  = shift;
    my $page=0;

    #_defineScraper();

    # data to process
    # read unproccessed urls into Array (of hashes)
    my (@data) = @{&daResultparms($siteID, $skip)};
    for my $i ( 0 .. $#data ) {
        ($page) = &scrapeResultList($siteID,$data[$i]{resultID},$data[$i]{url},1);
    }
    $page=0;
}

#-----------------------------------------------------------------------------
=pod

=head2 scrapeResultList()


  Stage    :

  Purpose  : check url, scrape data to build a result list
  Returns  :
  Argument : $_[0] - (siteID) - process this site
           : $_[1] - (resultID) - foreign key, link back to resultParms table
           : $_[2] - (url) - url to scrape
           : $_[3] - (page) - start page
  Throws   : -
  Comment  : if url has hit(s) data is stored into database
           : this list contains upto 4 urls that will be scraped at next stage

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub scrapeResultList {
    my $siteID     = shift;
    my $resultID   = shift;
    my $url        = shift;
    my $page       = shift;

    my $scrape_uri = $url . $page;
    my $lastpage=1;

    our $maxPage=1;
    my ($title,$isSubList,$search,$read,$browse,$print); #page & sitedID defined previously
    my (@row,@update);

    $c++; # counter, how many times has this sub been fired up?

    #scrape
    #$scrape_uri = uri_escape($scrape_uri);
    my $res = $ResultList->scrape( URI->new($scrape_uri) );

    # find lastpage from pageurls
    if ( exists( $res->{'pageurls'} ) ) {
        $lastpage = &lastPage( $res->{page}, @{ $res->{pageurls} } );
        $maxPage = $lastpage if ( $lastpage > $maxPage );
    }
    my $currentPage =  defined $res->{'page'} ? $res->{'page'} : $page ;

    my ($hits) = $res->{'comment'} =~ /(\d+)/; # strip comment for non-digits -> hits == digits
    print "$resultID \t: $hits\n" if (($gDebug) && (($c%$pr==0) || ($hits>0)));
    unless ( $hits >= $maxHits ) {
        if ($hits==0) {
            @update = (0, 1, $resultID, $siteID); #hits, checked, resultID, siteID ... Pages må vente
            #print "($hits, 1, $resultID, $siteID)\n" if ($gDebug);
            &DBIresultUpdate(\@update) if (isNew('resultID',$resultID));
        } else {
            for my $i ( 0 .. $#{ $res->{'data'} } ) {
                # this part only works if there is data to process thus hits>0
                my $isSubList = 0;
                #resultID, siteID, page
                $title = defined $res->{'data'}[$i]->{'title'} ? $res->{'data'}[$i]->{'title'} : '';
                #isSubList if  # char 149 (bullet)
                $_ = substr($title, 0, 1);
                $isSubList = 1 if (/\W/);
                $search = defined $res->{'data'}[$i]->{'search_url'} ? $res->{'data'}[$i]->{'search_url'} : '';
                $read   = defined $res->{'data'}[$i]->{'read_url'}   ? $res->{'data'}[$i]->{'read_url'}   : '';
                $browse = defined $res->{'data'}[$i]->{'browse_url'} ? $res->{'data'}[$i]->{'browse_url'} : '';
                $print  = defined $res->{'data'}[$i]->{'print_url'}  ? $res->{'data'}[$i]->{'print_url'}  : '';
                print "($i) $title\n" if ($gDebug);
                @update = ($hits, 1, $resultID, $siteID); #hits, checked, resultID, siteID ... Pages must wait
                #print "($hits, 1, $resultID, $siteID)\n" if ($gDebug);
                #       `resultID` `siteID` `page` `title` `isSubList` `search` `read` `browse` `print`));
                @row = ($resultID, $siteID, $page, $title, $isSubList, $search, $read, $browse, $print);
                &DBIresultUpdate(\@update) if (isNew('resultID',$resultID)); #save only if it's new
                my ($sth_handle,$resultListID) = &DBIresultList2DB(\@row);
            } # for
        } # if else
        $page++;
        return ($page) if ($page>=$maxHits); # Failsafe for termination, should never happen IRL
        #if ($gsState>0)
        #{
        #    my $sleep = (rand($gsRand)/(rand($gsFact)*31) );
        #    $sleep = (int($sleep*1000))/1000;
        #    $slept += $sleep;
        #    print "Sleep: $sleep - $slept\t" if ($gDebug);
        #    sleep($sleep);
        #}
        #$siteID,$resultID,$url,$page
        ($page) = &scrapeResultList($siteID,$resultID,$url,$page) if $page < $maxPage; #recursive (repeat if more pages)
    } #unless
    return ($page);
}

#-----------------------------------------------------------------------------
=pod

=head2 parm2CSV()


  Stage    : 2

  Purpose  : save data to predefined filehandle
  Returns  :
  Argument : $_[0] - arrayref to data
  Throws   : -
  Comment  : saves "prints" data to csv file tab seprated

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub parm2CSV {
    my $string = "";
    our $csvFH;

    $string = join("\t",@{$_[0]});
    $string .="\n";
    #print "$string" if ($count % $pr == 0);
    print "." if ($count % $pr == 0);
    print $csvFH $string ;
    $count++; # next resultID
}


#-----------------------------------------------------------------------------
=pod

=head2 isNew()

  Stage    : 2

  Purpose  : Holds counter value for a given key
  Returns  : undef,0,1
  Argument : $_[0] - (key) - key for hash
           : $_[1] - (new) - new value
  Throws   : -
  Comment  : Check's if key has incremented, True only if newer (larger)
           : Autoincrements always get larger....
           :
           : Use only on counters, or variables that have postiv increments
           : True only if new>old{$key}, false otherwise
           : Note! returns undef if new == 0 (reset state)
           : value to check should always be >0

 See Also  :

=cut

#-----------------------------------------------------------------------------
sub isNew{
    my $key = shift;
    my $new = shift;
    our %old;
    my $rtn = undef;
    unless ($new == 0){
        if ($new>$old{$key}){
           $old{$key}=$new;
           $rtn=1;
        } else {$rtn=0;}
    } else {$old{$key} = 0;} #rtn undef
    return $rtn
}


#-----------------------------------------------------------------------------
=pod

=head2 daResultparms()

  Stage    : 2

  Purpose  : Retrieve URLs (and ID) - to be scraped - on Digital Archives of Norway.
  Returns  : ref to 'Array of hashes'
                `resultID` - id
                `url`      - url to scrape
  Argument : $_[0] - (siteID) - <integer> process this site
           : $_[1] - (skip)   - <boolean>
           :

  Throws   : Die - on SQL error
  Comment  : MySQL
           : Skip false is the default, new items have skip=false, skip true is set for
           : items we normally want to skip, eg those with hits=0 this speeds up next re-run.
           : If we want to test those later on, check those who have skip=true.
           : NB Uses Limit set globally
           :
           : `checked` = FALSE -> normally those rows wich isn't scraped before.

See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daResultparms {
    my $skip = defined $_[1] ? $_[1] : 0;
    my @fields = (qw(resultID url));
    my ($resultID, $url, $ref);
    my %data =();
    my %rtn = ();
    my $LIMIT ="";
    $LIMIT = "LIMIT $gLimit" if ($gLimit);
    my $sql = qq{SELECT `resultID`,`url` FROM `$db`.`resultparms` WHERE `checked`=false AND `siteID`=? AND `skip`= ? ORDER BY `resultID` $LIMIT};
    our $dbh = &Connect2DB() if not($Connected);
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute( $_[0], $skip );
    #my $r = $sth->rows;
    #my @rows_loh = @{ $sth->fetchall_arrayref( {} ) };
    #return ( \@rows_loh );
    $ref = $sth->fetchall_arrayref({});
    if ($DBI::errstr) {
        print "Error detected: $DBI::errstr\n";
        return $ref;
    }elsif (ref($ref) eq 'ARRAY') {
        return $ref;
    } else {
        print "\nError: ";
        print Dumper($ref);
    }
}

#-----------------------------------------------------------------------------
=pod

=head2 daGeography()

  Stage    : 2

  Purpose  : Retrieve geographic form options previously stored in the database.
  Returns  : ref to 'Array of hashes'
                `r` - code for region (region)
                `f` - code for county (fylke)
                `k` - code for municipal (kommune)
                `bit` - string to put in url to define next search
  Argument : $_[0] - (siteID) - <integer> inputs are from this site
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Gets geographic info for given site, from view.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daGeography {
    my @rows = ();
    my $ref =\@rows;
    if ($InG){
        my $sql = qq{SELECT `r`,`f`,`k`,`bit` FROM `$db`.`vgeography` WHERE `siteID`=? ORDER BY `k` };
        #my $sql = qq{SELECT `r`,`f`,`k`,`bit` FROM `da`.`vgeography` WHERE `siteID`=? ORDER BY `k` };
        our $dbh = &Connect2DB() if not($Connected);
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        $ref = $sth->fetchall_arrayref({});
        if ($DBI::errstr) {
            print "Error detected: $DBI::errstr\n";
            return $ref;
        }elsif (ref($ref) eq 'ARRAY') {
            return $ref;
        } else {
            print "\nError: ";
            print Dumper($ref);
        }
    }# if
}

#-----------------------------------------------------------------------------
=pod

=head2 daGeography2()

  Stage    : 2

  Purpose  : Retrieve geographic form options previously stored in the database.
  Returns  : ref to 'Array of hashes'
                `r` - code for region (region)
                `f` - code for county (fylke)
                `bit` - string to put in url to define next search
  Argument : $_[0] - (siteID) - <integer> inputs are from this site
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Gets geographic info for given site, from view.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daGeography2 {
    my @rows = ();
    my $ref =\@rows;
    if($InG) {
        my $sql = qq{SELECT `r`,`f`,`bit` FROM `$db`.`vgeography2` WHERE `siteID`=? ORDER BY `f` };
        our $dbh = &Connect2DB() if not($Connected);
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        $ref = $sth->fetchall_arrayref({});
        if ($DBI::errstr) {
            print "Error detected: $DBI::errstr\n";
            return $ref;
        }elsif (ref($ref) eq 'ARRAY') {
            return $ref;
        } else {
            print "\nError: ";
            print Dumper($ref);
        }
    }# if
}

#-----------------------------------------------------------------------------
=pod

=head2 daSource()

  Stage    : 2

  Purpose  : Retrieve source form options previously stored after scraping
  Returns  : ref to 'Array of hashes'
                `ka` - code for source category (kilde)
                `kt` - code for source type (kildetype)
                `bit` - string to put in url to define next search
  Argument : $_[0] - (siteID) - <integer> inputs are from this site
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Digital Archives of Norway. Gets source info for given site.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daSource {
    my @rows = ();
    my $ref =\@rows;
    if ($InS) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql = qq{SELECT `ka`,`kt`,`bit` FROM `$db`.`vInputKT` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        $ref = $sth->fetchall_arrayref({});
        if ($DBI::errstr) {
            print "Error detected: $DBI::errstr\n";
            return $ref;
        }elsif (ref($ref) eq 'ARRAY') {
            return $ref;
        } else {
            print "\nError: ";
            print Dumper($ref);
        }
    }# if
}

#-----------------------------------------------------------------------------
=pod

=head2 daListType()

  Stage    : 2

  Purpose  : Retrieve church book list types
  Returns  : ref to 'Array of hashes'
                `ka` - code for source category (kilde)
                `kt` - code for source type (kildetype)
                `lt` - code for list type (listetype)
                `bit` - string to put in url to define next search
  Argument : $_[0] - (siteID) - <integer> inputs are from this site
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Gets source info for given site.
           : Creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daListType {
    my @rows = ();
    my $ref =\@rows;
    if ($InL) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql = qq{SELECT `ka`,`lt`,`bit` FROM `$db`.`vInputLT` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        $ref = $sth->fetchall_arrayref({});
        if ($DBI::errstr) {
            print "Error detected: $DBI::errstr\n";
            return $ref;
        }elsif (ref($ref) eq 'ARRAY') {
            return $ref;
        } else {
            print "\nError: ";
            print Dumper($ref);
        }
    }# if
}

#-----------------------------------------------------------------------------
=pod

=head2 daTheme()

  Stage    : 2

  Purpose  : Retrieve form options - themes types
  Returns  : ref to 'Array of hashes'
                `theme` - code for source theme (tema)
                `bit` - string to put in url to define next search
  Argument : $_[0] - (siteID) - <integer> inputs are from this site
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Data is sorted into themes.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

  See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daTheme {
    my @rows = ();
    my $ref =\@rows;
    if  ($InT) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql= qq{SELECT `theme`,`bit` FROM `$db`.`vInputTheme` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
             or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        $ref = $sth->fetchall_arrayref({});
        if ($DBI::errstr) {
            print "Error detected: $DBI::errstr\n";
            return $ref;
        }elsif (ref($ref) eq 'ARRAY') {
            return $ref;
        } else {
            print "\nError: ";
            print Dumper($ref);
        }
    }# if
}

#-----------------------------------------------------------------------------
=pod

=head2 daFormat()

  Stage    : 2

  Purpose  : Retrieve form options - format types
  Returns  : ref to 'Array of hashes'
                `format` - code for source format (format)
                `bit` - string to put in url to define next search
  Argument : $_[0] - (siteID) - <integer> inputs are from this site
  Throws   : Die - on SQL error
  Comment  : MySQL
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).


 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daFormat {
    my @rows = ();
    my $ref =\@rows;
    if ($InF) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql= qq{SELECT `format`,`bit` FROM `$db`.`vInputFormat` where `siteID`=?};
        #my $sql= qq{SELECT `format`,`bit` FROM `da`.`vInputFormat` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        $ref = $sth->fetchall_arrayref({});
        if ($DBI::errstr) {
            print "Error detected: $DBI::errstr\n";
            return $ref;
        }elsif (ref($ref) eq 'ARRAY') {
            return $ref;
        } else {
            print "\nError: ";
            print Dumper($ref);
        }
    }# if
}

#-----------------------------------------------------------------------------
=pod

=head2 daOrgan()

  Stage    : 2

  Purpose  : Retrieve form options - Organ types
  Returns  : ref to 'Array of hashes'
                `ok` - code for organ (Organ)
                `ko` - subcode for `ok`
                `bit` - string to put in url to define next search
  Argument : $_[0] - (siteID) - <integer> inputs are from this site
  Throws   : Die - on SQL error
  Comment  : MySQL
           : The function creates an array of hashes (to be traversed later).
           : (Currently only 2 Organs - mining, industry)
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daOrgan {
    my @rows = ();
    my $ref =\@rows;
    if ($InO) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql= qq{SELECT `ok`,`ko`,`bit` FROM `$db`.`vInputKO` where `siteID`=?};
        #my $sql= qq{SELECT `ok`,`ko`,`bit` FROM `da`.`vInputKO` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        $ref = $sth->fetchall_arrayref({});
        if ($DBI::errstr) {
            print "Error detected: $DBI::errstr\n";
            return $ref;
        }elsif (ref($ref) eq 'ARRAY') {
            return $ref;
        } else {
            print "\nError: ";
            print Dumper($ref);
        }
    }# if
}


#-----------------------------------------------------------------------------
=pod

=head2 DBIloadCSVresultparms()

  Stage    : 2

  Purpose  : Bulk save CSV file containing form data from web page
  Returns  : (\$sth) -  ref to statement handle
           : ($rows) - number of inserted rows
  Argument : $_[0] - (file) - file with data
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Saves file to table "resultparms" using LOAD DATA.
           : File expected to have headers in first line

 See Also  : DBIloadFile()

=cut

#-----------------------------------------------------------------------------
sub DBIloadCSVresultparms {
    my $file   = shift;
    #my $runID  = shift;

    #my @fields = @{ $_[2] };
    #my $tab    = exists $cfg{'DBI.fTerm'} ? $cfg{'DBI.fTerm'} : '\x{09}'; #defalt tab is x09 (TAB)
    #my $lf     = exists $cfg{'DBI.lTerm'} ? $cfg{'DBI.fTerm'} : '\x{0A}'; #default linfeed is  x0A (LF)
    my $tab    = '\t'; #defalt tab is x09 (TAB)
    my $lf     = '\n'; #default linfeed is  x0A (LF)
    my $rows=0;
    our $dbh = &Connect2DB() if not($Connected);
    my $sql = qq{LOAD DATA LOCAL INFILE '$file' REPLACE INTO TABLE `$db`.`resultparms` CHARACTER SET UTF8 FIELDS TERMINATED BY ',' ENCLOSED BY '"' IGNORE 1 LINES (resultID, siteID, r, f, k, ka, kt, lt, format, theme, ok, ko, url, skip, runID)};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $rows = $sth->execute();
    if ($rows>0)
    {
        print "\nLoaded $rows rows\n" if ($gDebug);
    }
    else {
        print "Can't execute SQL statement: ", $sth->errstr(), "\n";
    }
    return (\$sth,$rows);
}

#-----------------------------------------------------------------------------
=pod

=head2 DBIloadFile()

  Stage    : 2

  Purpose  : Generic file loader. Wrapper for DBI Load DATA function.
  Returns  : (\$sth) -  ref to statement handle
           : ($rows) - number of inserted rows
  Argument : $_[0] - (file) filename,
           : $_[1] - (table) tablename,
           : $_[2] - (fields) ref to array of fields
           : $_[3] - (set) "SET" statement
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Bulk saves data from a file to database.
           : File expected to have headers in first line
           : SET can be any valid SQL (Should failsafe it?)

 See Also  : DBIloadCSVresultparms()

=cut

#-----------------------------------------------------------------------------
sub DBIloadFile {
    #ToDo ignore lines, set terminated by etc as options
    my $file   = $_[0];
    my $table  = $_[1];
    my @fields = @{ $_[2] };
    my $set    = $_[3] if (length($_[3])); # eg SET columnX = CURRENT_TIMESTAMP
    #y $tab    = exists $cfg{'DBI.fTerm'} ? $cfg{'DBI.fTerm'} : '\x{09}'; #defalt tab is x09 (TAB)
    #y $lf     = exists $cfg{'DBI.lTerm'} ? $cfg{'DBI.fTerm'} : '\x{0A}'; #default linfeed is  x0A (LF)
    #my $tab    = '\t'; #defalt tab is x09 (TAB)
    my $tab    = ','; #defalt tab is x09 (TAB)
    my $lf     = '\n'; #default linfeed is  x0A (LF)
    my $rows=0;
    our $dbh = &Connect2DB() if not($Connected);
    my $fieldlist = join ", ", @fields;
    #CHARACTER SET UTF8 FIELDS TERMINATED BY ',' ENCLOSED BY '"' IGNORE 1 LINES
    my $sql = qq{LOAD DATA LOCAL INFILE '$file' REPLACE INTO TABLE `$db`.`$table` CHARACTER SET UTF8 FIELDS TERMINATED BY  '$tab' ENCLOSED BY '"' IGNORE 1 LINES ( $fieldlist ) };
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $rows = $sth->execute();
    if ($rows>0)
    {
        print "Loaded $rows rows\n" if ($gDebug);
    }
    else {
        print "Can't execute SQL statement: ", $sth->errstr(), "\n";
    }
    return (\$sth,$rows);
}


#-----------------------------------------------------------------------------
=pod

=head2 DBIresultParms2DB()

  Stage    : 2

  Returns  : (\$sth) -  ref to statement handle
           : ($resultID) - Last ID insterted
  Argument : $_[0] - (row) ref to array. list/"row" of data to be saved
                `r`      - code for region (region)
                `f`      - code for county (fylke)
                `k`      - code for municipal (kommune)
                `ka`     - code for source category (kilde)
                `kt`     - code for source type (kildetype)
                `lt`     - subcode for `kt`, list type (listetype)
                `format` - code for ...(Format)
                `theme`  - code for ...(Tema)
                `ok`     - code for organ (Organ)
                `ko`     - subcode for `ok`
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Saving form parameters to database one row at a time.
            :
           : Not all permutations of parameters will yield result (URL - with
           : data to further scrape), some parameters are logically linked,
           : however, there are 10 different parameters that all have several
           : possibilities. Each value gives different URL to check (later).
           : Not all fields in table resultParms get saved/updated.
           : Some things need to be scraped later on.
           : Following fields are for keeping track of next stage
           : * Checked=true means site is chekcked/scraped
           : * changed/hits/pages/runID is filled in after scrape

  See Also : DBIresultUpdate()

=cut

#-----------------------------------------------------------------------------
sub DBIresultParms2DB {
    my @row= @{ $_[0]};
    #our $resultID;
    our $dbh = &Connect2DB() if not($Connected);
    my @fields =(qw(`siteID` `hits` `url` `r` `f` `k` `ka` `kt` `lt` `format` `theme` `ok` `ko`));
    my $fieldlist = join ", ", @fields;
    my $field_placeholders = join ', ', ('?') x @fields;
    my $sql = qq{REPLACE INTO `$db`.`resultParms` ( $fieldlist ) VALUES( $field_placeholders )};
    #my $sql = qq{REPLACE INTO `da`.`resultParms` ( $fieldlist ) VALUES( $field_placeholders )};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    if ($sth->execute($row[0],$row[1],$row[2],$row[3],$row[4],$row[5],$row[6],$row[7],$row[8],$row[9],$row[10],$row[11],$row[12]))
    {
        $resultID = $sth->{mysql_insertid};
    } else {
        #or die
        print "Can't execute SQL statement: ", $sth->errstr(), "\n";
        print "NOT ok - insert\n";
    }
    return (\$sth,$resultID);
}

#-----------------------------------------------------------------------------
=pod

=head2 DBIresultUpdate()

  Stage    : 2

  Purpose  : Update a single line in resultparms.
  Returns  : True/False (ok/fail)
  Argument : $_[0] - (data) ref to list of data
                0=>hits, (value)
                1=>checked, (value)
                2=>resultID, (where)
                3=>siteID, (where)
  Throws   : Die - on SQL error in preperation, not execution
  Comment  : MySQL
           : First 2 arguments are update values, next 2 are identificators in where clause
           : hits - number of sources to further lookup. pages >1 if data to further lookup.
           : if pages=0, then skip=true (no data found, don't waste time on next normal run).
           : Sometimes not all data can be harvested on a single page,  (pages are then => 2)

 See Also  : DBIresultParms2DB()

=cut

#-----------------------------------------------------------------------------
sub DBIresultUpdate {
    #0=>hits, 1=>checked, (skip), 2=>resultID, 3=>siteID
    my @data = @{ $_[0] };
    my $rtn;
    our $dbh = &Connect2DB() if not($Connected);
    my $skip = ($data[0]>0) ? 0 : 1; #hits >0 -> false else true
    my $sql =qq{Update `$db`.`resultparms` SET `hits`=?, `checked`=?, `skip`=?, `runID`=? WHERE `resultID`=? AND `siteID`=? };
    #my $sql =qq{Update `da`.`resultparms` SET `hits`=?, `checked`=?, `skip`=?, `runID`=? WHERE `resultID`=? AND `siteID`=? };
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    if ($sth->execute($data[0],$data[1],$skip,$runID,$data[2],$data[3]))
    {
        $rtn=1; #ok
        #print "Update: $data[0],$data[1],$skip,$data[2],$data[3]\n" if ($gDebug);
    }
    else {
        #or die ?
        print "\nUpdateFailed: $data[0],$data[1],$skip,$data[2],$data[3]\n" if ($gDebug);
        $rtn=0; #not ok
        print "Can't execute SQL statement: ", $sth->errstr(), "\n";
    }
    return $rtn;
}


#-----------------------------------------------------------------------------
#                            S T A G E  3
#-----------------------------------------------------------------------------
=pod

=head2 DBIresultList2DB()

  Stage    : 3

  Purpose  : Save array of arrays (resultlist) to the database
  Returns  : ref to statement handler & Last ID insterted C<\$sth,$resultListID>
  Argument :  $_[0] - (data) ref to array (list)
           : Columns: `resultID` `siteID` `page` `title` `isSubList` `search` `read` `browse` `print` `runID`
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Digital Archives of Norway "Finn kilde" (Find source) has listing
           : (resultList) that is saved to database.
           : Data from scraping is an array of arrays.

 See Also   :

=cut

#-----------------------------------------------------------------------------
sub DBIresultList2DB {
    my @data = @{ $_[0] };
    our $dbh = &Connect2DB() if not($Connected);
    #our $resultListID;
                   # $resultID, $siteID, $page, $title, $isSubList, $search, $read, $browse, $print);
    my @fields = (qw(`resultID` `siteID` `page` `title` `isSubList` `search` `read` `browse` `print` `runID`));
    my $fieldlist = join ", ", @fields;
    #my $field_placeholders = join ", ", map { '?' } @fields;
    my $field_placeholders = join ', ', ('?') x @fields;
    my $sql =qq{REPLACE INTO `$db`.`resultList` ( $fieldlist ) VALUES( $field_placeholders )};
    #my $sql =qq{REPLACE INTO `da`.`resultList` ( $fieldlist ) VALUES( $field_placeholders )};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    if ($sth->execute($data[0],$data[1],$data[2],$data[3],$data[4],$data[5],$data[6],$data[7],$data[8],$runID))
    {
        $resultListID = $sth->{mysql_insertid};
        #print "insert ok $row\n" if ($gDebug);
    }
    else {
        #or die
        print "Can't execute SQL statement: ", $sth->errstr(), "\n";
        print "NOT ok - insert\n";
    }
    return (\$sth,$resultListID);
}


#-----------------------------------------------------------------------------
#                            S T A G E  4
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
#                            S T A G E  5
#-----------------------------------------------------------------------------
=pod

=head2 parseURI()

  Stage    : 5

  Purpose  : Split URI into several elments
  Returns  : ($base) - base of URI
           : ($uri)  - uri to metadata-info on source
           : ($daID) - DA-ID internal (Digitalarkivet) ID
           : ($cat)  - (Main) category
           : ($lt)   - List type, subcategory
           : ($file) - Boolean ('is' file or not)
  Argument : : $_[0] - (str) <string> URI
  Throws   :
  Comment  : Parses URI, returns elements into logical parts of the URI
           : URI has structural info on source. returns URI that shows metadata
           : of source. Category and lt are main components of logical structure.
           : Expects URI like http://digitalarkivet.arkivverket.no/kb/sok/dp/17101
           : or http://xml.arkivverket.no/matrikler/ma01001723.pdf

 See Also   :

=cut

#-----------------------------------------------------------------------------
sub parseURI{
    my @str;
    my $base = '';
    my $daID = '';
    my $cat  = '';
    my $lt   = '';
    my $uri  = '';
    my $file = 0;

    @str = split(/\//,$_[0]); # input URI
    $base = shift @str; #remove http:
    $base = shift @str; #remove blank -> //
    $base = shift @str;
    $_  = pop @str;
    if (m/\./){
        $file = 1;
    } elsif ( $#str == 2 ) {
        $daID=$_;
        $uri="http://digitalarkivet.arkivverket.no/kilde/$daID";
        $lt = pop   @str;
        $cat= shift @str;
    } else {
        $daID=$_;
        $uri="http://digitalarkivet.arkivverket.no/kilde/$daID";
    }
    return ($base, $uri, $daID, $cat, $lt, $file);
}
#-----------------------------------------------------------------------------
#                            S T A G E  6
#-----------------------------------------------------------------------------


1;    #return true if this file is required by another program

__END__

=pod

=head1 SEE ALSO

perl(1), I<DigitalArkivet-GetForm.pl>, I<DigitalArkivet-finn_kilde.pl>, I<DigitalArkivet-eiendom_avansert.pl>



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
useful, but it is provided 'as is' and without any express
or implied warranties. For details, see the full text of
the license in the file LICENSE.

=cut
