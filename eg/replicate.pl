use strict;
use warnings;

use 5.012;

use AnyEvent::CouchDB;
use AnyEvent::CouchDB::Stream;

my ( $host_orig, $db_orig, $host_dest, $db_dest ) = @ARGV;

my $cv = my $done = AE::cv;

my $couch_orig   = couch($host_orig);
my $couchdb_orig = $couch_orig->db($db_orig);

my $couch_dest   = couch($host_dest);
my $couchdb_dest = $couch_dest->db($db_dest);

my $l = AnyEvent::CouchDB::Stream->new(
    url       => $host_orig,
    database  => $db_orig,
    on_change => sub {
        my $change = shift;
        say "document "
            . $change->{id}
            . " with sequence "
            . $change->{seq}
            . " have been updated";
        $couchdb_orig->open_doc( $change->{id} )->cb(
            sub {
                my $data = $_[0]->recv;
                $couchdb_dest->save_doc($data);
            }
        );
    },
);

$cv->recv;
