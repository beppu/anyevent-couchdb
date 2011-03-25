package AnyEvent::CouchDB::Exceptions;

use Exception::Class (
  'AnyEvent::CouchDB::Exception' => {
    fields => [ 'headers', 'body' ],
  },
  'AnyEvent::CouchDB::Exception::JSONError' => {
    isa => 'AnyEvent::CouchDB::Exception'
  },
  'AnyEvent::CouchDB::Exception::BadRequest' => {
    isa => 'AnyEvent::CouchDB::Exception'
  },
);

AnyEvent::CouchDB::Exception->Trace($ENV{ANYEVENT_COUCHDB_DEBUG});

1;
