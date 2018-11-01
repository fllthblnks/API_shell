package shellModules::connManager;

use strict;
use warnings;

require LWP;
use LWP::UserAgent;
use Data::Dumper;
use HTTP::Cookies;


sub new{
	my $class = shift;
	my $self = { username    => shift,
		     password    => shift,
		     path_suffix => shift,
		     cookie_file => shift};
	my %hosts;

	my $cookie_jar = HTTP::Cookies->new(
			file =>    $self->{cookie_file},
			autosave => 1,
			ignore_discard => 1 );

	$cookie_jar->load;

	my $ua = LWP::UserAgent->new();
	$ua->agent("API_shell/0.1");
	$ua->ssl_opts( verify_hostname => 0 ,SSL_verify_mode => 0x00);
	$ua->cookie_jar($cookie_jar);

	$self->{user_agent} = $ua;
	$self->{hosts}      = \%hosts;
	$self->{cookie_jar} = $cookie_jar;

	bless $self, $class;
	return $self;
}



sub request{
	my $self = shift;
	my %argu = @_;
	my $url;

	do{
	my $ua = $self->{user_agent};
	my $UID = &get_UID($self, $argu{ctrl_ip});


	if(defined($argu{cmd})){
		$argu{cmd} =~ s/\s/\+/ig;
		$url = "https://" . $argu{ctrl_ip} . ':4343/v1/configuration/showcommand?json=1&command=' . $argu{cmd} . "&UIDARUBA=$UID";
	}elsif(defined($argu{config_path})){
		$url = "https://" . $argu{ctrl_ip} . ":4343/" . $self->{path_suffix} . $argu{command_url} . "?config_path=" . $argu{config_path} . "&UIDARUBA=$UID";
	}else{
		$url = "https://" . $argu{ctrl_ip} . ":4343/" . $self->{path_suffix} . $argu{command_url} . "?UIDARUBA=$UID";
	}


	my $req = HTTP::Request->new(GET => $url);
	$req->header( 'Content-Type' => 'application/json' );


	my $response = $ua->request($req);

	if($response->is_success() ){
		return $response->decoded_content();
	}

	&login_to_controller($self, $argu{ctrl_ip});

	}while(1);

}


sub get_UID{
	my $self = shift;
	my $ip   = shift;


	if(defined($self->{hosts}->{$ip}{UID})){
                return $self->{hosts}{$ip}{UID};
	}else{
		&login_to_controller($self, $ip);
		&read_cookie($self, $ip);
		return $self->{hosts}{$ip}{UID};
	}

}


sub read_cookie{
	my $self = shift;
	my $ip   = shift;


	open(CKI, $self->{cookie_file});

	foreach my $line (<CKI>){
		if($line =~ /$ip/){
			$line =~ /SESSION\=([^;]+)/;
			$self->{hosts}{$ip}{UID} = $1;

		}
	}	

	close(CKI);

	return $self->{hosts}{$ip}{UID};


}


sub login_to_controller{
	my $self = shift;
	my $ip   = shift;




	my $url = "https://$ip:4343/screens/wms/wms.login";

	my $ua = $self->{user_agent};


	$ua->post($url, { opcode   => 'login',
			url      => 'login.html',
			needxml  => '0',
			uid      => $self->{username},
			passwd   => $self->{password} });

	$self->{cookie_jar}->save();


	return 1;
}




1;
