package AnyEvent::CouchDB::Stream;

use strict;
use warnings;
use URI;
use AnyEvent::HTTP;
use Scalar::Util;
use JSON;
use Try::Tiny;

our $VERSION = '0.01';

sub new {
    my $class        = shift;
    my %args         = @_;
    my $server       = delete $args{url};
    my $db           = delete $args{database};
    my $timeout      = delete $args{timeout};
    my $filter       = delete $args{filter};
    my $since        = delete $args{since} || 1;
    my $on_change    = delete $args{on_change};
    my $on_error     = delete $args{on_error} || sub { die @_ };
    my $on_eof       = delete $args{on_eof} || sub { };
    my $on_keepalive = delete $args{on_keepalive} || sub { };
    my $headers      = delete $args{headers}
        || { 'Content-Type' => 'application/json' };

    my $uri = URI->new($server);
    $uri->path( $db. '/_changes' );
    $uri->query_form( filter => $filter, feed => "continuous", since => $since );

    my $self = bless {}, $class;

    {
        Scalar::Util::weaken( my $self = $self );
        my $set_timeout = $timeout
            ? sub {
            $self->{timeout}
                = AE::timer( $timeout, 0, sub { $on_error->('timeout') } );
            }
            : sub { };

        $set_timeout->();

        $self->{connection_guard} = http_get(
            $uri,
            headers   => $headers,
            on_header => sub {
                my ($headers) = @_;
                if ( $headers->{Status} ne '200' ) {
                    return $on_error->(
                        "$headers->{Status}: $headers->{Reason}: $uri");
                }
                return 1;
            },
           want_body_handle => 1,
            sub {
                my ( $handle, $headers ) = @_;
                if ($handle) {
                    $handle->on_error(
                        sub {
                            undef $handle;
                            $on_error->( $_[2] );
                        }
                    );
                    $handle->on_eof(
                        sub {
                            undef $handle;
                            $on_eof->(@_);
                        }
                    );
                    my $reader;
                    $reader = sub {
                        my ( $handle, $json ) = @_;
                        $set_timeout->();
                        if ($json) {
                            try {
                              $on_change->(JSON::decode_json($json));
                            } 
                            catch {
                              # I'm not sure why, but sometimes
                              # some weird characters show up
                              # in between the JSON objects.
                            };
                        }
                        else {
                            $on_keepalive->();
                        }
                        $handle->push_read( line => $reader );
                    };
                    $handle->push_read( line => $reader );
                    $self->{guard} = AnyEvent::Util::guard {
                        $on_eof->();
                        $handle->destroy if $handle;
                        undef $reader;
                    };
                }
           }
        );
    }
    $self;
}

1;
__END__

=head1 NAME

AnyEvent::CouchDB::Stream - Watch changes from a CouchDB database.

=head1 SYNOPSIS

  use AnyEvent::CouchDB::Stream;
  my $listener = AnyEvent::CouchDB::Stream->new(
      url       => 'http://localhost:5984',
      database  => 'test',
      on_change => sub {
          my $change = shift;
          warn "document $change->{_id} updated";
      },
      on_keepalive => sub {
          warn "ping\n";
      },
      timeout => 1,
  );

=head1 DESCRIPTION

AnyEvent::CouchDB::Stream is an interface to the CouchDB B<changes> database API.

=head2 OPTIONS

=over 4

=item B<url>

URL of the CouchDB host.

=item B<database>

Name of the CouchDB database.

=item B<timeout>

Number of seconds to wait before timing out.  On timeout, The on_error 
code ref will be called with an argument of 'timeout'.

=item B<filter>

Name of the filter to execute on this notifier.

=item B<since>

Number to fetch changes from. Defaults to 1.

=item B<on_change>

A code ref to execute when a change notification is received. It is mandatory.

=item B<on_keepalive>

A code ref to execute when keepalive is called.

=item B<on_error>

A code ref to execute on error. Code ref is passed the error message.

=item B<on_eof>

A code ref to execute on eof

=item B<headers>

An optional hashref of headers that should be used for the HTTP request.
Defaults to C< { 'Content-Type' => 'application/json' } >.

=back

=head1 AUTHOR

franck cuny E<lt>franck.cuny@linkfluence.netE<gt>

=head1 SEE ALSO

L<AnyEvent::HTTP>, L<AnyEvent::CouchDB>, L<AnyEvent::Twitter::Stream>, L<http://books.couchdb.org/relax/reference/change-notifications>

=head1 LICENSE

Copyright 2010 by Linkfluence

L<http://linkfluence.net>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
