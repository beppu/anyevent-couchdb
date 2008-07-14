package AnyEvent::CouchDB;

use strict;
use warnings;
our $VERSION = '0.99';

use JSON::XS;
use AnyEvent::HTTP;
use AnyEvent::CouchDB::Database;
use URI::Escape;

# TODO - add error handling
# TODO - let user configure success and error if they so desire
my $cvcb = sub {
  my ($options, $status) = @_;
  $status ||= 200;
  my $cv = AnyEvent->condvar;
  my $cb = sub { $cv->send(decode_json($_[0])) };
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

  use AnyEvent::CouchDB;
  use Data::Dump 'pp';

  my $couch = AnyEvent::CouchDB->new('http://localhost:5984/');
  print pp( $couch->all_dbs->recv ), "\n";
  print pp( $couch->info->recv    ), "\n";

  my $db = $couch->db('database');

=head1 DESCRIPTION

AnyEvent::CouchDB is a non-blocking CouchDB client based on jquery.couch.js.

=head1 API

=head2 Object Construction

=head3 $couch = AnyEvent::CouchDB->new([ $url ])

=head3 $db = $couch->db($name)

=head2 Queries and Actions

=head3 $cv = $couch->all_dbs([ \%options ])

=head3 $cv = $couch->info([ \%options ])

=head3 $cv = $couch->replicate($source, $target, [ \%options ])


=head1 SEE ALSO

=head2 Related Modules

L<AnyEvent::CouchDB::Database>, L<AnyEvent::HTTP>, L<AnyEvent>

=head2 Other CouchDB-related Perl Modules

=head3 Client Libraries

L<Net::CouchDb>

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
