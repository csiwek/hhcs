#!/usr/bin/perl
use strict;
use OWNet ;
use Config::Simple;
use Sys::Syslog;                          # all except setlogsock, or:
use Sys::Syslog qw(:DEFAULT setlogsock);  # default set, plus setlogsock
require DBI;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use threads;
use threads::shared;
use Data::Dumper;
use lib '/root/hhcs';
use HHCS::Sensor; 

our $forever :shared = 1;
our $verbose = 3;

my $cfg = new Config::Simple('/root/hhcs/hhcs.cfg');

my $temp_on = 50;
my $temp_off = 56;

sub log_debug {
    my $texto = shift;
    $texto =~ s/\0//g;
    print "DBG:".":$texto\n" if $verbose>2;
#    syslog('debug',"DBG:".$texto) if $verbose>2;
}
sub log_info {
    my $texto = shift;
    $texto =~ s/\0//g;
    print "DBG:".":$texto\n" if $verbose>2;
    syslog('debug',"DBG:".$texto) if $verbose>2;
}



sub ReadCFG {
	log_info "Reading configuration from the config File";
	$temp_on = $cfg->param("boiler.temp_on");
	$temp_off = $cfg->param("boiler.temp_off");
}

ReadCFG();

my $zone_counter= 0;
my $boiler_status = 0;
my $heating_required = 0;
my $cooling_down  = 0;  # Cooling down mode when temp of boilere have reaches max
my $direction = 'init';
my $energy_save = 1;  ###  Use this to permamently disable energy saving
	
$SIG{INT} = 'catch_term';
$SIG{KILL} = 'catch_term';
$SIG{TERM} = 'catch_term';
$SIG{USR1} = 'dump_vars';
$SIG{HUP} = 'ReadCFG';


setlogsock 'unix';
openlog "hhcs", "pid,ndelay,cons", 'user';

my $sensor = HHCS::Sensor->new();


sub dump_vars {

	log_info "zone_counter      $zone_counter\n";
	log_info "boiler_status     $boiler_status\n";
	log_info "heating_required: $heating_required\n";
	log_info "cooling_down:     $cooling_down\n";
	log_info "direction:        $direction\n";
}

sub init_gpio {
	my $ret;
	$ret = `echo 66 > /sys/class/gpio/export`;
	$ret = `echo 67 > /sys/class/gpio/export`;
	$ret = `echo 69 > /sys/class/gpio/export`;
	$ret = `echo 68 > /sys/class/gpio/export`;
	$ret = `echo 45 > /sys/class/gpio/export`; # Realy 5 Upstaris
	$ret = `echo 44 > /sys/class/gpio/export`; # Relay 6 Downstairs
	$ret = `echo 23 > /sys/class/gpio/export`; # Boiler
	$ret = `echo 65 > /sys/class/gpio/export`; # Hearbeat LED


	$ret = `echo "out" > /sys/class/gpio/gpio66/direction`;
	$ret = `echo "out" > /sys/class/gpio/gpio67/direction`;
	$ret = `echo "out" > /sys/class/gpio/gpio69/direction`;
	$ret = `echo "out" > /sys/class/gpio/gpio68/direction`;
	$ret = `echo "out" > /sys/class/gpio/gpio45/direction`; # relay 5 (Upstaris)
	$ret = `echo "out" > /sys/class/gpio/gpio44/direction`; # Relay 6 (Downstaris)
	$ret = `echo "out" > /sys/class/gpio/gpio23/direction`; # Relay 7 Boiler
	$ret = `echo "out" > /sys/class/gpio/gpio65/direction`; #HEARTBEAT LED



}


sub catch_term  {
    my $signame = shift;
    log_debug("SIG received: ".$signame. ". Trying to close process gracefully");
    my $ret;
    $ret = `echo 0 > /sys/class/gpio/gpio66/value`;
    $ret = `echo 0 > /sys/class/gpio/gpio67/value`; 
    $ret = `echo 0 > /sys/class/gpio/gpio69/value`;
    $ret = `echo 0 > /sys/class/gpio/gpio68/value`; 
    $ret = `echo 0 > /sys/class/gpio/gpio45/value`; # Relay 5 (upstairs)
    $ret = `echo 0 > /sys/class/gpio/gpio44/value`; # Relay 6 Downstairs
    $ret = `echo 0 > /sys/class/gpio/gpio23/value`; # Relay 7 (Boiler) 
    $ret = `echo 0 > /sys/class/gpio/gpio65/value`; # Heartbeat LED 

    sleep(3);
    $forever=0;
}



our $owserver = OWNet->new( "localhost:2125" ) ;
#print $owserver->read( "/28.9521EA030000/temperature" ) ."\n" ;


log_info("list of devices : ". Dumper($owserver->dir("/")));

sub Tree($$) {
   my $ow = shift ;
   my $path = shift ;

   log_info("Path: $path");

   # first try to read
   my $value = $ow->read($path) ;
   if ( defined($value) ) {
     log_info($value);
     return ;
   }


}
Tree( $owserver, '/' ) ;




log_debug "Connecting to Database, dsn: ".$cfg->param("database.dsn") ;
my $dbh= DBI->connect($cfg->param("database.dsn"), $cfg->param("database.user"), $cfg->param("database.password"), { mysql_auto_reconnect => 1} );


sub init {
	
	my $query = "SELECT * FROM sensors WHERE enabled = 1";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	if ($sth->rows > 0) {
		while (my $sensors_ref = $sth->fetchrow_hashref()) {
			log_debug "Found Reading sensor: ".$sensors_ref->{'name'}.", ". $sensors_ref->{'ow_addr'};
			my $reading = $owserver->read( $sensors_ref->{'ow_addr'} );
			$reading =~ s/^\s+//;
			$reading =~ s/\s+$//;
			log_debug $sensors_ref->{'name'}." Value:: ".$reading;
#		$sensor->addSensor($sensors_ref->{'id'}, $sensors_ref->{'ow_addr'},  $sensors_ref->{'name'});
		}
		
	}


}


sub read_sensors {
	
#	my $dbh= DBI->connect($cfg->param("database.dsn"), $cfg->param("database.user"), $cfg->param("database.password"), { mysql_auto_reconnect => 1} );
#	while($forever) {
#		sleep(5);
#		log_debug "Read_sensors:: $forever";
#	}
#	log_debug "Read_sensors:: Exiting..."; 
	my $dbh1= DBI->connect($cfg->param("database.dsn"), $cfg->param("database.user"), $cfg->param("database.password"), { mysql_auto_reconnect => 1} );
	while ($forever){	
		my $query = "SELECT * FROM sensors WHERE enabled = 1";
		my $sth = $dbh1->prepare($query);
		$sth->execute();
		if ($sth->rows > 0) {
			while (my $sensors_ref = $sth->fetchrow_hashref()) {
				log_debug "Found Reading sensor: ".$sensors_ref->{'name'}.", ". $sensors_ref->{'ow_addr'};
				my $reading = $owserver->read( $sensors_ref->{'ow_addr'} );
				$reading =~ s/^\s+//;
				$reading =~ s/\s+$//;
				log_debug $sensors_ref->{'name'}." Value:: ".$reading;
				my $q2 = " UPDATE sensors SET value = '$reading' WHERE id='".$sensors_ref->{'id'}."'";
				my $sth2 = $dbh1->prepare($q2);	
				$sth2->execute();
			}
		
		}

		sleep(3);
	}
	threads->exit(0);
}

sub main {
        log_debug "Main loop";
	init();
	init_gpio();
        my $threadcnt=0;
	my $sens_out;
	my $sens_in;
	my $query = "UPDATE zones set direction='$direction'";
	my $sth = $dbh->prepare($query);
        $sth->execute();

        my $thr1 = threads->create(sub { &read_sensors; });
        $thr1->set_thread_exit_only(1);
	$threadcnt=$threadcnt+1;
	my $cnt;
	my $mythread = threads->self;
	log_debug "main thread: ". $mythread->tid();
	do {
		log_debug "\n\n\nMain loop:: $forever";
		log_debug "Zone counter: $zone_counter";
		log_debug "Cooling Down mode: $cooling_down";
		log_debug "Boiler status: $boiler_status";
		log_debug "Direction: $direction";
		log_debug "Heating Required:: $heating_required\n\n\n";
		sleep 11;
		$cnt=$threadcnt;
		foreach my $thr (threads->list(threads::running)) {
			# Donâjoin the main thread or ourselves
			if ($thr->tid && !threads::equal($thr, threads->self)) {
				#log_debug "Main loop:: unjoining ". threads->self;
				$cnt--;
			}
		}
		#log_debug "MAIN LOOP|".($threadcnt - $cnt)." threads still running";


	my $query2 = "SELECT zones.id, zones.name, zones.temp_low, zones.temp_high, zones.enabled, zones.direction, sensors.value, relays.path FROM zones JOIN sensors on zones.sensor_id = sensors.id JOIN relays ON zones.relay_id = relays.id WHERE zones.enabled = 1";
	my $sth2 = $dbh->prepare($query2);
	$sth2->execute();

            while ((my $zone = $sth2->fetchrow_hashref()) && ($forever == 1)) {
		if (($zone->{direction} eq 'up') && ($zone->{value} >= $zone->{temp_high}))  {
			log_info "Diabling heating in zone ".$zone->{name}." ". $zone->{value}. " >= ".$zone->{temp_high};
			my $cmd = "echo 0 > ".$zone->{path};					
			my $ret = `$cmd`;
			my $q3 = "UPDATE zones SET direction = 'down' WHERE id='".$zone->{id}."'";
			my $sth3 = $dbh->prepare($q3);
			$sth3->execute();
			$zone_counter--;

		}
		if (($zone->{direction} eq 'down') && ($zone->{value} <= $zone->{temp_low}))  {
			log_info "Enabling heating in zone ".$zone->{name}." ". $zone->{value}. " <= ".$zone->{temp_low};
			my $cmd = "echo 1 > ".$zone->{path};					
			my $ret = `$cmd`;
			my $q3 = "UPDATE zones SET direction = 'up' WHERE id='".$zone->{id}."'";
			my $sth3 = $dbh->prepare($q3);
			$sth3->execute();
			$zone_counter++;
			# If the cooling down mode is enabled we need to disable it back
			if ($cooling_down){
				$cooling_down = 0;
			}

		}
		if (($zone->{direction} eq 'init') && ($zone->{value} <= $zone->{temp_high}))  {
			log_info "Enabling heating in zone ".$zone->{name}." ". $zone->{value}. " < ".$zone->{temp_high};
			my $cmd = "echo 1 > ".$zone->{path};					
			my $ret = `$cmd`;
			my $q3 = "UPDATE zones SET direction = 'up' WHERE id='".$zone->{id}."'";
			my $sth3 = $dbh->prepare($q3);
			$sth3->execute();
			$zone_counter++;


		}
		if (($zone->{direction} eq 'init') && ($zone->{value} > $zone->{temp_high}))  {
			log_info "Diabling heating in zone ".$zone->{name}." ". $zone->{value}. " > ".$zone->{temp_low};
			my $cmd = "echo 0 > ".$zone->{path};					
			my $ret = `$cmd`;
			my $q3 = "UPDATE zones SET direction = 'down' WHERE id='".$zone->{id}."'";
			my $sth3 = $dbh->prepare($q3);
			$sth3->execute();
			#$zone_counter--;
		}
	    }   # End while
	
	my $query = "SELECT * FROM sensors WHERE enabled = 1";
        $sth = $dbh->prepare($query);
	$sth->execute();
	my $ret;
        if ($sth->rows > 0) {
        	while (my $sens = $sth->fetchrow_hashref()) {
			if ($sens->{'name'} eq 'flow-in'){
				$sens_in = $sens->{'value'};
			} elsif ($sens->{'name'} eq 'flow-out'){
				$sens_out = $sens->{'value'};
			}
		}
	}

	if (($sens_in >= $temp_off) && (!$cooling_down)){
		$cooling_down = 1;
		$direction = 'down';
		log_info "Main loop:: Cooling Down mode.  Disabling Boiler. Sens_out: $sens_in  >=  $temp_off ";
	} elsif (($sens_in <= $temp_on) && ($cooling_down)){
		$cooling_down = 0;
		$direction = 'up';
		log_info "Main loop:: Heating mode. Enabling Boiler. Sens_out: $sens_in  < $temp_on ";
	}
	if ($energy_save eq 0) {
		
		 $cooling_down = 0;	
	
	}
	if ($zone_counter >0){
		if (($direction ne 'init') && (!$cooling_down)){
			log_debug "Heating Required check:: Required Direction:  $direction";
			$heating_required = 1;
			$direction='up';
		}
		if (($direction ne 'init') && ($cooling_down)){
			log_debug "Heating Required check:: Not Required. Direction: $direction  ";
			$heating_required = 0;
		}
		if (($direction eq 'init') && ($sens_in < $temp_off)){
			log_debug "Heating Required check:: INIT: Enabling Boiler. Sens_out: $sens_in  < $temp_off ";
			$heating_required = 1;
			$cooling_down = 0;
			$direction = "up";
		} elsif (($direction eq 'init') && ($sens_in >= $temp_off)){
			log_debug "Heating Required check:: INIT: Heating required but temp too big Boiler. Sens_out: $sens_in  >= $temp_off ";
			$heating_required = 1;
			if (!$energy_save){
				$cooling_down = 1;
			}
			$direction = "down";
		}

	} else {
			log_debug " Boiler not required by zones";
			$direction = "down";
			$heating_required=0;
			if (!$energy_save){
				$cooling_down = 1;
			}
	}



		$boiler_status = `cat /sys/class/gpio/gpio23/value`;
		chomp($boiler_status);
		log_debug  "==================== WE ARE HERE 1  $boiler_status   $cooling_down  ";
		if (($heating_required eq 1) && ($cooling_down ne 1)){
			log_debug  "==================== WE ARE HERE 2  $boiler_status   $cooling_down  ";
			if ($boiler_status eq 0) {
				log_debug  "Bolier is disabled but heating reqired. Enabling.";
				my $cmd = "echo 1 > /sys/class/gpio/gpio23/value";
				my $ret = `$cmd`;
			}		

		} else {
			# In all other cases we don't need the boiler to be on
			if ($boiler_status eq 1){
				log_debug  "Bolier is enabled but heating Not reqired. Disabling.";
				my $cmd = "echo 0 > /sys/class/gpio/gpio23/value";
				my $ret = `$cmd`;
			
			}

		}


		#  This ist the hartbeet LED
		$ret = `echo 1 > /sys/class/gpio/gpio65/value`;
		sleep(0.2);
		$ret = `echo 0 > /sys/class/gpio/gpio65/value`;
	
	log_debug "Direction: $direction";
	} until ($forever==0 || $cnt > 0);
	$thr1->detach();	
	$forever=0;
	sleep(3);
	log_debug  "HHCS exiting.";

}	
exit main();
