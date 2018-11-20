# CLI getopts and validation
#
# vim: ts=4 sts=4 et sw=4 ft=perl
#
package shellModules::cliHelper;

use strict;
use warnings;

use Getopt::Std;
use Term::ReadKey;
use Term::ReadLine;
use Data::Dumper;

my $IPV4_RE = qr/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;

# 
# usage(msg, [dont_die])
# Print CLI arg usage and then exit with msg
# acts as help if dont_die=0
#
sub usage {
    my $self = shift;
    my $msg = shift || "";
    my $dont_die = shift || 0;
    
    print "\n";
    print "Usage: $0 [options] [MM ipaddr]\n";
    print "\n";
    print "Options:\n";
    print "     -s <file>        file of standalone name,ipaddr to connect to\n";
    print "     -u <username>    Specify ssh/webui username, default is admin\n";
    print "     -p <password>    Specify ssh/webui password, else will be prompted\n";
    print "     -d N             enable debug trace level N (0 to 5)\n";
    print "\n";
    print "Standalone:\n";
    print "     Create a file with individual standalone controllers, one per line\n";
    print "\n";
    print "     example:\n";
    print "           mc01,1.2.3.4\n";
    print "           mc02,5.6.7.8\n";
    print "\n";

    die($msg . "\n\n") if $dont_die == 0;
    exit(1);
}

#
# new()
# 
sub new {
    my $class = shift;
    my $self = { };
    
    $self->{opts} = {};
    getopts("hs:u:p:d:", $self->{opts});

    # put bare MM into opts if it exists
    $self->{opts}{mm} = pop(@ARGV);

    bless $self, $class;
    return $self;
}

#
# validate()
# check and validate the things passed to getopts in new()
#
sub validate {
    my $self = shift;
    my $opts = $self->{opts};

    # deal with help first
    if (defined($opts->{h})) {
        $self->usage("", 1);
    }

    # Either we got an MM IP, or standalone file, or the user gives an MM IP
    if (defined($opts->{mm})) {
        if (defined($opts->{s})) {
            $self->usage("Error: can't specify -s <ipaddr> and MM IP address together");
        }
        if ($opts->{mm} !~ /$IPV4_RE/) {
            $self->usage("Error: MM IP address $opts->{mm} is invalid");
        }
    }
    elsif (not defined($opts->{s})) {
        $self->ask_mm_ip();
    }
    elsif (defined($opts->{s})) {
        if (not -e $opts->{s}) {
            $self->usage("Error: standalone file $opts->{s} does not exist");
        }
    }

    # verify debug level
    if (defined($opts->{d})) {
        if (($opts->{d} =~ /\D/) || ($opts->{d} < 0) || ($opts->{d} > 5)) {
            $self->usage("Error: Invalid debug value, choose 0 to 5");
        }
    }

    # set default username
    if (not defined($opts->{u})) {
        $opts->{u} = "admin";
    }
    if (not defined($opts->{p})) {
        $self->request_creds();
    }

    # dump state for debugging
    $self->_dump();
}

#
# _dump
# print debug state/dump
#
sub _dump {
    my $self = shift;
    if ((defined $self->{opts}{d}) and ($self->{opts}{d} > 4)) {
        print("\n---------cli-------------\n");
        print(Dumper($self) . "\n");
        print("\n-------------------------\n");
    }
}

# 
# ask_mm_ip
# Ask for an MM ip from STDIN, validate it
#
sub ask_mm_ip {
    my $self = shift;
    my $opts = $self->{opts};
    my $mm_ip;
    my $ok = 0;

    while ($ok == 0) {
        print "MM IP address: ";
        $mm_ip = <STDIN>;
        chomp($mm_ip);
        if ($mm_ip !~ /$IPV4_RE/) {
            print "Invalid MM IP address entered\n";
        }
        else {
            $ok = 1;
        }
    }
    $opts->{mm} = $mm_ip;
}

#
# get_mm_ip
# return the mm ip if defined
#
sub get_mm_ip {
    my $self = shift;
    my $opts = $self->{opts};
    if (defined($opts->{mm})) {
        return $opts->{mm};
    }
    else {
        die("Cannot get mm IP if it's not defined in opts\n");
    }
}

# 
# is_standalone
# return 1 if operating with a standalone file
#
sub is_standalone {
    my $self = shift;
    my $opts = $self->{opts};
    return defined($opts->{s}) ? 1 : 0;
}

#
# read_standalone_file(\%device)
# read the standalone file into device hash ref
#
sub read_standalone_file {
    my $self = shift;
    my $opts = $self->{opts};

    my $devices = shift;
    if (not $self->is_standalone()) {
        die("Not operating in standalone mode");
    }

    # file existance is checked in validate()
    open(FIC, $opts->{s});
    foreach my $line (<FIC>){
        chomp($line);
        my @a = split(",", $line);
        $devices->{'/md/' . $a[0]}{name} = $a[0];
        $devices->{'/md/' . $a[0]}{ctrl_ip} = $a[1];
    }
    close(FIC);
}

#
# request_creds
# Request user credentials for both SSH and WebUI_API
#
sub request_creds {
    my $self = shift;
    my $opts = $self->{opts};
    my $ok = 0;

    while ($ok == 0) {
        print "Please input your credentials.\n";
        print "Username [$opts->{u}]: ";
        my $us = <STDIN>;
        chomp($us);
        if ($us ne ""){ $opts->{u} = $us; }
    
        print "Password: ";
        ReadMode 2;
        my $pass = <STDIN>;
        ReadMode 0;
        chomp($pass);
        if ($pass eq "") { 
            print "Empty password, try again...\n"; 
        }
        else {
            $opts->{p} = $pass;
            $ok = 1;
        }
    }
}

# 
# get_username_password(\$u, \$p)
# store username and password into refs
#
sub get_username_password {
    my $self = shift;
    my $u_ref = shift;
    my $p_ref = shift;
    my $opts = $self->{opts};
    $$u_ref = $opts->{u};
    $$p_ref = $opts->{p};
}

#
# get_dbg_level
# return the debug level
#
sub get_dbg_level {
    my $self = shift;
    my $opts = $self->{opts};
    return $opts->{d} || 0;
}

1;
