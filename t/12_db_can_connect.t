# -*-perl-*-

# $Id: 12_db_can_connect.t,v 1.2 2004/07/23 14:03:16 cwinters Exp $

use strict;
use Test::More tests => 6;
require DBI;

my $dbh = DBI->connect( "DBI:Mock:", '', '',
                        { RaiseError => 1, PrintError => 0 } );

ok( $dbh->{Active}, '...our handle with the default settting is Active' );
ok( $dbh->ping, '...and successfuly pinged handle' );

$dbh->{mock_can_connect} = 0;

ok( ! $dbh->{Active},
    "...our handle is no longer Active after setting mock_can_connect'" );
ok( ! $dbh->ping,
    '...and unsuccessfuly pinged handle (good)' );

eval {
	$dbh->prepare( "SELECT foo FROM bar" );
};
if ( $@ ) {
    my $con_re = qr{^No connection present};
	like( $@, $con_re,
          'Preparing statement against inactive handle throws expected exception' );
    like( $dbh->errstr, $con_re,
          'Preparing statement against inactive handle sets expected DBI error' );
}
else {
	fail( 'Preparing statement against inactive handle did not throw exception!' );
}

$dbh->disconnect();

