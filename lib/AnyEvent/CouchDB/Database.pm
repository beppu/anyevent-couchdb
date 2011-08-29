package AnyEvent::CouchDB::Database;

use strict;
use warnings;
no  warnings 'once';
use JSON::XS;
use AnyEvent::HTTP;
use AnyEvent::CouchDB::Exceptions;
use Data::Dump::Streamer;
use URI::Escape qw( uri_escape uri_escape_utf8 );
use IO::All;
use MIME::Base64;

our $default_json;

# manual import ;-)
*cvcb           = *AnyEvent::CouchDB::cvcb;
*default_json   = *AnyEvent::CouchDB::default_json;
*_build_headers = *AnyEvent::CouchDB::_build_headers;

our $query = sub {
  my $options = shift;
  my $json    = $default_json;
  my @buf;
  if (defined($options) && keys %$options) {
    for my $name (keys %$options) {
      next if ($name eq 'error' || $name eq 'success' || $name eq 'headers');
      my $value = $options->{$name};
      if ($name eq 'key' || $name eq 'startkey' || $name eq 'endkey') {
        $value = ref($value)
          ? uri_escape($json->encode($value))
          : (defined $value)
            ? uri_escape_utf8(qq{"$value"})
            : 'null';
      } else {
        $value = uri_escape_utf8($value);
      }
      if ($name eq 'group' || $name eq 'reduce' || $name eq 'descending' || $name eq 'include_docs') {
        $value = $value
          ? ( ($value eq 'false') ? 'false' : 'true' )
          : 'false';
      }
      push @buf, "$name=$value";
    }
  }
  (@buf)
    ? '?' . join('&', @buf)
    : '';
};

our $code_to_string = sub {
  ref($_[0])
    ? sprintf 'do { my $CODE1; %s; $CODE1 }',
      Data::Dump::Streamer->new->Data($_[0])->Out
    : $_[0];
  # ^- taken from CouchDB::View::Document ------^
};

sub new {
  my ($class, $name, $uri, $json_encoder) = @_;
  $json_encoder ||= $default_json;
  my $self = bless { name => $name, uri => $uri, json_encoder => $json_encoder } => $class;
  if (my $userinfo = $self->uri->userinfo) {
    my $auth = encode_base64($userinfo, '');
    $self->{http_auth} = "Basic $auth";
  }
  return $self;
}

sub name {
  $_[0]->{name};
}

sub uri {
  $_[0]->{uri};
}

sub json_encoder {
  my ($self, $encoder) = @_;
  if ($encoder) {
    $self->{json_encoder} = $encoder;
  } else {
    $self->{json_encoder};
  }
}

sub json {
  my ( $self, $target ) = @_;
  ref($target) ? $self->json_encoder->encode($target) : $target;
}

sub compact {
  my ( $self, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, 202, $self->json_encoder );
  http_request(
    POST    => ( $self->uri . "_compact" ),
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub create {
  my ( $self, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, 201, $self->json_encoder );
  http_request(
    PUT     => $self->uri,
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub drop {
  my ( $self, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  http_request(
    DELETE  => $self->uri,
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub info {
  my ( $self, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  http_request(
    GET     => $self->uri,
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub all_docs {
  my ( $self, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  http_request(
    GET     => $self->uri . '_all_docs' . $query->($options),
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub all_docs_by_seq {
  my ( $self, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  http_request(
    GET     => $self->uri . '_all_docs_by_seq' . $query->($options),
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub open_doc {
  my ( $self, $doc_id, $options ) = @_;
  if ( not defined $doc_id ) {
    AnyEvent::CouchDB::Exception::UndefinedDocument->throw(
      "An undefined id was passed to open_doc()."
    );
  }
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  my $id = uri_escape_utf8($doc_id);
  if ( $id =~ qr{^_design%2F} ) {
    $id =~ s{%2F}{/}g;
  }
  http_request(
    GET     => $self->uri . $id . $query->($options),
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub open_docs {
  my ( $self, $doc_ids, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  $options ||= {};
  $options->{'include_docs'} = 'true';
  http_request(
    POST    => $self->uri . '_all_docs' . $query->($options),
    headers => $self->_build_headers($options),
    body    => $self->json( { "keys" => $doc_ids } ),
    $cb
  );
  $cv;
}

sub save_doc {
  my ( $self, $doc, $options ) = @_;

  # create attachment stubs for new inlined attachments
  my $_attachments = sub {
    my ( $doc ) = @_;
    my $_a = $doc->{_attachments};
    return unless defined $_a;
    my $revpos = $doc->{_rev};
    $revpos =~ s/-.*$//;
    for my $key (keys %$_a) {
      if ( exists($_a->{$key}{data}) ) {
        my $file = $_a->{$key};
        $file->{length} = length(decode_base64($file->{data}));
        $file->{revpos} = $revpos;
        $file->{stub}   = JSON::true();
        delete $file->{data};
      }
    }
  };

  if ( $options->{success} ) {
    my $orig = $options->{success};
    $options->{success} = sub {
      my ($resp) = @_;
      $orig->($resp);
      $doc->{_id}  = $resp->{id};
      $doc->{_rev} = $resp->{rev};
      $_attachments->($doc);
    };
  }
  else {
    $options->{success} = sub {
      my ($resp) = @_;
      $doc->{_id}  = $resp->{id};
      $doc->{_rev} = $resp->{rev};
      $_attachments->($doc);
    };
  }
  my ( $cv, $cb ) = cvcb( $options, 201, $self->json_encoder );
  my ( $method, $uri );
  if ( not defined $doc->{_id} ) {
    $method = 'POST';
    $uri    = $self->uri;
  }
  else {
    $method = 'PUT';
    $uri    = $self->uri . uri_escape_utf8( $doc->{_id} );
  }
  http_request(
    $method => $uri . $query->($options),
    headers => $self->_build_headers($options),
    body    => $self->json($doc),
    $cb
  );
  $cv;
}

sub remove_doc {
  my ( $self, $doc, $options ) = @_;
  die("Document is missing _id!") unless ( defined $doc->{_id} );
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  http_request(
    DELETE => $self->uri
        . uri_escape_utf8( $doc->{_id} )
        . $query->( { rev => $doc->{_rev} } ),
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub attach {
  my ( $self, $doc, $attachment, $options ) = @_;
  my $body < io( $options->{src} );
  $options->{type} ||= 'text/plain';
  if ( $options->{success} ) {
    my $orig = $options->{success};
    $options->{success} = sub {
      my ($resp) = @_;
      $orig->($resp);
      $doc->{_id}  = $resp->{id};
      $doc->{_rev} = $resp->{rev};
      $doc->{_attachments} ||= {};
      $doc->{_attachments}->{$attachment} = {
        'content_type' => $options->{type},
        'length'       => length($body),
        'stub'         => JSON::XS::true,
      };
    };
  }
  else {
    $options->{success} = sub {
      my ($resp) = @_;
      $doc->{_id}  = $resp->{id};
      $doc->{_rev} = $resp->{rev};
      $doc->{_attachments} ||= {};
      $doc->{_attachments}->{$attachment} = {
        'content_type' => $options->{type},
        'length'       => length($body),
        'stub'         => JSON::XS::true,
      };
    };
  }
  my ( $cv, $cb ) = cvcb( $options, 201, $self->json_encoder );
  http_request(
    PUT => $self->uri
        . uri_escape_utf8( $doc->{_id} ) . "/"
        . uri_escape_utf8($attachment)
        . $query->( { rev => $doc->{_rev} } ),
    headers => $self->_build_headers($options),
    body    => $body,
    $cb
  );
  $cv;
}

sub open_attachment {
  my ( $self, $doc, $attachment, $options ) = @_;
  my $cv = AnyEvent->condvar;

  # passthrough handler without json encoding
  my $success = sub {
    $options->{success}->(@_) if ($options->{success});
    $cv->send(@_);
  };

  # error handler that croaks with http headers
  my $error = sub {
    my $headers = shift;
    $options->{error}->(@_) if ($options->{error});
    $cv->croak(encode_json $headers);
  };

  my $cb = sub {
    my ($body, $headers) = @_;
    if ($headers->{Status} >= 200 and $headers->{Status} < 400) {
      $success->(@_);
    } else {
      $error->($headers);
    }
  };

  http_request(
    GET => $self->uri
        . uri_escape_utf8( $doc->{_id} ) . "/"
        . uri_escape_utf8($attachment),
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub detach {
  my ( $self, $doc, $attachment, $options ) = @_;
  if ( $options->{success} ) {
    my $orig = $options->{success};
    $options->{success} = sub {
      my ($resp) = @_;
      $orig->($resp);
      $doc->{_id}  = $resp->{id};
      $doc->{_rev} = $resp->{rev};
      delete $doc->{_attachments}->{$attachment};
    };
  }
  else {
    $options->{success} = sub {
      my ($resp) = @_;
      $doc->{_id}  = $resp->{id};
      $doc->{_rev} = $resp->{rev};
      delete $doc->{_attachments}->{$attachment};
    };
  }
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  http_request(
    DELETE => $self->uri
        . uri_escape_utf8( $doc->{_id} ) . "/"
        . uri_escape_utf8($attachment)
        . $query->( { rev => $doc->{_rev} } ),
    headers => $self->_build_headers($options),
    $cb
  );
  $cv;
}

sub bulk_docs {
  my ( $self, $docs, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  http_request(
    POST    => $self->uri . '_bulk_docs',
    headers => $self->_build_headers($options),
    body    => $self->json( { docs => $docs } ),
    $cb
  );
  $cv;
}

sub query {
  my ( $self, $map_fun, $reduce_fun, $language, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  $language ||= ( ref($map_fun) eq 'CODE' ) ? 'text/perl' : 'javascript';
  my $body = {
    language => $language,
    map      => $code_to_string->($map_fun),
  };
  if ($reduce_fun) {
    $body->{reduce} = $code_to_string->($reduce_fun);
  }
  http_request(
    POST    => $self->uri . '_temp_view' . $query->($options),
    headers => $self->_build_headers($options),
    body    => $self->json($body),
    $cb
  );
  $cv;
}

sub view {
  my ( $self, $name, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  my ( $dname, $vname ) = split( '/', $name );
  my $uri = $self->uri . "_design/" . $dname . "/_view/" . $vname;
  if ( $options->{keys} ) {
    my $body = { keys => $options->{keys} };
    my $opts = { %$options };
    delete $opts->{keys};
    http_request(
      POST    => $uri . $query->($opts),
      headers => $self->_build_headers($options),
      body    => $self->json($body),
      $cb
    );
  }
  else {
    my $headers = $self->_build_headers($options);
    http_request(
      GET     => $uri . $query->($options),
      headers => $headers,
      $cb
    );
  }
  $cv;
}

sub head {
  my ( $self, $path, $options ) = @_;
  my ( $cv, undef ) = cvcb( $options, undef, $self->json_encoder );
  my $headers = $self->_build_headers($options);
  my $uri     = $self->uri . "$path" . $query->($options);
  http_request(
    HEAD    => $uri,
    headers => $headers,
    sub { $cv->send( $_[1] ); }
  );
  $cv;
}

sub get {
  my ( $self, $path, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  my $headers = $self->_build_headers($options);
  my $uri     = $self->uri . "$path" . $query->($options);
  http_request(
    GET     => $uri,
    headers => $headers,
    $cb
  );
  $cv;
}

sub post {
  my ( $self, $path, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  my $headers = $self->_build_headers($options);
  my $uri     = $self->uri . "$path";
  http_request(
    POST    => $uri,
    headers => $headers,
    body    => $query->($options),
    $cb
  );
  $cv;
}

sub delete {
  my ( $self, $path, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  my $headers = $self->_build_headers($options);
  my $uri     = $self->uri . "$path" . $query->($options);
  http_request(
    DELETE  => $uri,
    headers => $headers,
    $cb
  );
  $cv;
}

sub put {
  my ( $self, $path, $options ) = @_;
  my ( $cv, $cb ) = cvcb( $options, undef, $self->json_encoder );
  my $headers = $self->_build_headers($options);
  my $uri     = $self->uri . "$path";
  http_request(
    PUT     => $uri,
    headers => $headers,
    body    => $query->($options),
    $cb
  );
  $cv;
}


__END__

=head1 NAME

AnyEvent::CouchDB::Database - an object representing a CouchDB database

=head1 SYNOPSIS

  use AnyEvent::CouchDB;
  $db = couchdb('bavl');
  my $map = 'function(doc){
    if(doc.type == "Phrase"){ emit(null, doc) }
  }';
  my $phrases = $db->query($map)->recv;
  my $recordings = $db->view('recordings/all')->recv;

=head1 DESCRIPTION

Objects of this class represent a single CouchDB database.  This object is used
create and drop databases as well as operate on the documents within the database.

=head1 API

=head2 General

=head3 $db = AnyEvent::CouchDB::Database->new($name, $uri)

This method takes a name and a URI, and constructs an object representing a
CouchDB database.  The name should be conservative in the characters it uses,
because it needs to be both URI friendly and portable across filesystems.
Also, the URI that you pass in should contain a trailing slash.

=head3 $db->name

This method returns the name of the database.

=head3 $db->uri

This method returns the base URI of the database.

=head3 $db->json_encoder([ $json_encoder ])

This method is a mutator for setting a custom JSON encoder.  You should
pass in an object that responds to C<encode> and C<decode>.  Instances of
L<JSON> and L<JSON::XS> are good candidates.

=head2 Options

All the methods that accept an optional hashref of options can set an "headers"
key, wich will be added to all the requests. So you can add basic
authentication to your requests if needed:

  my $couchdb = couch("http://127.0.0.1:5984/");
  my $db      = $couchdb->db("mydb");
  my $auth    = encode_base64('user:s3kr3t', '');

  my $res = $db->create({headers => {'Authorization' => 'Basic '.$aut}})->recv;

B<UPDATE>:  You can now make authenticated requests by placing the username and
password in the URI.

  my $db = couchdb('http://user:s3kr3t@127.0.0.1:5984/mydb');

=head2 Database Level Operations

=head3 $cv = $db->create([ \%options ])

This method is used to create a CouchDB database.  It returns an L<AnyEvent>
condvar.

=head3 $cv = $db->drop([ \%options ])

This method is used to drop a CouchDB database, and it returns a condvar.

=head3 $cv = $db->info([ \%options ])

This method is used to request a hashref of info about the current CouchDB
database, and it returns a condvar.

=head3 $cv = $db->compact([ \%options ])

This method is used to request that the current CouchDB database
be compacted, and it returns a condvar.

=head2 Document Level Operations

=head3 $cv = $db->open_doc($id, [ \%options ])

This method is used to request a single CouchDB document by its C<id>, and
it returns a condvar.

=head3 $cv = $db->open_docs($ids, [ \%options ])

This method is used to request multiple CouchDB documents by their C<ids>, and
it returns a condvar.

=head3 $cv = $db->save_doc($doc, [ \%options ])

This method can be used to either create a new CouchDB document or update an
existing CouchDB document.  It returns a condvar.

Note that upon success, C<$doc> will have its C<_id> and C<_rev> keys
updated.  This allows you to save C<$doc> repeatedly using the same hashref.

=head3 $cv = $db->remove_doc($doc, [ \%options ])

This method is used to remove a document from the database, and it returns a
condvar.

=head3 $cv = $db->attach($doc, $attachment, \%options)

This method adds an attachment to a document, and it returns a condvar.  Note
that the C<%options> are NOT optional for this method.  You must provide a
C<src> for the data which should be a path that can be understood by
L<IO::All>.  You must also provide a MIME content C<type> for this data.  If
none is provided, it'll default to C<text/plain>.

B<Example>:

  $db->attach($doc, "issue.net", {
    src  => '/etc/issue.net',
    type => 'text/plain'
  })->recv;

=head3 $cv = $db->detach($doc, $attachment, [ \%options ])

This method removes an attachment from a document, and it returns a condvar.

B<Example>:

  $db->detach($doc, "issue.net")->recv;

=head3 $cv = $db->open_attachment($doc, $attachment)

This method retrieves an attachment and returns the contents as a condvar.

B<Example>:

  my($body, $headers) = $db->open_attachment($doc, "issue.net")->recv;
  my $content_type    = $headers->{'content-type'};

=head3 $cv = $db->bulk_docs(\@docs, [ \%options ])

This method requests that many create, update, and delete operations be
performed in one shot.  You pass it an arrayref of documents, and it'll
return a condvar.

=head2 Database Queries

=head3 $cv = $db->view($name, [ \%options ])

This method lets you query views that have been predefined in CouchDB design
documents.  You give it a name which is of the form "$design_doc/$view", and
you may pass in C<\%options> as well to manipulate the result-set.

This method returns a condvar.

=head3 $cv = $db->all_docs([ \%options ])

This method is used to request a hashref that contains an index of all the
documents in the database.  Note that you B<DO NOT> get the actual documents.
Instead, you get their C<id>s, so that you can fetch them later.
To get the documents in the result, set parameter C<include_docs> to 1 in
the C<\%options>.

=head3 $cv = $db->all_docs_by_seq([ \%options ])

This method is similar to the C<all_docs> method, but instead of using document ids
as a key, it uses update sequence of the document instead.  (The update_seq is an
integer that is incremented every time the database is updated.  You can get the
current update_seq of a database by calling C<info>.)

This method returns a condvar.

=head3 $cv = $db->query($map, [ $reduce ], [ $language ], [ \%options ])

This method lets you send ad-hoc queries to CouchDB.  You have to at least give
it a map function.  If you pass in a string, it'll assume the function is
written in JavaScript (unless you tell it otherwise).  If you pass in a
coderef, it will be turned into a string, and you had better have a Perl-based
view server (like L<CouchDB::View>) installed.  The same goes for the optional
reduce function.  The 3rd parameter lets you explicitly tell this method what
language the map and reduce functions are written in.  The final parameter,
C<\%options>, can be used to manipulate the result-set in standard ways.

This method returns a condvar.

=head2 Generic HTTP Methods

=head3 $cv = $db->head($path, [ \%options ])

=head3 $cv = $db->get($path, [ \%options ])

=head3 $cv = $db->post($path, [ \%options ])

=head3 $cv = $db->put($path, [ \%options ])

=head3 $cv = $db->delete($path, [ \%options ])

=head1 AUTHOR

John BEPPU E<lt>beppu@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (c) 2008-2011 John BEPPU E<lt>beppu@cpan.orgE<gt>.

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
