use ExtUtils::MakeMaker;

print <<EOM ;

    ,----------------------------------.
    | CouchDB version 0.9.0+ required! |
    `--. ,-----------------------------'
       |/
       `
      -b

EOM

WriteMakefile (
  NAME          => 'AnyEvent::CouchDB',
  AUTHOR        => 'John BEPPU <beppu@cpan.org>',
  LICENSE       => 'mit',
  VERSION_FROM  => 'lib/AnyEvent/CouchDB.pm',
  ABSTRACT_FROM => 'lib/AnyEvent/CouchDB.pm',
  EXE_FILES     => [ 'bin/couchdb-push' ],
  META_MERGE    => {
    no_index    => { directory => [ qw(eg) ] },
  },
  PREREQ_PM     => {
    'AnyEvent::HTTP'       => 1.11,
    'CouchDB::View'        => 0,
    'JSON::XS'             => 0,
    'Data::Dump::Streamer' => 0,
    'IO::All'              => 0,
    'Scope::Guard'         => 0,
  },
);

