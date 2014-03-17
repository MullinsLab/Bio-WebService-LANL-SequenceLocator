# NAME

Bio::WebService::LANL::SequenceLocator - Locate sequences within HIV using LANL's web tool

# SYNOPSIS

    use Bio::WebService::LANL::SequenceLocator;
    

    my $locator = Bio::WebService::LANL::SequenceLocator->new(
        agent_string => 'Your Organization - you@example.com',
    );
    my @sequences = $locator->find([
        "agcaatcagatggtcagccaaaattgccctatagtgcagaacatccaggggcaagtggtacatcaggccatatcacctagaactttaaatgca",
    ]);

See ["EXAMPLE RESULTS"](#EXAMPLE RESULTS) below.

# DESCRIPTION

This library provides simple programmatic access to
[LANL's HIV sequence locator](http://www.hiv.lanl.gov/content/sequence/LOCATE/locate.html)
web tool and is also used to power
[a simple, JSON-based web API](http://indra.mullins.microbiol.washington.edu/locate-sequence/)
for the same tool (via [Bio::WebService::LANL::SequenceLocator::Server](http://search.cpan.org/perldoc?Bio::WebService::LANL::SequenceLocator::Server)).

Nearly all of the information output by LANL's sequence locator is parsed and
provided by this library, though the results do vary slightly depending on the
base type of the query sequence.  Multiple query sequences can be located at
the same time and results will be returned for all.

Results are extracted from both tab-delimited files provided by LANL as well as
the HTML itself.

# EXAMPLE RESULTS

    # Using @sequences from the SYNOPSIS above
    use JSON;
    print encode_json(\@sequences);
    

    __END__
    [
       {
          "query" : "sequence_1",
          "query_sequence" : "AGCAATCAGATGGTCAGCCAAAATTGCCCTATAGTGCAGAACATCCAGGG GCAAGTGGTACATCAGGCCATATCACCTAGAACTTTAAATGCA",
          "base_type" : "nucleotide",
          "reverse_complement" : "0",
          "similarity_to_hxb2" : "94.6",
          "start" : "373"
          "end" : "462",
          "genome_start" : "1162",
          "genome_end" : "1251",
          "polyprotein" : "Gag",
          "region_names" : [
             "Gag",
             "p17",
             "p24"
          ],
          "regions" : [
             {
                "cds" : "Gag",
                "aa_from_protein_start" : [ "125", "154" ],
                "na_from_cds_start" : [ "373", "462" ],
                "na_from_hxb2_start" : [ "1162", "1251" ],
                "na_from_query_start" : [ "1", "93" ],
                "protein_translation" : "SNQMVSQNCPIVQNIQGQVVHQAISPRTLNA"
             },
             {
                "cds" : "p17",
                "aa_from_protein_start" : [ "125", "132" ],
                "na_from_cds_start" : [ "373", "396" ],
                "na_from_hxb2_start" : [ "1162", "1185" ],
                "na_from_query_start" : [ "1", "27" ],
                "protein_translation" : "SNQMVSQNC"
             },
             {
                "cds" : "p24",
                "aa_from_protein_start" : [ "1", "22" ],
                "na_from_cds_start" : [ "1", "66" ],
                "na_from_hxb2_start" : [ "1186", "1251" ],
                "na_from_query_start" : [ "28", "93" ],
                "protein_translation" : "PIVQNIQGQVVHQAISPRTLNA"
             }
          ],
       }
    ]

# METHODS

## new

Returns a new instance of this class.  An optional parameter `agent_string`
should be provided to identify yourself to LANL out of politeness.  See the
["SYNOPSIS"](#SYNOPSIS) for an example.

## find

Takes an array ref of sequence strings.  Sequences may be in amino acids or
nucleotides and mixed freely.  Sequences should not be in FASTA format.

Returns a list of hashrefs when called in list context, otherwise returns an
arrayref of hashrefs.

See ["EXAMPLE RESULTS"](#EXAMPLE RESULTS) for the structure of the data returned.

# AUTHOR

Thomas Sibley <trsibley@uw.edu>

# COPYRIGHT

Copyright 2014 by the Mullins Lab, Department of Microbiology, University of
Washington.

# LICENSE

Licensed under the same terms as Perl 5 itself.