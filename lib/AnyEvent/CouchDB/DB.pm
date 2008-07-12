package AnyEvent::CouchDB::DB;

use strict;
use warnings;
use JSON::XS;
use AnyEvent::HTTP;
use Data::Dump::Streamer;
use URI::Escape;

# TODO - add error handling similar to what's in jquery.couch.js
# TODO - (but make it appropriate to perl)
our $cvcb = sub {
  my $cv = AnyEvent->condvar;
  my $cb = sub {
    my $data;
    eval {
      $data = decode_json($_[0]);
    };
    if ($@) {
      $cv->croak($@, $_[0], encode_json($_[1]));
    } else {
      $cv->send($data);
    }
  };
  ($cv, $cb);
};

# TODO - encode cgi params that couchdb expects
our $query = sub { "?" };

our $code_to_string = sub {
  ref($_[0])
    ? sprintf 'do { my $CODE1; %s; $CODE1 }',
      Data::Dump::Streamer->new->Data($_[0])->Out;
    : $_[0]
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
  my ($cv, $cb) = $cvcb->($options);
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
  http_get($self->uri."_all_docs".$query->($options), $cb);
  $cv;
}

sub open_doc {
  my ($self, $doc_id, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get($self->uri.uri_escape($doc_id).$query->($options), $cb);
  $cv;
}

sub save_doc {
  my ($self, $doc, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  my ($method, $uri);
  if (defined $doc->{_id}) {
    $method = 'POST';
    $uri    = $self->uri;
  } else {
    $method = 'PUT';
    $uri    = $self->uri.uri_escape($doc->{_id});
  }
  http_request(
    $method => $uri.$query->($options),
    headers => { 'Content-Type' => 'application/json' },
    $cb
  );
  $cv;
}

sub remove_doc {
  my ($self, $doc, $options) = @_;
  die("Document is missing _id!") unless (defined $doc->{_id});
  my ($cv, $cb) = $cvcb->($options);
  http_request(
    DELETE  => $self->uri.uri_escape($doc->{_id}).$query->({ rev => $doc->{_rev} }),
    $cb
  );
  $cv;
}

sub query {
  my ($self, $map_fun, $reduce_fun, $language, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  $language ||= (ref($map_fun)) ? 'text/perl' : 'javascript';
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

1;
