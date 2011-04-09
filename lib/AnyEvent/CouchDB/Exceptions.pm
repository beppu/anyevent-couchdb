package AnyEvent::CouchDB::Exceptions;

use Exception::Class (
  'AnyEvent::CouchDB::Exception' => {
    fields => [ 'headers', 'response' ],
  },
  'AnyEvent::CouchDB::Exception::JSONError' => {
    isa         => 'AnyEvent::CouchDB::Exception',
    description => 'JSON decoding error',
  },
  'AnyEvent::CouchDB::Exception::HTTPError' => {
    isa         => 'AnyEvent::CouchDB::Exception'
    description => 'HTTP error',
  },
);

AnyEvent::CouchDB::Exception->Trace($ENV{ANYEVENT_COUCHDB_DEBUG});

1;

__END__

=head1 NAME

AnyEvent::CouchDB::Exceptions - Exception::Class-based exceptions for AnyEvent::CouchDB

=head1 SYNOPSIS

  use Try::Tiny;
  use Data::Dump 'pp';
  use AnyEvent::CouchDB;

  my $db = couchdb("food");
  try {
    my $vegetables = $db->open('vegetables')->recv;
  } 
  catch {
    when (ref eq 'AnyEvent::CouchDB::Exception::HTTPError') {
      # handle an HTTP error
    }
    when (ref eq 'AnyEvent::CouchDB::Exception::JSONError') {
      # handle a JSON decoding error
    }
    default {
      $_->show_trace(1);
      warn "$_";
      warn "HEADERS  : " . pp($_->headers);
      warn "RESPONSE : " . $_->response;
    }
  };

=head1 DESCRIPTION

This module defines a family of exception classes.

=over 4

=item AnyEvent::CouchDB::Exception

The base exception class who's superclass is L<Exception::Class::Base>

=item AnyEvent::CouchDB::Exception::HTTPError

A subclass of AnyEvent::CouchDB::Exception for HTTP errors

=item AnyEvent::CouchDB::Exception::JSONError

A subclass of AnyEvent::CouchDB::Exception for JSON decoding errors

=back


=head1 API

=head2 Provided by AnyEvent::CouchDB::Exception

This module provides the following methods in addition to the methods provided
by L<Exception::Class::Base>.

=head3 $e->headers

This method will return the HTTP response headers if they were available at
the time the exception was thrown.

=head3 $e->response

This method will return the HTTP response body if it was available at
the time the exception was thrown.

=cut
