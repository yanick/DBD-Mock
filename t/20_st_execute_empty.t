# -*-perl-*-

# $Id: 20_st_execute_empty.t,v 1.3 2004/02/04 21:36:23 cwinters Exp $

use strict;
use Test::More tests => 12;

require DBI;

my $sql = 'SELECT * FROM foo WHERE bar = ? AND baz = ?';

{
    my $dbh = DBI->connect( 'DBI:Mock:', '', '' );
    my $sth = eval { $dbh->prepare( $sql ) };
    ok( ! $@, 'Statement handle prepared ok' );
    is( ref( $sth ), 'DBI::st',
        'Statement handle returned of the proper type' );
    is( $sth->{mock_my_history}->statement, $sql,
        'Statement handle stores SQL (method on tracker)' );
    is( $sth->{mock_statement}, $sql,
        'Statement handle stores SQL (attribute)' );
    is( $sth->{mock_is_executed}, 'no',
        'Execute flag not set yet' );
    eval { $sth->execute() };
    ok( ! $@, 'Called execute() ok (no params)' );
    is( $sth->{mock_is_executed}, 'yes',
        'Execute flag set after execute()' );
    my $t_params = $sth->{mock_my_history}->bound_params;
    is( scalar @{ $t_params }, 0,
        'No parameters tracked (method on tracker)' );
    my $a_params = $sth->{mock_params};
    is( scalar @{ $a_params }, 0,
        'No parameters tracked (attribute)' );
    is( $sth->{mock_is_finished}, 'no',
        'Finished flag not set yet' );
    eval { $sth->finish };
    ok( ! $@, 'Called finish() ok' );
    is( $sth->{mock_is_finished}, 'yes',
        'Finished flag set after finish()' );
}
