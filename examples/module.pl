use strict;
use warnings;
use Bio::WebService::LANL::SequenceLocator;

my $locator = Bio::WebService::LANL::SequenceLocator->new(
    agent_string => 'Your Organization - you@example.com',
);

my @sequences = $locator->find([
    "agcaatcagatggtcagccaaaattgccctatagtgcagaacatcc"
   ."aggggcaagtggtacatcaggccatatcacctagaactttaaatgca",
]);
