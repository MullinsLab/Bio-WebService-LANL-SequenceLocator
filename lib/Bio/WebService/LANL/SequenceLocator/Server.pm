#!/usr/bin/env perl
use strictures 1;
use utf8;
use 5.018;

package Bio::WebService::LANL::SequenceLocator::Server;
use Web::Simple;

use Bio::WebService::LANL::SequenceLocator;
use FindBin;
use JSON qw< encode_json >;
use Plack::App::File;
use namespace::autoclean;

has contact => (
    is      => 'ro',
    default => sub { $ENV{SERVER_ADMIN} || '[no address provided]' },
);

has locator => (
    is      => 'ro',
    isa     => sub {
        die "Attribute 'locator' is not a Bio::WebService::LANL::SequenceLocator"
            unless $_[0]->isa("Bio::WebService::LANL::SequenceLocator");
    },
    lazy    => 1,
    builder => sub { Bio::WebService::LANL::SequenceLocator->new( agent_string => $_[0]->contact ) },
);

has about_page => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { "$FindBin::Bin/about.html" },
);

sub dispatch_request {
    sub (POST + /within/hiv + %@sequence~) {
        my ($self, $sequences) = @_;

        return error(422 => 'At least one value for "sequence" is needed.')
            unless $sequences and @$sequences;

        my $results = $self->locator->lanl_locate($sequences)
            or return error(503 => "Backend request to LANL failed, sorry!  Contact @{[ $self->contact ]} if the problem persists.");

        my $json = eval { encode_json($results) };
        if ($@ or not $json) {
            warn $@ ? "Error encoding JSON response: $@\n"
                    : "Failed to encode JSON response, but no error?!\n";
            return error(500 => "Error encoding results to JSON.  Contact @{[ $self->contact ]}");
        }

        return [
            200,
            [ 'Content-type' => 'application/json' ],
            [ $json, "\n" ],
        ];
    },
    sub (GET + /within/hiv) {
        error( 405 => "You must make location requests using POST." )
    },
    sub (GET + /) {
        state $about = Plack::App::File->new(file => $_[0]->about_page);
        $about;
    },
}

sub error {
    return [
        shift,
        [ 'Content-type' => 'text/plain' ],
        [ join " ", @_ ]
    ];
}

__PACKAGE__->run_if_script;
