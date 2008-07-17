package AnyEvent::CouchDB;

use strict;
use warnings;
our $VERSION = '0.99';

use JSON::XS;
use AnyEvent::HTTP;
use AnyEvent::CouchDB::Database;
use URI::Escape;
use Data::Dump 'pp';

our $cvcb = sub {
  my ($options, $status) = @_;
  $status ||= 200;
  my $cv = AnyEvent->condvar;

  # default success handler sends back decoded json response
  my $success = $options->{success} || sub {
    my ($response) = @_;
    $cv->send($response);
  };

  # default error handler croaks w/ http headers and response
  my $error = $options->{error} || sub {
    my ($headers, $response) = @_;
    $cv->croak(pp([$headers, $response]));
  };

  my $cb = sub {
    my ($body, $headers) = @_;
    my $response;
    eval { $response = decode_json($body); };
    $cv->croak(pp(['decode_error', $@, $body, $headers])) if ($@);
    if ($headers->{Status} == $status) {
      $success->($response);
    } else {
      $error->($headers, $response);
    }
  };
  ($cv, $cb);
};

sub new {
  my ($class, $url) = @_;
  $url ||= 'http://localhost:5984';
  bless { url => $url } => $class;
}

sub all_dbs {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get $self->{url}.'/_all_dbs', $cb;
  $cv;
}

sub db {
  my ($self, $name) = @_;
  my $uri = $self->{url} . "/" . uri_escape($name) . "/";
  AnyEvent::CouchDB::Database->new($name, $uri);
}

sub info {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get $self->{url}.'/', $cb;
  $cv;
}

sub replicate {
  my ($self, $source, $target, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  my $body = encode_json({ source => $source, target => $target });
  http_request(
    POST    => $self->{url}.'/_replicate', 
    headers => { 'Content-Type' => 'application/json' },
    body    => $body, 
    $cb
  );
  $cv;
}

1;

__END__

=head1 NAME

AnyEvent::CouchDB - a non-blocking CouchDB client based on jquery.couch.js

=head1 SYNOPSIS

Getting information about a CouchDB server:

  use AnyEvent::CouchDB;
  use Data::Dump 'pp';

  my $couch = AnyEvent::CouchDB->new;
  print pp( $couch->all_dbs->recv ), "\n";
  print pp( $couch->info->recv    ), "\n";

Get an object representing a CouchDB database:

  my $db = $couch->db('database');

=head1 DESCRIPTION

AnyEvent::CouchDB is a non-blocking CouchDB client implemented on top of the
L<AnyEvent> framework.  Using this library will give you the ability to run
many CouchDB requests asynchronously.  However, it can also be used synchronously
if you want.

Its API is based on jquery.couch.js, but we've adapted the API slightly so that
it makes sense in an asynchronous Perl environment.

The main thing you have to remember is that all the data retrieval methods
return an AnyEvent condvar, C<$cv>.  If you want the actual data from the
request, it's up to you to call C<recv> on it.

Also note that C<recv> will throw an exception if the request fails, so be
prepared to catch exceptions where appropriate.

=head1 API

=head2 Object Construction

=head3 $couch = AnyEvent::CouchDB->new([ $url ])

This method will instantiate an object that represents a CouchDB server.
By default, it connects to L<http://localhost:5984>, but you may explicitly
give it another URL if you want to connect to a CouchDB server on another
server and/or a non-default port.

=head3 $db = $couch->db($name)

This method takes a name and returns an L<AnyEvent::CouchDB::Database> object.
This is the object that you'll use to work with CouchDB documents.

=head2 Queries and Actions

=head3 $cv = $couch->all_dbs()

This method requests an arrayref that contains the names of all the databases
hosted on the current CouchDB server.  It returns an AnyEvent condvar that
you'll be expected to call C<recv> on to get the data back.

=head3 $cv = $couch->info()

This method requests a hashref of info about the current CouchDB server and
returns a condvar that you should call C<recv> on.  The hashref that's returned
looks like this:

  {
    couchdb => 'Welcome',
    version => '0.7.3a658574'
  }

=head3 $cv = $couch->replicate($source, $target, [ \%options ])

This method requests that a C<$source> CouchDB database be replicated to a
C<$target> CouchDB database.  To represent a local database, pass in just
the name of the database.  To represent a remote database, pass in the
URL to that database.  Note that both databases must already exist for
the replication to work.

B<Examples>:

  # local to local
  $couch->replicate('local_a', 'local_a_backup')->recv;

  # local to remote
  $couch->replicate('local_a', 'http://elsewhere/remote_a')->recv

  # remote to local
  $couch->replicate('http://elsewhere/remote_a', 'local_a')->recv

As usual, this method returns a condvar that you're expected to call C<recv> on.
Doing this will return a hashref that looks something like this upon success:

  {
    history => [
      {
        docs_read       => 0,
        docs_written    => 0,
        end_last_seq    => 149,
        end_time        => "Thu, 17 Jul 2008 18:08:13 GMT",
        missing_checked => 44,
        missing_found   => 0,
        start_last_seq  => 0,
        start_time      => "Thu, 17 Jul 2008 18:08:13 GMT",
      },
    ],
    ok => bless(do { \(my $o = 1) }, "JSON::XS::Boolean"),
    session_id      => "cac3c6259b452c36230efe5b41259c04",
    source_last_seq => 149,
  }

=head1 SEE ALSO

=head2 Related Modules

L<AnyEvent::CouchDB::Database>, L<AnyEvent::HTTP>, L<AnyEvent>

=head2 Other CouchDB-related Perl Modules

=head3 Client Libraries

L<Net::CouchDb>,
L<CouchDB::Client>,
L<POE::Component::CouchDB::Client>

=head3 View Servers

L<CouchDB::View>

=head3 Search Servers

None exist, yet.

=head1 AUTHOR

John BEPPU E<lt>beppu@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (c) 2008 John BEPPU E<lt>beppu@cpan.orgE<gt>.

=head2 The "MIT" License

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

=cut

# Local Variables: ***
# mode: cperl ***
# indent-tabs-mode: nil ***
# cperl-close-paren-offset: -2 ***
# cperl-continued-statement-offset: 2 ***
# cperl-indent-level: 2 ***
# cperl-indent-parens-as-block: t ***
# cperl-tab-always-indent: nil ***
# End: ***
# vim:tabstop=8 softtabstop=2 shiftwidth=2 shiftround expandtab
