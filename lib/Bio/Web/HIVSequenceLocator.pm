#!/usr/bin/env perl
use strict;
use warnings;

package Bio::Web::HIVSequenceLocator;
use Web::Simple;

use FindBin;
use HTTP::Request::Common;
use JSON qw< encode_json >;
use List::AllUtils qw< pairwise >;
use Plack::App::File;
use URI;

our $VERSION = 20140306;

has contact => (
    is      => 'ro',
    default => sub { 'mullspt+cfar@uw.edu' },
);

has agent => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
        require LWP::UserAgent;
        my $self  = shift;
        my $agent = LWP::UserAgent->new(
            agent => join(" ", __PACKAGE__ . "/$VERSION", $self->contact),
        );
        $agent->env_proxy;
        return $agent;
    },
);

has about_page => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { "$FindBin::Bin/about.html" },
);

has lanl_base => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { 'http://www.hiv.lanl.gov' },
);

has lanl_endpoint => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { shift->lanl_base . '/cgi-bin/LOCATE/locate.cgi' },
);

sub dispatch_request {
    sub (POST + /within/hiv + %@sequence~) {
        my ($self, $sequences) = @_;

        return error(422 => 'At least one value for "sequence" is needed.')
            unless $sequences and @$sequences;

        my $results = $self->lanl_locate($sequences)
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
    sub (GET + /) {
        Plack::App::File->new(file => $_[0]->about_page);
    },
}

sub request {
    my $self = shift;
    my $req  = shift;
    my $response = $self->agent->request($req);

    if (not $response->is_success) {
        warn sprintf "Request failed: %s %s -> %s\n",
            $req->method, $req->uri, $response->status_line;
        return;
    }

    return $response->decoded_content;
}

sub lanl_locate {
    my ($self, $sequences) = @_;

    my $content = $self->lanl_submit($sequences)
        or return;

    return $self->lanl_parse($content);
}

sub lanl_submit {
    my ($self, $sequences) = @_;

    # Submit multiple sequences at once using FASTA
    my $fasta = join "\n", map {
        ("> sequence_$_", $sequences->[$_ - 1])
    } 1 .. @$sequences;

    # LANL only presents the parseable table.txt we want if there's more
    # than a single sequence...
    $fasta .= "\n> BOGUS_FAKE_HACK\n"
        if @$sequences == 1;

    return $self->request(
        POST $self->lanl_endpoint,
        Content_Type => 'form-data',
        Content      => [
            organism            => 'HIV',
            DoReverseComplement => 1,
            SEQ                 => $fasta,
        ],
    );
}

sub lanl_parse {
    my ($self, $content) = @_;
    my @results;

    # For now, just return the two tables which are easily parseable.
    for my $pattern (qr{"(.+/table\.txt)"}, qr{"(.+/simple_results\.txt)"}) {
        unless ($content =~ $pattern) {
            warn "Couldn't find $pattern in LANL's HTML: $content\n";
            next;
        }

        my $table_url = URI->new_abs($1, $self->lanl_base)->as_string;
        my $table = $self->request(GET $table_url)
            or next;

        my (@these_results, %seen);
        my @lines  = split "\n", $table;
        my @fields = map {
            s/^SeqName$/query/;         # standard key
            s/(?<=[a-z])(?=[A-Z])/_/g;  # undo CamelCase
            y/A-Z/a-z/;                 # normalize to lowercase
            # Account for the same field twice in the same data table
            if ($seen{$_}++) {
                $_ = /^(start|end)$/
                    ? "protein_$_"
                    : join "_", $_, $seen{$_};
            }
            $_;
        } split "\t", shift @lines;

        for (@lines) {
            my @values = split "\t";
            my %data;
            @data{@fields} = @values;

            next if $data{query} eq 'BOGUS_FAKE_HACK';

            push @these_results, \%data;
        }

        # Merge with existing results, if any
        @results = @results
                 ? pairwise { +{ %$a, %$b } } @results, @these_results
                 : @these_results;
    }

    return unless @results;
    return \@results;
}

sub error {
    return [
        shift,
        [ 'Content-type' => 'text/plain' ],
        [ join " ", @_ ]
    ];
}

__PACKAGE__->run_if_script;
