package WWW::Scraper::DigitalArkivet::Database;
use strict;
use warnings;

BEGIN {
    use Exporter ();
    use vars qw/$VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS/;
    $VERSION = sprintf "%d.%03d", q$Revision: 0.3 $ =~ /(\d+)/g;
    @ISA         = qw/Exporter/;
    @EXPORT      = qw//;
    @EXPORT_OK   = qw/&Connect2DB &Disconnect2DB &DBIresetDA &getRunID &DBIForm2DB
    &daResultparms &daGeography &daGeography2 &daSource &daListType &daTheme
    daFormat &daOrgan &DBIloadCSVresultparms &DBIloadFile &DBIresultParms2DB
    &DBIresultParms2DB &DBIresultUpdate &DBIresultList2DB &doDBIrunStart
    &doDBIrunStat/;
    %EXPORT_TAGS = (ALL => [qw/&Connect2DB &Disconnect2DB &DBIresetDA &getRunID &DBIForm2DB
                    &daResultparms &daGeography &daGeography2 &daSource &daListType &daTheme
                    daFormat &daOrgan &DBIloadCSVresultparms &DBIloadFile &DBIresultParms2DB
                    &DBIresultParms2DB &DBIresultUpdate &DBIresultList2DB &doDBIrunStart
                    &doDBIrunStat/],
                    Stage1  => [qw/&DBIForm2DB/],
                    Stage2  => [qw/&getRunID &doDBIrunStart &doDBIrunStat/]
                    );
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

See TODO file
CDC or SCD data approach?

=head1 CONFIGURATION AND ENVIRONMENT

Tested on win7, no known ties to this platform should work for other platforms.
    see config file - B<DigitalArkivet.cfg>


=head1 BUGS


=head1 SUPPORT


=head1 DEPENDENCIES

Requires modules Config::Simple and DBI (amd DBD::mysql)
Database structure as of DA-webscraper.mwb v.0.


=head1 AUTHOR

Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>
Member of DIS-Norge, The Genealogy Society of Norway-DIS

Please drop me an email if you use this in any project. It would be nice to
know if it's usable for others in any capacity. Any suggestions for improvement
are also appreciated.


=head1 REVISION HISTORY

 0.04 - 31.07.2015 - Module
 0.04 - 01.07.2015 - POD - Documented, minor bugfix'es
 0.03 - 01.10.2014 - Added proc resetDA
 0.02 - 21.09.2014 - Added Tables resultList, resultParms, resultBrowse.
                     Views: vgeography,vinput,vinputf,vinputformat,vinputk,
                            vinputka, vinputkt,vinputlt,vinputr,vinputtheme
 0.01 - 01.08.2014 - Created. Tables form, site, toscrape

=cut

#-----------------------------------------------------------------------------

# modules



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
=pod

=head2 Connect2DB()

  Purpose  : Establish and hold connection to a database
  Returns  : Database handle
  Argument : <none>
  Throws   : Die - on SQL error
  Comment  : MySQL
  Comment  : Connects to a database, returns the handle to it for further use.

 See Also  : Disconnect2DB()

=cut

#-----------------------------------------------------------------------------
sub Connect2DB {
    _readCFG() if not($cfg_set);
    my $dsn = "dbi:$driver:$db:$host:$port";
    our $dbh;
    our $runID;

    #eval { $dbh = DBI->connect( $dsn, $user, $pwd, \%attr ); };
    eval { $dbh = DBI->connect( $dsn, $user, $pwd, $attr ); };
    if ( $DBI::err && $@ =~ /^(\S+) (\S+) failed: / ) {
        print "SQL error: $DBI::errstr ($DBI::err) $1 $2 - $@\n";
    }
    else {
        $Connected = 1;
        $runID = &getRunID(); #process id, used as key
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
  Comment  : MySQL
           : Connect to a database, returns the handle to it for further use.

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

=cut

#-----------------------------------------------------------------------------
sub getRunID {
    our $dbh = &Connect2DB() if not($Connected);
    my $rtn = defined $cfg{'ID.Run'} ? $cfg{'ID.Run'} : 1; #failsafe value
    my $sql = qq{CALL getRunID()};
    #my $sql= qq{SELECT `runID` FROM `$db`.`run` ORDER BY `runID` DESC LIMIT 1};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute();
    ($runID) = $sth->fetchrow_array;
    if (defined $runID) {
        if ($runID>$rtn) {
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
           : (autoincrement) number.
           :

=cut

#-----------------------------------------------------------------------------
sub getResultatID {
    our $dbh = &Connect2DB() if not($Connected);
    my $rtn = defined $cfg{'ID.Resultat'} ? $cfg{'ID.Resultat'} : 1; #failsafe value
    my $sql = qq{CALL getResultatID()};
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    $sth->execute();
    ($ResultatID) = $sth->fetchrow_array;
    if (defined $ResultatID) {
        if ($ResultatID>$rtn) {
            $rtn = $ResultatID; #database value used instead
            $config->param("ID.Resultat",$ResultatID);
            $config->write();
        }
    return $rtn;
    }
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
           : "of run"/ harvesting of data

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
    my $sql= qq{SELECT `runID` FROM `$db`.`run` ORDER BY `runID` DESC LIMIT 1};
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
  Comment  : MySQL
           : invokes stored procedure `runStat`
           : Used to track progress of run, also updates som statsical data
           : ()

 See Also  : doDBIrunStart()

=cut

#-----------------------------------------------------------------------------
sub doDBIrunStat {
    use URI::Escape;
    my $pID    = shift; # runID
    our $dbh = &Connect2DB() if not($Connected);
    my $sql = qq{CALL `$db`.`runStat`( ? ) } ;
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
  Comment  : MySQL
           : Skip false is the default, new items have skip=false, skip true is set for
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
    my $sql = qq{SELECT `resultID`,`url` FROM `$db`.`resultparms` WHERE `checked`=false AND `siteID`=? AND `skip`= ? ORDER BY `resultID` $LIMIT};
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
  Comment  : MySQL
           : Gets geographic info for given site, from view.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------

sub daGeography {
    my @rows_loh = ();
    if ($InG){
        my $sql = qq{SELECT `r`,`f`,`k`,`bit` FROM `$db`.`vgeography` WHERE `siteID`=? ORDER BY `k` };
        #my $sql = qq{SELECT `r`,`f`,`k`,`bit` FROM `da`.`vgeography` WHERE `siteID`=? ORDER BY `k` };
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
  Comment  : MySQL
           : Gets geographic info for given site, from view.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------

sub daGeography2 {
    my @rows_loh = ();
    if($InG) {
        my $sql = qq{SELECT `r`,`f`,`bit` FROM `$db`.`vgeography2` WHERE `siteID`=? ORDER BY `f` };
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
  Comment  : MySQL
           : Digital Archives of Norway. Gets source info for given site.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daSource {
    my @rows_loh = ();
    if ($InS) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql = qq{SELECT `ka`,`kt`,`bit` FROM `$db`.`vInputKT` where `siteID`=?};
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
  Comment  : MySQL
           : Gets source info for given site.
           : Creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daListType {
    my @rows_loh = ();
    if ($InL) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql = qq{SELECT `ka`,`lt`,`bit` FROM `$db`.`vInputLT` where `siteID`=?};
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
  Comment  : MySQL
           : Data is sorted into themes.
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

  See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daTheme {
    my @rows_loh = ();
    if  ($InT) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql= qq{SELECT `theme`,`bit` FROM `$db`.`vInputTheme` where `siteID`=?};
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
  Comment  : MySQL
           : The function creates an array of hashes (to be traversed later).
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).


 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daFormat {
    my @rows_loh = ();
    if ($InF) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql= qq{SELECT `format`,`bit` FROM `$db`.`vInputFormat` where `siteID`=?};
        #my $sql= qq{SELECT `format`,`bit` FROM `da`.`vInputFormat` where `siteID`=?};
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
  Comment  : MySQL
           : The function creates an array of hashes (to be traversed later).
           : (Currently only 2 Organs - mining, industry)
           : Locally scoped "boolean" var may prevent SQL to be executed (IF clause).

 See Also  : daResultparms(), daGeography2(), daGeography2(), daSource(), daListType(), daTheme(), daFormat(), daOrgan()

=cut

#-----------------------------------------------------------------------------
sub daOrgan {
    my @rows_loh = ();
    if ($InO) {
        our $dbh = &Connect2DB() if not($Connected);
        my $sql= qq{SELECT `ok`,`ko`,`bit` FROM `$db`.`vInputKO` where `siteID`=?};
        #my $sql= qq{SELECT `ok`,`ko`,`bit` FROM `da`.`vInputKO` where `siteID`=?};
        our $sth = $dbh->prepare($sql)
          or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
        $sth->execute($_[0]);
        my $r=$sth->rows;
        @rows_loh = @{$sth->fetchall_arrayref({})};
    }
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
  Comment  : MySQL
           : Saves file to table "resultparms" using LOAD DATA.
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
    my $sql = qq{LOAD DATA LOCAL INFILE '$file' REPLACE INTO TABLE `$db`.`resultparms` CHARACTER SET UTF8 FIELDS TERMINATED BY ',' IGNORE 1 LINES (resultID, siteID, r, f, k, ka, kt, lt, format, theme, ok, ko, url, skip)};
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
  Argument :  0-filename,
                1-tablename,
                2-array of fields,
                3-"SET"
  Throws   : Die - on SQL error
  Comment  : MySQL
           : Bulk saves data from a file to database.
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
    my $sql = qq{LOAD DATA REPLACE INFILE $file INTO `$db`.`$table` ( $fieldlist ) TERMINATED BY  '$tab' $set )};
    #my $sql = qq{LOAD DATA REPLACE INFILE $file INTO `da`.`$table` ( $fieldlist ) TERMINATED BY  '$tab' $set )};
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
    our $resultID;
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
  Argument :  0=>hits,
                1=>checked,
                2=>resultID,
                3=>siteID
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
    our $resultListID;
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
terms of the Artistic License 2.0. The full text of the license can be found in the
LICENSE file included with this module, or L<http://cpansearch.perl.org/src/NWCLARK/perl-5.8.9/Artistic>


=head1  DISCLAIMER OF WARRANTY


This program is distributed in the hope that it will be
useful, but it is provided 'as is' and without any express
or implied warranties. For details, see the full text of
the license in the file LICENSE.


=cut

1;
