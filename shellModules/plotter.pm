# vim: ts=4 sts=4 et sw=4 ft=perl
package shellModules::plotter;
use strict;
use warnings 'all';

use Chart::Gnuplot;


sub new{
    my $class = shift;
    my $self;


    my $chart = Chart::Gnuplot->new(
            output => "./output.png",
            title  => "TITLE",
            xlabel => "dB delta",
            ylabel => "count",
            imagesize => "0.8, 0.8",
            legend => {
            position => 'right'
            });

       

    my @x_axis;
    my @y_axis;

    $self->{chart} = $chart;
    $self->{x} = \@x_axis;
    $self->{y} = \@y_axis;

    bless $self, $class;
    return $self;
}


sub addData{
    my $self = shift;
    my $data = shift;

    my @x_axis = @{$self->{x}};
    my @y_axis = @{$self->{y}};

    push(@x_axis, $#x_axis + 1);
    push(@y_axis, $data);

    $self->{x} = \@x_axis;
    $self->{y} = \@y_axis;
    
}


sub printData{
    my $self = shift;
    
    my @x_axis = @{$self->{x}};
    my @y_axis = @{$self->{y}};


}


sub generateImage{
    my $self = shift;

    my $chart = $self->{chart};


    my $tmp_dataset = Chart::Gnuplot::DataSet->new(
            xdata => \@{$self->{x}},
            ydata => \@{$self->{y}},
            style => "linespoints",
            title => "title");

    my @dataset;

    push(@dataset, $tmp_dataset);

    $chart->plot2d(@dataset);



}




1;
