#!/usr/bin/env perl
use strictures 1;
use utf8;
use 5.018;

=head1 NAME

Bio::WebService::LANL::SequenceLocator::Server - A JSON web API for LANL's HIV sequence locator

=head1 SYNOPSIS

After installation:

    plackup `perldoc -l Bio::WebService::LANL::SequenceLocator::Server`

Or from a git checkout or tarball:

    plackup     # uses app.psgi

Or as a L<Server::Starter> managed service:

    examples/service start

=head1 DESCRIPTION

This server powers
L<a simple, JSON-based web API|http://indra.mullins.microbiol.washington.edu/locate-sequence/>
for the L<LANL's HIV sequence locator|http://www.hiv.lanl.gov/content/sequence/LOCATE/locate.html>
using L<Bio::WebService::LANL::SequenceLocator>.

=head1 ENVIRONMENT

=head2 SERVER_ADMIN

Set the SERVER_ADMIN environment variable before starting the server to provide
a contact address in requests to LANL and server error messages in API
responses.

=head1 INSTALLATION

The prerequisites for this server are optional and are probably not installed
by default on your computer when you install this distribution.  From a git
checkout or tarball, you can install the necessary modules with
L<cpanm|App::cpanminus>:

    cpanm --with-all-features --installdeps .

=cut

package Bio::WebService::LANL::SequenceLocator::Server;
use Web::Simple;

use Bio::WebService::LANL::SequenceLocator;
use File::Share qw< dist_file >;
use JSON qw< encode_json >;
use Plack::App::File;
use Path::Tiny;

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
    builder => sub {
        Bio::WebService::LANL::SequenceLocator->new(
            agent_string => join " ", "via", __PACKAGE__, $_[0]->contact
        )
    },
);

has about_page => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { dist_file('Bio-WebService-LANL-SequenceLocator', 'about.html') },
);

sub dispatch_request {
    sub (POST + /within/hiv) {
        sub (%fasta= + %base~) {
            my ($self, $fasta, $base) = @_;
            return $self->locate_sequences_from_fasta($fasta, $base);
        },
        sub (*fasta= + %base~) {
            my ($self, $fasta, $base) = @_;
            return error(422 => $fasta->reason)
                unless $fasta->is_upload;
            return $self->locate_sequences_from_fasta(path($fasta->path)->slurp, $base);
        },
        sub (%@sequence~&base~) {
            my ($self, $sequences, $base) = @_;
            return $self->locate_sequences($sequences, $base);
        },
    },
    sub (GET + /within/hiv) {
        error( 405 => "You must make location requests using POST." )
    },
    sub (GET + /) {
        state $about = Plack::App::File->new(file => $_[0]->about_page);
        $about;
    },
}

sub locate_sequences_from_fasta {
    my ($self, $fasta, $base) = @_;
    my $sequences = $self->read_fasta(\$fasta)
        or return error( 422 => "Couldn't parse FASTA; invalid formating?" );
    return $self->locate_sequences($sequences, $base);
}

sub locate_sequences {
    my ($self, $sequences, $base) = @_;

    return error(422 => 'At least one value for "sequence" is needed.')
        unless $sequences and @$sequences;

    my $results = $self->locator->find($sequences, base => $base)
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
}

sub read_fasta {
    my ($self, $fasta) = @_;

    # XXX TODO: preserve sequence names and use them in output?
    my (@sequences) = map { chomp; $_ }
                     split /^>.*\R/m, $$fasta;

    # Remove any leading garbage before the first description line (usually
    # just the empty string)
    shift @sequences;
    return \@sequences;
}

sub error {
    return [
        shift,
        [ 'Content-type' => 'text/plain' ],
        [ join(" ", @_), "\n" ]
    ];
}

__PACKAGE__->run_if_script;

=head1 AUTHOR

Thomas Sibley E<lt>trsibley@uw.eduE<gt>

=head1 COPYRIGHT

Copyright 2014 by the Mullins Lab, Department of Microbiology, University of
Washington.

=head1 LICENSE

Licensed under the same terms as Perl 5 itself.

=cut
