#!/usr/bin/env perl
use strict;
use warnings;

package HIVSequenceLocator;
use Web::Simple;

use FindBin;
use JSON qw< encode_json >;
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
    sub (POST + /locate/hiv + %@sequence=) {
        my ($self, $sequences) = @_;

#        # Submit a single sequence param as-is (assuming either a bare sequence
#        # or user-submitted fasta).  Join multiple sequence params into fasta
#        # automatically for a simpler API.
#        my $seq = @$sequences == 1
#                ? $sequences->[0]
#                : join("\n", map { ("> sequence_$_", $sequences->[$_ - 1]) } 1 .. @$sequences);
        
        my $seq = join "\n", map {
            ("> sequence_$_", $sequences->[$_ - 1])
        } 1 .. @$sequences;

        # LANL only presents the parseable table.txt we want if there's more
        # than a single sequence...
        $seq .= "\n> BOGUS_FAKE_HACK\n"
            if @$sequences == 1;

        my $content = $self->lanl_request($seq)
            or return error(503 => 'Backend request to LANL failed');

        my $results = $self->lanl_parse_html($content)
            or return error(500 => "Couldn't parse HTML returned by LANL, sorry!  Contact @{[ $self->contact ]}.");

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

sub lanl_request {
    my ($self, $input) = @_;
    my $response = $self->agent->post(
        $self->lanl_endpoint,
        Content_Type => 'form-data',
        Content      => [
            organism            => 'HIV',
            DoReverseComplement => 1,
            SEQ                 => $input,
        ],
    );

    if (not $response->is_success) {
        warn "Request failed: POST ", $self->lanl_endpoint, " -> ", $response->status_line, "\n";
        return;
    }

    return $response->decoded_content;
}

sub lanl_parse_html {
    my ($self, $content) = @_;
    my @results;

    # XXX TODO
    # Eventually parse the HTML returned to pull out for each sequence:
    #   - name (inside <h3>)
    #   - image of hxb2 location
    #   - CDS and full position table
    #   - alignment to hxb2 score
    #   - alignment to hxb2 diagram
    #   - discriminating nucleotide vs. amino acid in LANL HTML is... annoying

    # For now, just return the reduced positions table.
    if ($content =~ m{"(.+/table\.txt)"}) {
        my $table_url = URI->new_abs($1, $self->lanl_base)->as_string;
        my $response  = $self->agent->get($table_url);

        if (not $response->is_success) {
            warn "Request failed: GET $table_url -> ", $response->status_line, "\n";
            return;
        }

        my @fields;
        my @table = split "\n", $response->decoded_content;
        for (@table) {
            my @values = split "\t";
            unless (@fields) {
                @fields = @values;
                next;
            }
            my %data;
            @data{@fields} = @values;

            next if $data{query} eq 'BOGUS_FAKE_HACK';

            push @results, \%data;
        }
    } else {
        warn "Couldn't find table.txt link in LANL's HTML: $content\n";
        return;
    }

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
