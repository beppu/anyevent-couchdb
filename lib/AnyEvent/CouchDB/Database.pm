package AnyEvent::CouchDB::Database;

use strict;
use warnings;
use JSON::XS;
use AnyEvent::HTTP;
use Data::Dump 'pp';
use Data::Dump::Streamer;
use URI::Escape 'uri_escape_utf8';

our $cvcb = sub {
  my ($options, $status) = @_;
  $status ||= 200;
  my $cv = AnyEvent->condvar;

  # default success handler sends back decoded json response
  my $success = $options->{success} || sub {
    my ($resp) = @_;
    $cv->send($resp);
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
    $cv->croak(pp(['decode_error', $@, $body, encode_json($headers)])) if ($@);
    if ($headers->{Status} == $status) {
      $success->($response);
    } else {
      $error->($headers, $response);
    }
  };
  ($cv, $cb);
};

our $query = sub { 
  my $options = shift;
  my @buf;
  if (defined($options) && keys %$options) {
    for my $name (keys %$options) {
      next if ($name eq 'error' || $name eq 'success');
      my $value = $options->{$name};
      if ($name eq 'key' || $name eq 'startkey' || $name eq 'endkey') {
        $value = ref($value) ? encode_json($value) : qq{"$value"};
      }
      push @buf, "$name=".uri_escape_utf8($value);
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

our $json = sub {
  ref($_[0]) ? encode_json($_[0]) : $_[0];
};

sub new {
  my ($class, $name, $uri) = @_;
  bless { name => $name, uri => $uri } => $class;
}

sub name {
  $_[0]->{name};
}

sub uri {
  $_[0]->{uri};
}

sub compact {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options, 202);
  http_request(
    POST    => ($self->uri . "_compact"),
    headers => { 'Content-Type' => 'application/json' },
    $cb
  );
  $cv;
}

sub create {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_request(
    PUT     => $self->uri,
    headers => { 'Content-Type' => 'application/json' },
    $cb
  );
  $cv;
}

sub drop {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_request(
    DELETE  => $self->uri,
    $cb
  );
  $cv;
}

sub info {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get($self->uri, $cb);
  $cv;
}

sub all_docs {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get($self->uri.'_all_docs'.$query->($options), $cb);
  $cv;
}

sub open_doc {
  my ($self, $doc_id, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get($self->uri.uri_escape_utf8($doc_id).$query->($options), $cb);
  $cv;
}

sub save_doc {
  my ($self, $doc, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  my ($method, $uri);
  if (not defined $doc->{_id}) {
    $method = 'POST';
    $uri    = $self->uri;
  } else {
    $method = 'PUT';
    $uri    = $self->uri.uri_escape_utf8($doc->{_id});
  }
  http_request(
    $method => $uri.$query->($options),
    headers => { 'Content-Type' => 'application/json' },
    body    => $json->($doc),
    $cb
  );
  $cv;
}

sub remove_doc {
  my ($self, $doc, $options) = @_;
  die("Document is missing _id!") unless (defined $doc->{_id});
  my ($cv, $cb) = $cvcb->($options);
  http_request(
    DELETE  => $self->uri.uri_escape_utf8($doc->{_id}).$query->({ rev => $doc->{_rev} }),
    $cb
  );
  $cv;
}

sub bulk_docs {
  my ($self, $docs, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_request(
    POST    => $self->uri.'_bulk_docs',
    headers => { 'Content-Type' => 'application/json' },
    body    => $json->($docs),
  );
  $cv;
}

sub query {
  my ($self, $map_fun, $reduce_fun, $language, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  $language ||= (ref($map_fun) eq 'CODE') ? 'text/perl' : 'javascript';
  my $body = {
    language => $language,
    map      => $code_to_string->($map_fun),
  };
  if ($reduce_fun) {
    $body->{reduce} = $code_to_string->($reduce_fun);
  }
  http_request(
    POST    => $self->uri.'_temp_view'.$query->($options),
    headers => { 'Content-Type' => 'application/json' },
    body    => encode_json($body),
    $cb
  );
  $cv;
}

sub view {
  my ($self, $name, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get($self->uri."_view/".$name.$query->($options), $cb);
  $cv;
}

sub search {
  my ($self, $query, $options) = @_;
  warn "NOT IMPLEMENTED YET";
}

1;

__END__

=head1 NAME

AnyEvent::CouchDB::Database - an object representing a CouchDB database

=head1 SYNOPSIS

  use AnyEvent::CouchDB;
  use Data::Dump 'pp';

  my $couch = AnyEvent::CouchDB->new;
  my $db    = $couch->db('database');

  print pp($db->info->recv), "\n";
  my $cv = $db->save_doc({ just => 'give', me => 'a', hashref => { } });
  #
  # do other time-consuming operations
  #
  $cv->recv;  # when recv returns, the couchdb request finished

=head1 DESCRIPTION

Objects of this class represent a single CouchDB database.

=head1 API

=head2 General

=head3 $db = AnyEvent::CouchDB::Database->new($name, $uri)

=head3 $db->name

=head3 $db->uri

=head2 Database Level Operations

=head3 $cv = $db->create

=head3 $cv = $db->drop

=head3 $cv = $db->info

=head3 $cv = $db->compact

=head2 Document Level Operations

=head3 $cv = $db->open_doc($id)

=head3 $cv = $db->save_doc($doc)

=head3 $cv = $db->remove_doc($id)

=head3 $cv = $db->bulk_docs(\@docs)

=head2 Database Queries

=head3 $cv = $db->query($map, $reduce, $options)

Ad-hoc query - give it an arbitrary map and reduce function

=head3 $cv = $db->view($view, $options)

View query - use map/reduce functions that have been defined in design
documents

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
