#!/usr/bin/perl
use strict;
use OWNet ;
use Config::Simple;

my $owserver = OWNet->new( "localhost:2125" ) ;
print $owserver->read( "/28.9521EA030000/temperature" ) ."\n" ;
