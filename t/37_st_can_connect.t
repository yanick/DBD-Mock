# -*-perl-*-

# $Id: 37_st_can_connect.t,v 1.2 2004/05/08 19:50:06 cwinters Exp $

use strict;
use Test::More tests => 3;
require DBI;

my $dbh = DBI->connect( "DBI:Mock:", '', '',
                        { RaiseError => 1, PrintError => 0 } );

# NOTE: checking to see if 'prepare' fails is covered in
# 12_db_can_connect.t, so don't recheck it here

my $sth_exec = eval { $dbh->prepare( 'SELECT foo FROM bar' ) };
if ( $@ ) {
    die "Unexpected failure on prepare: $@";
}

# turn off the handle between the prepare and execute...

$dbh->{mock_can_connect} = 0;
eval { $sth_exec->execute };
if ( $@ ) {
    like( $@, qr/^No connection present/,
          'Executing statement against inactive db throws expected execption' );
}
else {
    fail( 'Executing statement against inactive db did not throw exception!' );
}

# turn off the database between execute and fetch

$dbh->{mock_can_connect} = 1;
$dbh->{mock_add_resultset} = [ [ qw( foo bar ) ],
                               [ qw( this that ) ],
                               [ qw( tit tat ) ] ];
my $sth_fetch = $dbh->prepare( 'SELECT foo, bar FROM baz' );
$sth_fetch->execute;
my $row = eval { $sth_fetch->fetchrow_arrayref };
ok( ! $@, 'Initial fetch ok (db still active)' );

$dbh->{mock_can_connect} = 0;
$row = eval { $sth_fetch->fetchrow_arrayref };
if ( $@ ) {
    like( $sth_fetch->errstr, qr/^No connection present/,
          'Fetching row against inactive db throws expected exception' );
}
else {
    fail( 'Fetching row against inactive db did not throw exception!' );
}
