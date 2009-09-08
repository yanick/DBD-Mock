use 5.006;

use strict;
use warnings;

use Test::More no_plan => 1;

use DBI;

my $dbh = DBI->connect( 'DBI:Mock:', '', '' )
    || die "Cannot create handle: $DBI::errstr\n";

$dbh->{mock_start_insert_id} = ['Foo', 123];
$dbh->{mock_start_insert_id} = ['Baz', 345];

{
    my $sth = $dbh->prepare('INSERT INTO Foo (foo, bar) values (?, ?)');

    $sth->execute(15, 17);
    cmp_ok($dbh->{mock_last_insert_id}, '==', 123, '... got the right insert id');
    cmp_ok($dbh->last_insert_id((undef)x4), '==', 123, '... got the right insert id from last_insert_id');

    $sth->execute(16, 18);
    cmp_ok($dbh->{mock_last_insert_id}, '==', 124, '... got the right insert id');
    cmp_ok($dbh->last_insert_id((undef)x4), '==', 124, '... got the right insert id from last_insert_id');

    $sth->execute(19, 34);
    cmp_ok($dbh->{mock_last_insert_id}, '==', 125, '... got the right insert id');
    cmp_ok($dbh->last_insert_id((undef)x4), '==', 125, '... got the right insert id from last_insert_id');
}

{
    my $sth = $dbh->prepare('INSERT INTO Baz (foo, bar) values (?, ?)');

    $sth->execute(90, 41);
    cmp_ok($dbh->{mock_last_insert_id}, '==', 345, '... got the right insert id');
    cmp_ok($dbh->last_insert_id((undef)x4), '==', 345, '... got the right insert id from last_insert_id');

    $sth->execute(32, 71);
    cmp_ok($dbh->{mock_last_insert_id}, '==', 346, '... got the right insert id');
    cmp_ok($dbh->last_insert_id((undef)x4), '==', 346, '... got the right insert id from last_insert_id');

    $sth->execute(77, 42);
    cmp_ok($dbh->{mock_last_insert_id}, '==', 347, '... got the right insert id');
    cmp_ok($dbh->last_insert_id((undef)x4), '==', 347, '... got the right insert id from last_insert_id');
}
