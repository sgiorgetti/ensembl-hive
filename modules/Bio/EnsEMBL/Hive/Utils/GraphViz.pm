=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::GraphViz

=head1 DESCRIPTION

    An extension of GraphViz that employs a collection of hacks
    to use some functionality of dot that is not available through GraphViz.

    There are at least 3 areas where we need it:
        (1) passing in some parameters of the drawing (such as pad => ...)
        (2) drawing clusters (boxes) around semaphore fans
        (3) using the newest node types (such as Mrecord, tab and egg) with HTML-like labels

=head1 EXTERNAL DEPENDENCIES

    GraphViz

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2017] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Utils::GraphViz;

use strict;
use warnings;
use base ('GraphViz');


=head2 new

    Title   :  new (constructor)
    Function:  Instantiates a new Utils::GraphViz object
                by injecting some variables unsupported by GraphViz (but understood by dot) directly into the dot output.
                We rely on a particular quoting pattern used in dot's input format to fool GraphViz (which luckily doesn't escape quotes).

=cut

sub new {
    my $class       = shift @_;
    my %all_params  = @_;

    my $ratio_value = delete $all_params{'ratio'} || 'compress';
    my $injection = join('', map { '"; ' . $_ . ' = "' . $all_params{$_} } sort keys %all_params);

    return $class->SUPER::new( 'ratio' => $ratio_value.$injection );
}


sub cluster_2_nodes {
    my $self = shift @_;
    if(@_) {
        $self->{_cluster_2_nodes} = shift @_;
    }
    return $self->{_cluster_2_nodes} ||= {};
}


sub cluster_2_colour_pair {
    my $self = shift @_;
    if(@_) {
        $self->{_cluster_2_colour_pair} = shift @_;
    }
    return $self->{_cluster_2_colour_pair} ||= {};
}


sub nested_bgcolour {
    my $self = shift @_;
    if(@_) {
        $self->{_nested_bgcolour} = shift @_;
    }
    return $self->{_nested_bgcolour};
}


sub dot_input_filename {
    my $self = shift @_;
    if(@_) {
        $self->{_dot_input_filename} = shift @_;
    }
    return $self->{_dot_input_filename};
}


sub display_cluster_names_by_level {    # FIXME: if we want to introduce "-include" equivalent for A-diagrams as well,
                                        #        this interface will no longer be adequate, so we will need something more specific.
    my $self = shift @_;
    if(@_) {
        $self->{_display_cluster_names_by_level} = shift @_;
    }
    return $self->{_display_cluster_names_by_level} || {};
}


sub display_subgraph {
    my ($self, $cluster_name, $depth) = @_;

    my ($box_colour_pair, $auto_colour) = $self->cluster_2_colour_pair->{$cluster_name} || ($self->nested_bgcolour, 1);
    my ($colour_scheme, $colour_offset) = $box_colour_pair && @$box_colour_pair;
    my $cluster_label                   = $self->display_cluster_names_by_level->{$depth}
                                            ? ( ($cluster_name=~/\_{3}(\w+)$/) ? $1 : $cluster_name )
                                            : '';

    my $prefix = "\t" x $depth;
    my  $text = '';
        $text .= $prefix . "subgraph cluster_${cluster_name} {\n";  #   NB: the "cluster_" prefix absolutely must be present.
        $text .= $prefix . qq{\tlabel="$cluster_label";\n};         #   In case some levels need the labels and some don't, need to override the parent level

    if($colour_scheme) {
        $text .= $prefix . "\tstyle=filled;\n";

        if(defined($colour_offset)) {
            $text .= $prefix . "\tcolorscheme=$colour_scheme;\n";
            $text .= $prefix . "\tcolor=".($auto_colour ? $colour_offset+$depth : $colour_offset).";\n";
        } else {    # it's just a simple colour:
            $text .= $prefix . "\tcolorscheme=X11;\n";
            $text .= $prefix . "\tcolor=${colour_scheme};\n";
        }
    } # otherwise just draw a black frame around the subgraph

    foreach my $node_name ( @{ $self->cluster_2_nodes->{ $cluster_name } || [] } ) {

        if( @{ $self->cluster_2_nodes->{ $node_name } || [] } ) {
            $text .= $self->display_subgraph( $node_name, $depth+1 );
        } else {
            $text .= $prefix . "\t${node_name};\n";
        }
    }
    $text .= $prefix . "}\n";

    return $text;
}


sub top_level_cluster_names {
    my $self = shift @_;

    my %top_level_candidate_set = map { ($_ => 1) } keys %{ $self->cluster_2_nodes };

        # remove all keys that have been mentioned in the values (subclusters) :
    foreach my $vector (values %{ $self->cluster_2_nodes }) {
        foreach my $element (@$vector) {
            if(exists $top_level_candidate_set{$element}) {
                delete $top_level_candidate_set{$element};
            }
        }
    }

        # what remains are the top-level clusters:
    return [ sort keys %top_level_candidate_set ];
}


sub _as_debug {
    my $self = shift @_;

    my $text = $self->SUPER::_as_debug;

    $text=~s/^}$//m;

    foreach my $top_level_cluster_name (@{ $self->top_level_cluster_names }) {
        $text .= $self->display_subgraph( $top_level_cluster_name, 0);
    }
    $text .= "}\n";

        # GraphViz.pm thinks 'record' is the only shape that allows HTML-like labels,
        # but newer versions of dot allow more freedom.
        # Since we wanted to stick with the older GraphViz, we initially ask for shape="record",
        # but put the desired shape into the comment and patch dot input after generation:
        #
    $text=~s/\bcomment="new_shape:(\w+)",\s(.*shape=)"record"/$2"$1"/mg;

    if(my $dot_input_filename = $self->dot_input_filename) {
        open(my $dot_input, ">", $dot_input_filename) or die "cannot open > $dot_input_filename : $!";
        print $dot_input $text;
        close $dot_input;
    }

    return $text;
}


sub add_node {
    my $self        = shift @_;
    my $node_name   = shift @_;
    my %param_hash  = @_;

    my $desired_shape   = delete $param_hash{'shape'};  # smuggle in the desired shape as a comment, to be substituted later by _as_debug() method

    return $self->SUPER::add_node($node_name, %param_hash, $desired_shape ? (shape => 'record', comment => qq{new_shape:$desired_shape}) : () );
}


sub protect_string_for_display {    # NB: $self is only needed for calling, and isn't used in any other way

    my ($self, $string, $length_limit, $drop_framing_curlies) = @_;

    if($drop_framing_curlies) {
        $string=~s/^\{//;       # drop leading curly
        $string=~s/\}$//;       # drop trailing curly
    }

    if(defined( $length_limit )) {
        $string=~s{^(.{$length_limit}).+}{$1 \.\.\.};   # shorten down to $length_limit characters
    }

    $string=~s{&}{&amp;}g;      # Since we are in HTML context now, ampersands should be escaped (first thing after trimming)
    $string=~s{"}{&quot;}g;     # should fix a string display bug for pre-2.16 GraphViz'es
    $string=~s{<}{&lt;}g;
    $string=~s{>}{&gt;}g;

    return $string;
}

1;

