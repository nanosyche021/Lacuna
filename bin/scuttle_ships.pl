#!/usr/bin/env perl
#
#based on upgrade_all script and send_all script
#Thankyou Norway for the addition of the mass scuttle API call!


use strict;
use warnings;
use DateTime;
use Getopt::Long          (qw(GetOptions));
use List::Util            (qw(first));
use POSIX                  qw( floor );
use Time::HiRes            qw( sleep );
use Try::Tiny;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use JSON;
use Exception::Class;

my $login_attempts  = 5;
my $reattempt_wait  = 0.1;
my $hold=0;
my $combat=0;
my $stealth=0;
my $speed=0;
my @types;
my $noconfirm=0;

  our %opts = (
        v => 0,
        config => "lacuna.yml",
  );
  
GetOptions(\%opts,
    'types=s@'          => \@types,
    'speed=i'           => \$speed,
    'hold=i'            => \$hold,
    'combat=i'          => \$combat,
    'stealth=i'         => \$stealth,
    'planet=s@',
    'skip=s@',
    'noconfirm=i'        => \$noconfirm,
    'v|verbose',
);

  usage() if !@types;
  usage() if (!$combat && !$hold && !$stealth && !$speed);

  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config} || "lacuna.yml",
    rpc_sleep => $opts{sleep},
    # debug    => 1,
  );

  my $json = JSON->new->utf8(1);
  $json = $json->pretty([1]);
  $json = $json->canonical([1]);
  open(OUTPUT, ">", $opts{dumpfile}) || die "Could not open $opts{dumpfile} for writing";

  my $status;
  my $empire = $glc->empire->get_status->{empire};
  print "Starting RPC: $glc->{rpc_count}\n";

# Get planets
  my %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};
  $status->{planets} = \%planets;
  
  my $topok;
  my @plist = planet_list(\%planets, \%opts);

  my $pname;
    
$topok = eval {  
    for $pname (@plist) {
      print "Inspecting $pname\n";
      my $firstthemepark;
      my $planet    = $glc->body(id => $planets{$pname});
      my $result    = $planet->get_buildings;
      my $buildings = $result->{buildings};
      my $station = $result->{status}{body}{type} eq 'space station' ? 1 : 0;
      if ($station) {
        next;
      }
# Station and checking for resources needed.
      my ($sarr) = bstats($buildings);
      for my $bld (@$sarr) {
        my $ok;
        my $type = get_type_from_url($bld->{url});
        my $bldpnt = $glc->building( id => $bld->{id}, type => $type);
        if ($bld->{name} eq 'Space Port') {
          my @ships;
          $ok = eval {
            my $ships;
            $ships = $bldpnt->view_all_ships(
              {
                no_paging => 1,
              },
            )->{ships};
            print "Total of ", scalar @$ships, " found.\n";
            
            my $shiptypescount=0;
            for my $ship ( @$ships ) {
              next if @types && !grep { $ship->{type} eq $_ } @types;
              $shiptypescount = $shiptypescount + 1;
              if ($combat != 0) {
                if ($ship->{combat}<=$combat) {
                  push @ships, $ship->{id};
                }
              }
              elsif ($stealth != 0) {
                if ($ship->{stealth}<=$stealth) {
                  push @ships, $ship->{id};
                }
              }
              elsif ($hold != 0) {
                if ($ship->{hold_size}<=$hold) {
                  push @ships, $ship->{id};
                }
              }
              elsif ($speed != 0) {
                
                if ($ship->{speed}<=$speed) {
                  push @ships, $ship->{id};
                }
              }
            }
            print $shiptypescount," qualify for type.\n";            
            print scalar @ships," qualify criteria selected.\n";
            if (scalar @ships == 0) {
              no warnings;
              last;
            }            
            #ask for confirmation unless specifically set to false in options
            if ($noconfirm == 0) {
              my $conf = "N";
              print "Y to scuttle ships from $pname, N to skip.\n";
              $conf = <>;
              if ($conf =~ "Y") {
                #$build->{arch}->assemble_glyphs($build->{recipe}, $num_bld);
                $bldpnt->mass_scuttle_ship([@ships]);               
              }
              no warnings;
              last;
            }
            else {
              $bldpnt->mass_scuttle_ship([@ships]);
              no warnings;
              last;
            }
          };
          if (!$ok) {
            if ( $@ =~ "Slow down" ) {
              print "Gotta slow down... sleeping for 60\n";
              sleep(60);
            }               
            else {
              print "$@\n";
            }                          
          } 
          else {
            print scalar @ships," ships scuttled from $pname.\n";
          }
        }   
    }
  }
}; 
unless ($topok) {
  if ( $@ =~ "Slow down" ) {
    print "Gotta slow down... sleeping for 60\n";
    sleep(60);
  }
  else {
    print "$@\n";
  }
}   
   
 print OUTPUT $json->pretty->canonical->encode($status);
 close(OUTPUT);
 print "Ending   RPC: $glc->{rpc_count}\n";

exit;

sub planet_list {
  my ($phash, $opts) = @_;

  my @good_planets;
  for my $pname (sort keys %$phash) {
    if ($opts->{skip}) {
      next if (grep { $pname eq $_ } @{$opts->{skip}});
    }
    if ($opts->{planet}) {
      push @good_planets, $pname if (grep { $pname eq $_ } @{$opts->{planet}});
    }
    else {
      push @good_planets, $pname;
    }
  }
  return @good_planets;
}

sub bstats {
  my @sarr;
  my ($bhash) = @_;
  
  for my $bid (sort keys %$bhash) {
      my $doit = check_type($bhash->{$bid});
      if ($doit) {
        my $ref = $bhash->{$bid};
        $ref->{id} = $bid;
        push @sarr, $ref if ($ref->{efficiency} == 100);
      }
  }
  return (\@sarr);
}

sub check_type {
  my ($bld) = @_;
  
  print "Checking $bld->{name} - " if ($opts{v});
  if ($bld->{name} eq 'Space Port') {
    print "Adding to list!\n" if ($opts{v}); 
    return 1;
  }
  else {
    print "\n" if ($opts{v});
    return 0;
  }
}

sub sec2str {
  my ($sec) = @_;

  my $day = int($sec/(24 * 60 * 60));
  $sec -= $day * 24 * 60 * 60;
  my $hrs = int( $sec/(60*60));
  $sec -= $hrs * 60 * 60;
  my $min = int( $sec/60);
  $sec -= $min * 60;
  return sprintf "%04d:%02d:%02d:%02d", $day, $hrs, $min, $sec;
}

sub get_type_from_url {
  my ($url) = @_;

  my $type;
  eval {
    $type = Games::Lacuna::Client::Buildings::type_from_url($url);
  };
  if ($@) {
    print "Failed to get building type from URL '$url': $@";
    return 0;
  }
  return 0 if not defined $type;
  return $type;
}

sub request {
    my ( %params )= @_;
    
    my $method = delete $params{method};
    my $object = delete $params{object};
    my $params = delete $params{params} || [];
    
    my $request;
    my $error;
    
RPC_ATTEMPT:
    for ( 1 .. $login_attempts ) {
        
        try {
            $request = $object->$method(@$params);
        }
        catch {
            $error = $_;
            
            # if session expired, try again without a session
            my $client = $object->client;
            
            if ( $client->{session_id} && $error =~ /Session expired/i ) {
                
                warn "GLC session expired, trying again without session\n";
                
                delete $client->{session_id};
                
                sleep $reattempt_wait;
            }
            elsif ($error =~ /1010/) {
              print "Taking a break.\n";
              sleep 60;
            }
            else {
                # RPC error we can't handle
                # supress "exiting subroutine with 'last'" warning
                no warnings;
                last RPC_ATTEMPT;
            }
        };
        
        last RPC_ATTEMPT
            if $request;
    }
    
    if (!$request) {
        warn "RPC request failed $login_attempts times, giving up\n";
        die $error;
    }
    
    return $request;
}

sub usage {
    diag(<<END);
Usage: $0 [options]

This program will scuttle ships on all your planets below OR EQUAL
to a certain hold size, combat level, or stealth level.  If you
use multiple criteria such as stealth and combat, it will scuttle 
ships that are below that stealth OR combat.

Options:
  --help             - This info.
  --verbose          - Print out more information
  --planet           - list of planets to scuttle from, if omitted
                       all planets will be enumerated through
  --skip             - list of planets to skip
  --hold             - scuttle ships lower than this hold size
  --combat           - scuttle ships lower than this combat level
  --stealth          - scuttle ships lower than this stealth level
  --speed            - scuttle ships lower than this speed
  --types            - an array of ship types to scuttle
                       ex: snark3, supply_pod2, placebo5
  --noconfirm        - Will scuttle ships without confirmation for
                       each planet if set to 1                
  );
END
  exit 1;
}

sub verbose {
    return unless $opts{v};
    print @_;
}

sub output {
    return if $opts{q};
    print @_;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}

sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}
