package DBD::Mock;

# $Id: Mock.pm,v 1.14 2004/05/09 04:49:20 cwinters Exp $

#   Copyright (c) 2004 Chris Winters (spawned from original code
#   Copyright (c) 1994 Tim Bunce)
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use vars qw( $drh $err $errstr );
require DBI;

$DBD::Mock::VERSION = sprintf( "%d.%02d", q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/o );

$drh    = undef;    # will hold driver handle
$err    = 0;		# will hold any error codes
$errstr = '';       # will hold any error messages

sub driver {
    return $drh if ( $drh );
    my ( $class, $attr ) = @_;
    $class .= "::dr";
    $drh = DBI::_new_drh( $class, {
        Name        => 'Mock',
        Version     => $DBD::Mock::VERSION,
        Attribution => 'DBD Mock driver by Chris Winters (orig. from Tim Bunce)',
        Err         => \$DBD::Mock::err,
 		Errstr      => \$DBD::Mock::errstr,
    });
    return $drh;
}

sub CLONE {
    undef $drh;
}


########################################
# DRIVER

package DBD::Mock::dr;

use strict;

use vars qw( $imp_data_size );
$imp_data_size = 0;

sub connect {
    my ( $drh, $dbname, $user, $auth, $attr ) = @_;
    $attr ||= {};
    my $dbh = DBI::_new_dbh( $drh, {
        Name                   => $dbname,

        # holds all statements applied to handle until manually cleared
        mock_statement_history => [],

        # ability to fake a failed DB connection
        mock_can_connect       => 1,

        # rest of attributes
        %{ $attr },
    }) or return undef;
    return $dbh;
}

sub DESTROY {
    undef;
}

########################################
# DATABASE

package DBD::Mock::db;

use strict;

use vars qw( $imp_data_size );
$imp_data_size = 0;

sub ping {
 	my ( $dbh ) = @_;
 	return $dbh->{mock_can_connect};
}

sub prepare {
    my( $dbh, $statement ) = @_;

    my $sth = DBI::_new_sth( $dbh, { Statement => $statement });
    $sth->trace_msg( "Preparing statement '$statement'\n", 1 );
    my %track_params = (
        statement => $statement,
    );

    # If we have available resultsets seed the tracker with one

    my ( $rs );
    if ( my $all_rs = $dbh->{mock_rs} ) {
        if ( my $by_name = $all_rs->{named}{ $statement } ) {
            $rs = $by_name;
        }
        else {
            $rs = shift @{ $all_rs->{ordered} };
        }
    }
    if ( ref $rs eq 'ARRAY' and scalar @{ $rs } > 0 ) {
        my $fields = shift @{ $rs };
        $track_params{return_data} = $rs;
        $track_params{fields}      = $fields;
        $sth->STORE( NAME          => $fields );
        $sth->STORE( NUM_OF_FIELDS => scalar @{ $fields } );
    }
    else {
        $sth->trace_msg( 'No return data set in DBH', 1 );
    }

 	# do not allow a statement handle to be created if there is no
 	# connection present.

 	unless ( $dbh->FETCH( 'Active' ) ) {
 		$dbh->DBI::set_err( 1, "No connection present" );
 		if ( $dbh->FETCH( 'PrintError' ) ) {
 			warn "No connection present";
 		}
 		if ( $dbh->FETCH( 'RaiseError' ) ) {
 			die "No connection present";
 		}
 		return undef;
 	}

    # This history object will track everything done to the statement

    my $history = DBD::Mock::StatementTrack->new( %track_params );

    $sth->STORE( mock_my_history => $history );

    # ...now associate the history object with the database handle so
    # people can browse the entire history at once, even for
    # statements opened and closed in a black box

    my $all_history = $dbh->FETCH( 'mock_statement_history' );
    push @{ $all_history }, $history;

    return $sth;
}

sub FETCH {
    my ( $dbh, $attrib ) = @_;
    $dbh->trace_msg( "Fetching DB attrib '$attrib'\n" );
    if ( $attrib eq 'AutoCommit' ) {
        return $dbh->{mock_auto_commit};
    }
 	elsif ( $attrib eq 'Active' ) {
        return $dbh->{mock_can_connect};
    }
    elsif ( $attrib eq 'mock_all_history' ) {
        return $dbh->{mock_statement_history};
    }
    elsif ( $attrib =~ /^mock/ ) {
        return $dbh->{ $attrib };
    }
    else {
        return $dbh->SUPER::FETCH( $attrib );
    }
}

sub STORE {
    my ( $dbh, $attrib, $value ) = @_;
    $dbh->trace_msg( "Storing DB attribute '$attrib'\n" );
    if ( $attrib eq 'AutoCommit' ) {
        $dbh->{mock_auto_commit} = $value;
        return $value;
    }
    elsif ( $attrib eq 'mock_clear_history' ) {
        if ( $value ) {
            $dbh->{mock_statement_history} = [];
        }
        return [];
    }
    elsif ( $attrib eq 'mock_add_resultset' ) {
        $dbh->{mock_rs} ||= { named   => {},
                              ordered => [] };
        if ( ref $value eq 'ARRAY' ) {
            my @copied_values = @{ $value };
            push @{ $dbh->{mock_rs}{ordered} }, \@copied_values;
            return \@copied_values;
        }
        elsif ( ref $value eq 'HASH' ) {
            my $name = $value->{sql};
            unless ( $name ) {
                die "Indexing resultset by name requires passing in 'sql' ",
                    "as hashref key to 'mock_add_resultset'.";
            }
            my @copied_values = @{ $value->{results} };
            $dbh->{mock_rs}{named}{ $name } = \@copied_values;
            return \@copied_values;
        }
        else {
            die "Must provide an arrayref or hashref when adding ",
                "resultset via 'mock_add_resultset'.\n";
        }
    }
    elsif ( $attrib =~ /^mock/ ) {
        return $dbh->{ $attrib } = $value;
    }
    else {
        return $dbh->SUPER::STORE( $attrib, $value );
    }
}

sub DESTROY {
    undef
}

########################################
# STATEMENT

package DBD::Mock::st;

use strict;

use vars qw( $imp_data_size );
$imp_data_size = 0;

sub bind_param {
    my ( $sth, $param_num, $val, $attr ) = @_;
    my $tracker = $sth->FETCH( 'mock_my_history' );
    $tracker->bound_param( $param_num, $val );
    return 1;
}

sub execute {
    my ( $sth, @params ) = @_;

    unless ( $sth->{Database}->{mock_can_connect} ) {
 		$sth->DBI::set_err( 1, "No connection present" );
 		if ( $sth->FETCH( 'PrintError' ) ) {
 			warn "No connection present";
            return 0;
 		}
 		if ( $sth->FETCH( 'RaiseError' ) ) {
 			die "No connection present";
 		}
    }

    my $tracker = $sth->FETCH( 'mock_my_history' );
    if ( @params ) {
        $tracker->bound_param_trailing( @params );
    }
    $tracker->mark_executed;
    my $fields = $tracker->fields;
    $sth->STORE( NUM_OF_PARAMS => $tracker->num_params );
    return '0E0';
}

sub fetch {
    my( $sth ) = @_;

    unless ( $sth->{Database}->{mock_can_connect} ) {
 		$sth->DBI::set_err( 1, "No connection present" );
 		if ( $sth->FETCH( 'PrintError' ) ) {
 			warn "No connection present";
            return undef;
 		}
 		if ( $sth->FETCH( 'RaiseError' ) ) {
 			die "No connection present";
 		}
    }

    my $tracker = $sth->FETCH( 'mock_my_history' );
    return $tracker->next_record;
}

sub finish {
    my ( $sth ) = @_;
    $sth->FETCH( 'mock_my_history' )->is_finished( 'yes' );
}

sub FETCH {
    my ( $sth, $attrib ) = @_;
    $sth->trace_msg( "Fetching ST attribute '$attrib'\n" );
    my $tracker = $sth->{mock_my_history};
    $sth->trace_msg( "Retrieved tracker: " . ref( $tracker ) . "\n" );
    if ( $attrib eq 'NAME' ) {
        return $tracker->fields;
    }
    elsif ( $attrib eq 'NUM_OF_FIELDS' ) {
        return $tracker->num_fields;
    }
    elsif ( $attrib eq 'NUM_OF_PARAMS' ) {
        return $tracker->num_params;
    }
    elsif ( $attrib eq 'TYPE' ) {
        my $num_fields = $tracker->num_fields;
        return [ map { $DBI::SQL_VARCHAR } ( 0 .. $num_fields ) ];
    }
    elsif ( $attrib eq 'Active' ) {
        return $tracker->is_active;
    }
    elsif ( $attrib !~ /^mock/ ) {
        return $sth->SUPER::FETCH( $attrib );
    }

    # now do our stuff...

    if ( $attrib eq 'mock_my_history' ) {
        return $tracker;
    }
    if ( $attrib eq 'mock_statement' ) {
        return $tracker->statement;
    }
    elsif ( $attrib eq 'mock_params' ) {
        return $tracker->bound_params;
    }
    elsif ( $attrib eq 'mock_num_records' ) {
        return scalar @{ $tracker->return_data };
    }
    elsif ( $attrib eq 'mock_current_record_num' ) {
        return $tracker->current_record_num;
    }
    elsif ( $attrib eq 'mock_fields' ) {
        return $tracker->fields;
    }
    elsif ( $attrib eq 'mock_is_executed' ) {
        return $tracker->is_executed;
    }
    elsif ( $attrib eq 'mock_is_finished' ) {
        return $tracker->is_finished;
    }
    elsif ( $attrib eq 'mock_is_depleted' ) {
        return $tracker->is_depleted;
    }
    else {
        die "I don't know how to retrieve statement attribute '$attrib'\n";
    }
}

sub STORE {
    my ( $sth, $attrib, $value ) = @_;
    $sth->trace_msg( "Storing ST attribute '$attrib'\n" );
    if ( $attrib =~ /^mock/ ) {
        return $sth->{ $attrib } = $value;
    }
    elsif ( $attrib eq 'NAME' ) {
        # no-op...
        return;
    }
    else {
        $value ||= 0;
        return $sth->DBD::_::st::STORE( $attrib, $value );
    }
}

sub DESTROY {
    undef
}


########################################
# TRACKER

package DBD::Mock::StatementTrack;

use strict;

$DBD::Mock::StatementTrack::AUTOLOAD = '';

my %BOOLEAN_FIELDS = map { $_ => 1 } qw( is_executed );
my %SINGLE_FIELDS  = map { $_ => 1 } qw( statement current_record_num );
my %MULTI_FIELDS   = map { $_ => 1 } qw( return_data fields bound_params );

sub new {
    my ( $class, %params ) = @_;
    $params{return_data}      ||= [];
    $params{fields}           ||= [];
    $params{bound_params}     ||= [];
    $params{is_executed}      ||= 'no';
    $params{is_finished}      ||= 'no';
    $params{current_record_num} = 0;
    my $self = bless( \%params, $class );
    return $self;
}

sub num_fields {
    my ( $self ) = @_;
    return scalar @{ $self->{fields} };
}

sub num_params {
    my ( $self ) = @_;
    return scalar @{ $self->{bound_params} };
}

sub bound_param {
    my ( $self, $param_num, $value ) = @_;
    $self->{bound_params}->[ $param_num - 1 ] = $value;
    return $self->bound_params;
}

sub bound_param_trailing {
    my ( $self, @values ) = @_;
    push @{ $self->{bound_params} }, @values;
}

# Rely on the DBI's notion of Active: a statement is active if it's
# currently in a SELECT and has more records to fetch

sub is_active {
    my ( $self, $value ) = @_;
    return 0 unless ( $self->statement =~ /^\s*select/ism );
    return 0 unless ( $self->is_executed );
    return 0 if ( $self->is_depleted );
    return 1;
}

sub is_finished {
    my ( $self, $value ) = @_;
    if ( defined $value and $value eq 'yes' ) {
        $self->{is_finished}        = 'yes';
        $self->{current_record_num} = 0;
        $self->{return_data}        = [];
    }
    elsif ( defined $value ) {
        $self->{is_finished} = 'no';
    }
    return $self->{is_finished};
}

####################
# RETURN VALUES

sub mark_executed {
    my ( $self ) = @_;
    $self->is_executed( 'yes' );
    $self->current_record_num(0);
}

sub next_record {
    my ( $self ) = @_;
    return undef if ( $self->is_depleted );
    my $rec_num = $self->current_record_num;
    my $rec = $self->return_data->[ $rec_num ];
    $self->current_record_num( $rec_num + 1 );
    return $rec;
}

sub is_depleted {
    my ( $self ) = @_;
    return ( $self->current_record_num >= scalar @{ $self->return_data } );
}

# DEBUGGING AID

sub to_string {
    my ( $self ) = @_;
    my $num_records = scalar @{ $self->return_data };
    return join ( "\n",
                  $self->{statement},
                  "Values: [" . join( '] [', @{ $self->{bound_params} } ) . "]",
                  "Records: on $self->{current_record_num} of $num_records\n",
                  "Executed? $self->{is_executed}; Finished? $self->{is_finished}" );
}

# PROPERTIES (since we don't want the usual suspect Class::Accessor as
# dependency)

sub AUTOLOAD {
    my ( $self, @params ) = @_;
    my $request = $DBD::Mock::StatementTrack::AUTOLOAD;
    $request =~ s/.*://;
    my $class = ref $self;
    unless ( $class ) {
        die "Cannot fill method '$request' as a class method ",
            "in '", __PACKAGE__, "'\n";
    }
    no strict 'refs';
    if ( $BOOLEAN_FIELDS{ $request } ) {
        *{ $class . '::' . $request } = sub {
            my ( $self, $yes_no ) = @_;
            if ( defined $yes_no ) {
                $self->{ $request } = $yes_no;
            }
            return ( $self->{ $request } eq 'yes' ) ? 'yes' : 'no';
        }
    }
    elsif ( $SINGLE_FIELDS{ $request } ) {
        *{ $class . '::' . $request } = sub {
            my ( $self, $value ) = @_;
            if ( defined $value ) {
                $self->{ $request } = $value;
            }
            return $self->{ $request };
        }
    }
    elsif ( $MULTI_FIELDS{ $request } ) {
        *{ $class . '::' . $request } = sub {
            my ( $self, @values ) = @_;
            if ( scalar @values ) {
                push @{ $self->{ $request } }, @values;
            }
            return $self->{ $request };
        }
    }
    else {
        die "Don't know how to handle '$request' in ", __PACKAGE__, "; ",
            "called from [", join( ', ', caller ), "]\n";
    }
    return $self->$request( @params );
}

# Otherwise AUTOLOAD will try to handle it...
sub DESTROY { return }

1;

__END__

=head1 NAME

DBD::Mock - Mock database driver for testing

=head1 SYNOPSIS

 use DBI;

 # ...connect as normal, using 'Mock' as your driver name
 my $dbh = DBI->connect( 'DBI:Mock:', '', '' )
               || die "Cannot create handle: $DBI::errstr\n";
 
 # ...create a statement handle as normal and execute with parameters
 my $sth = $dbh->prepare( 'SELECT this, that FROM foo WHERE id = ?' );
 $sth->execute( 15 );
 
 # Now query the statement handle as to what has been done with it
 my $params = $sth->{mock_params};
 print "Used statement: ", $sth->{mock_statement}, "\n",
       "Bound parameters: ", join( ', ', @{ $params } ), "\n";

=head1 DESCRIPTION

=head2 Purpose

Testing with databases can be tricky. If you are developing a system
married to a single database then you can make some assumptions about
your environment and ask the user to provide relevant connection
information. But if you need to test a framework that uses DBI,
particularly a framework that uses different types of persistence
schemes, then it may be more useful to simply verify what the
framework is trying to do -- ensure the right SQL is generated and
that the correct parameters are bound. C<DBD::Mock> makes it easy to
just modify your configuration (presumably held outside your code) and
just use it instead of C<DBD::Foo> (like L<DBD::Pg> or L<DBD::mysql>)
in your framework.

There is no distinct area where using this module makes sense. (Some
people may successfully argue that this is a solution looking for a
problem...) Indeed, if you can assume your users have something like
L<DBD::AnyData> or L<DBD::SQLite> or if you do not mind creating a
dependency on them then it makes far more sense to use these
legitimate driver implementations and test your application in the
real world -- at least as much of the real world as you can create in
your tests...

And if your database handle exists as a package variable or something
else easily replaced at test-time then it may make more sense to use
L<Test::MockObject> to create a fully dynamic handle. There is an
excellent article by chromatic about using L<Test::MockObject> in this
and other ways, strongly recommended. (See L<SEE ALSO> for a link)

=head2 How does it work?

C<DBD::Mock> comprises a set of classes used by DBI to implement a
database driver. But instead of connecting to a datasource and
manipulating data found there it tracks all the calls made to the
database handle and any created statement handles. You can then
inspect them to ensure what you wanted to happen actually
happened. For instance, say you have a configuration file with your
database connection information:

 [DBI]
 dsn      = DBI:Pg:dbname=myapp
 user     = foo
 password = bar

And this file is read in at process startup and the handle stored for
other procedures to use:

 package ObjectDirectory;
 
 my ( $DBH );
 
 sub run_at_startup {
     my ( $class, $config ) = @_;
     $config ||= read_configuration( ... );
     my $dsn  = $config->{DBI}{dsn};
     my $user = $config->{DBI}{user};
     my $pass = $config->{DBI}{password};
     $DBH = DBI->connect( $dsn, $user, $pass ) || die ...;
 }
 
 sub get_database_handle {
     return $DBH;
 }

A procedure might use it like this (ignoring any error handling for
the moment):

 package My::UserActions;
 
 sub fetch_user {
     my ( $class, $login ) = @_;
     my $dbh = ObjectDirectory->get_database_handle;
     my $sql = q{
         SELECT login_name, first_name, last_name, creation_date, num_logins
           FROM users
          WHERE login_name = ?
     };
     my $sth = $dbh->prepare( $sql );
     $sth->execute( $login );
     my $row = $sth->fetchrow_arrayref;
     return ( $row ) ? User->new( $row ) : undef;
 }

So for the purposes of our tests we just want to ensure that:

=over 4

=item 1.

The right SQL is being executed

=item 2.

The right parameters are bound

=back

Assume whether the SQL actually B<works> or not is irrelevant for this
test :-)

To do that our test might look like:

 my $config = ObjectDirectory->read_configuration( ... );
 $config->{DBI}{dsn} = 'DBI:Mock:';
 ObjectDirectory->run_at_startup( $config );
 my $login_name = 'foobar';
 my $user = My::UserActions->fetch_user( $login_name );
 
 # Get the handle from ObjectDirectory; this is the same handle used
 # in the 'fetch_user()' procedure above
 my $dbh = ObjectDirectory->get_database_handle();
 
 # Ask the database handle for the history of all statements executed
 # against it
 my $history = $dbh->{mock_all_history};
 
 # Now query that history record to see if our expectations match
 # reality
 is( scalar @{ $history }, 1,
     'Correct number of statements executed' );
 my $login_st = $history->[0];
 like( $login_st->statement, qr/SELECT login_name.*FROM users WHERE login_name = ?/sm,
       'Correct statement generated' );
 my $params = $login_st->bound_params;
 is( scalar @{ $params }, 1,
     'Correct number of parameters bound' );
 is( $params->[0], $login_name,
     'Correct value for parameter 1' );

 # Reset the handle for future operations
 $dbh->{mock_clear_history} = 1;

The list of properties and what they return is listed below. But in an overall view:

=over 4

=item *

A database handle contains the history of all statements created
against it. Other properties set for the handle (e.g., 'PrintError',
'RaiseError') are left alone and can be queried as normal, but they do
not affect anything. (A future feature may track the sequence/history
of these assignments but if there is no demand it probably will not
get implemented.)

=item *

A statement handle contains the statement it was prepared with plus
all bound parameters or parameters passed via C<execute()>. It can
also contain predefined results for the statement handle to 'fetch',
track how many fetches were called and what its current record is.

=back

=head2 A Word of Warning

This may be an incredibly naive implementation of a DBD. But it works
for me...

=head1 PROPERTIES

Since this is a normal DBI statement handle we need to expose our
tracking information as properties (accessed like a hash) rather than
methods.

=head2 Database Handle Properties

B<mock_all_history>

Returns an array reference with all history
(a.k.a. C<DBD::Mock::StatementTrack>) objects created against the
database handle in the order they were created. Each history object
can then report information about the SQL statement used to create it,
the bound parameters, etc..

B<mock_can_connect>

This statement allows you to simulate a downed database connection.
This is useful in testing how your application/tests will perform in
the face of some kind of catastrophic event such as a network outage
or database server failure. It is a simple boolean value which
defaults to on, and can be set like this:

 # turn the database off
 $dbh->{mock_can_connect} = 0;
 
 # turn it back on again
 $dbh->{mock_can_connect} = 1;

The statement handle checks this value as well, so something like this
will fail in the expected way:

 $dbh = DBI->connect( 'DBI:Mock:', '', '' );
 $dbh->{mock_can_connect} = 0;
 
 # blows up!
 my $sth = eval { $dbh->prepare( 'SELECT foo FROM bar' ) });
 if ( $@ ) {
     # Here, $DBI::errstr = 'No connection present'
 }

Turning off the database after a statement prepare will fail on the
statement C<execute()>, which is hopefully what you would expect:

 $dbh = DBI->connect( 'DBI:Mock:', '', '' );
 
 # ok!
 my $sth = eval { $dbh->prepare( 'SELECT foo FROM bar' ) });
 $dbh->{mock_can_connect} = 0;
 
 # blows up!
 $sth->execute;

Similarly:

 $dbh = DBI->connect( 'DBI:Mock:', '', '' );
 
 # ok!
 my $sth = eval { $dbh->prepare( 'SELECT foo FROM bar' ) });
 
 # ok!
 $sth->execute;

 $dbh->{mock_can_connect} = 0;
 
 # blows up!
 my $row = $sth->fetchrow_arrayref;

Note: The handle attribute C<Active> and the handle method C<ping>
will behave according to the value of C<mock_can_connect>. So if
C<mock_can_connect> were to be set to 0 (or off), then both C<Active>
and C<ping> would return false values (or 0).

B<mock_add_resultset( \@resultset | \%sql_and_resultset )>

This stocks the database handle with a record set, allowing you to
seed data for your application to see if it works properly.. Each
recordset is a simple arrayref of arrays with the first arrayref being
the fieldnames used. Every time a statement handle is created it asks
the database handle if it has any resultsets available and if so uses
it.

Here is a sample usage, partially from the test suite:

 my @user_results = (
    [ 'login', 'first_name', 'last_name' ],
    [ 'cwinters', 'Chris', 'Winters' ],
    [ 'bflay', 'Bobby', 'Flay' ],
    [ 'alincoln', 'Abe', 'Lincoln' ],
 );
 my @generic_results = (
    [ 'foo', 'bar' ],
    [ 'this_one', 'that_one' ],
    [ 'this_two', 'that_two' ],
 );
 
 my $dbh = DBI->connect( 'DBI:Mock:', '', '' );
 $dbh->{mock_add_resultset} = \@user_results;    # add first resultset
 $dbh->{mock_add_resultset} = \@generic_results; # add second resultset
 my ( $sth );
 eval {
     $sth = $dbh->prepare( 'SELECT login, first_name, last_name FROM foo' );
     $sth->execute();
 };

 # this will fetch rows from the first resultset...
 my $row1 = $sth->fetchrow_arrayref;
 my $user1 = User->new( login => $row->[0],
                        first => $row->[1],
                        last  => $row->[2] );
 is( $user1->full_name, 'Chris Winters' );
 
 my $row2 = $sth->fetchrow_arrayref;
 my $user2 = User->new( login => $row->[0],
                        first => $row->[1],
                        last  => $row->[2] );
 is( $user2->full_name, 'Bobby Flay' );
 ...
 
 my $sth_generic = $dbh->prepare( 'SELECT foo, bar FROM baz' );
 $sth_generic->execute;
 
 # this will fetch rows from the second resultset...
 my $row = $sth->fetchrow_arrayref;

You can also associate a resultset with a particular SQL statement
instead of adding them in the order they will be fetched:

 $dbh->{mock_add_resultset} = {
     sql     => 'SELECT foo, bar FROM baz',
     results => [
         [ 'foo', 'bar' ],
         [ 'this_one', 'that_one' ],
         [ 'this_two', 'that_two' ],
     ],
 };

This will return the given results when the statement 'SELECT foo, bar
FROM baz' is prepared. Note that they will be returned B<every time>
the statement is prepared, not just the first. (This behavior could
change.)

B<mock_clear_history>

If set to a true value all previous statement history operations will
be erased. This B<includes> the history of currently open handles, so
if you do something like:

 my $dbh = get_handle( ... );
 my $sth = $dbh->prepare( ... );
 $dbh->{mock_clear_history} = 1;
 $sth->execute( 'Foo' );

You will have no way to learn from the database handle that the
statement parameter 'Foo' was bound.

This is useful mainly to ensure you can isolate the statement
histories from each other. A typical sequence will look like:

 set handle to framework
 perform operations
 analyze mock database handle
 reset mock database handle history
 perform more operations
 analyze mock database handle
 reset mock database handle history
 ...

=head2 Statement Handle Properties

B<Active>

Returns true if the handle is a 'SELECT' and has more records to
fetch, false otherwise. (From the DBI.)

B<mock_statement>

The SQL statement this statement handle was C<prepare>d with. So if
the handle were created with:

 my $sth = $dbh->prepare( 'SELECT * FROM foo' );

This would return:

 SELECT * FROM foo

The original statement is unmodified so if you are checking against it
in tests you may want to use a regex rather than a straight equality
check. (However if you use a phrasebook to store your SQL externally
you are a step ahead...)

B<mock_fields>

Fields used by the statement. As said elsewhere we do no analysis or
parsing to find these, you need to define them beforehand. That said,
you do not actually need this very often.

Note that this returns the same thing as the normal statement property
'FIELD'.

B<mock_params>

Returns an arrayref of parameters bound to this statement in the order
specified by the bind type. For instance, if you created and stocked a
handle with:

 my $sth = $dbh->prepare( 'SELECT * FROM foo WHERE id = ? AND is_active = ?' );
 $sth->bind_param( 2, 'yes' );
 $sth->bind_param( 1, 7783 );

This would return:

 [ 7738, 'yes' ]

The same result will occur if you pass the parameters via C<execute()>
instead:

 my $sth = $dbh->prepare( 'SELECT * FROM foo WHERE id = ? AND is_active = ?' );
 $sth->execute( 7783, 'yes' );

B<mock_records>

An arrayref of arrayrefs representing the records the mock statement
was stocked with.

B<mock_num_records>

Number of records the mock statement was stocked with; if never
stocked it is still 0. (Some weirdos might expect undef...)

B<mock_current_record_num>

Current record the statement is on; returns 0 in the instances when
you have not yet called C<execute()> and if you have not yet called a
C<fetch> method after the execute.

B<mock_is_executed>

Whether C<execute()> has been called against the statement
handle. Returns 'yes' if so, 'no' if not.

B<mock_is_finished>

Whether C<finish()> has been called against the statement
handle. Returns 'yes' if so, 'no' if not.

B<mock_is_depleted>

Returns 'yes' if all the records in the recordset have been
returned. If no C<fetch()> was executed against the statement, or If
no return data was set this will return 'no'.

B<mock_my_history>

Returns a C<DBD::Mock::StatementTrack> object which tracks the
actions performed by this statement handle. Most of the actions are
separately available from the properties listed above, so you should
never need this.

=head1 THE DBD::Mock::StatementTrack OBJECT

Under the hood this module does most of the work with a
C<DBD::Mock::StatementTrack> object. This is most useful when you are
reviewing multiple statements at a time, otherwise you might want to
use the C<mock_*> statement handle attributes instead.

=head2 Methods

B<new( %params )>

Takes the following parameters:

=over 4

=item *

B<return_data>: Arrayref of return data records

=item *

B<fields>: Arrayref of field names

=item *

B<bound_params>: Arrayref of bound parameters

=item *

B<is_executed>: Boolean (as 'yes' or 'no') indicating whether the
statement has been executed.

=item *

B<is_finished>: Boolean (as 'yes' or 'no') indicating whether the
statement has been finished.

=back

B<statement> (Statement attribute 'mock_statement')

Gets/sets the SQL statement used.

B<fields>  (Statement attribute 'mock_fields')

Gets/sets the fields to use for this statement.

B<bound_params>  (Statement attribute 'mock_params')

Gets/set the bound parameters to use for this statement.

B<return_data>  (Statement attribute 'mock_records')

Gets/sets the data to return when asked (that is, when someone calls
'fetch' on the statement handle).

B<current_record_num> (Statement attribute 'mock_current_record_num')

Gets/sets the current record number.

B<is_active()> (Statement attribute 'Active')

Returns true if the statement is a SELECT and has more records to
fetch, false otherwise. (This is from the DBI, see the 'Active' docs
under 'ATTRIBUTES COMMON TO ALL HANDLES'.)

B<is_executed( $yes_or_no )> (Statement attribute 'mock_is_executed')

Sets the state of the tracker 'executed' flag.

B<is_finished( $yes_or_no )> (Statement attribute 'mock_is_finished')

If set to 'yes' tells the tracker that the statement is finished. This
resets the current record number to '0' and clears out the array ref
of returned records.

B<is_depleted()> (Statement attribute 'mock_is_depleted')

Returns true if the current record number is greater than the number
of records set to return.

B<num_fields>

Returns the number of fields set in the 'fields' parameter.

B<num_params>

Returns the number of parameters set in the 'bound_params' parameter.

B<bound_param( $param_num, $value )>

Sets bound parameter C<$param_num> to C<$value>. Returns the arrayref
of currently-set bound parameters. This corresponds to the
'bind_param' statement handle call.

B<bound_param_trailing( @params )>

Pushes C<@params> onto the list of already-set bound parameters.

B<mark_executed()>

Tells the tracker that the statement has been executed and resets the
current record number to '0'.

B<next_record()>

If the statement has been depleted (all records returned) returns
undef; otherwise it gets the current recordfor returning, increments
the current record number and returns the current record.

B<to_string()>

Tries to give an decent depiction of the object state for use in
debugging.

=head1 SEE ALSO

L<DBI>

L<DBD::NullP>, which provided a good starting point

L<Test::MockObject>, which provided the approach

Test::MockObject article - L<http://www.perl.com/pub/a/2002/07/10/tmo.html>

=head1 COPYRIGHT

Copyright (c) 2004 Chris Winters. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHORS

Chris Winters E<lt>chris@cwinters.comE<gt>

Stevan Little E<lt>stevan@iinteractive.comE<gt>
