#!/usr/bin/env perl
# Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use Test::More;

use Cwd;
use File::Basename;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use Bio::EnsEMBL::Hive::Utils::Test qw(get_test_urls);
use Bio::EnsEMBL::Hive::Utils::URL;

# For finding the sample db dump's location, so it can be loaded.
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $db_urls = get_test_urls(-driver => 'mysql');

SKIP: {
  skip "no MySQL test database defined", 1 if (scalar(@$db_urls) < 1); 
  foreach my $db_url (@$db_urls) {
    my $parsed_url = Bio::EnsEMBL::Hive::Utils::URL::parse($db_url);
    
    my $dbname;
    if ($parsed_url->{dbname} ne '') {
      $dbname = $parsed_url->{dbname};
    } else {
      BAIL_OUT("db url $db_url did not have a parsable dbname - check that get_test_urls.t also fails");
    }
    
    my $server_url;
    $server_url .= $parsed_url->{driver};
    $server_url .= "://";
    $server_url .= $parsed_url->{user} if (defined($parsed_url->{user}));
    $server_url .= ":" . $parsed_url->{pass} if (defined($parsed_url->{pass}));
    $server_url .= "@" . $parsed_url->{host} if (defined($parsed_url->{host}));
    $server_url .= ":" . $parsed_url->{port} if (defined($parsed_url->{port}));
    $server_url .= "/";
    
    prepare_db($server_url, $dbname);
    
    my $dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-url => $db_url,
							-no_sql_schema_version_check => 1);
    my $dbc = $dba->dbc();
    
    my $dbc_query_sql = "SELECT SQL_NO_CACHE * FROM manyrows";
    my $find_pid_sql = "SELECT ID FROM information_schema.processlist " .
      "WHERE DB = '$dbname'";
    my $find_pid_cmd = $ENV{'EHIVE_ROOT_DIR'}.'/scripts/db_cmd.pl ' .
      "-url $server_url " .
	"-sql \"$find_pid_sql\"";
    
    my $sth = $dbc->prepare($dbc_query_sql);
    my @find_pid_results = `$find_pid_cmd`;
    
    if (scalar(@find_pid_results) != 2) {
      BAIL_OUT("more than one process id accessing test database, bailing out");
    }
    
    my $found_pid = $find_pid_results[1];
    chomp($found_pid);
    
    my $kill_sql = "KILL $found_pid";
    my $kill_cmd = $ENV{'EHIVE_ROOT_DIR'}.'/scripts/db_cmd.pl ' .
      "-url $server_url " .
	"-sql \"$kill_sql\"";
    
    my @kill_results = `$kill_cmd`;
    
    $sth->execute();
    
    my $fetched_row_count = 0;
    while (my @values = $sth->fetchrow_array()) {
      $fetched_row_count++;
    }
    is($fetched_row_count, 10, "were we able to fetch all rows after a db kill");
  }
}

done_testing();

sub prepare_db {
  my ($server_url, $dbname) = @_;
  my $full_db_url = $server_url . $dbname;

  my $drop_command = $ENV{'EHIVE_ROOT_DIR'}.'/scripts/db_cmd.pl ' .
    "-url $server_url " .
      "-sql \"DROP DATABASE IF EXISTS $dbname\"";

  my $create_command = $ENV{'EHIVE_ROOT_DIR'}.'/scripts/db_cmd.pl ' .
    "-url $server_url " .
      "-sql \"CREATE DATABASE $dbname\""; 

  my $load_command = $ENV{'EHIVE_ROOT_DIR'}.'/scripts/db_cmd.pl '  .
    "-url $full_db_url " .
      "< " . $ENV{'EHIVE_ROOT_DIR'} . "/t/02.api/sql/reconnect_test.sql";

  `$drop_command`;
  `$create_command`;
  `$load_command`;
}
