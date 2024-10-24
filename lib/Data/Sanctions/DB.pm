package Data::Sanctions::DB;

use strict;
use warnings;

use DateTime::Format::Strptime;
use BOM::Database::ClientDB;
use Try::Tiny;

=head1 NAME

Data::Sanctions::DB - A module for managing sanction list providers in the database.

=head1 SYNOPSIS

  use Data::Sanctions::DB;

  my $sanctions_db = Data::Sanctions::DB->new();
  $sanctions_db->insert_or_update_sanction_list_provider(
      'Provider A',
      'http://provider-a.com',
      '2023-10-01 12:00:00',
      'hash123',
      100
  );

=head1 METHODS

=head2 new

Creates a new instance of the Data::Sanctions::DB package.

=head2 insert_or_update_sanction_list_provider

Inserts or updates a sanction list provider in the database.

  $sanctions_db->insert_or_update_sanction_list_provider(
      $provider_name,
      $provider_url,
      $publish_date,
      $hash,
      $number_of_entries
  );

=cut

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;

    # Initialize the database connection
    $self->{dbic} = BOM::Database::ClientDB->new({
            broker_code  => 'FOG',
            db_operation => 'write',
        })->db->dbic;

    return $self;
}

=head2 insert_or_update_sanction_list_provider

Inserts or updates a sanction list provider in the database.

  $sanctions_db->insert_or_update_sanction_list_provider(
      $provider_name,
      $provider_url,
      $publish_date,
      $hash,
      $number_of_entries
  );

=cut

sub insert_or_update_sanction_list_provider {
    my ($self, $p_provider_name, $p_provider_url, $p_publish_date, $p_hash, $p_number_of_entries) = @_;

    # Input validation
    return 0 unless defined $p_provider_name && defined $p_provider_url && defined $p_publish_date && defined $p_hash && defined $p_number_of_entries;

    try {
        $self->{dbic}->run(
            fixup => sub {
                $_->selectall_arrayref(
                    'SELECT compliance.insert_or_update_sanction_list_provider(?, ?, ?, ?, ?)',
                    {Slice => {}},
                    $p_provider_name, $p_provider_url, $p_publish_date, $p_hash, $p_number_of_entries
                );
            });
        return 1;
    } catch {
        warn "Failed to insert or update sanction list provider: $_";
        return 0;
    };
}

=head2 fetch_audit_entries_for_sanction_list_provider

Fetches audit entries for a specific sanction list provider by ID.

  my $audit_entries = $sanctions_db->fetch_audit_entries_for_sanction_list_provider($provider_id);

=cut

sub fetch_audit_entries_for_sanction_list_provider {
    my ($self, $p_id) = @_;

    # Input validation
    return unless defined $p_id;

    my $audit_entries;
    try {
        $audit_entries = $self->{dbic}->run(
            fixup => sub {
                $_->selectall_arrayref('SELECT * FROM audit.fetch_audit_entries_for_sanction_list_provider(?)', {Slice => {}}, $p_id);
            });
    } catch {
        warn "Failed to fetch audit entries for sanction list provider: $_";
        return;
    };

    return $audit_entries;
}

=head2 fetch_sanction_list_providers

Fetches all sanction list providers.

  my $sanction_list_providers = $sanctions_db->fetch_sanction_list_providers();

=cut

sub fetch_sanction_list_providers {
    my ($self) = @_;

    my $sanction_list_providers;
    try {
        $sanction_list_providers = $self->{dbic}->run(
            fixup => sub {
                $_->selectall_arrayref('SELECT * FROM compliance.fetch_sanction_list_providers()', {Slice => {}});
            });
    } catch {
        warn "Failed to fetch sanction list providers: $_";
        return;
    };

    return $sanction_list_providers;
}

1;
