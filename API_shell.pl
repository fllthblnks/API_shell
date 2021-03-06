#!/usr/bin/perl
# ArubaOS 8.0 API Shell
#
# vim: ts=4 sts=4 et sw=4 ft=perl
#

use strict;
use warnings 'all';
use Data::Dumper;
use Term::ReadKey;
use Term::ReadLine;
use POSIX;
use lib '.';
use shellModules::dispManager;
use shellModules::connManager;
use shellModules::plotter;
use shellModules::cliHelper;
use Date::Parse;
use IO::Compress::Gzip qw(gzip $GzipError);
use Time::HiRes qw(time);
use File::Path qw(make_path);

use JSON;               # Needs to be installed
if($^O ne "MSWin32"){
    use Net::SSH::Perl;     # Needs to be installed
}


# Other required modules
# LWP::Protocol::https
# LWP::UserAgent
# Char::Gnuplot (optional)


use constant DATETIME => strftime("%Y-%m-%d_%H-%M-%S", localtime);


# Global CLI object. Put new user related globals in this
my $cli = shellModules::cliHelper->new();
$cli->validate();


my $version = "0.4.2";
my $path_suffix = "v1/configuration/object/";
my $cookie_file = "cookie.dat";

my %UID;
my %devices;
my $now; 
my $cur_path = '/md';
my %raw_data;

my $username;
my $password;
$cli->get_username_password(\$username, \$password);



# dbg level > 5 will set tracing in connManager for request/response
my $api_int = shellModules::connManager->new($username, $password, $path_suffix, $cookie_file, $cli->get_dbg_level());


if($cli->is_standalone()){
    # Standalone mode
    $cli->read_standalone_file(\%devices);
    #print(Dumper(\%devices));

}
else{
    # MM Mode

    &update_switches();
    &get_time_offset();
    &get_debugged_users();
}

print "\n\nWelcome to API_shell v$version\n";
print "Send feedback to Guillaume Germain (ggermain at hpe.com)\n";
if($cli->is_standalone()){
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

    next if not defined($cmd);
    if($cmd eq "" || $cmd eq " "){ next; }

    &update_switches();

    if($cmd =~ s/ssh//){ &start_ssh($cmd); 
}elsif($cmd =~ s/^cd //){ $cur_path = $cmd; &get_debugged_users();
}elsif($cmd eq "exit"){ exit; 
}elsif($cmd =~ s/^find_ap //){ &find_AP($cmd);
}elsif($cmd =~ s/^find_user_mac //){ &find_User($cmd, 'mac-addr');
}elsif($cmd eq "api_shell plot"){ &plot_image(); 
}elsif($cmd eq "show tech-support"){ print "You should use 'api_shell get logs' instead.\n"; next; 
}elsif($cmd =~ /^api_shell/){
    if($cmd eq "api_shell get logs"){
        $now = DATETIME; 
        &grab_show_tech();
    }elsif($cmd =~ /api_shell get crash/){
        $now = DATETIME;
        &grab_crash();
    }elsif($cmd =~ /api_shell dashboard/){
        &display_dashboard($cmd);
    }
    else{
        print "Unknown api_shell command.\n";
        print "Currently supported:\n";
        print "\tapi_shell dashboard\n";
        print "\tapi_shell dashboard all\n";
        print "\tapi_shell get logs\n";
        print "\tapi_shell get crash\n";
    }
}
else{

    if($cmd =~ /ap-name (\S+)/){
        &decode_command(&get_command(
                    ctrl_ip => [&find_AP($1)],
                    cmd     => $cmd
                    ));
    }elsif($cmd =~ /client-mac (\S+)/){
        &decode_command(&get_command(
                    ctrl_ip => [&find_User($1, 'mac-addr', 'Current switch')],
                    cmd     => $cmd
                    ));

    }else{
        &decode_command(&get_command(
                    ctrl_ip => [&ip_list_by_path()],
                    cmd     => $cmd
                    ));


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


sub fork_get_crash{
    my $ctrl_ip = shift;

    if(!defined($ctrl_ip)){ return; }

    &get_command(ctrl_ip => [$ctrl_ip],
                 cmd     => 'tar crash');

    my $logs = $api_int->request(
            ctrl_ip     => $ctrl_ip,
            full_url    => 'screens/cmnutil/crash.tar',
            method      => 'POST',
            'content-type' => 'application/x-www-form-urlencoded',
            args        => [ 'operand' => '', operand2 => 'get-crash', operand3 => 'tech-support'],
            exclude_UID => 1
            );

    make_path("crash_files");

    my $filename = "./show_tech/tar_crash_" . $now . "_" . $ctrl_ip . ".tar.gz";

    my $z = new IO::Compress::Gzip($filename) or die "$ctrl_ip gzip failed: $GzipError\n";   

    $z->write($logs);
    $z->close();

    print "$ctrl_ip crash dump succesfully fetched (" . length($logs) . " bytes)\n";
}


sub fork_show_tech{
    my $ctrl_ip = shift;

    if(!defined($ctrl_ip)){ return; }

    my $out = $api_int->request(
            ctrl_ip     => $ctrl_ip,
            full_url    => 'screens/cmnutil/execFPCliCommand.xml?show%20tech-support-web-hook'
            ); 


    if($out =~ /SUCCESS/){
        my $logs = $api_int->request(
                ctrl_ip     => $ctrl_ip,
                full_url    => 'screens/cmnutil/log-download.tar',
                method      => 'POST',
                'content-type' => 'application/x-www-form-urlencoded',
                args        => [ 'operand' => '', operand2 => 'get-logs', operand3 => 'tech-support'],
                exclude_UID => 1
                ); 

        make_path("show_tech");

        my $filename = "./show_tech/tar_logs_" . $now . "_" . $ctrl_ip . ".tar.gz";


        my $z = new IO::Compress::Gzip($filename) or die "$ctrl_ip gzip failed: $GzipError\n";   

        $z->write($logs);
        $z->close();

        print "$ctrl_ip logs succesfully fetched (" . length($logs) . " bytes)\n";
    }else{
        print "$ctrl_ip unable to fetch the logs\n";
    }
    return;
}



sub grab_show_tech{
    my $ctrl_ip = shift;

    `mkdir -p ./show_tech`;


    my @ips = &ip_list_by_path();


    print "Fetching logs from devices in $cur_path (" .  ($#ips+1) . " devices). Please wait... This will take a while.\n";

    my @kids;

    for(my $i = 0; $i < @ips; $i++){
        my $pid = open($kids[$i], "-|");
        if($pid == 0){
            &fork_show_tech($ips[$i]);
            exit;
        }
    }

    foreach my $fh (@kids){
        my @lines = <$fh>;
        print @lines;
    }

    return;
}



sub grab_crash{
    my $ctrl_ip = shift;

    &update_switches;
    
    `mkdir -p ./crash_files`;


    my @ips;

    foreach my $p (keys %devices){
        if($devices{$p}{CrashInfo} eq "yes"){
            push(@ips, $devices{$p}{ctrl_ip});
            &debug("Added $p $devices{$p}{ctrl_ip} to list of controllers", 3);       
        }
    }

    if(!@ips){
        print "No crash files on controllers\n";
        return;
    }

    print "Fetching crash dump from devices in $cur_path (" .  ($#ips+1) . " devices). Please wait... This will take a while.\n";

    my @kids;

    for(my $i = 0; $i < @ips; $i++){
        my $pid = open($kids[$i], "-|");
        if($pid == 0){
            &fork_get_crash($ips[$i]);
            exit;
        }
    }

    foreach my $fh (@kids){
        my @lines = <$fh>;
        print @lines;
    }

    return;
}



sub start_ssh{
    my $name = shift;
    my $ip = $cli->get_mm_ip();
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





sub display_dashboard(){


    my %cpu = %{&get_command(ctrl_ip => [&ip_list_by_path('/')],
            cmd     => 'show cpuload')};

    my %mem = %{&get_command(ctrl_ip => [&ip_list_by_path('/')],
            cmd     => 'show memory')};

    my @meta = ("IP Address", "Name", "Type", "Model", "Version", "Status", "Configuration State", "CrashInfo", "TimeOffset", "CPU", "MEM");

    if(defined($_[0])){
        if($_[0] =~ /all/){
            @meta = ("IP Address", "MAC", "Name", "Nodepath", "Type", "Location", "Model", "Version", "Status", "Uptime", "Configuration State", "Config ID", "CrashInfo", "Config Sync Time (sec)", "TimeOffset", "CPU", "MEM");
        }
    }    

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
    shellModules::dispManager->print_header_and_table(\@meta, \@data, [], \%raw_data);


}


sub find_User(){
    my $info = shift;
    my $info_type = shift;
    my $info_needed = shift;

    my $cmd = "show global-user-table list $info_type $info";


    &debug("Searching for user $info", 2);
    my %res = %{&get_command(
            ctrl_ip => [$cli->get_mm_ip()],
            cmd     => $cmd
            )};

    my %result = %{decode_json($res{out}{$cli->get_mm_ip()})};


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
    my %result_sw_debug = %{&get_command(
            ctrl_ip => [$cli->get_mm_ip()],
            cmd	    => 'show switches debug'
            )};

    my %result_sw = %{&get_command(
            ctrl_ip => [$cli->get_mm_ip()],
            cmd         => 'show switches'
            )};

    my %res_sw_debug = %{decode_json($result_sw_debug{out}{$cli->get_mm_ip()})};
    my %res_sw       = %{decode_json($result_sw{out}{$cli->get_mm_ip()})};

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


    foreach my $name (keys %d){
        my $dev = $d{$name}{Nodepath};
        if($dev !~ /\/mm/){
            $dev .= "/" . $name;
        }


        foreach my $field (("IP Address", "MAC", "Name", "Nodepath", "Type", "Location", "Model", "Version", "Status", "Uptime", "Configuration State", "Config ID", "CrashInfo", "Config Sync Time (sec)")){
            if(defined($d{$name}{$field})){
                $devices{$dev}{$field} = $d{$name}{$field};
            }else{
                if($field ne "Status"){	$devices{$dev}{$field} = " "; }
            }
        }

        $devices{$dev}{ctrl_ip} = $d{$name}{"IP Address"};

        &debug("Added device " . $name . " to devices (" . $dev . ") with status " . $devices{$dev}{Status}, 3);

    }


}


sub find_AP(){
    my $ap_name = shift;

    my %result = %{&get_command(
            ctrl_ip => [$cli->get_mm_ip()],
            cmd     => "show ap database | include $ap_name"
            )};


    my %res = %{decode_json($result{out}{$cli->get_mm_ip()})};


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
    shellModules::dispManager->print_cmd(shift(), \%raw_data);


}




sub debug(){
    my $txt = shift;
    my $lvl = shift;

    if($cli->get_dbg_level() > $lvl){
        print STDERR "DEBUG: " . $txt . "\n";
    }

}



sub get_debugged_users{

    my %r = %{decode_json($api_int->request(
                command_url => 'log_lvl_user_debug',
                ctrl_ip     => $cli->get_mm_ip(),
                config_path => $cur_path,
                method      => 'GET'
                ))};

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


sub plot_image(){
    print "Input command to plot: ";
    my $cmd = <STDIN>;
    chomp($cmd);


    my $plott = shellModules::plotter->new();


    my %out = shellModules::dispManager->merge_data(
            &get_command(
                ctrl_ip => [&ip_list_by_path()],
                cmd     => $cmd
                ), \%raw_data);



    if(@{$out{meta}} == 0 ){
        print "This command cannot be plotted as it outputted as pure text from the API and does not include JSON formatted data\n";
        return;

    }

    open(OUT, ">./plot_config.txt");

    print OUT "## $cmd\n#\n"; 
    print OUT "## Sampling Interval\n";
    print OUT "1\n\n";
    print OUT "## Number of samples\n";
    print OUT "120\n\n";
    print OUT "## Uncomment the line of the columns you want to plot on the graph. Column needs to contain a numerical value.\n";
    print OUT "## Columns\n";
    foreach my $i (@{$out{meta}}){
        print OUT "#" . $i . "\n";
    }

    print OUT "\n\n";
    print OUT "## Data to filter on. You probably want to MAC addresses or IP addresses here. Put one per line\n";
    print OUT "## Filters\n\n";



    close(OUT); 

    system("nano plot_config.txt");



    my $pid = fork();
    if($pid == 0){


        for(my $i = 0; $i < 120; $i++){
            my %cpu = %{&get_command(
                    ctrl_ip => [$cli->get_mm_ip()],
                    cmd     => $cmd
                    )};


# Process cpuload info for controller
            my %cpu_res = %{decode_json($cpu{out}{$cli->get_mm_ip()})};
            my @cpu_perc = split(" ", $cpu_res{'_data'}[0]);
            $cpu_perc[5] =~ s/\%//;

            $plott->addData(sprintf("%.1f", (100 - $cpu_perc[5])));
            $plott->printData();
            $plott->generateImage();

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

        &debug("Fetching time from " . $devices{$dev_path}{ctrl_ip}, 5);
        my %res = %{decode_json($cmd_tme{out}{$devices{$dev_path}{ctrl_ip}})};

        my $ctrl_dtime = $res{'_data'}[0];

        &debug("Current time at controller " . $devices{$dev_path}{ctrl_ip} . " is " . $ctrl_dtime . " and time offset is " . (str2time($ctrl_dtime) - time), 3);

        $devices{$dev_path}{TimeOffset} = sprintf("%.1f", str2time($ctrl_dtime) - time);		
        $raw_data{TimeOffset}{$devices{$dev_path}{ctrl_ip}} = sprintf("%.1f", str2time($ctrl_dtime) - time);
    }

}

