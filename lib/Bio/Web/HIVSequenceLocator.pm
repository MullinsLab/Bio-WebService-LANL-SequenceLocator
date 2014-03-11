#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use 5.018;

package Bio::Web::HIVSequenceLocator;
use Web::Simple;

use FindBin;
use HTML::LinkExtor;
use HTML::TableExtract;
use HTTP::Request::Common;
use JSON qw< encode_json >;
use List::AllUtils qw< pairwise part min max >;
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

has _bogus_slug => (
    is      => 'ro',
    default => sub { 'BOGUS_SEQ_SO_TABULAR_FILES_ARE_LINKED_IN_OUTPUT' },
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
    $fasta .= "\n> " . $self->_bogus_slug . "\n"
        if @$sequences == 1;

    return $self->request(
        POST $self->lanl_endpoint,
        Content_Type => 'form-data',
        Content      => [
            organism            => 'HIV',
            DoReverseComplement => 0,
            SEQ                 => $fasta,
        ],
    );
}

sub lanl_parse {
    my ($self, $content) = @_;

    # Fetch and parse the two tables provided as links which removes the need
    # to parse all of the HTML.
    my @results = $self->lanl_parse_tsv($content);

    # Now parse the table data from the HTML
    my @tables = $self->lanl_parse_tables($content);

    return unless @results and @tables;

    @results = pairwise {
        my $new = {
            %$a,
            base_type       => $b->{base_type},
            regions         => $b->{rows},
            region_names    => [ map { $_->{cds} } @{$b->{rows}} ],
        };
        delete $new->{$_} for qw(protein protein_start protein_end);
        $new;
    } @results, @tables;

    # Fill in genome start/end for amino acid sequences
    for my $r (@results) {
        next unless $r->{base_type} eq 'amino acid';

        if ($r->{genome_start} or $r->{genome_end}) {
            warn "Amino acid sequence with genome start/end already?!",
                 " query <$r->{query_sequence}>";
            next;
        }

        $r->{genome_start} = min map { $_->{na_from_hxb2_start}[0] } @{$r->{regions}};
        $r->{genome_end}   = max map { $_->{na_from_hxb2_start}[1] } @{$r->{regions}};

        my $genome_length = $r->{genome_end} - $r->{genome_start} + 1;
        if ((length($r->{query_sequence}) * 3) != $genome_length) {
            warn "Detected bad genome start/end ($r->{genome_end} - $r->{genome_start} = $genome_length)",
                 " for query <$r->{query_sequence}>?  Query length (in NA) is ",
                 length($r->{query_sequence}) * 3;
        }
    }

    return \@results;
}

sub lanl_parse_tsv {
    my ($self, $content) = @_;
    my @results;
    my %urls;

    my $extract = HTML::LinkExtor->new(
        sub {
            my ($tag, %attr) = @_;
            return unless $tag eq 'a' and $attr{href};
            return unless $attr{href} =~ m{/(table|simple_results)\.txt$};
            $urls{$1} = $attr{href};
        },
        $self->lanl_base,
    );
    $extract->parse($content);

    for my $table_name (qw(table simple_results)) {
        next unless $urls{$table_name};
        my $table = $self->request(GET $urls{$table_name})
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

            next if $data{query} eq $self->_bogus_slug;

            push @these_results, \%data;
        }

        # Merge with existing results, if any
        @results = @results
                 ? pairwise { +{ %$a, %$b } } @results, @these_results
                 : @these_results;
    }

    return @results;
}

sub lanl_parse_tables {
    my ($self, $content) = @_;
    my @tables;

    my %columns_for = (
        'amino acid'    => [
            "CDS"                                               => "cds",
            "AA position relative to protein start in HXB2"     => "aa_from_protein_start",
            "AA position relative to query sequence start"      => "aa_from_query_start",
            "AA position relative to polyprotein start in HXB2" => "aa_from_polyprotein_start",
            "NA position relative to CDS start in HXB2"         => "aa_from_cds_start",
            "NA position relative to HXB2 genome start"         => "na_from_hxb2_start",
        ],
        'nucleotide'    => [
            "CDS"                                                   => "cds",
            "Nucleotide position relative to CDS start in HXB2"     => "na_from_cds_start",
            "Nucleotide position relative to query sequence start"  => "na_from_query_start",
            "Nucleotide position relative to HXB2 genome start"     => "na_from_hxb2_start",
            "Amino Acid position relative to protein start in HXB2" => "aa_from_protein_start",
        ],
    );

    for my $base_type (sort keys %columns_for) {
        my ($their_cols, $our_cols) = part {
            state $i = 0;
            $i++ % 2
        } @{ $columns_for{$base_type} };

        my $extract = HTML::TableExtract->new( headers => $their_cols );
        $extract->parse($content);

        # Examine all matching tables
        for my $table ($extract->tables) {
            my %table = (
                coords      => [$table->coords],
                base_type   => $base_type,
                columns     => $our_cols,
                rows        => [],
            );
            for my $row ($table->rows) {
                @$row = map { defined $_ ? s/^\s+|\s*$//gr : $_ } @$row;

                # An empty row with only a sequence string in the first column.
                if (    $row->[0]
                    and $row->[0] =~ /^[A-Za-z]+$/
                    and not grep { defined and length } @$row[1 .. scalar @$row - 1])
                {
                    $table{rows}->[-1]{protein_translation} = $row->[0];
                    next;
                }

                # Not all rows are data, some are informational sentences.
                next if grep { not defined } @$row;

                my %row;
                @row{@$our_cols} =
                    map { ($_ and $_ eq "NA")       ? undef     : $_ }
                    map { ($_ and /(\d+) → (\d+)/)  ? [$1, $2]  : $_ }
                        @$row;

                push @{$table{rows}}, \%row;
            }
            push @tables, \%table
                if @{$table{rows}};
        }
    }

    # Sort by depth, then within each depth by count
    @tables = sort {
        $a->{coords}[0] <=> $b->{coords}[0]
     or $a->{coords}[1] <=> $b->{coords}[1]
    } @tables;

    return @tables;
}

sub error {
    return [
        shift,
        [ 'Content-type' => 'text/plain' ],
        [ join " ", @_ ]
    ];
}

__PACKAGE__->run_if_script;
