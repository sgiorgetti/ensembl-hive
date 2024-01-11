=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::LogMessageAdaptor

=head1 SYNOPSIS

    $dba->get_LogMessageAdaptor->store_job_message($job_id, $msg, $message_class);

    $dba->get_LogMessageAdaptor->store_worker_message($worker, $msg, $message_class);

    $dba->get_LogMessageAdaptor->store_hive_message($msg, $message_class);

    $dba->get_LogMessageAdaptor->store_beekeeper_message($beekeeper_id, $msg, $message_class, $status);

=head1 DESCRIPTION

    This is currently an "objectless" adaptor that helps to store either warning-messages or die-messages generated by jobs

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2024] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::DBSQL::LogMessageAdaptor;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor');


sub default_table_name {
    return 'log_message';
}


sub store_job_message {
    my ($self, $job_id, $msg, $message_class) = @_;

    if($job_id) {
        chomp $msg;   # we don't want that last "\n" in the database

        my $table_name = $self->table_name();

            # Note: the timestamp 'when_logged' column will be set automatically
        my $sql = qq{
            INSERT INTO $table_name (job_id, role_id, worker_id, retry, status, msg, message_class)
                               SELECT job_id, role_id, worker_id, retry_count, status, ?, ?
                                 FROM job
                                 JOIN role USING(role_id)
                                WHERE job_id=?
        };

        my $sth = $self->prepare( $sql );
        $sth->execute( $msg, $message_class, $job_id );
        $sth->finish();

    } else {
        $self->store_hive_message($msg, $message_class);
    }
}


sub store_worker_message {
    my ($self, $worker_or_id, $msg, $message_class) = @_;

    my ($worker, $worker_id) = ref($worker_or_id) ? ($worker_or_id, $worker_or_id->dbID) : (undef, $worker_or_id);
    my $role_id   = $worker && $worker->current_role && $worker->current_role->dbID;

    chomp $msg;   # we don't want that last "\n" in the database

    my $table_name = $self->table_name();

        # Note: the timestamp 'when_logged' column will be set automatically
    my $sql = qq{
        INSERT INTO $table_name (worker_id, role_id, status, msg, message_class)
                           SELECT worker_id, ?, status, ?, ?
                             FROM worker WHERE worker_id=?
    };
    my $sth = $self->prepare( $sql );
    $sth->execute( $role_id, $msg, $message_class, $worker_id );
    $sth->finish();
}


sub store_hive_message {
    my ($self, $msg, $message_class) = @_;

    chomp $msg;   # we don't want that last "\n" in the database

        # Note: the timestamp 'when_logged' column will be set automatically
    my $log_message = {
        'msg'           => $msg,
        'message_class' => $message_class,
        'status'        => 'UNKNOWN',
    };
    return $self->store($log_message);
}

sub store_beekeeper_message {
    my ($self, $beekeeper_id, $msg, $message_class, $status) = @_;

    chomp $msg;

    my $log_message = {
        'beekeeper_id'  => $beekeeper_id,
        'msg'           => $msg,
        'message_class' => $message_class,
        'status'        => $status,
    };
    return $self->store($log_message);
}

sub count_analysis_events {
    my ($self, $analysis_id, $message_class) = @_;

    return $self->count_all("JOIN role USING (role_id) WHERE analysis_id = ? AND message_class = ?", undef, $analysis_id, $message_class);
}

1;
