use strict;
use warnings FATAL => 'all';
use 5.018;

use Test::More;
use Test::Deep;
use Path::Tiny;
use JSON qw< decode_json >;
use FindBin '$RealBin';
use HTTP::Request::Common;

use_ok('Bio::WebService::LANL::SequenceLocator');
use_ok('Bio::WebService::LANL::SequenceLocator::Server');

my @tests = (
    {   name        => "mixed bases",
        sequences   => ['SLYNTVAVLYYVHQR', 'TCATTATATAATACAGTAGCAACCCTCTATTGTGTGCATCAAAGG'],
        json        => path("$RealBin/data/mixed-bases.json"),
    },
    {   name        => "amino acids",
        sequences   => ['MGGDMKDNW'],
        args        => { base => 'aa' },
        json        => path("$RealBin/data/amino-acids.json"),
    },
    {   name        => "nucleotides",
        sequences   => ['agcaatcagatggtcagccaaaattgccctatagtgcagaacatccaggggcaagtggtacatcaggccatatcacctagaactttaaatgca'],
        args        => { base => 'nuc' },
        json        => path("$RealBin/data/nucleotides.json"),
    },
);

for my $test (@tests) {
    my $expected = decode_json($test->{json}->slurp);
    cmp_deeply from_native($test), $expected, "native: " . $test->{name} || "";
    cmp_deeply from_web($test),    $expected, "web:    " . $test->{name} || "";
}

sub from_native {
    my $test = shift;
    state $locator = Bio::WebService::LANL::SequenceLocator->new(
        agent_string => 'automated testing'
    );
    return scalar $locator->find($test->{sequences}, %{$test->{args} || {}});
}

sub from_web {
    my $test = shift;
    state $app = Bio::WebService::LANL::SequenceLocator::Server->new(
        contact => 'automated testing'
    );
    my $response = $app->run_test_request(
        POST '/within/hiv' => [
            sequence => $test->{sequences},
            %{$test->{args} || {}},
        ],
    );
    note "Request failed: POST /within/hiv -> ", $response->status_line, "\n"
        unless $response and $response->is_success;
    return decode_json($response->decoded_content);
}

done_testing;
