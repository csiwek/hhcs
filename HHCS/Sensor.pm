package HHCS::Sensor;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Carp;
require Exporter;
require AutoLoader;
use Data::Dumper;
@EXPORT = qw(

);
$VERSION = '0.01';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    $self->{SENSORS} =[];
    bless($self, $class);
    return $self;
}

sub version {

        return $VERSION;
}



sub addSensor {
	my $self = shift;
	my ($s_id, $s_addr, $s_name) = @_;
	print ("Adding sensor: $s_id, $s_addr, $s_name\n ");
	my $s_val  = {
			"addr" => $s_addr,
			"value" => '',
			"name" => $s_name
	
	};
	my %tmp_hash  = $self->{SENSORS};
	$tmp_hash{$s_id} = $s_val;
	$self->{SENSORS} = \%tmp_hash;
	print Dumper($self->{SENSORS});
}

sub getSensors{
	my $self = shift;
	return $self->{SENSORS};
   	
}

sub setValue{
	my $self = shift;
	my ($s_id, $value) =  @_;
	

}	
