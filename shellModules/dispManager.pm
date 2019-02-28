# vim: ts=4 sts=4 et sw=4 ft=perl
package shellModules::dispManager;
use strict;
use warnings 'all';
use Data::Dumper;
use JSON;
use Term::ANSIColor qw(:constants);
use Time::HiRes qw(time);
use Date::Parse;


# Receives the output of the web requests and formats it for next steps
sub merge_data{
    my $self = shift;
    my $href = shift;
    my %lines;
    if(!defined($href)){ return; }
    my %raw_data = %{shift()};
    %lines = %{$href};
    my %out;
    my %comp;
    my @info;
    my @meta;
    my @data;



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

    # Prepare hash array for output
    $out{info} = \@info;
    $out{meta} = \@meta;
    $out{data} = \@data;
    $out{comp} = \%comp;


    return %out;
}


# 
sub print_cmd{
    my $self = shift;
    my $href = shift;
    my %lines;
    if(!defined($href)){ return; }
    my %raw_data = %{shift()};
    %lines = %{$href}; 
    my %col_size;


    my %d = &merge_data($self, $href, \%raw_data);

    my @info = @{$d{info}};
    my @meta = @{$d{meta}};
    my @data = @{$d{data}};
    my %comp = %{$d{comp}};


    if($lines{cmd} =~ /^show\+log\+/){
        print_dated($self, \%comp, \%raw_data);
    }elsif(@meta > 0){
        print_header_and_table($self, \@meta, \@info, \@data, \%raw_data);
    }else{
        print_data(\%comp, \%raw_data);
    }

    print "\n";
}


sub print_dated{
    my $self = shift;
    my %comp = %{shift()};
    my %raw_data = %{shift()};
    my %tmp_sort;

    # Put in an array with time to be sorted after the fact
    foreach my $ip (keys %comp){
        my @data = @{$comp{$ip}{data}};
        foreach my $l (@data){
            my @o = split("\n", $l);

            foreach my $c (@o){
                $c =~ s/([A-Za-z]+\s+\d \d+:\d+:\d+ )//;
                my @a;
                my $time_corrected = str2time($1) - $raw_data{TimeOffset}{$ip};
                if(defined($tmp_sort{$time_corrected}{$ip})){
                    @a = @{$tmp_sort{$time_corrected}{$ip}};
                }
                push(@a, $c);
                $tmp_sort{$time_corrected}{$ip} = \@a;

            }

        }

    }

    # Print the sorted data
    foreach my $tm (sort keys %tmp_sort){
        foreach my $ip (sort keys %{$tmp_sort{$tm}}){
            foreach my $line (@{$tmp_sort{$tm}{$ip}}){
                &prnt($tm . " " . $ip . " " . $line . "\n", \%raw_data);
            }
        }
    }



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
