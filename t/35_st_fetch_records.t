# -*-perl-*-

# $Id: 35_st_fetch_records.t,v 1.1 2004/02/04 21:36:43 cwinters Exp $

use strict;
use Test::More tests => 32;
use Data::Dumper qw( Dumper );

require DBI;

my @rs_one = (
    [ 'this', 'that' ],
    [ 'this_one', 'that_one' ],
    [ 'this_two', 'that_two' ],
);

my @rs_two = (
    [ 'login', 'first_name', 'last_name' ],
    [ 'cwinters', 'Chris', 'Winters' ],
    [ 'bflay', 'Bobby', 'Flay' ],
    [ 'alincoln', 'Abe', 'Lincoln' ],
);

my $dbh = DBI->connect( 'DBI:Mock:', '', '' );

# Seed the handle with two resultsets...

$dbh->{mock_add_resultset} = [ @rs_one ];
$dbh->{mock_add_resultset} = [ @rs_two ];

# run the first one
{
    my ( $sth );
    eval {
        $sth = $dbh->prepare( 'SELECT this, that FROM foo' );
        $sth->execute();
    };
    check_resultset( $sth, [ @rs_one ] );
}

{
    my ( $sth );
    eval {
        $sth = $dbh->prepare( 'SELECT login, first_name, last_name FROM foo' );
        $sth->execute();
    };
    check_resultset( $sth, [ @rs_two ] );
}

sub check_resultset {
    my ( $sth, $check ) = @_;
    my $fields  = shift @{ $check };
    is( $sth->{mock_num_records}, scalar @{ $check },
        'Correct number of records reported by statement' );
    is( $sth->{mock_current_record_num}, 0,
        'Current record number correct before fetching' );
    for ( my $i = 0; $i < scalar @{ $check }; $i++ ) {
        my $rec_num = $i + 1;
        my $this_check = $check->[$i];
        my $this_rec = $sth->fetchrow_arrayref;
        my $num_fields = scalar @{ $this_check };
        is( scalar @{ $this_rec }, $num_fields,
            "Record $rec_num, correct number of fields ($num_fields)" );
        for ( my $j = 0; $j <  $num_fields; $j++ ) {
            my $field_num = $j + 1;
            is( $this_rec->[$j], $this_check->[$j],
                "Record $rec_num, field $field_num" );
        }
        is( $sth->{mock_current_record_num}, $rec_num,
            "Record $rec_num, current record number tracked" );
        if ( $rec_num == scalar @{ $check } ) {
            ok( $sth->{mock_is_depleted},
                'Resultset depleted properly' );
        }
        else {
            ok( ! $sth->{mock_is_depleted},
                'Resultset not yet depleted' );
        }
    }

}
