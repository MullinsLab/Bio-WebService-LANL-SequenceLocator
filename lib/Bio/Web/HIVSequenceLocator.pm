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

# Gathered from:
#   http://www.hiv.lanl.gov/tmp/locate/26284.1.png
#   http://www.hiv.lanl.gov/content/sequence/HIV/MAP/landmark.html
#   http://www.hiv.lanl.gov/content/sequence/HIV/MAP/hxb2.xls
#   and an existing data structure in Viroverse
has hxb2_regions => (
    is      => 'ro',
    isa     => sub { die "hxb2_regions must be a HASHREF" unless ref $_[0] eq 'HASH' },
    default => sub {
      + {
            'LTR5'        => [    1,  634 ],
            'GAG'         => [  790, 2292 ],
            'GAG-P17'     => [  790, 1186 ],
            'GAG-P24'     => [ 1186, 1879 ],
            'GAG-P2'      => [ 1879, 1921 ],
            'GAG-P7'      => [ 1921, 2086 ],
            'GAG-P1'      => [ 2086, 2134 ],
            'GAG-P6'      => [ 2134, 2292 ],
            'POL'         => [ 2085, 5906 ],
            'POL-PROT'    => [ 2253, 2550 ],
            'POL-RT'      => [ 2250, 3870 ],
            'POL-RNASE'   => [ 3870, 4320 ],
            'POL-INT'     => [ 4230, 5096 ],
            'VIF'         => [ 5041, 5619 ],
            'VPR'         => [ 5559, 5850 ],
            'TAT-TAT1'    => [ 5831, 6045 ],
            'REV-REV1'    => [ 5970, 6045 ],
            'VPU'         => [ 6062, 6310 ],
            'GP160'       => [ 6225, 8797 ],  # aka ENV
            'GP160-GP120' => [ 6225, 7758 ],
            'GP160-GP41'  => [ 7558, 8797 ],
            'TAT-TAT2'    => [ 8379, 8469 ],
            'REV-REV2'    => [ 8379, 8653 ],
            'NEF'         => [ 8797, 9417 ],
            'LTR3'        => [ 9086, 9719 ],
        };
    },
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

    # Fetch and parse the two tables provided as links which removes the need
    # to parse all of the HTML.
    my $results = $self->lanl_parse_tsv($content);

    # Add missing fields here that we can calculate to normalize the results a
    # little.  It's too bad LANL's results don't include these in the data
    # files, only the HTML.
    for my $r (@$results) {
        # Skip anything that doesn't look like an amino-acid sequence result
        next unless $r->{query_sequence} =~ /[^ATCGU]/i;
        next if $r->{genome_start} or $r->{genome_end};

        # Expand amino acid position to nucleotide position
        $r->{na_start} = $r->{start} * 3 - 2;
        $r->{na_end}   = $r->{end}   * 3;

        # Calculate genome position based on start of polyprotein
        if ($r->{polyprotein} and $r->{protein}) {
            my $region = join "-", map { uc } $r->{polyprotein}, $r->{protein};
            if ( my $pos = $self->hxb2_regions->{$region} ) {
                # Relative position 1 is == region start, so subtract 1 to make
                # relative pos. zero-based.
                $r->{"genome_$_"} = $pos->[0] + $r->{"na_$_"} - 1
                    for qw(start end);
            } elsif ($r->{polyprotein}) {
                warn "BUG: Missing HXB2 coordinates for $region",
                     " (query sequence <$r->{query_sequence}>)";
            }
        }
    }


    return unless @$results;
    return $results;
}

sub lanl_parse_tsv {
    my ($self, $content) = @_;
    my @results;

    # XXX TODO: replace this with HTML::LinkExtor
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
            s/ +/_/g;                   # no spaces
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

    return \@results;
}


            }
        }
    }

}

sub error {
    return [
        shift,
        [ 'Content-type' => 'text/plain' ],
        [ join " ", @_ ]
    ];
}

__PACKAGE__->run_if_script;
