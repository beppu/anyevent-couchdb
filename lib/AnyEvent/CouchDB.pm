package AnyEvent::CouchDB;

use strict;
use warnings;
our $VERSION = '1.11';

use JSON::XS;
use AnyEvent::HTTP;
use AnyEvent::CouchDB::Database;
use URI;
use URI::Escape;
use File::Basename;
use Data::Dump 'pp';

use Exporter;
use base 'Exporter';

our @EXPORT = qw(couch couchdb);

# default JSON encoder
our $default_json = JSON::XS->new->utf8;

sub cvcb {
  my ($options, $status, $json) = @_;
  $status ||= 200;
  $json   ||= $default_json;
  my $cv = AnyEvent->condvar;

  # default success handler sends back decoded json response
  my $success = sub {
    my ($resp) = @_;
    $options->{success}->(@_) if ($options->{success});
    $cv->send($resp);
  };

  # default error handler croaks w/ http headers and response
  my $error = sub {
    my ($headers, $response) = @_;
    $options->{error}->(@_) if ($options->{error});
    $cv->croak(pp([$headers, $response]));
  };

  my $cb = sub {
    my ($body, $headers) = @_;
    my $response;
    eval { $response = $json->decode($body); };
    $cv->croak(pp(['decode_error', $@, $body, $headers])) if ($@);
    if ($headers->{Status} >= $status and $headers->{Status} < 400) {
      $success->($response);
    } else {
      $error->($headers, $response);
    }
  };
  ($cv, $cb);
}

sub couch {
  AnyEvent::CouchDB->new(@_);
}

sub couchdb {
  my $db = shift;
  if ($db =~ /^http:/) {
    my $uri  = $db;
    my $name = basename($db);
    $uri .= '/' if ($uri !~ /\/$/);
    AnyEvent::CouchDB::Database->new($name, $uri);
  } else {
    AnyEvent::CouchDB->new->db($db);
  }
}

sub new {
  my ($class, $url) = @_;
  $url ||= 'http://localhost:5984/';
  bless { url => URI->new($url) } => $class;
}

sub all_dbs {
  my ($self, $options) = @_;
  my ($cv, $cb) = cvcb($options);
  http_get $self->{url}.'_all_dbs', $cb;
  $cv;
}

sub db {
  my ($self, $name) = @_;
  my $uri = $self->{url}->clone;
  $uri->path($name . "/");
  AnyEvent::CouchDB::Database->new($name, $uri);
}

sub info {
  my ($self, $options) = @_;
  my ($cv, $cb) = cvcb($options);
  http_get $self->{url}->as_string, $cb;
  $cv;
}

sub config {
  my ($self, $options) = @_;
  my ($cv, $cb) = cvcb($options);
  http_get $self->{url} . '_config', $cb;
  $cv;
}

sub replicate {
  my ($self, $source, $target, $options) = @_;
  my ($cv, $cb) = cvcb($options);
  my $body = $default_json->encode({ source => $source, target => $target });
  http_request(
    POST    => $self->{url}.'_replicate', 
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

  my $couch = couch('http://localhost:5984/');
  print pp( $couch->all_dbs->recv ), "\n";
  print pp( $couch->info->recv    ), "\n";

Get an object representing a CouchDB database:

  my $db = $couch->db('database');
  $db    = couchdb('database');
  $db    = couchdb('http://somewhere.com:7777/database/');

Work with individual CouchDB documents;

  my $user = $db->open_doc('~larry')->recv;
  $user->{name} = "larry";
  $db->save_doc($user)->recv;

Query a view:

  $db->view('users/all', { startkey => 'b', endkey => 'bZZZ' })->recv

Finally, an asynchronous example:

  # Calling cb will not block whereas calling recv *will* block.
  $db->all_docs->cb(sub { 
    my ($cv) = @_;
    print pp( $cv->recv ), "\n"; 
  });

  # However, you have to be in an event loop at some point in time.
  AnyEvent->condvar->recv;

=head1 DESCRIPTION

AnyEvent::CouchDB is a non-blocking CouchDB client implemented on top of the
L<AnyEvent> framework.  Using this library will give you the ability to run
many CouchDB requests asynchronously, and it was intended to be used within
a L<Coro>+L<AnyEvent> environment.  However, it can also be used synchronously
if you want.

Its API is based on jquery.couch.js, but we've adapted the API slightly so that
it makes sense in an asynchronous Perl environment.

=head2 AnyEvent condvars

The main thing you have to remember is that all the data retrieval methods
return an AnyEvent condvar, C<$cv>.  If you want the actual data from the
request, there are a few things you can do.

You may have noticed that many of the examples in the SYNOPSIS call C<recv>
on the condvar.  You're allowed to do this under 2 circumstances:

=over 4
      
=item Either you're in a main program,

Main programs are "allowed to call C<recv> blockingly", according to the
author of L<AnyEvent>.

=item or you're in a Coro + AnyEvent environment.

When you call C<recv> inside a coroutine, only that coroutine is blocked
while other coroutines remain active.  Thus, the program as a whole is
still responsive.

=back

If you're not using Coro, and you don't want your whole program to block,
what you should do is call C<cb> on the condvar, and give it a coderef to
execute when the results come back.  The coderef will be given a condvar
as a parameter, and it can call C<recv> on it to get the data.  The final
example in the SYNOPSIS gives a brief example of this.

Also note that C<recv> will throw an exception if the request fails, so be
prepared to catch exceptions where appropriate.

Please read the L<AnyEvent> documentation for more information on the proper
use of condvars.

=head2 The \%options Parameter

Many data retrieval methods will take an optional C<\%options> hashref.
Most of these options get turned into CGI query parameters.  The standard
CouchDB parameters are as follows:

=over 4

=item key=keyvalue

This lets you pick out one document with the specified key value.

=item startkey=keyvalue

This makes it so that lists start with a key value that is greater than or
equal to the specified key value.

=item startkey_docid=docid

This makes it so that lists start with a document with the specified docid.

=item endkey=keyvalue

This makes it so that lists end with a key value that is less than or
equal to the specified key value.

=item count=max_rows_to_return

This limits the number of results to the specified number or less.
If count is set to 0, you won't get any rows, but you I<will> get
the metadata for the request you made.

=item update=boolean

If you set C<update> to C<false>, CouchDB will skip doing any updating of a
view.  This will speed up the request, but you might not see all the latest
data.

=item descending=boolean

Views are sorted by their keys in ascending order.  However, if you set
C<descending> to C<true>, they'll come back in descending order.

=item skip=rows_to_skip

The skip option should only be used with small values, as skipping a large
range of documents this way is inefficient (it scans the index from the
startkey and then skips N elements, but still needs to read all the index
values to do that). For efficient paging use startkey and/or startkey_docid.

=back


You may also put subroutine references in the C<success> and C<error> keys of
this hashref, and they will be called upon success or failure of the request.



=head2 Documents Are Plain Hashrefs

Finally, note that the CouchDB documents you get back are plain hashrefs.  They
are not blessed into any kind of document class.  


=head1 API

=head2 Convenience Functions

=head3 $couch = couch([ $url ]);

This is a short-cut for:

  AnyEvent::CouchDB->new($url)

and it is exported by default.  It will return a connection to a CouchDB server,
and if you don't pass it a URL, it'll assume L<http://localhost:5984/>.  Thus,
you can type:

  $couch = couch;

=head3 $db = couchdb($name_or_url);

This function will construct an L<AnyEvent::CouchDB::Database> object for you.
If you only give it a name, it'll assume that the CouchDB server is at
L<http://localhost:5984/>.  You may also give it a full URL to a CouchDB
database to connect to.

This function is also exported by default.

=head2 Object Construction

=head3 $couch = AnyEvent::CouchDB->new([ $url ])

This method will instantiate an object that represents a CouchDB server.
By default, it connects to L<http://localhost:5984/>, but you may explicitly
give it another URL if you want to connect to a CouchDB server on another
server or a non-default port.

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

=head3 $cv = $couch->config()

This method requests a hashref of info regarding the configuration of the
current CouchDB server.  It returns a condvar that you should call C<recv> on.

=head3 $cv = $couch->replicate($source, $target, [ \%options ])

This method requests that a C<$source> CouchDB database be replicated to a
C<$target> CouchDB database.  To represent a local database, pass in just
the name of the database.  To represent a remote database, pass in the
URL to that database.  Note that both databases must already exist for
the replication to work.

B<Examples>:

  # local to local
  $couch->replicate('local_db', 'local_db_backup')->recv;

  # local to remote
  $couch->replicate('local_db', 'http://elsewhere/remote_db')->recv

  # remote to local
  $couch->replicate('http://elsewhere/remote_db', 'local_db')->recv

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

=head2 Scripts

=over 4

=item L<couchdb-push>

Push documents from the filesystem to CouchDB

=back

=head2 Related Modules

L<AnyEvent::CouchDB::Database>, L<AnyEvent::HTTP>, L<AnyEvent>

=head2 Other CouchDB-related Perl Modules

=head3 Client Libraries

L<Net::CouchDb>,
L<CouchDB::Client>,
L<POE::Component::CouchDB::Client>,
L<DB::CouchDB>

=head3 View Servers

L<CouchDB::View> - This lets you write your map/reduce functions in Perl
instead of JavaScript.

=head2 The Original JavaScript Version

L<http://svn.apache.org/repos/asf/couchdb/trunk/share/www/script/jquery.couch.js>

=head2 The Reason for Existence

AnyEvent::CouchDB exists, because I needed a non-blocking CouchDB client that
I could use within L<Continuity> and L<Squatting>.

=head1 AUTHOR

John BEPPU E<lt>beppu@cpan.orgE<gt>

=head1 SPECIAL THANKS

Jan-Felix Wittman (for bug fixes, feature enhancements, and interesting couchdb discussion)

Yuval Kogman (for bug fixes)

=head1 COPYRIGHT

Copyright (c) 2008-2009 John BEPPU E<lt>beppu@cpan.orgE<gt>.

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
