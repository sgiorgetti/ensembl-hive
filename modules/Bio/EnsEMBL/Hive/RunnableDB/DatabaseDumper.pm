
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::DatabaseDumper

=head1 DESCRIPTION

This is a Runnable to dump the tables of a database (by default,
all of them).

The following parameters are accepted:

 - src_db_conn : the connection parameters to the database to be
    dumped (by default, the current eHive database if available)

 - exclude_ehive [boolean=0] : do we exclude the eHive-specific tables
    from the dump

 - table_list [string or array of strings]: the list of tables
    to include in the dump. The '%' wildcard is accepted.

 - exclude_list [boolean=0] : do we consider 'table_list' as a list
    of tables to be excluded from the dump (instead of included)

 - output_file [string] : the file to write the dump to

=head1 SYNOPSIS

standaloneJob.pl RunnableDB/DatabaseDumper.pm -exclude_ehive 1 -exclude_list 1 -table_list "['peptide_align_%']" -src_db_conn mysql://ensro@127.0.0.1:4313/mm14_compara_homology_67 -output_file ~/dump1.sql

=cut

package Bio::EnsEMBL::Hive::RunnableDB::DatabaseDumper;

use strict;

use base ('Bio::EnsEMBL::Hive::Process');

sub fetch_input {
    my $self = shift @_;

    # The final list of tables
    my @tables = ();
    $self->param('tables', \@tables);
    my @ignores = ();
    $self->param('ignores', \@ignores);

    # Would be good to have this from eHive
    my @ehive_tables = qw(worker dataflow_rule analysis_base analysis_ctrl_rule job job_message job_file analysis_data resource_description analysis_stats analysis_stats_monitor monitor msg progress resource_class);

    # Connection parameters
    my $src_db_conn  = $self->param('src_db_conn');
    my $src_dbc = $src_db_conn ? $self->go_figure_dbc($src_db_conn) : $self->db->dbc;
    $self->param('src_dbc', $src_dbc);

    $self->input_job->transient_error(0);
    die 'Only the "mysql" driver is supported.' if $src_dbc->driver ne 'mysql';

    # Get the table list in either "tables" or "ignores"
    die 'The parameter "table_list" is mandatory' unless $self->param('table_list');
    if ($self->param('exclude_list')) {
        my $table_list = $self->_get_table_list;
        push @ignores, @$table_list;
    } else {
        push @tables, @{$self->_get_table_list};
    }

    # eHive tables are dumped unless exclude_ehive is defined
    if ($self->param('exclude_ehive')) {
        push @ignores, @ehive_tables;
    } elsif ($self->param('table_list')) {
        push @tables, @ehive_tables;
    }

    # Output file / output database
    $self->param('output_file') || $self->param('output_db') || die 'One of the parameters "output_file" and "output_db" is mandatory';
    if ($self->param('output_file')) {
        $self->param('real_output_file', $self->param_substitute($self->param('output_file')));
    } else {
        $self->param('real_output_db', $self->go_figure_dbc($self->param_substitute($self->param('output_db'))));
        die 'Only the "mysql" driver is supported.' if $self->param('real_output_db')->driver ne 'mysql';
    }

    $self->input_job->transient_error(1);
}


# Splits a string into a list of strings
# Ask the database for the list of tables that match the wildcard "%"

sub _get_table_list {
    my $self = shift @_;

    my $table_list = $self->param_substitute($self->param('table_list') || '');
    my @newtables = ();
    my $dbc = $self->param('src_dbc');
    foreach my $initable (ref($table_list) eq 'ARRAY' ? @$table_list : split(' ', $table_list)) {
        if ($initable =~ /%/) {
            $initable =~ s/_/\\_/g;
            my $sth = $dbc->db_handle->table_info(undef, undef, $initable, undef);
            push @newtables, map( {$_->[2]} @{$sth->fetchall_arrayref});
        } else {
            push @newtables, $initable;
        }
    }
    return \@newtables;
}


sub run {
    my $self = shift @_;

    my $src_dbc = $self->param('src_dbc');
    my $tables = $self->param('tables');
    my $ignores = $self->param('ignores');

    my $cmd = join(' ', 
        'mysqldump',
        $self->mysql_conn_from_dbc($src_dbc),
        @$tables,
        map {sprintf('--ignore-table=%s.%s', $src_dbc->dbname, $_)} @$ignores,
        $self->param('output_file') ? sprintf('> %s', $self->param('real_output_file')) : sprintf(' | mysql %s', $self->mysql_conn_from_dbc($self->param('real_output_db'))),
    );

    print "$cmd\n" if $self->debug;
    unless ($self->param('skip_dump')) {
        if(my $return_value = system($cmd)) {
            die "system( $cmd ) failed: $return_value";
        }
    }
}


sub mysql_conn_from_dbc {
    my ($self, $dbc) = @_; 

    return '--host='.$dbc->host.' --port='.$dbc->port." --user='".$dbc->username."' --pass='".$dbc->password."' ".$dbc->dbname;
}


1;
