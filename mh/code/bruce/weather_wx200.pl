####################################################
#
# weather_wx200.pl
#
# Author: Bruce Winter (brucewinter@home.net)
#
# This function will parse a string of data read from a wx200 weather station.
# It stores the results in the specified hash arry.
#
# Example usage:
#  
#  $wx200_port = new  Serial_Item(undef, undef, 'serial2');
#  &read_wx200($data, \%weather) if $data = said $wx200_port;
#
# A complete usage example is at:
#    http://misterhouse.net/mh/code/Bruce/weather_monitor.pl
#
# Lots of other good WX200 software links at:
#    http://weatherwatchers.org/wxstation/wx200/software.html
#
####################################################

# Category=Weather

                                # Parse wx200 datastream into array pointed at with $wptr
                                # Lots of good info on the WX200 from:  http://wx200.planetfall.com/

                                # Set up array of data types, including group index,
                                # group name, length of data, and relevant subroutine 
my %wx_datatype = (0x8f => ['humid', 35, \&wx_humid],
                   0x9f => ['temp',  34, \&wx_temp],
                   0xaf => ['barom', 31, \&wx_baro],
                   0xbf => ['rain',  14, \&wx_rain],
                   0xcf => ['wind',  27, \&wx_wind]);
        
sub read_wx200 {
    my ($data, $wptr, $debug) = @_;

    my @data = unpack('C*', $data);

    while (@data) {
        my $group = $data[0];
        my $dtp = $wx_datatype{$group};

                                # Check for valid datatype
        unless ($dtp) {
            my $length = @data;
            printf("Bad weather data.  group=%x length=$length\n", $group);
            return; 
        }
                                # If we don't have enough data, return what is left for next pass
        if ($$dtp[1] > @data) {
            return pack('C*', @data);
        }

                                # Pull out the number of bytes needed for this data type
        my @data2 = splice(@data, 0, $$dtp[1]);

                                # Check the checksum
        my $checksum1 = pop @data2;
        my $checksum2 = 0;
        for (@data2) {
            $checksum2 += $_;
        }
        $checksum2 &= 0xff;     # Checksum is lower 8 bits of the sum
        if ($checksum1 != $checksum2) {
            print "Warning, bad wx200 type=$$dtp[0] checksum: cs1=$checksum1 cs2=$checksum2\n";
            next;
        }
                                # Process the data
#       print "process data $$dtp[0], $$dtp[1]\n";
        &{$$dtp[2]}($wptr, $debug, @data2);
    }
}


sub wx_humid {
    my ($wptr, $debug, @data) = @_;
    $$wptr{HumidIndoor}  = sprintf('%x', $data[8]);
    $$wptr{HumidOutdoor} = sprintf('%x', $data[20]);
    print "humidity = $$wptr{HumidIndoor}, $$wptr{HumidOutdoor}\n" if $debug;
#   $wx_counts{time}++;
}
#8F. 8	DD	all	Humid	Indoor:    10<ab<97 % @ 1
#8F.20	DD	all	Humid	Outdoor:    10<ab<97 % @ 1

sub wx_temp {
    my ($wptr, $debug, @data) = @_;
    $$wptr{TempIndoor}  = &wx_temp2(@data[1..2]);
    $$wptr{TempOutdoor} = &wx_temp2(@data[16..17]);
    print "temp = $$wptr{TempIndoor}, $$wptr{TempOutdoor}\n"  if $debug;

    $$wptr{Summary_Short} = sprintf("%4.1f/%2d/%2d %3d%% %3d%%",
                              $$wptr{TempIndoor}, $$wptr{TempOutdoor}, $$wptr{WindChill},
                              $$wptr{HumidIndoor}, $$wptr{HumidOutdoor});
    $$wptr{Summary} = sprintf("In/out/chill: %4.1f/%2d/%2d Humid:%3d%% %3d%%",
                              $$wptr{TempIndoor}, $$wptr{TempOutdoor}, $$wptr{WindChill},
                              $$wptr{HumidIndoor}, $$wptr{HumidOutdoor});

#   $wx_counts{temp}++;
}
#9F. 1	DD	all	Temp	Indoor: 'bc' of 0<ab.c<50 degrees C @ 0.1
#9F. 2	-B	0-2	Temp	Indoor: 'a' of <ab.c> C
#9F. 2	-B	3	Temp	Indoor: Sign 0=+, 1=-
#9F.16	DD	all	Temp	Outdoor: 'bc' of -40<ab.c<60 degrees C @ 0.1
#9F.17	-B	0-2	Temp	Outdoor: 'a' of <ab.c> C
#9F.17	-B	3	Temp	Outdoor: Sign 0=+, 1=-

sub wx_temp2 {
    my ($n1, $n2) = @_;
    my $temp   =  sprintf('%x%02x', 0x07 & $n2, $n1);
    substr($temp, 2, 0) = '.';
    $temp *= -1 if 0x08 & $n2;
    $temp = &convert_c2f($temp);
    return $temp;
}

sub wx_baro {
    my ($wptr, $debug, @data) = @_;
    $$wptr{Barom}    = sprintf('%x%02x', $data[2], $data[1]);
    $$wptr{BaromSea} = sprintf('%x%02x%02x', 0x0f & $data[5], $data[4], $data[3]);
    substr($$wptr{BaromSea}, -1, 0) = '.';
    $$wptr{DewIndoor}  =  &convert_c2f(sprintf('%x', $data[7]));
    $$wptr{DewOutdoor} =  &convert_c2f(sprintf('%x', $data[18]));
    print "baro = $$wptr{Barom}, $$wptr{BaromSea} dew=$$wptr{DewIndoor}, $$wptr{DewOutdoor}\n"  if $debug;
#   $wx_counts{baro}++;
}
#AF. 1	DD	all	Barom	Local: 'cd' of 795<abcd<1050 mb @ 1
#AF. 2	DD	all	Barom	Local: 'ab' of <abcd> mb
#AF. 3	DD	all	Barom	SeaLevel: 'de' of 795<abcd.e<1050 mb @ .1
#AF. 4	DD	all	Barom	SeaLevel: 'bc' of <abcd.e> mb
#AF. 5	-D	all	Barom	SeaLevel: 'a' of <abcd.e> mb
#AF. 5	Bx	0,1	Barom	Format: 0=inches, 1=mm, 2=mb, 3=hpa
#AF. 7	DD	all	Dewpt	Indoor:    0<ab<47 degrees C @ 1
#AF.18	DD	all	Dewpt	Outdoor:    0<ab<56 degrees C @ 1

sub wx_rain {
    my ($wptr, $debug, @data) = @_;
    $$wptr{RainRate} = sprintf('%x%02x', 0x0f & $data[2], $data[1]);
    $$wptr{RainYest} = sprintf('%x%02x',        $data[4], $data[3]);
    $$wptr{RainTotal}= sprintf('%x%02x',        $data[6], $data[5]);
    $$wptr{RainRate} = sprintf('%3.1f', $$wptr{RainRate} / 25.4);
    $$wptr{RainYest} = sprintf('%3.1f', $$wptr{RainYest} / 25.4);
    $$wptr{RainTotal}= sprintf('%3.1f', $$wptr{RainTotal}/ 25.4);
    print "rain = $$wptr{RainRate}, $$wptr{RainYest}, $$wptr{RainTotal}\n"  if $debug;

    $$wptr{SummaryRain} = sprintf("Rain Recent/Total: %3.1f / %4.1f  Barom: %4d",
                                  $$wptr{RainYest}, $$wptr{RainTotal}, $$wptr{Barom});

#   print "rain=@data\n";
#   $wx_counts{rain}++;
}
#BF. 1	DD	all	Rain	Rate: 'bc' of 0<abc<998 mm/hr @ 1
#BF. 2	-D	all	Rain	Rate: 'a' of <abc> mm/hr
#BF. 2	Bx	all
#BF. 3	DD	all	Rain	Yesterday: 'cd' of 0<abcd<9999 mm @ 1
#BF. 4	DD	all	Rain	Yesterday: 'ab' of <abcd> mm
#BF. 5	DD	all	Rain	Total: 'cd' of <abcd> mm
#BF. 6	DD	all	Rain	Total: 'ab' of <abcd> mm


sub wx_wind {
    my ($wptr, $debug, @data) = @_;
    $$wptr{WindGustSpeed} = sprintf('%x%02x', 0x0f & $data[2], $data[1]);
    $$wptr{WindAvgSpeed}  = sprintf('%x%02x', 0x0f & $data[5], $data[4]);
    substr($$wptr{WindGustSpeed}, -1, 0) = '.';
    substr($$wptr{WindAvgSpeed}, -1, 0)  = '.';
                                # Convert from meters/sec to miles/hour  = 1609.3 / 3600
    $$wptr{WindGustSpeed} = sprintf('%3d', $$wptr{WindGustSpeed} * 2.237);
    $$wptr{WindAvgSpeed}  = sprintf('%3d', $$wptr{WindAvgSpeed}  * 2.237);
    $$wptr{WindGustDir}   = sprintf('%x%01x', $data[3], $data[2] >> 4);
    $$wptr{WindAvgDir}    = sprintf('%x%01x', $data[6], $data[5] >> 4);

    $$wptr{WindChill} = sprintf('%x', $data[16]);
    $$wptr{WindChill} *= -1 if 0x20 & $data[21];
    $$wptr{WindChill} = &convert_c2f($$wptr{WindChill});

    $$wptr{SummaryWind} = sprintf("Wind avg/gust:%3d /%3d  from the %s",
                                  $$wptr{WindAvgSpeed}, $$wptr{WindGustSpeed}, convert_direction($$wptr{WindAvgDir}));

    print "wind = $$wptr{WindGustSpeed}, $$wptr{WindAvgSpeed}, $$wptr{WindGustDir}, $$wptr{WindAvgDir} chill=$$wptr{WindChill}\n" 
        if $debug;
#   print "wind=@data\n";
#   $wx_counts{wind}++;
}
#CF. 1	DD	all	Wind	Gust Speed: 'bc' of 0<ab.c<56 m/s @ 0.2
#CF. 2	-D	all	Wind	Gust Speed: 'a' of <ab.c> m/s
#CF. 2	Dx	all	Wind	Gust Dir:   'c' of 0<abc<359 degrees @ 1
#CF. 3	DD	all	Wind	Gust Dir:   'ab' of <abc>
#CF. 4	DD	all	Wind	Avg Speed:  'bc' of 0<ab.c<56 m/s @ 0.1
#CF. 5	-D	all	Wind	Avg Speed:  'a' of <ab.c> m/s
#CF. 5	Dx	all	Wind	Avg Dir:    'c' of <abc>
#CF. 6	DD	all	Wind	Avg Dir:    'ab' of <abc>
#CF.16	DD	all	Chill	Temp: -85<ab<60 degrees C @ 1
#CF.21	Bx	1	Chill	Temp: Sign 0=+, 1=-
