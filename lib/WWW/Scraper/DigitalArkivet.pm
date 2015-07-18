package WWW::Scraper::DigitalArkivet;
use strict;
use warnings;

BEGIN {
    use Exporter ();
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION     = '0.03';
    @ISA         = qw(Exporter);
    #Give a hoot don't pollute, do not export more than needed by default
    @EXPORT      = qw();
    @EXPORT_OK   = qw();
    %EXPORT_TAGS = ();
}

#-----------------------------------------------------------------------------
=pod

=head1 NAME

B<WWW::Scraper::DigitalArkivet> - Routines to web scrape Digitalarkivet


=head1 VERSION

 0.03 - 14.07.2015


=head1 SYNOPSIS

  use WWW::Scraper::DigitalArkivet;


=head1 DESCRIPTION

Library for routines to web scrape metadata of sources from the Digital Archives
of Norway also known as Digitalarkivet. None of the routines are dependable on a
database, DBI related routines are split into separate library

=head1 USAGE

You can create it now by using the command shown above from this directory.

At the very least you should be able to use this set of instructions
to install the module...

perl Makefile.PL
make
make test
make install

If you are on a windows box you should use 'nmake' rather than 'make'.


=head1 BUGS


=head1 SUPPORT


=head1 CONFIGURATION AND ENVIRONMENT

Tested on win7, no known ties to this platform should work for other platforms.
    see config file - B<DigitalArkivet.cfg>


=head1 DEPENDENCIES

Requires modules Web::Scraper, Text::Trim
Databasestructure as of DigitalArkivet-webscraper.mwb v.0.x


=head1 AUTHOR

    Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>
    Member of DIS-Norge, The Genealogy Society of Norway-DIS
    CPAN ID: RBH

Please drop me an email if you use this in any project. It would be nice to
know if it's usable for others in any capacity. Any suggestions for improvement
are also appreciated.


=head1 REVISION HISTORY

 0.03 - 14.07.2015 - Module
 0.02 - 01.05.2015 - POD - Documented
 0.01 - 01.08.2014 - Created.

=cut

#-----------------------------------------------------------------------------
use Text::Trim;
use Web::Scraper;
use 5.008001;
#
our $VERSION = '0.03';
our $res;
our %site;
our $gDebug;
our @input;
our @select;
our @radio;
our @rlist;
our @data;

# ToDo? retrieve from da.toSrape

# Define scraper objects - pattern to scrape/hold data
$input[0] = scraper {
    # Kildekategori
    process 'div.listGroup > ul.grouped > li', 'data[]' => scraper {
        process 'input',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
        process 'label',
          'label_for' => '@for',
          'text'      => 'TEXT';
    };
};

$input[1] = scraper {
    process 'ul.sublist1 > li', 'data[]' => scraper {
        process 'input',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
        process 'label',
          'label_for' => '@for',
          'text'      => 'TEXT';
    };
};

$input[2] = scraper {
    # Geografi
    process 'ul.sublist2 > li', 'data[]' => scraper {
        process 'input',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
        process 'label',
          'label_for' => '@for',
          'text'      => 'TEXT';
    };
};

$input[3] = scraper {
    # Mainly text inputs
    # Personinformasjon, Hendelsesinformasjon / Eiendomsinformasjon
    process 'ol.form > li', 'data[]' => scraper {
        process 'label',
          'label_for' => '@for',
          'text'      => 'TEXT';
        process 'input',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
    };
};

# Radio eiendom_avansert
$radio[0] = scraper {
    process 'ul > li', 'data' => scraper {
        process 'label[]',
          'label_for' => '@for',
          'text'      => 'TEXT';
        process 'input[]',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
    };
};

# grab select
$select[0] = scraper {
    process 'ol.form > li', 'data[]' => scraper {
        process 'label',
          'label_for' => '@for',
          'text'      => 'TEXT';
        process 'select',
          'id'      => '@id',
          'name'    => '@name',
          'value[]' => scraper {
            process 'option',
              'value' => '@value',
              'text'  => 'TEXT';
          };
    };
};

$rlist[0] = scraper {
    process 'div.listGroup > ul.grouped > li', 'data[]' => scraper {
        process 'input',
          'id'    => '@id',
          'value' => '@value',
          'type'  => '@type',
          'name'  => '@name';
        process 'label',
          'label_for' => '@for',
          'text'      => 'TEXT';
    };
};

#-----------------------------------------------------------------------------
=pod

=head1 METHODS

Each subroutine/function (method) is documented. To avoid problems with timeout/
network errors and memory issues data should be gathered in chunks by re-runs,
each run should collect a given (not too large) amount of data until there is no
more to collect. Some sort of cron job needs to repeat these runs until the whole
site is scraped.

Data is collected at different stages and stored in a database. Enabling re-runs
to pick up were "left off".

Note: Memory usage required to hold/store data temporarily in internal data
structures depend on chunk sizes. Default chunk size could be larger memory wise,
but are kept smaller due to user experience on failure in communications.


=over 12

=item *

B<Stage 1>

What are the searchable options?
Look at the form, compile list for later use

    a) grab all data about inputs.
    b) store data (to a database).

=item *

B<Stage 2>

Scrape url's based upon options.
(For each option combo) save 'Result of search'.

=item *

B<Stage 3>

Examine results from stage 2

    1. Search
    2. Browse
    3. Info. Details about each source
    4.

=item *

B<Stage 4>

    1. Try ID numbers - not published. Find info about (hidden) sources
    2. Last 100

=back

=cut

#-----------------------------------------------------------------------------
################################ subroutines #################################
#-----------------------------------------------------------------------------
=pod

=head2 processFormInput()

Web scrape form inputs - process inputs on form

=over 12

=item *

B<Input:>

    $_[0] - level
    $_[1] - scrape
    $_[2] - seperator

=item *

B<Output:> \@data - handle to array containing data

=back

=cut

#-----------------------------------------------------------------------------
sub processFormInput {

    my $level  = $_[0];
    my $scrape = $_[1];
    my $tab    = $_[2];    #Fieldseperator
    my $j      = 0;
    my $id;
    my $lf;
    my $name2;
    my $i;

    my $num;
    my @row = ( '', '', '', '', '', '' );

    $res = $scrape->scrape( URI->new( $site{'url'} ) );
    $num = $#{ $res->{data} } + 1; #starts with 0 add 1 for actual number

    print "\n- - - - -    [$level]: $num elements - - - - -\n";

    # prints only first time when $level=0
    unless ($level) {
        print FIL join( $tab,
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
                $site{'siteID'}, $level, $j, $label_for, $text, $name, $value,
                $id, $type, $name2
            );
            #fix label for, split into 3 pieces
            my @LF = &labelFor( $label_for, $tab );
            foreach my $lf (@LF) {
                push( @row, $lf );
            }
            print FIL join( $tab, @row );
            print FIL "\n";
            push( @data, join( ',', @row ) );
        }
        else {
            my $text =
              $res->{data}[$i]->{text} ? trim( $res->{data}[$i]->{text} ) : "";
            my $value =
              $res->{data}[$i]->{value} ? $res->{data}[$i]->{value} : "";
            my $id   = $res->{data}[$i]->{id}   ? $res->{data}[$i]->{id}   : "";
            my $type = $res->{data}[$i]->{type} ? $res->{data}[$i]->{type} : "";
            print "\nFANT !!\ttext: $text\tvalue: $value\tid: $id\ttype: $type\n" if ($gDebug);
        }
    }
    print "j: $j . . $num\n" if ($gDebug);
    sleep(1);    # Do not DDOS server

    return \@data;
}

#-----------------------------------------------------------------------------
=pod

=head2 labelFor()

Decode label attribute "for" eg ka14kt0. The label's for the attribute has a
numbering system up to 3 levels. break string into 3 parts, prefix/number and
make an array of each part. Pad with "null" if needed to make an array (of 3).
Used later to process hierarchal structures of the inputs.

=over 12

=item *

B<Input:> labelfor (string)

=item *

B<Output:> array of 3 strings

=back

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

    if ( length($str) > 0 ) {
        #non digits, split on digits
        @tmp = split /\d/, $str;
        for $i ( 0 .. $#tmp ) {
            push @prefix, $tmp[$i] if ( length( $tmp[$i] ) > 0 );
        }
        #digits, split on non digits
        @tmp = split /\D/, $str;
        for $i ( 0 .. $#tmp ) {
            push @number, $tmp[$i] if ( length( $tmp[$i] ) > 0 );
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
        return @string;
    }
    else {
        return ("null","null","null");
    }
}

#-----------------------------------------------------------------------------
=pod

=head2 lastPage()

lastPage, of all "lastpages" scraped only last is relevant. web scrape gets too
many urls, this routine fixes last page. Need only the actual page number of
last page. nor url. (Thus need last page in scope)

=over 12

=item *

B<Input:>

=item *

B<Output:>

=back

=cut

#-----------------------------------------------------------------------------
sub lastPage {
    my $page     = shift;    # Remove the first member from @_.
    my @pageurls = @_;
    if (@pageurls) {
        my @page = split /page=/, $pageurls[-1];

        #last page of last array has relevant data
        return $page[-1];
    }
    else {                   #return curent page
        return $_[0];        # $page ? $_[0] possible error must debug
    }
}

#-----------------------------------------------------------------------------
=pod

=head2 s2hms()

Converts seconds into hours, minutes and seconds

=over 12

=item *

B<Input:> seconds

=item *

B<Output:> hh:mm:ss

=back

=cut

#-----------------------------------------------------------------------------
sub s2hms{
    my $s = shift;
    my $rtn = "";
    my $d1 = $s/(3600*24);
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
    return $rtn;

}

#-----------------------------------------------------------------------------
=pod

=head2 padZero()

Zero pad string  eg. 003 & 02

=over 12

=item *

B<Input:> string

    $_[0] - number (to pad)
    $_[1] - lenght (maximum)

=item *

B<Output:> zero padded number

=back

=cut

#-----------------------------------------------------------------------------
sub padZero {
  my ($num, $len) = @_;
  #return '0' x ($len - length $num) . $num;
  return substr('0'x$len.$num, -$len);
}

1;    #return true if this file is required by another program

__END__

=pod

=head1 SEE ALSO

perl(1), I<WWW::Scraper::DigitalArkivet::Database>, I<DigitalArkivet-finn_kilde.pl>, I<DigitalArkivet-eiendom_avansert.pl>



=head1 LICENCE AND COPYRIGHT

Copyright (c) 2015 Rolf B. Holte - L<http://www.holte.nu/> - <rolfbh@disnorge.no>

B<Artistic License (Perl)>
Author (Copyright Holder) wishes to maintain "artistic" control over the licensed
software and derivative works created from it.

This code is free software; you can redistribute it and/or modify it under the
terms of the Artistic License 2.0. For details, see the full text of the
license in the file LICENSE.

The full text of the license can be found in the
LICENSE file included with this module or L<perlartistic>


=head1  DISCLAIMER OF WARRANTY

This program is distributed in the hope that it will be
useful, but it is provided 'as is' and without any express
or implied warranties. For details, see the full text of
the license in the file LICENSE.

=cut
