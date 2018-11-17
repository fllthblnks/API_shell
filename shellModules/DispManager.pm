package shellModules::DispManager;
use strict;
use warnings 'all';
#use Data::Dumper;
use JSON;
use Term::ANSIColor qw(:constants);



sub print_cmd{
	my $self = shift;
	my $href = shift;
	my %lines;
	if(!defined($href)){ return; }
	my %raw_data = %{shift()};
	%lines = %{$href}; 
	my %comp;
	my @info;
	my @meta;
	my @data;
	my %col_size;

	

	foreach my $ip (keys %{$lines{out}}){
		my $line = $lines{out}{$ip};

		if($line eq ""){ next; }

		if($line =~ /\<my_xml_tag3xxx\>/){
			$line =~ s/\<my_xml_tag3xxx\>//;
			$line =~ s/\<\/my_xml_tag3xxx\>//;
			$line =~ s/^(\W)+//ig;
			my @splt = split("\n", $line);

			$comp{$ip}{data} = \@splt;


		}else{  
			my %h = %{decode_json($line)};


			if(defined($h{'_data'})){
				@data = @{$h{'_data'}};
				my @s;
				foreach my $l (@data){
					my @o = split("\n", $l);
					push(@s, @o);
				}
				$comp{$ip}{data} = \@s;
					
				delete($h{'_data'});
			}

			if(defined($h{'_meta'})){
				pop(@data);
				
				@meta = @{$h{'_meta'}};
				unshift(@meta, "ControllerIP");
				#$comp{meta} = \@u;
				delete($h{'_meta'});

				my @tmp_keys = keys(%h);

				foreach my $item_name (@tmp_keys){
					my @tmp_h = @{$h{$item_name}};

					for(my $i = 0; $i < @tmp_h; $i++){
						my %j = %{$tmp_h[$i]};
						$j{ControllerIP} = $ip;
						push(@info, \%j);
					}
				}
			}
		}

	}



	if(@meta > 0){

		print_header_and_table(\@meta, \@info, \@data, \%raw_data);

	}else{

		print_data(\%comp, \%raw_data);
	}

	print "\n";
}

sub print_header_and_table(){
	my $self = shift;
	my @meta = @{shift()};
	my @info = @{shift()};
	my @data = @{shift()};
	my %raw_data = %{shift()};
	my %col_size;

	foreach my $col (@meta){
		$col_size{$col} = &size(\@info, $col);
	}


# Print header
	foreach my $d (@meta){
		if($^O ne "MSWin32"){
			print ON_WHITE, BLACK, sprintf("%-" . ($col_size{$d}+2) . "s", $d), RESET, " ";
		}else{
			print sprintf("%-" . ($col_size{$d}+3) . "s", $d);
		}
	}
	print "\n";

# Print content for each line
	for(my $e = 0; $e < @info; $e++){
		my %c = %{$info[$e]};
#print %c;
		foreach my $d (@meta){
			if(defined($c{$d})){
				&prnt(sprintf("%-" . ($col_size{$d}+3) . "s", $c{$d}), \%raw_data);
			}else{
				&prnt(sprintf("%-" . ($col_size{$d}+3) . "s", " "), \%raw_data);
			}

		}
		print "\n";
	}

	if(@data){
		foreach my $d (@data){
			print $d . "\n";
		}
	}


	print "\n";
}

sub print_data(){
	my %comp = %{shift()};
	my %raw_data = %{shift()};

	foreach my $ip (keys %comp){
		my @d = @{$comp{$ip}{data}};
		foreach my $line (@d){
			print $ip . " " . $line  . "\n"; 
		}
	}

}




sub prnt{
	my $txt = shift;
	my %raw_data = %{shift()};

	foreach my $k (keys %raw_data){
		if($txt =~ /$k/){
			if($^O eq "MSWin32"){
				print $txt;
			}else{
				print YELLOW, $txt, RESET;
			}
			return;
		}
	}
	print $txt;

}




sub size{
	my @info = @{shift()};
	my $col_name = shift;
	my $biggest = length($col_name);


	for(my $i = 0;  $i < @info; $i++){
		my %s = %{$info[$i]};
		if(defined($s{$col_name})){
			if(length($s{$col_name}) > $biggest){
				$biggest = length($s{$col_name});
			}
		}
	}


	return $biggest;
}




1;
