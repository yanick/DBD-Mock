# -*-perl-*-

# $Id: 14_db_parser.t,v 1.1 2004/07/23 14:23:58 cwinters Exp $

use strict;
use Test::More tests => 3;

require DBI;

{
    my $dbh = DBI->connect( 'DBI:Mock:', '', '', { RaiseError => 1, PrintError => 0 } )
        || die DBI->errstr;
    eval { $dbh->{mock_add_parser} = \&parse_select };
    ok( ! $@, "Added parser to db handle" );
    my $st1 = eval { $dbh->prepare( 'SELECT myfield FROM mytable' ) };
    diag( $@ ) if ( $@ );
    ok( ! $@, 'Prepared proper SELECT statement' );

    my $good_error = qq{Failed to parse statement. Error: incorrect use of '*'. } .
                     qq{Statement: SELECT * FROM mytable\n};
    my $sth2 = eval { $dbh->prepare( 'SELECT * FROM mytable' ) };
    is( $@, $good_error,
        'Parser failure generates correct error' );
}

sub parse_select {
    my ( $sql ) = @_;
    return unless ( $sql =~ /^\s*select/i );
    if ( $sql =~ /^\s*select\s+\*/i ) { 
        die "incorrect use of '*'\n";
    }
}

sub parse_insert {
    my ( $sql ) = @_;
    return unless ( $sql =~ /^\s*insert/i );
    unless ( $sql =~ /^\s*insert\s+into\s+mytable/i ) { 
        die "incorrect table name\n";
    }
}

sub parse_update {
    my ( $sql ) = @_;
    return unless ( $sql =~ /^\s*update/i );
    unless ( $sql =~ /^\s*update\s+mytable/ ) { 
        die "incorrect table name\n";
    }
}

