use ExtUtils::MakeMaker;

WriteMakefile (
  NAME          => 'AnyEvent::CouchDB',
  AUTHOR        => 'John BEPPU <beppu@cpan.org>',
  LICENSE       => 'mit',
  VERSION_FROM  => 'lib/AnyEvent/CouchDB.pm',
  ABSTRACT_FROM => 'lib/AnyEvent/CouchDB.pm',
  EXE_FILES     => [ ],
  PREREQ_PM     => {
    'AnyEvent::HTTP' => 1.03,
    'CouchDB::View'  => 0,
    'JSON::XS'       => 0,
  },
  depend => { distmeta => 'metamunge' }
);

sub MY::libscan {
  my $self = shift;
  $_       = shift;
  # $self appears to be a blessed hashref that contains
  # all the attributes/value pairs passed to WriteMakeFile()
  # plus some other MakeMaker-related info.
  return 0 if /\.sw.$/ || /~$/;
  return $_;
}

sub MY::postamble {q{
metamunge :
	$(NOECHO) $(ECHO) 'no_index:'        >> $(DISTVNAME)/META.yml
	$(NOECHO) $(ECHO) '    directory:'   >> $(DISTVNAME)/META.yml
	$(NOECHO) $(ECHO) '        - eg'     >> $(DISTVNAME)/META.yml
	$(NOECHO) $(ECHO) '        - t'      >> $(DISTVNAME)/META.yml
}}
