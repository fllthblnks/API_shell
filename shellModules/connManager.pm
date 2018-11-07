package shellModules::connManager;

use strict;
use warnings;

require LWP;
use LWP::UserAgent;
use Data::Dumper;
use HTTP::Cookies;

use constant TRACE_DBG_LEVEL => 5;
use constant ALWAYS_TRACE => 1;

sub new{
	my $class = shift;
	my $self = { username    => shift,
		     password    => shift,
		     path_suffix => shift,
		     cookie_file => shift,
		     dbg_level => shift};
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
	
	$self->trace($self);
	bless $self, $class;
	return $self;
}

sub trace{
  my $self = shift;
  my $obj = shift;
  my $always = shift || 0;
  return if not $always and $self->{dbg_level} < TRACE_DBG_LEVEL;
  print("trace: " . Dumper($obj));
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

	$self->trace($url);
	my $req = HTTP::Request->new(GET => $url);
	$req->header( 'Content-Type' => 'application/json' );


	my $response = $ua->request($req);
	$self->trace($response);

	if($response->is_success() ){
		my $content = $response->decoded_content();
    		if ($content =~ /Error/){
      			$self->trace("-------- ERROR ------", ALWAYS_TRACE);
      			$self->trace($url, ALWAYS_TRACE);
      			$self->trace($content, ALWAYS_TRACE);
    		}
		return $content;
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
		return &read_cookie($self, $ip);
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


	my $response = $ua->post($url, {opcode   => 'login',
					url      => 'login.html',
					needxml  => '0',
					uid      => $self->{username},
					passwd   => $self->{password} });



	if(defined($response->header('set-cookie'))){
		if($response->header('set-cookie') =~ /SESSION\=\;/){
			print "Bad credentials. Please run the program again\n";
			exit;
		}
		$response->header('set-cookie') =~ /SESSION\=([^;]+)/;
		$self->{hosts}{$ip}{UID} = $1;
		$self->{cookie_jar}->save();
		return 1;
	}


	print "Unknown issue logging into the controller\n";
	exit;
	
}




1;
