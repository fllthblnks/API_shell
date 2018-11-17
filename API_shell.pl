#!/usr/bin/perl
# ArubaOS 8.0 API Shell

use strict;
use warnings 'all';
use JSON;		        # Needs to be installed
use Data::Dumper;
if($^O ne "MSWin32"){
    use Net::SSH::Perl;		# Needs to be installed
}
use Term::ReadKey;
#use LWP::UserAgent;		# Needs to be installed
use Term::ReadLine;
use POSIX;
use lib '.';
use shellModules::DispManager;
use shellModules::connManager;
use shellModules::Plotter;
use Chart::Gnuplot;		# Needs to be installed
use Date::Parse;

# Other required modules
# LWP::Protocol::https
# LWP::UserAgent


use Time::HiRes qw(time);

use constant DATETIME => strftime("%Y-%m-%d_%H-%M-%S", localtime);

my $mm_ip;
my $standalone_mode = 0;


if(defined($ARGV[0])){ 
    if($ARGV[0] eq "-s"){
        $standalone_mode = 1;
        &read_standalone($ARGV[1]);
    }else{
        $mm_ip = $ARGV[0];
    }
}else{
    print "MM IP address: ";
    $mm_ip = <STDIN>;
    chomp($mm_ip);
}

my $version = "0.4";
my $username   = "admin";
my $password   = "";
my $path_suffix = "v1/configuration/object/";
my $cookie_file = "cookie.dat";

my $dbg = 0;
my %UID;
my %devices;
my $now; 
my $cur_path = '/md';


my %raw_data;


&request_creds;



# dbg level > 5 will set tracing in connManager for request/response
my $api_int = shellModules::connManager->new($username, $password, $path_suffix, $cookie_file, $dbg);


if($standalone_mode == 1){


}else{


# Get MM's hostname
    my %tmp = %{decode_json(&exec(method     => 'GET',
                ctrl_ip         => $mm_ip,
                command_url => 'hostname'))};

    $devices{'/mm/mynode'}{Name} = $tmp{"_data"}{"hostname"}{"hostname"};

    &decode_hierarchy(&exec(method     => 'GET',
                ctrl_ip         => $mm_ip,
                command_url => 'node_hierarchy'), '');


    &update_switches();

    &get_time_offset();
    &get_debugged_users();
}

print "\n\nWelcome to API_shell v$version\n";
print "Send feedback to Guillaume Germain (ggermain at hpe.com)\n";
if($standalone_mode == 1){
    print "Running in standalone mode\n";
}else{
}

&display_dashboard();

print "\n";

my $term = new Term::ReadLine 'API_shell';



# Step into the main loop
while(1){
    my $prompt = "API_shell $cur_path> ";
    my $cmd = $term->readline($prompt);

    if($cmd eq "" || $cmd eq " "){ next; }

    &update_switches();

    if($cmd =~ s/ssh//){ &start_ssh($cmd); 
}elsif($cmd =~ s/^cd //){ $cur_path = $cmd; &get_debugged_users();
}elsif($cmd eq "exit"){ exit; 
}elsif($cmd =~ s/^find_ap //){ &find_AP($cmd);
}elsif($cmd =~ s/^find_user_mac //){ &find_User($cmd, 'mac-addr');
}elsif($cmd eq "plot"){ &plot_image(); 
}elsif($cmd eq "show tech-support"){ 
    if($^O eq "MSWin32"){
        print "Sorry, this function is not supported on Windows\n";
    }else{
        $now = DATETIME; 
        &grab_show_tech();	
    }
}
else{

    if($cmd =~ /ap-name (\S+)/){
        &decode_command(&get_command(ctrl_ip => [&find_AP($1)],
                    cmd     => $cmd));
    }elsif($cmd =~ /client-mac (\S+)/){
        &decode_command(&get_command(ctrl_ip => [&find_User($1, 'mac-addr', 'Current switch')],
                    cmd     => $cmd));

    }else{
        &decode_command(&get_command(ctrl_ip => [&ip_list_by_path()],
                    cmd     => $cmd));


    }
}
}



sub ip_list_by_path{
    my $arg = shift;
    my $path = $cur_path;

    if(defined($arg)){
        $path = $arg;
    }


    my @ips;

    &debug("Building IP list based on $path", 3);

    foreach my $k (keys %devices){
        if($k =~ /$path/){
            if($devices{$k}{Status} eq "up"){
                push(@ips, $devices{$k}{ctrl_ip});
                &debug("Added host $devices{$k}{ctrl_ip}", 3);
            }
        }
    }

    if(@ips == 0){
        print "No MD's currently up\n";
    }

    return @ips;	
}


sub fork_show_tech{
    my $ctrl_ip = shift;

    if(!defined($ctrl_ip)){ return; }

    print $ctrl_ip . "\n";
    print Dumper &exec(method     => 'GET',
                ctrl_ip         => $ctrl_ip,
                full_url => '/screens/cmnutil/execFPCliCommand.xml?show%20tech-support-web-hook'); 

    return;
}



sub grab_show_tech{
    my $ctrl_ip = shift;

    `mkdir -p ./show_tech`;


    my @ips;
    push(@ips, $mm_ip);

    foreach my $dev (keys %devices){
        push(@ips, $devices{$dev}{ctrl_ip});
    }

    print "Fetching show-tech from " .  ($#ips+1) . " controllers in the background.\n";

    foreach my $ip (@ips){
        my $pid = fork();
        if($pid == 0){
            &fork_show_tech($ip);
            exit;
        }
    }


}




sub start_ssh{
    my $name = shift;
    my $ip = $mm_ip;
    $name =~ s/^\ //;

    if(defined($name)){
        foreach my $dev (keys %devices){
            if($devices{$dev}{Name} eq $name){
                $ip = $devices{$dev}{ctrl_ip};
            }
        }
    }


    if($^O ne "MSWin32"){

        my $ssh = Net::SSH::Perl->new($ip, use_pty => 1, cipher => "aes256-cbc", mac => "hmac-sha1-96", options => [ "MACs +hmac-sha1" ], protocol => 2);

        $ssh->login($username, $password);


        use Term::ReadKey;
        ReadMode('raw');
        $ssh->shell;
        ReadMode('restore');
        print "\n";
    }else{
        print "Sorry, this function is not supported on Windows\n";
    }

}






sub decode_hierarchy{
    my $json = shift;	
    my $current_path = shift;

    my %hier = %{decode_json($json)};


    if($hier{name} eq '/'){
        $current_path = '/';
    }elsif($current_path eq '/'){
        $current_path .= $hier{name};
    }else{
        $current_path .= '/' . $hier{name};
    }


    my @childnodes = @{$hier{childnodes}};

    foreach my $cn (@childnodes){

        &decode_hierarchy(encode_json($cn), $current_path);
    }

    my @devices = @{$hier{devices}};


    foreach my $dv (@devices){
        &decode_hierarchy_device(encode_json($dv), $current_path);
    }


}

sub decode_hierarchy_device{
    my $jso = shift;
    my $current_pat = shift;
    my %dev = %{decode_json($jso)};

# Skip MMs
#if($current_pat eq "/mm"){ return; }

    $devices{$current_pat . '/' . $dev{mac}}{mac}    = $dev{mac};
    $devices{$current_pat . '/' . $dev{mac}}{type}   = $dev{type};
    $devices{$current_pat . '/' . $dev{mac}}{Name}   = $dev{name};
    $devices{$current_pat . '/' . $dev{mac}}{Status} = "down";


}




# Request user credentials for both SSH and WebUI_API
sub request_creds{
    if($password eq ""){
        print "\nPlease input your credentials.\n";
        print "Username [$username]: ";
        my $us = <STDIN>;
        chomp($us);
        if($us ne ""){ $username = $us; }

        print "Password: ";
        ReadMode 2;
        $password = <STDIN>;
        ReadMode 0;
        chomp($password);
    }



}

sub display_dashboard(){

    my %cpu = %{&get_command(ctrl_ip => [&ip_list_by_path('/')],
            cmd     => 'show cpuload')};

    my %mem = %{&get_command(ctrl_ip => [&ip_list_by_path('/')],
            cmd     => 'show memory')};

    my @meta = ("IP Address", "Name", "Type", "Model", "Version", "Status", "Configuration State", "Config ID", "CrashInfo", "TimeOffset", "CPU", "MEM");
    my @data;
    my @ctrl;

    foreach my $dev_path (keys %devices){
        if($devices{$dev_path}{Status} eq "up"){
# Process cpuload info for controller
            my %cpu_res = %{decode_json($cpu{out}{$devices{$dev_path}{ctrl_ip}})};
            my @cpu_perc = split(" ", $cpu_res{'_data'}[0]);
            $cpu_perc[5] =~ s/\%//;
            $devices{$dev_path}{CPU} = sprintf("%.1f", (100 - $cpu_perc[5])) . '%';


# Process memory info for controller
            my %mem_res = %{decode_json($mem{out}{$devices{$dev_path}{ctrl_ip}})};
            $mem_res{'_data'}[0] =~ s/\,//ig;
                my @mem_out = split(" ", $mem_res{'_data'}[0]);
            my $mem_perc = sprintf("%.1f", $mem_out[5] / $mem_out[3] * 100) . "%";
            $devices{$dev_path}{MEM} = $mem_perc;
        }



        my %f = %{$devices{$dev_path}};
        push(@data, \%f);

    }


# Print the data
    shellModules::DispManager->print_header_and_table(\@meta, \@data, [], \%raw_data);


}


sub find_User(){
    my $info = shift;
    my $info_type = shift;
    my $info_needed = shift;

    my $cmd = "show global-user-table list $info_type $info";


    &debug("Searching for user $info", 2);
    my %res = %{&get_command(ctrl_ip => [$mm_ip],
            cmd     => $cmd)};

    my %result = %{decode_json($res{out}{$mm_ip})};


    my @user_list = @{$result{"Global Users"}};

    for(my $i = 0; $i < @user_list; $i++){
        my %user = %{$user_list[$i]};

        foreach  my $k (keys %user){
            if(!defined($user{$k})){ next; }
            if($info eq $user{$k}){
                return $user{$info_needed};
            }
        }

    }

    print "Unable to find user " . $info . " on MM\n\n";
    return;
}


sub update_switches(){
    my %result_sw_debug = %{&get_command(ctrl_ip => [$mm_ip],
            cmd	    => 'show switches debug')};

    my %result_sw = %{&get_command(ctrl_ip => [$mm_ip],
            cmd         => 'show switches')};

    my %res_sw_debug = %{decode_json($result_sw_debug{out}{$mm_ip})};
    my %res_sw       = %{decode_json($result_sw{out}{$mm_ip})};

    my @tmp_res_debug = @{$res_sw_debug{"All Switches"}};
    my @tmp_res = @{$res_sw{"All Switches"}};

# Pull out data from array and put in hash named with IP Address
    my %d;	
    for(my $i = 0; $i < @tmp_res; $i++){
        my %t = %{$tmp_res[$i]};

        $d{$t{"Name"}} = \%t;
    }
    for(my $i = 0; $i < @tmp_res_debug; $i++){
        my %t = %{$tmp_res_debug[$i]};
        foreach my $k (keys %t){
            $d{$t{"Name"}}{$k} = $t{$k};
        }
    }


    foreach my $dev (keys %devices){
        my $name = $devices{$dev}{Name};


        foreach my $field (("Model", "Version", "Status", "IP Address", "CrashInfo", "Config ID", "Configuration State", "Type")){
            if(defined($d{$name}{$field})){
                $devices{$dev}{$field} = $d{$name}{$field};
            }else{
                if($field ne "Status"){	$devices{$dev}{$field} = " "; }
            }
        }

        $devices{$dev}{ctrl_ip} = $d{$name}{"IP Address"};

        &debug("Added device " . $name . " to devices with status " . $devices{$dev}{Status}, 3);

    }


}


sub find_AP(){
    my $ap_name = shift;

    my %result = %{&get_command(ctrl_ip => [$mm_ip],
            cmd     => "show ap database | include $ap_name")};




    my %res = %{decode_json($result{out}{$mm_ip})};


    my @ap_list = @{$res{"AP Database"}};			


    for(my $i = 0; $i < @ap_list; $i++){
        my %ap = %{$ap_list[$i]};


        if($ap_name eq $ap{Name}){
            if($ap{Status} =~ /^Up/){
                &debug("Found AP $ap_name at " . $ap{"Switch IP"}, 2);
                return $ap{"Switch IP"};
            }else{
                print "AP $ap_name has status " . $ap{Status} . "\n";
                return;
            }
        }	
    }

    print "Can't find AP $ap_name \n";
    return;
}

sub get_command(){
    my (%argu) = @_;	


    $argu{cmd} =~ s/\s/\+/ig;

    my @ips = @{$argu{ctrl_ip}};

    if(scalar(@ips) == 0){
        return;
    }

    my %cmd_result;
    $cmd_result{cmd} = $argu{cmd};

    my @kids;



    for(my $i = 0; $i < @ips; $i++){
        my $pid = open($kids[$i], "-|");

        if(!defined($pid)){
            die "Failed to fork: $!";
        }

        if(!$pid){
# CHILD

            my $time_before = time;

            my $curl_output = $api_int->request(ctrl_ip => $ips[$i], 
                    cmd     => $argu{cmd});	

# printing to FH and adding controller IP at the end of the string
            print $curl_output . "CTRL_IP=$ips[$i] ";

            &debug("Fetching " . $argu{cmd} . " from " . $ips[$i], 2);

            &debug("Command took " . (time - $time_before) . " seconds to run", 3);
            exit;
        }


    }

    foreach my $fh (@kids){
        my @lines = <$fh>;
        my $line = join('', @lines);

# Removing Controller IP at the end of the string
        $line =~ s/CTRL_IP=([^\s]+) //;
        my $ip = $1;
        $cmd_result{out}{$ip} = $line;
    }



    return \%cmd_result;
}

sub decode_command(){
    shellModules::DispManager->print_cmd(shift(), \%raw_data);


}





# Execute command on device
sub exec(){
    my (%argu) = @_;
    my $curl_output;



    my $time_before = time;

    $curl_output = $api_int->request(%argu);

    return $curl_output;


}


sub debug(){
    my $txt = shift;
    my $lvl = shift;

    if($dbg > $lvl){
        print STDERR "DEBUG: " . $txt . "\n";
    }

}



sub get_debugged_users{

    my %r = %{decode_json(&exec(command_url => 'log_lvl_user_debug',
                ctrl_ip => $mm_ip,
                config_path => $cur_path,
                method => 'GET'))};

    if(defined($r{'_data'}{'log_lvl_user_debug'})){

        my @user_list = @{$r{'_data'}{'log_lvl_user_debug'}};

        for(my $i = 0; $i < @user_list; $i++){
            my %s = %{$user_list[$i]};

            if($s{log_lvl} eq "debugging"){
                $raw_data{$s{mac}}{type} = 'debugged user';
            }
        }
    }
}


sub read_standalone(){
    my $file;

    if(defined($_[0])){
        $file = $_[0];
    }else{
        $file = "standalone_ip_list";
    }

    open(FIC, $file);

    foreach my $line (<FIC>){
        chomp($line);
        my @a = split(",", $line);
        $devices{'/md/' . $a[0]}{Name} = $a[0];
        $devices{'/md/' . $a[0]}{ctrl_ip} = $a[1];
    }

    close(FIC);



}


sub plot_image(){

    my $pid = fork();
    if($pid == 0){

        my $GG = shellModules::Plotter->new();

        for(my $i = 0; $i < 120; $i++){
            my %cpu = %{&get_command(
                    ctrl_ip => [$mm_ip],
                    cmd     => 'show cpuload'
                    )};


# Process cpuload info for controller
            my %cpu_res = %{decode_json($cpu{out}{$mm_ip})};
            my @cpu_perc = split(" ", $cpu_res{'_data'}[0]);
            $cpu_perc[5] =~ s/\%//;

            $GG->addData(sprintf("%.1f", (100 - $cpu_perc[5])));
            $GG->printData();
            $GG->generateImage();

            sleep 1;

        }


        exit;
    }


}


# Provides clock offset between controllers and the host that is running API_shell
sub get_time_offset(){

    my %cmd_tme = %{&get_command(ctrl_ip => [&ip_list_by_path('/')],
            cmd     => 'show clock')};

    foreach my $dev_path (keys %devices){
        if($devices{$dev_path}{'Status'} ne "up"){ next; }

        my %res = %{decode_json($cmd_tme{out}{$devices{$dev_path}{ctrl_ip}})};

        my $ctrl_dtime = $res{'_data'}[0];

        &debug("Current time at controller " . $devices{$dev_path}{ctrl_ip} . " is " . $ctrl_dtime . " and time offset is " . (str2time($ctrl_dtime) - time), 3);

        $devices{$dev_path}{TimeOffset} = sprintf("%.1f", str2time($ctrl_dtime) - time);		

    }

}

