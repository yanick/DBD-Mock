# -*-perl-*-

# $Id: 10_db_handle.t,v 1.1 2004/01/21 13:06:05 cwinters Exp $

use strict;
use Test::More tests => 9;

require DBI;

my $trace_log = 'tmp_dbi_trace.log';

{
    my $dbh = DBI->connect( 'DBI:Mock:', '', '' ) || die $DBI::errstr;
    is( ref( $dbh ), 'DBI::db',
        'DBI handle returned from connect()' );
}

{
    open STDERR, "> $trace_log";
    my $dbh = DBI->connect( 'DBI:Mock:', '', '',
                            { RaiseError => 1,
                              PrintError => 1,
                              AutoCommit => 1,
                              TraceLevel => 2 } ) || die $DBI::errstr;
    is( $dbh->{RaiseError}, 1,
        'RaiseError DB attribute set in connect()' );
    is( $dbh->{PrintError}, 1,
        'PrintError DB attribute set in connect()' );
    is( $dbh->{AutoCommit}, 1,
        'AutoCommit DB attribute set in connect()' );
    is( $dbh->{TraceLevel}, 2,
        'TraceLevel DB attribute set in connect()' );
    close STDERR;
    unlink( $trace_log ) if ( -f $trace_log );
}

{
    my $dbh = DBI->connect( 'DBI:Mock:', '', '' ) || die $DBI::errstr;
    $dbh->{RaiseError} = 1;
    $dbh->{PrintError} = 1;
    $dbh->{AutoCommit} = 1;
    $dbh->trace( 2, $trace_log );
    is( $dbh->{RaiseError}, 1,
        'RaiseError DB attribute set after connect()' );
    is( $dbh->{PrintError}, 1,
        'PrintError DB attribute set after connect()' );
    is( $dbh->{AutoCommit}, 1,
        'AutoCommit DB attribute set after connect()' );
    is( $dbh->{TraceLevel}, 2,
        'TraceLevel DB attribute set after connect()' );
    unlink( $trace_log ) if ( -f $trace_log );
}
