
use strict;
use warnings;

use 5.018;

use ExtUtils::MakeMaker 6.30;

use File::ShareDir::Install;
install_share dist => "share";


my %WriteMakefileArgs = (
  "ABSTRACT" => "Locate sequences within HIV using LANL's web tool",
  "AUTHOR" => "Thomas Sibley <trsibley\@uw.edu>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30",
    "File::ShareDir::Install" => "0.03"
  },
  "DISTNAME" => "Bio-WebService-LANL-SequenceLocator",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Bio::WebService::LANL::SequenceLocator",
  "PREREQ_PM" => {
    "HTML::LinkExtor" => 0,
    "HTML::TableExtract" => 0,
    "HTTP::Request::Common" => 0,
    "LWP::UserAgent" => 0,
    "List::AllUtils" => 0,
    "Moo" => 0,
    "strictures" => 0
  },
  "TEST_REQUIRES" => {
    "Test::More" => "0.88"
  },
  "VERSION" => 20140306,
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "HTML::LinkExtor" => 0,
  "HTML::TableExtract" => 0,
  "HTTP::Request::Common" => 0,
  "LWP::UserAgent" => 0,
  "List::AllUtils" => 0,
  "Moo" => 0,
  "Test::More" => "0.88",
  "strictures" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);

{
package
MY;
use File::ShareDir::Install qw(postamble);
}


