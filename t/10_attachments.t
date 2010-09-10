use Test::More;

use strict;
use warnings;
use Scope::Guard;
use AnyEvent::CouchDB;
use IO::All;

BEGIN {
    plan skip_all => 'Please set COUCHDB_TEST_URI to a CouchDB instance URI'
        unless $ENV{COUCHDB_TEST_URI};
    plan 'no_plan';
}

my $couch = couch($ENV{COUCHDB_TEST_URI});
my $name = $ENV{COUCHDB_TEST_DB_NAME} || "couch-$$";
my $db = $couch->db($name);
eval { $db->drop->recv };
my $sg = Scope::Guard->new(
    $ENV{COUCHDB_KEEP_DB} ? 
        sub { diag "Database kept. Name: ", $db->name }
    :   sub { $db->drop->recv }
);
$db->create->recv;

{
    my $doc = { _id => 'my_doc' };
    ok($db->save_doc($doc)->recv, 'Create test doc.');
    ok($db->attach($doc, 'testscript.pl', { src => $0, type => 'text/html' })->recv, 'Attach this script to doc.');
    my $attachment;
    eval {
        $attachment = $db->open_attachment($doc, 'testscript.pl')->recv;
    };
    ok((not $@), 'Get attachment contents.');
    diag $@ if $@;
    ok($attachment, 'Got attachment.');
    is($attachment, io($0)->slurp, 'Attachment unaltered upon retrieval.');
}

