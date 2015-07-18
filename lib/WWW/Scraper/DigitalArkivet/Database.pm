package WWW::Scraper::DigitalArkivet::Database;
use strict;
use warnings;

BEGIN {
    use Exporter ();
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $gDebug $Connected $runID %cfg);
    $VERSION     = '0.01';
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    @EXPORT_OK   = qw(Connect2DB() Disconnect2DB() DBIresetDA() getRunID() DBIform2DB()
    daResultparms() daGeography() daGeography2() daSource() daListType() daTheme()
    daFormat() daOrgan() DBIloadCSVresultparms() DBIloadFile() DBIresultParms2DB()
    DBIresultParms2DB() DBIresultUpdate() DBIresultList2DB() doDBIrunStart()
    doDBIrunStat() );
    %EXPORT_TAGS = ();
}

#-----------------------------------------------------------------------------
=pod


=head1 NAME

B<WWW::Scraper::DigitalArkivet::Database> - Database routines for Digitalarkivet.


=head1 SYNOPSIS

  use WWW::Scraper::DigitalArkivet::Database;


=head1 DESCRIPTION

Library for DBI related operations to save/retrieve metadata of sources from
national archival databases in Norway also known as Digitalarkivet -
the Digital Archives of Norway.


=head1 USAGE


=head1 TODO

CDC or SCD data approach?

=head1 CONFIGURATION AND ENVIRONMENT

Tested on win7, no known ties to this platform should work for other platforms.
    see config file - B<DigitalArkivet.cfg>


=head1 BUGS


=head1 SUPPORT


=head1 DEPENDENCIES

Requires modules Config::Simple and DBI
Database structure as of DA-webscraper.mwb v.0.


=head1 AUTHOR

Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>
Member of DIS-Norge, The Genealogy Society of Norway-DIS

Please drop me an email if you use this in any project. It would be nice to
know if it's usable for others in any capacity. Any suggestions for improvement
are also appreciated.


=head1 REVISION HISTORY

 0.04 - 14.07.2015 - Module
 0.04 - 01.07.2015 - POD - Documented, minor bugfix'es
 0.03 - 01.10.2014 - Added proc resetDA
 0.02 - 21.09.2014 - Added Tables resultList, resultParms, resultBrowse.
                     Views: vgeography,vinput,vinputf,vinputformat,vinputk,
                            vinputka, vinputkt,vinputlt,vinputr,vinputtheme
 0.01 - 01.08.2014 - Created. Tables form, site, toscrape

=cut

#-----------------------------------------------------------------------------

# modules
use Config::Simple;
use DBI;

# import configuration into %cfg hash:
Config::Simple->import_from( 'DA.cfg', \%cfg );

# Configurations from file overrides defaults (on the left)
my $driver = defined $cfg{'DBI.driver'} ? $cfg{'DBI.driver'} : "mysql";
my $db     = defined $cfg{'DBI.db'} ? $cfg{'DBI.db'} : "da";
my $host   = defined $cfg{'DBI.host'} ? $cfg{'DBI.host'} : "localhost";
my $port   = defined $cfg{'DBI.port'} ? $cfg{'DBI.port'} : "3306" ;
my $user   = defined $cfg{'DBI.user'} ? $cfg{'DBI.user'} : "root" ;
my $pwd    = defined $cfg{'DBI.pwd'} ? $cfg{'DBI.pwd'} : "";
my $attr   = defined $cfg{'DBI.attr'} ? $cfg{'DBI.attr'} : "PrintError,0,RaiseError,1,mysql_enable_utf8,1" ;
my $gLimit = defined $cfg{'DBI.limit'} ? $cfg{'DBI.limit'} : 10000;
my %attr   = @$attr;

# "boolean" vars that prevent SQL to be executed (IF clause).
# sections can be configured not to 'execute' by having value set to 0
# settings in configuration file if defined overides default values
my  $InG    = defined $cfg{'Input.geo'} ? $cfg{'Input..geo'} : 1;
my  $InS    = defined $cfg{'Input.src'} ? $cfg{'Input.src'} : 1;
my  $InL    = defined $cfg{'Input.lt'} ? $cfg{'Input.lt'} : 0;
my  $InT    = defined $cfg{'Input.theme'} ? $cfg{'Input.theme'} : 0;
my  $InF    = defined $cfg{'Input.format'} ? $cfg{'Input.format'} : 0;
my  $InO    = defined $cfg{'Input.organ'} ? $cfg{'Input.organ'} : 0;

$Connected = undef; # only defined if connected to DB.
$runID=&getRunID(); #process id, used as key




#-----------------------------------------------------------------------------
=pod

=head1 METHODS

Each subroutine/function (method) is documented.

B<NOTE:>

Stages correspond to those in Digitalarkivet.pl, data is collected at
different stages and stored in the database. Enabling re-runs to pick up were
"left off". Memory usage required to hold/store data temporary in internal
data structures depend on chunk sizes.

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

    a. Search
    b. Browse
    c. Info. Details about each source
    d.

=head3 B<Stage 4>

    1. Try ID numbers - not published. Find info about (hidden) sources
    2. Last 100

=cut

#-----------------------------------------------------------------------------
################################ subroutines #################################
#-----------------------------------------------------------------------------
=pod

=head2 Connect2DB()

  Purpose  : Establish and hold connection to a database
  Returns  : Database handle
  Argument : <none>
  Throws   : Die - on SQL error
  Comment  : Connects to a database, returns the handle to it for further use.

 See Also  : Disconnect2DB()

=cut

#-----------------------------------------------------------------------------
sub Connect2DB {
    my $dsn = "dbi:$driver:$db:$host:$port";
    our $dbh;

    eval { $dbh = DBI->connect( $dsn, $user, $pwd, \%attr ); };
    if ( $DBI::err && $@ =~ /^(\S+) (\S+) failed: / ) {
        print "SQL error: $DBI::errstr ($DBI::err) $1 $2 - $@\n";
    }
    else {
        $Connected = 1;
    }
    return $dbh;
}

#-----------------------------------------------------------------------------
=pod

=head2 Disconnect2DB()

  Purpose  : Terminate database connection
  Returns  : <none>
  Argument : <none>

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
  Comment  : Connect to a database, returns the handle to it for further use.

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
  Comment  : Every Run has a unique process number (autoincrement).
           : Used to identify which data is collected when. Every run has a
           : unique process number (autoincremented). Used to identify which
           : data is collected when. (During which run).

=cut

#-----------------------------------------------------------------------------
sub getRunID {
    our $dbh = &Connect2DB() if not($Connected);
    my $sql= qq{SELECT `runID` FROM `$cfg{'DBI.db'}`.`run` ORDER BY `runID` DESC LIMIT 1};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute();
    ($runID) = $sth->fetchrow_array;
    return  $runID;
}

#-----------------------------------------------------------------------------
=pod

=head2 doDBIrunStart()

  Purpose  : Start data gathering
  Returns  : (RunID) - last insert id (mysql)
  Argument : action, hash ref to options
  Throws   : Die - on SQL error
  Comment  : hashref pass as argument is converted into string &key1=value1&key2=value2 etc
           : Invokes stored procedure `runStart` with 2 arguments
           : (Options) -string of options conveterd from hashref (options to "run" started)
           : (State) - sleep state
           : Marks beginning of data gathering (Starts log into the database)
           : Enables logging of progress "of run"/ harvesting of data

 See Also  : doDBIrunStat()

=cut

#-----------------------------------------------------------------------------
sub doDBIrunStart {
    use URI::Escape;
    my $href    = shift; # hashref
    my $rtn;
    our $dbh = &Connect2DB() if not($Connected);
    my $pState = defined $cfg{'Sleep.state'} ? $cfg{'Sleep.state'} : 0;
    #build option string eg &opt1=x&opt2=y
    my $Options=join '&',map {uri_escape($_).'='.uri_escape($href->{$_})} grep {defined $href->{$_}} keys %$href;
    my $sql = qq{CALL `$cfg{'DBI.db'}`.`runStart`( ?, ? ) } ;
    our $sth = $dbh->prepare($sql)
            or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute($Options, $pState);
    $rtn = $sth->{mysql_insertid};
    return  $rtn
}


#-----------------------------------------------------------------------------
=pod

=head2 doDBIrunStat()

  Purpose  : log statistical data of harvesting
  Returns  : 1
  Argument : RunID
  Throws   : Die - on SQL error
  Comment  : invokes stored procedure `runStat`
           : Used to track progress of run, also updates som statsical data
           : ()

 See Also  : doDBIrunStart()

=cut

#-----------------------------------------------------------------------------
sub doDBIrunStat {
    use URI::Escape;
    my $pID    = shift; # runID
    our $dbh = &Connect2DB() if not($Connected);
    my $sql = qq{CALL `$cfg{'DBI.db'}`.`runStat`( ? ) } ;
    our $sth = $dbh->prepare($sql)
            or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    print "Can't execute SQL statement: ", $sth->errstr(), "\n" unless ($sth->execute($pID));
    return  1
}

#-----------------------------------------------------------------------------
=pod

=head2 DBIForm2DB()

  Stage    : 1

  Purpose  : Save form data to database. (Array from form into database).
  Returns  : Handle to execution of statement
  Argument : Handle to array with data
  Throws   : Die - on SQL error
  Comment  : All form's have a basic structure that is possible to save in tabular format.
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
    my @fields = (qq(`siteID` `level` `line` `label_for` `text` `name` `value` `id` `type` `name2` `lf1` `lf2` `lf3`));
    my $fieldlist = join ", ", @fields;
    my $field_placeholders = join ", ", map { '?' } @fields;
    my $sql = qq{REPLACE INTO `$cfg{'DBI.db'}`.`form` ( $fieldlist ) VALUES( $field_placeholders )};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    foreach my $row (@data) {
        #my $xx=0;
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
=pod

=head2 daResultparms()

  Stage    : 2

  Purpose  : Retrieve URLs (and ID) - to be scraped - on Digital Archives of Norway.
  Returns  : ref to 'list of hashes'
                `resultID` - id
                `url`      - url to scrape
  Argument : (siteID) - integer - inputs are from this site
             (skip)   - boolean
  Throws   : Die - on SQL error
  Comment  : Skip false is the default, new items have skip=false, skip true is set for
           : items we normally want to skip, eg those with hits=0 this speeds up next re-run.
           : If we want to test those later on, check those who have skip=true.
           :
           : `checked` = FALSE -> normally those rows wich isn't scraped before.

See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daResultparms {
    my $skip = defined $_[1] ? $_[1] : 0;
    my @fields = (qw(resultID url));
    my ($resultID, $url);
    my %data =();
    my %rtn = ();
    my $LIMIT ="";
    $LIMIT = "LIMIT $gLimit" if ($gLimit);
    my $sql = qq{SELECT `resultID`,`url` FROM `$cfg{'DBI.db'}`.`resultparms` WHERE `checked`=false AND `siteID`=? AND `skip`= ? ORDER BY `resultID` $LIMIT};
    our $dbh = &Connect2DB() if not($Connected);
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute( $_[0], $skip );
    #my $r = $sth->rows;
    my @rows_loh = @{ $sth->fetchall_arrayref( {} ) };
    return ( \@rows_loh );
}

#-----------------------------------------------------------------------------
=pod

=head2 daGeography()

  Stage    : 2

  Purpose  : Retrieve geographic form options previously stored in the database.
  Returns  : ref to 'list of hashes'
                `r` - code for region (region)
                `f` - code for county (fylke)
                `k` - code for municipal (kommune)
                `bit` - string to put in url to define next search
  Argument : (siteID) - integer - inputs are from this site
  Throws   : Die - on SQL error
  Comment  : Gets geographic info for given site, from view.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------

sub daGeography {
    my @rows_loh = ();
    if ($InG){
        my $sql = qq{SELECT `r`,`f`,`k`,`bit` FROM `$cfg{'DBI.db'}`.`vgeography` WHERE `siteID`=? ORDER BY `k` };
        our $dbh = &Connect2DB() if not($Connected);
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        my @rows_loh = @{ $sth->fetchall_arrayref( {} ) };
    }# if
    return ( \@rows_loh );
}

#-----------------------------------------------------------------------------
=pod

=head2 daGeography2()

  Stage    : 2

  Purpose  : Retrieve geographic form options previously stored in the database.
  Returns  : ref to list of hashes
                `r` - code for region (region)
                `f` - code for county (fylke)
                `bit` - string to put in url to define next search
  Argument : (siteID) - inputs are from this site
  Throws   : Die - on SQL error
  Comment  : Gets geographic info for given site, from view.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------

sub daGeography2 {
    my @rows_loh = ();
    if($InG) {
        my $sql = qq{SELECT `r`,`f`,`bit` FROM `$cfg{'DBI.db'}`.`vgeography2` WHERE `siteID`=? ORDER BY `f` };
        our $dbh = &Connect2DB() if not($Connected);
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        my @rows_loh = @{ $sth->fetchall_arrayref( {} ) };
    }# if
    return ( \@rows_loh );
}

#-----------------------------------------------------------------------------
=pod

=head2 daSource()

  Stage    : 2

  Purpose  : Retrieve source form options previously stored after scraping
  Returns  : ref to list of hashes
                `ka` - code for source category (kilde)
                `kt` - code for source type (kildetype)
                `bit` - string to put in url to define next search
  Argument : (siteID) - inputs are from this site
  Throws   : Die - on SQL error
  Comment  : Digital Archives of Norway. Gets source info for given site.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daSource {
    my @rows_loh = ();
    if ($InS) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql = qq{SELECT `ka`,`kt`,`bit` FROM `$cfg{'DBI.db'}`.`vInputKT` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        my @rows_loh = @{ $sth->fetchall_arrayref( {} ) };
    }# if
    return ( \@rows_loh );
}

#-----------------------------------------------------------------------------
=pod

=head2 daListType()

  Stage    : 2

  Purpose  : Retrieve church book list types
  Returns  : ref to list of hashes
                `ka` - code for source category (kilde)
                `kt` - code for source type (kildetype)
                `lt` - code for list type (listetype)
                `bit` - string to put in url to define next search
  Argument : (siteID) - inputs are from this site
  Throws   : Die - on SQL error
  Comment  : Gets source info for given site.
           : Creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daListType {
    my @rows_loh = ();
    if ($InL) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql = qq{SELECT `ka`,`lt`,`bit` FROM `$cfg{'DBI.db'}`.`vInputLT` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute( $_[0] );
        #my $r = $sth->rows;
        my @rows_loh = @{ $sth->fetchall_arrayref( {} ) };
    } # if
    return ( \@rows_loh );
}

#-----------------------------------------------------------------------------
=pod

=head2 daTheme()

  Stage    : 2

  Purpose  : Retrieve form options - themes types
  Returns  : ref to list of hashes
                `theme` - code for source theme (tema)
                `bit` - string to put in url to define next search
  Argument : (siteID) - inputs are from this site
  Throws   : Die - on SQL error
  Comment  : Data is sorted into themes.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

  See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daTheme {
    my @rows_loh = ();
    if  ($InT) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql= qq{SELECT `theme`,`bit` FROM `$cfg{'DBI.db'}`.`vInputTheme` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
             or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
          $sth->execute($_[0]);
         #my $r=$sth->rows;
        my @rows_loh = @{$sth->fetchall_arrayref({})};
    }
    return ( \@rows_loh );

}

#-----------------------------------------------------------------------------
=pod

=head2 daFormat()

  Stage    : 2

  Purpose  : Retrieve form options - format types
  Returns  : ref to list of hashes
                `format` - code for source format (format)
                `bit` - string to put in url to define next search
  Argument : (siteID) - inputs are from this site
  Throws   : Die - on SQL error
  Comment  : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).


 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daFormat {
    my @rows_loh = ();
    if ($InF) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql= qq{SELECT `format`,`bit` FROM `$cfg{'DBI.db'}`.`vInputFormat` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute($_[0]);
        #my $r=$sth->rows;
        my @rows_loh = @{$sth->fetchall_arrayref({})}; # each row as a hashref (in a list)
    }
    return ( \@rows_loh );
}

#-----------------------------------------------------------------------------
=pod

=head2 daOrgan()

  Stage    : 2

  Purpose  : Retrieve form options - Organ types
  Returns  : ref to list of hashes
                `ok` - code for organ (Organ)
                `ko` - subcode for `ok`
                `bit` - string to put in url to define next search
  Argument : (siteID) - inputs are from this site
  Throws   : Die - on SQL error
  Comment  : The function creates an array of hashes (to be traversed later).
           : (Currently only 2 Organs - mining, industry)
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daOrgan {
    my @rows_loh = ();

# ToDo: vInputOK must be in DB !!
 # SELECT * FROM `vinput` where `siteID`=1 and `name2`in ('ok','ko')
#    if ($InO) {
#        our $dbh = &Connect2DB() if not($Connected);
#        my $sql= qq{SELECT `ok`,`ko`,`bit` FROM `$cfg{'DBI.db'}`.`vInputOK` where `siteID`=?};
#        our $sth = $dbh->prepare($sql)
#          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
#        $sth->execute($_[0]);
#        my $r=$sth->rows;
#        @rows_loh = @{$sth->fetchall_arrayref({})};
#    }
    return ( \@rows_loh );
}

#-----------------------------------------------------------------------------
=pod

=head2 DBIloadCSVresultparms()

  Stage    : 2

  Purpose  : Bulk save CSV file containing form data from web page
  Returns  : (\$sth) -  ref to statement handle
           : ($rows) - number of inserted rows
  Argument : (siteID) - inputs are from this site
  Throws   : Die - on SQL error
  Comment  : Saves file to table "resultparms" using LOAD DATA.
           : File expected to have headers in first line

 See Also  : DBIloadFile()

=cut

#-----------------------------------------------------------------------------
sub DBIloadCSVresultparms {
    my $file   = $_[0];
    #my @fields = @{ $_[2] };
    my $tab    = exists $cfg{'DBI.fTerm'} ? $cfg{'DBI.fTerm'} : '\x{09}'; #defalt tab is x09 (TAB)
    my $lf     = exists $cfg{'DBI.lTerm'} ? $cfg{'DBI.fTerm'} : '\x{0A}'; #default linfeed is  x0A (LF)
    my $rows=0;
    our $dbh = &Connect2DB() if not($Connected);
    my $sql = qq{LOAD DATA LOCAL INFILE '$file' REPLACE INTO TABLE `$cfg{'DBI.db'}`.`resultparms` CHARACTER SET UTF8 FIELDS TERMINATED BY ',' IGNORE 1 LINES (resultID, siteID, r, f, k, ka, kt, lt, format, theme, ok, ko, url, skip)};
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
  Argument :   0-filename,
                1-tablename,
                2-array of fields,
                3-"SET"
  Throws   : Die - on SQL error
  Comment  : Bulk saves data from a file to database.
           : File expected to have headers in first line
           : SET can be any valid SQL (Should failsafe it?)

 See Also  : DBIloadCSVresultparms()

=cut

#-----------------------------------------------------------------------------
sub DBIloadFile {
    my $file   = $_[0];
    my $table  = $_[1];
    my @fields = @{ $_[2] };
    my $set    = $_[3] if (length($_[3])); # eg SET columnX = CURRENT_TIMESTAMP
    my $tab    = exists $cfg{'DBI.fTerm'} ? $cfg{'DBI.fTerm'} : '\x{09}'; #defalt tab is x09 (TAB)
    my $lf     = exists $cfg{'DBI.lTerm'} ? $cfg{'DBI.fTerm'} : '\x{0A}'; #default linfeed is  x0A (LF)
    my $rows=0;
    our $dbh = &Connect2DB() if not($Connected);
    my $fieldlist = join ", ", @fields;
    my $sql = qq{LOAD DATA REPLACE INFILE $file INTO `$cfg{'DBI.db'}`.`$table` ( $fieldlist ) TERMINATED BY  '$tab' $set )};
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
  Argument : list of data to be saved
                `r` - code for region (region)
                `f` - code for county (fylke)
                `k` - code for municipal (kommune)
                `ka` - code for source category (kilde)
                `kt` - code for source type (kildetype)
                `lt` - subcode for `kt`, list type (listetype)
                `format` - code for ...(Format)
                `theme` - code for ...(Tema)
                `ok` - code for organ (Organ)
                `ko` - subcode for `ok`
  Throws   : Die - on SQL error
  Comment  : Saving form parameters to database one row at a time.
            :
           : Not all permutations of parameters will yield result (URL - with
           : data to further scrape), some parameters are logically linked,
           : however, there are 10 different parameters that all have several
           : possibilities. Each value gives different URL to check (later).
           : Not all fields in table resultParms get saved/updated.
           : Some things need to be scraped later on.
           : Following fields are for keeping track of next stage
           :  * Checked=true means site is chekcked/scraped
           :  * changed/hits/pages/runID is filled in after scrape

  See Also : DBIresultUpdate()

=cut

#-----------------------------------------------------------------------------
sub DBIresultParms2DB {
    my @row= @{ $_[0]};
    our $resultID;
    our $dbh = &Connect2DB() if not($Connected);
    my @fields =(qw(`siteID` `hits` `url` `r` `f` `k` `ka` `kt` `lt` `format` `theme` `ok` `ko`));
    my $fieldlist = join ", ", @fields;
    my $field_placeholders = join ', ', ('?') x @fields;
    my $sql = qq{REPLACE INTO `$cfg{'DBI.db'}`.`resultParms` ( $fieldlist ) VALUES( $field_placeholders )};
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
  Argument :   0=>hits,
                1=>checked,
                2=>resultID,
                3=>siteID
  Throws   : Die - on SQL error in preperation, not execution
  Comment  : First 2 arguments are update values, next 2 are identificators in where clause
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
    my $sql =qq{Update `$cfg{'DBI.db'}`.`resultparms` SET `hits`=?, `checked`=?, `skip`=?, `runID`=? WHERE `resultID`=? AND `siteID`=? };
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    if ($sth->execute($data[0],$data[1],$skip,$runID,$data[2],$data[3]))
    {
        $rtn=1; #ok
        #print "Update: $data[0],$data[1],$skip,$data[2],$data[3]\n" if ($gDebug);
    }
    else {
        #or die ?
        $rtn=0; #not ok
        print "Can't execute SQL statement: ", $sth->errstr(), "\n";
    }
    return $rtn;
}

#-----------------------------------------------------------------------------
=pod

=head2 DBIresultList2DB()

  Stage    : 3

  Purpose  : Save array of arrays (resultlist) to the database
  Returns  : ref to statement handler & Last ID insterted C<\$sth,$resultListID>
  Argument : ref to array of array
           : Columns: `resultID` `siteID` `page` `title` `isSubList` `search` `read` `browse` `print` `runID`
  Throws   : Die - on SQL error
  Comment  : Digital Archives of Norway "Finn kilde" (Find source) has listing
           : (resultList) that is saved to database.
           : Data from scraping is an array of arrays.

 See Also   :

=cut

#-----------------------------------------------------------------------------
sub DBIresultList2DB {
    my @data = @{ $_[0] };
    our $dbh = &Connect2DB() if not($Connected);
    our $resultListID;
                   # $resultID, $siteID, $page, $title, $isSubList, $search, $read, $browse, $print);
    my @fields = (qw(`resultID` `siteID` `page` `title` `isSubList` `search` `read` `browse` `print` `runID`));
    my $fieldlist = join ", ", @fields;
    #my $field_placeholders = join ", ", map { '?' } @fields;
    my $field_placeholders = join ', ', ('?') x @fields;

    my $sql =qq{REPLACE INTO `$cfg{'DBI.db'}`.`resultList` ( $fieldlist ) VALUES( $field_placeholders )};

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


1;    #return true if this file is required by another program

__END__

=head1 SEE ALSO

I<WWW::Scraper::DigitalArkivet>, I<DigitalArkivet-finn_kilde.pl>, I<DigitalArkivet-eiendom_avansert.pl>,


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2015 Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>

B<Artistic License (Perl)>
Author (Copyright Holder) wishes to maintain "artistic" control over the licensed
software and derivative works created from it.

This code is free software; you can redistribute it and/or modify it under the
terms of the Artistic License 2.0. For details, see the full text of the
license in the file LICENSE.

The full text of the license can be found in the
LICENSE file included with this module, or "L<perlartistic>".


=head1  DISCLAIMER OF WARRANTY

This program is distributed in the hope that it will be
useful, but it is provided “as is” and without any express
or implied warranties. For details, see the full text of
the license in the file LICENSE.


=cut


#################### main pod documentation begin ###################
## Below is the stub of documentation for your module.
## You better edit it!




=head1 HISTORY

0.01 Wed Jul 15 20:56:09 2015
    - original version; created by ExtUtils::ModuleMaker 0.54


=head1 AUTHOR

    Rolf B. Holte
    CPAN ID: RBH
    Member of DIS-Norge, The Genealogy Society of Norway-DIS
    rolfbh@disnorge.no
    http://www.holte.nu/

=head1 COPYRIGHT

B<Artistic License (Perl)>
Author (Copyright Holder) wishes to maintain "artistic" control over the licensed
software and derivative works created from it.

The full text of the license can be found in the
LICENSE file included with this module, or "L<perlartistic>".
=head1 SEE ALSO

perl(1).

=cut

#################### main pod documentation end ###################


1;
# The preceding line will help the module return a true value
