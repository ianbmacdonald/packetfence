package captiveportal::DynamicRouting::AuthModule::SMS;

=head1 NAME

DynamicRouting::AuthModule::SMS

=head1 DESCRIPTION

SMS authentication module

=cut

use Moose;
extends "captiveportal::DynamicRouting::AuthModule";

use pf::person;
use pf::activation;
use pf::log;
use pf::constants;

has 'required_fields' => (is => 'rw', isa => 'ArrayRef[Str]', builder => '_build_required_fields', lazy => 1);

has 'custom_fields' => (is => 'rw', isa => 'ArrayRef[Str]', required => 1);

has 'request_fields' => (is => 'rw', traits => ['Hash'], default => sub {return {}});

has 'pid_field' => ('is' => 'rw', default => sub { "phonenumber" } );

sub _build_required_fields {
    my ($self) = @_;
    return ["phonenumber", "mobileprovider", @{$self->custom_fields}];
}

sub merged_fields {
    my ($self) = @_;
    return { map { $_ => $self->request_fields->{$_} } @{$self->required_fields} };
}

sub execute_child {
    my ($self) = @_;
    $self->request_fields($self->app->hashed_params()->{fields} || {});

    if($self->app->request->param("pin")){
        $self->validation();
    }
    elsif(pf::activation::activation_has_entry($self->current_mac,'sms')){
        $self->prompt_code();
    }
    elsif($self->app->request->method eq "POST"){
        $self->validate_info();
    }
    else {
        $self->prompt_info();
    }
}

sub prompt_code {
    my ($self) = @_;
    $self->render("sms/validate.html");
}

sub prompt_info {
    my ($self) = @_;
    my $previous = $self->app->request->parameters();
    $self->render("guest.html", {
        type => "SMS", 
        previous_request => $self->app->request->parameters(),
        fields => $self->merged_fields,
    });
}

sub validate_info {
    my ($self) = @_;
    my $phonenumber = $self->request_fields->{phonenumber} || die "Can't find phone number field";
    my $pid = $self->request_fields->{$self->pid_field} || die "Can't find PID field";
    my $mobileprovider = $self->request_fields->{mobileprovider} || die "Can't find Mobile phone provider field";

    # not sure we should set the portal + source here...
    person_modify($self->current_mac, %{ $self->request_fields }, portal => $self->app->profile->getName, source => $self->source->id);
    pf::activation::sms_activation_create_send( $self->current_mac, $pid, $phonenumber, $self->app->profile->getName, $mobileprovider );

    $self->username($pid);
    $self->session->{phonenumber} = $phonenumber;
    $self->session->{mobileprovider} = $mobileprovider;

    $self->prompt_code();
}

sub validate_pin {
    my ($self, $pin) = @_;

    get_logger->debug("Mobile phone number validation attempt");
    if (my $record = pf::activation::validate_code($pin)) {
        return ($TRUE, 0, $record);
    }
    else {
        return ($FALSE, $GUEST::ERROR_INVALID_PIN);
    }
}

sub validation {
    my ($self) = @_;

    my $pin = $self->app->hashed_params->{'pin'} || die "Can't find PIN in request";
    my ($status, $reason, $record) = $self->validate_pin($pin);
    if($status){
        pf::activation::set_status_verified($pin);
        $self->done();
    }
    else {
        die "Can't validate PIN : $reason.";
    }
}

sub auth_source_params {
    my ($self) = @_;
    return {
        username => $self->app->session->{username},
        phonenumber => $self->session->{phonenumber}
    };
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2016 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

__PACKAGE__->meta->make_immutable;

1;

