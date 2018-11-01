#!/usr/bin/perl
# ArubaOS 8.0 API Shell

use strict;
use warnings;
use JSON;
use Data::Dumper;
#use Net::SSH::Perl;
use Term::ReadKey;
use Term::ReadLine;
use POSIX;
use shellModules::DispManager;
use shellModules::connManager;

use Time::HiRes qw(time);

use constant DATETIME => strftime("%Y-%m-%d_%H-%M-%S", localtime);

my $mm_ip;
if(defined($ARGV[0])){ 
	$mm_ip = $ARGV[0];
}else{
	print "MM IP address: ";
	$mm_ip = <STDIN>;
	chomp($mm_ip);
}

my $version = "0.2";
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




my $api_int = shellModules::connManager->new($username, $password, $path_suffix, $cookie_file);




&decode_hierarchy(&exec(method     => 'GET',
			ctrl_ip         => $mm_ip,
			command_url => 'node_hierarchy'), '');



foreach my $dev_path (keys %devices){
# Fetch Controller VLAN from MM
	my %ctrl_vlan_tmp = %{decode_json(&exec(method  => 'GET',
				ctrl_ip          => $mm_ip,
				config_path => $dev_path,
				command_url => 'ctrl_ip'))};


	$devices{$dev_path}{ctrl_vlan} = $ctrl_vlan_tmp{'_data'}{'ctrl_ip'}{'id'};



# Fetch IP from VLAN 
	my %int_vlan_tmp = %{decode_json(&exec(method      => 'GET',
				ctrl_ip          => $mm_ip,
				config_path => $dev_path,
				command_url => 'int_vlan'))}; 



	my @int_vlan = @{$int_vlan_tmp{'_data'}{'int_vlan'}};

	foreach my $h (@int_vlan){
		my %i = %{$h};
		if($i{id} ==  $devices{$dev_path}{ctrl_vlan}){
			$devices{$dev_path}{ctrl_ip} = $i{'int_vlan_ip'}{'ipaddr'};
		}

	}

}


print "\n\nWelcome to API_shell v$version\n";
print "Send feedback to Guillaume Germain (ggermain at hpe.com)\n";
print "MM - " . $mm_ip . "\n";
foreach my $dev_name (keys %devices){
	print $devices{$dev_name}{name} . " (" . $devices{$dev_name}{ctrl_ip} . ") " . $dev_name . "\n";

}
print "\n";

my $term = new Term::ReadLine 'Demo';


&get_debugged_users();

# Step into the main loop
while(1){
	my $prompt = "API_shell $cur_path> ";
	my $cmd = $term->readline($prompt);
	$term->addhistory($cmd);


	if($cmd =~ s/ssh//){ &start_ssh($cmd); 
}elsif($cmd =~ s/^cd //){ $cur_path = $cmd; &get_debugged_users();
}elsif($cmd eq ""){ next; 
}elsif($cmd eq "exit"){ exit; 
}elsif($cmd =~ s/^find_ap //){ &find_AP($cmd);
}elsif($cmd =~ s/^find_user_mac //){ &find_User($cmd, 'mac-addr'); 
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

	my @ips;

	foreach my $k (keys %devices){
		if($k =~ /$cur_path/){
			push(@ips, $devices{$k}{ctrl_ip});
		}
	}

	return @ips;	
}


sub fork_show_tech{
	my $ctrl_ip = shift;

	my $ssh = Net::SSH::Perl->new($ctrl_ip, use_pty => 1, cipher => "aes256-cbc", mac => "hmac-sha1-96", options => [ "MACs +hmac-sha1" ], protocol => 2);


	$ssh->login($username, $password);
	my ($out, $err, $exit) = $ssh->cmd("show tech-support | exclude key,passphrase,mgmt-user");

	open(OUT, '>./show_tech/' . $now . '-' . $ctrl_ip . '.txt');
	print OUT $out;
	close(OUT);
	print "\nGrabbed show tech-support for $ctrl_ip (" . length($out) . " bytes)\n";

	exit;
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
		}
	}


}




sub start_ssh{
	my $name = shift;
	my $ip = $mm_ip;
	$name =~ s/^\ //;

	foreach my $dev (keys %devices){
		if($devices{$dev}{name} eq $name){
			$ip = $devices{$dev}{ctrl_ip};
		}
	}


	if($^O ne "MSWin32"){

		my $ssh = Net::SSH::Perl->new($ip, use_pty => 1, cipher => "aes256-cbc", mac => "hmac-sha1-96", options => [ "MACs +hmac-sha1" ], protocol => 2);

		$ssh->login($username, $password);


		use Term::ReadKey;
		ReadMode('raw');
		$ssh->shell;
		ReadMode('restore');

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

	$devices{$current_pat . '/' . $dev{mac}}{mac}  = $dev{mac};
	$devices{$current_pat . '/' . $dev{mac}}{type} = $dev{type};
	$devices{$current_pat . '/' . $dev{mac}}{name} = $dev{name};

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


	foreach my $ip (@ips){
		my $time_before = time;

		&debug("Fetching " . $argu{cmd} . " from " . $ip, 2);

		my $curl_output = $api_int->request(ctrl_ip => $ip, 
			cmd     => $argu{cmd});	


		&debug("Command output for $ip\n" . $curl_output, 4);

		&debug("Command took " . (time - $time_before) . " seconds to run", 3);

		$cmd_result{out}{$ip} = $curl_output;	

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

	return $api_int->request(%argu);


}


sub debug(){
	my $txt = shift;
	my $lvl = shift;

	if($dbg > $lvl){
		print "DEBUG: " . $txt . "\n";
	}

}



sub get_debugged_users{

	my %r = %{decode_json(&exec(command_url => 'log_lvl_user_debug',
	ctrl_ip => $mm_ip,
	config_path => $cur_path,
	method => 'GET'))};

	my @user_list = @{$r{'_data'}{'log_lvl_user_debug'}};

	for(my $i = 0; $i < @user_list; $i++){
		my %s = %{$user_list[$i]};

		if($s{log_lvl} eq "debugging"){
			$raw_data{$s{mac}}{type} = 'debugged user';
		}
	}

}
