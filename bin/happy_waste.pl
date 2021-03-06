#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            qw( max );
use Games::Lacuna::Client ();

my $rpcsleep = 2;

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  $cfg_file = eval{
    require File::HomeDir;
    require File::Spec;
    my $dist = File::HomeDir->my_dist_config('Games-Lacuna-Client');
    File::Spec->catfile(
      $dist,
      'login.yml'
    ) if $dist;
  };
  unless ( $cfg_file and -e $cfg_file ) {
    die "Did not provide a config file";
  }
}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	rpc_sleep => $rpcsleep,
	
	# debug    => 1,
);

# Load the planets
my $empire  = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

my $max_length = max map { length } keys %planets;

my @results = ( {
                  name      => "Name",
                  happy     => "Happiness",
                  happyhour => "Happy/hr",
                  waste     => "Waste",
                  wastehour => "Waste/hr",
                  wastecap  => "Waste Cap",
              } );

# Scan each planet
foreach my $name ( sort keys %planets ) {

    # Load planet data
    my $planet = $client->body( id => $planets{$name} );
    my $body   = $planet->get_status->{body};

    next if $body->{type} eq 'space station';

    push @results, {
        name      => $name,
        happy     => commify( $body->{happiness}),
        happyhour => commify( $body->{happiness_hour}),
        waste     => commify( $body->{waste_stored} ),
        wastehour => commify( $body->{waste_hour} ),
        wastecap  => commify( $body->{waste_capacity} ),
    };
}

my $max_name      = max map { length $_->{name} }      @results;
my $max_happy     = max map { length $_->{happy} }     @results;
my $max_happyhour = max map { length $_->{happyhour} } @results;
my $max_waste     = max map { length $_->{waste} }     @results;
my $max_wastehour = max map { length $_->{wastehour} } @results;
my $max_wastecap  = max map { length $_->{wastecap} }  @results;

#printf "%${max_name}s: %${max_happy}s @ %${max_happyhour}s/hr Waste: %${max_waste}s: @ %${max_wastehour}s/hr %${max_wastecap}s\n", "Happiness", "Happy/hr", "Waste", "Waste/hr", "Waste Cap";
for my $planet (@results) {
    printf "%${max_name}s: %${max_happy}s @ %${max_happyhour}s/hr | %${max_waste}s: @ %${max_wastehour}s/hr %${max_wastecap}s\n",
        $planet->{name},
        $planet->{happy},
        $planet->{happyhour},
        $planet->{waste},
        $planet->{wastehour},
        $planet->{wastecap};
}

sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $text;
}
