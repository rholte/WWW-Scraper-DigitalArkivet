#!/usr/bin/perl -w
use strict;
use DBI;
use Config::Simple;
use Data::Dumper::Simple;
#use Log::Log4perl qw(get_logger :levels);
use Text::CSV_XS qw( csv );
use Text::Trim;
use WWW::Scraper::DigitalArkivet (':Fix');
use URI;
use Web::Scraper;
use utf8;

#qw/&buildCSVparamList  &processParamList &isNew &getRunID &doDBIrunStart &doDBIrunStat &DBIloadCSVdaParms &s2hms/; # &buildCSVparamList  &processParamList   &getRunID &doDBIrunStart


my ($Connected,%cfg,$config,$gDebug,$gLimit,$driver,$db, $host, $port, $user,$pwd,$attr,$cfg_set);
our ($fix,$year1, $year2, $place, $subplace, $daID, $geoID, $placeID, $url, $uri, $name, $print);
#our ($db,$Connected);
my ($recent, $label1,$label2, $at, $author);

_rCFG();
_defineScraper();
my (@recent) = @{&daRecent()};
my @list = ('df','dødfødte','dp','døpte','gr','begravde','if','innflyttede',
        'im','innmeldte','in','introduserte kvinner','kf','konfirmerte',
        'ko','kommunikanter','pa','offentlige skriftemål','uf','utflyttede',
        'um','utmeldte','va','vaksinerte','vi','viede'); # key,value
my %lt = @list; #converts into hash where lt{key}=value;
my %item;
my $item;
#for my $i ( 0 .. $#recent )
while (defined($item = shift @recent))
{
    # $recent[$i]{year1}, $recent[$i]{year2}, $recent[$i]{place}, $recent[$i]{subplace}, $recent[$i]{daID}, $recent[$i]{url}, $recent[$i]{name}
    #($year1, $year2,$place,$subplace,$geoID,$placeID,$at,$author,$daID,$url);
    #`year1`=?, `year2`=?, `place`=?, `subplace`=?, `geoID`=?, `placeID`=?, `at`=?, `author`=?  WHERE `daID`=? AND `url`=? };
        $fix=0;
        my $r=0;
        #my $s=0;
        my $k=0;
        $year1    = $$item{'year1'}    ||'';
        $year2    = $$item{'year2'}    ||'';
        $place    = $$item{'place'}    ||'';
        $subplace = $$item{'subplace'} ||'';
        $geoID    = $$item{'geoID'}    ||'';
        $placeID  = $$item{'placeID'}  ||'';
        $at       = $$item{'at'}       ||'';
        $author   = $$item{'author'}   ||'';
        $daID     = $$item{'daID'}     ||'';
        $url      = $$item{'url'}      ||'';
        $uri      =trim($$item{'uri'}) ||'';
        $name     =trim($$item{'name'})||'';
        print  "$#recent \n";
#        #count empty keys (not including uri & name)
#        foreach my $key (keys $item){
#                $r++ if ($$item{$key} eq '' && (($key ne 'uri')||($key ne 'name')));
#        }
        my $res   = $print->scrape( URI->new( $uri ) );
        my $title = $res->{title} ? trim($res->{title}) : "";
         #geoID via table->label1->Geografisk ID: ... table->value1-> (geoID)
        my $gID    = $res->{data}[0]->{table}[5]->{value1} ? $res->{data}[0]->{table}[5]->{value1} : "";
        $geoID = $gID if (!$geoID);
        my $j=2; #0->links, 1->about source, start checking at index 2
        my $ok=0;
        $_ = $res->{h4}[$j] ? $res->{h4}[$j] : "";
        if (m/.kbar versjon/) {
                $ok=1;
                $k=1;
        } else {
                $j++;
                $_ = $res->{h4}[$j] ? $res->{h4}[$j] : "";
                if (m/.kbar versjon/) {
                        $ok=1
                } else {
                        $j++;
                        $_ = $res->{h4}[$j] ? $res->{h4}[$j] : "";
                        $ok=1 if (m/.kbar versjon/);
                }
        }
        $j-=1; #remove offset (for about source)
        # need to find right index, need to find $label's data
        my ($_base, $_uri, $_daID, $_cat, $_lt, $_file) = &parseURI($url);
        my $label=$lt{$_lt};
        #$label=lc $label;
        $label=trim $label;
        my $ok2=0;
        if (ref $res->{h3} eq 'HASH'){
                my $max = scalar (keys $res->{h3});
                $_=$res->{h3}[$j] ? $res->{h3}[$j] : "";
                $_= lc $_;
                $_= trim $_;
                $ok2=1 if ($label eq $_ ); #true if right index
                unless ($ok2) {
                        while ($j<=$max) {
                                $j++;
                                $_=$res->{h3}[$j] ? $res->{h3}[$j] : "";
                                $_= lc $_;
                                $_= trim $_;
                                $ok2=1 if ($label eq $_ );
                        }
                }
        };
        # ->new offset
        $j++;
        if (!$author && $ok && $ok2) {
                $label2    = $res->{data}[$j]->{table}[2]->{label2} ? trim($res->{data}[$j]->{table}[2]->{label2}) : "";
                $author = $res->{data}[$j]->{table}[2]->{value2} ? $res->{data}[$j]->{table}[2]->{value2} : "" if ($label2 eq 'Transkribert av:')
        }
        if (!$at && $ok && $ok2) {
                $label1    = $res->{data}[1]->{table}[6]->{label2}  ? trim($res->{data}[1]->{table}[6]->{label2})  : "";
                $label2    = $res->{data}[$j]->{table}[6]->{label2} ? trim($res->{data}[$j]->{table}[6]->{label2}) : "";
                if (($label1 eq 'Knyttet til:') || ($label1 eq 'Beliggenhet:')) {
                    $at = $res->{data}[1]->{table}[6]->{value2} ? $res->{data}[2]->{table}[6]->{value2} : "";
                } elsif (($label2 eq 'Knyttet til:') || ($label2 eq 'Beliggenhet:')) {
                    $at = $res->{data}[$j]->{table}[6]->{value2} ? $res->{data}[$j]->{table}[6]->{value2} : "";
                }
        }
        #my $y1 = $res->{data}[1]->{table}[0]->{value1} ? $res->{data}[1]->{table}[0]->{value1} : "";
        #my $y2 = $res->{data}[1]->{table}[0]->{value2} ? $res->{data}[1]->{table}[0]->{value2} : "";
        ($year1, $year2) = &getYearYear($name) if ((!$year1) || (!$year2));
        ($place, $subplace) = &getPlace($name) unless ($place && $subplace);
        $placeID=&getPlaceID($geoID) if (!$placeID && $geoID);
        my @row = ($year1,$year2,$place,$subplace,$geoID,$placeID,$at,$author,$daID,$url);
        $fix = ($year1 ne $$item{'year1'}) ||
               ($year2 ne $$item{'year2'}) ||
               ($place ne $$item{'place'}) ||
               ($subplace ne $$item{'subplace'}) ||
               ($geoID ne $$item{'geoID'}) ||
               ($placeID ne $$item{'placeID'}) ||
               ($at ne $$item{'at'}) ||
               ($author ne $$item{'author'}) ? 1 : 0;
        &daRecentUpdate(\@row) if ($fix);
        @row  = undef;
        $res  = undef;
        $item = undef;
}
&Disconnect2DB();
#print "\n";
#print "--------------------------------\n";
#print "---       Dump av data       ---\n";
#print "--------------------------------\n";
##print Dumper(\@recent);
#print "\n";
#print "--------------------------------\n";
#print "---            End           ---\n";
#print "--------------------------------\n";

sub Connect2DB {
    #readCFG() if not($cfg_set);
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
    }
    return $dbh;
}

sub Disconnect2DB {
    if ($Connected) {
        our $dbh->disconnect();
        $Connected = 0;
    }
}

sub _rCFG {
    # import configuration into %cfg hash:
    $config = Config::Simple->import_from( 'DigitalArkivet.cfg', \%cfg );
    $gDebug = defined $cfg{'Debug.debug'}? $cfg{'Debug.debug'}: 1;
    # Configurations from file overrides defaults (on the left)
    $gLimit = defined $cfg{'DBI.limit'}  ? $cfg{'DBI.limit'}  : "10000";
    $driver = defined $cfg{'DBI.driver'} ? $cfg{'DBI.driver'} : "mysql";
    $db     = defined $cfg{'DBI.db'}     ? $cfg{'DBI.db'}     : "da";
    $host   = defined $cfg{'DBI.host'}   ? $cfg{'DBI.host'}   : "localhost";
    $port   = defined $cfg{'DBI.port'}   ? $cfg{'DBI.port'}   : "3306" ;
    #$user   = defined $cfg{'DBI.user'}   ? $cfg{'DBI.user'}   : "root" ;
    $user   = "root";
    $pwd    = "";
    #defined $cfg{'DBI.pwd'}    ? $cfg{'DBI.pwd'}    : "";
    $attr = {
                PrintError=>0,
                RaiseError=>1,       #Make database errors fatal to script
                mysql_enable_utf8=>1 #charset fix
           };
    $cfg_set=1;
}

sub _defineScraper {
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
}

sub daRecent{
    my @rows_loh = ();
      #my $sql = qq{SELECT DISTINCT `year1`,`year2`,`place`,`subplace`,`daID`,`geoID`,`url`,`uri`,`name` FROM `$db`.`source__recent` WHERE   (`placeID` is null or `placeID` like '' )  };
      my $sql = qq{SELECT DISTINCT `year1`,`year2`,`place`,`subplace`,`daID`,`geoID`,`placeID`,`at`,`author`,`url`,`uri`,`name` FROM `$db`.`source__recent` };
      $sql .= qq{ WHERE `daID`>0 AND ((`year1` is null or `year1` like '') or (`year2` is null or `year2` like '') or (`at` is null or `at` like '' ) or (`author` is null or `author` like '' ) or (`place` is null or `place` like '' ) or (`placeID` is null or `placeID` like '' ))};
      $sql .= qq{ ORDER BY `daID` ASC};
      #$sql .=$where;
      our $dbh = &Connect2DB() if not($Connected);
      our $sth = $dbh->prepare($sql)
        or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
      $sth->execute();
      my $r = $sth->rows;
      @rows_loh = @{ $sth->fetchall_arrayref( {} ) };
    return ( \@rows_loh );
}

sub daRecentUpdate {
    #0=>year1, 1=>year2, 2=>place, 3=>subplace, 4=>`daID, 5=>url
    my @data = @{ $_[0] };
    my $rtn;
    our $dbh = &Connect2DB() if not($Connected);
    my $sql =qq{Update `$db`.`source__recent` SET `year1`=?, `year2`=?, `place`=?, `subplace`=?, `geoID`=?, `placeID`=?, `at`=?, `author`=?  WHERE `daID`=? AND `url`=? };
    our $sth = $dbh->prepare($sql)
      or die "Can't prepare SQL statement: ", $dbh->errstr(), "\n";
    if ($sth->execute($data[0],$data[1],$data[2],$data[3],$data[4],$data[5],$data[6],$data[7],$data[8],$data[9]))
    {
        $rtn=1; #ok
        print "Update: $data[8] - $data[0]\t$data[1]\t$data[2]\t$data[3]\t$data[4]\t$data[5]\t$data[6]\t$data[7]\n";
    }
    else {
        #or die ?
        print "\nUpdateFailed: $data[8] - $data[0]\t$data[1]\t$data[2]\t$data[3]\t$data[4]\t$data[5]\t$data[6]\t$data[7]\t$data[9]\n";
        $rtn=0; #not ok
        print "Can't execute SQL statement: ", $sth->errstr(), "\n";
    }
    return $rtn;
}

sub getYearYear {
    my $txt = shift;
    if ($txt=~ m/for.(\d{4})/) {
        $txt = substr($txt,0,$-[0]); # removes (pre)match from $txt
    };
    if ($txt=~ m/(\d{4}).(\d{4})/){
        $fix=1;
        return ( $1, $2 );
    } elsif ($txt=~ m/(\d{4})/) {
        $fix=1;
        return ( $1, $1 );
    } else {
        return ( '', '' );
    };
}
#($src=~ m/for \d*(\D+) kjøpstad/)    || ($src=~ m/for (\D+) kjøpstad/)    ||
sub getPlace {
    my $txt = shift;
    #my $mustfix=0;
     if (!$place) {
#if  (($txt=~ m/for \d* (\D+) prestegjeld/) || ($txt=~ m/for \d* (\D+) kommune/) ||
#             ($txt=~ m/for \d* (\D+) ladested/) || ($txt=~ m/for \d* (\D+) kjøpstad/) ||
 #            ($txt=~ m/for \d* (\D+) herred/) || ($txt=~ m/for \d* (\D+) so.n/) ||
 #            ($txt=~ m/for \d* (\D+) sorenskriver/) || ($txt=~ m/for \d* (\D+) fogderi/) ||
 #            ($txt=~ m/for \d* (\D+) menighet/))
        $_ = $txt;
        if  (m/ for (\d{4})\w* (\D+) (prestegjeld|kommune|ladested|landsogn|kj.pstad|herred|sorenskriver|fogderi|menighet|Baptistmenighet)/g) {
                #$mustfix=1;
                $place = $1;
        } elsif (m/ for (\D+) (prestegjeld|kommune|ladested|landsogn|kj.pstad|herred|sorenskriver|fogderi|menighet|Baptistmenighet)/g){
                $place = $1;
        } elsif (m/ for\s*\d{4}\w* (\D+) prestegjeld \D+ (sokn|sogn)/) {
                #$mustfix=1;
                $place = $1;
        }elsif (m/ for (\D+) prestegjeld \D+ (sokn|sogn)/) {
                #$mustfix=1;
                $place = $1;
        } elsif (m/ i (\D+)/) {
                #$mustfix=1;
                $place = $1;
        } elsif (m/ for (\D+)/) {
                #$mustfix=1;
                $place = $1;
        } elsif (m/ Norske /gi){
                $place = 'Norge';
        }
        #if ($mustfix) {
        #        $fix=1;
        #        $txt = substr($txt,0,$-[0]);
        #        #$txt=substr($txt,0,$&);
        #}
     }#!$place
     if (!$subplace) {
        $_ = $txt;
        if (m/(\D+) so.n/){
        #    $fix=1;
            $subplace = $1;
        } elsif (m/(\w+.\(\w+\)).so.n/){
        #    $fix=1;
            $subplace = $1;
        }else {
            $subplace = '';
        };
     }
     return ($place,$subplace);
}

sub getPlaceID {
        my $geoID = shift;
        $geoID =~ m/^(\d{4}).*/;
        $placeID=$1;
        return $placeID;
}

1;
