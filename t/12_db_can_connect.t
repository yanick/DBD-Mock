# -*-perl-*-

# $Id: 12_db_can_connect.t,v 1.1 2004/05/08 19:17:06 cwinters Exp $

use strict;
use Test::More tests => 5;
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
	$dbh->prepare(" SELECT foo FROM bar" );
};
if ( $@ ) {
	ok( $@ =~ /^No connection present/ && $dbh->errstr eq "No connection present",
        'Preparing statement against inactive handle throws expected exception' );
}
else {
	fail( 'Preparing statement against inactive handle did not throw exception!' );
}

$dbh->disconnect();

