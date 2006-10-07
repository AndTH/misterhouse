# Category = Weather

#@ Reads iButton One Wire Weather Station data broadcast from the OWW program.
#@  This program is freely available from http://www.simon.lenhuish.net/projects/oww
#@  this is a multiplatrorm networkable weatherstation server/client for use
#@  with the Dallas One wire weather station (all versions)
#@ Default parameters are for the station to be running on the localhost
#@  at port 8888, you can override this with the owwserver_host_port ini
#@  parameter.  This may point to a machine other than the localhost.

=begin_comment
"
version 1.02	rel date 1/20/02
 v 101-102 updated i variable declaration, cleaned up tk interface, added menu selection description

 v 1.03    added wind chill calclulation, Status bar and TK entries
	   calculated per NWS 'new' method, Note chill only available < 50F

 v 1.04	   changed wind chill formatting to include (avg/peak) chill calculations

 v 1.05    2/17/04
           Updated variable names to allow interaction to weather_rrd_update.pl	   

 v 1.06    2/21/04
	   Found anomilties and a mis alignment in data sent to rrd, also added dummy
           value for WindGustDir, as rrd wasnt using data.
	   
 v 1.07    2/28/04
	   Found a bug with passing the wind dir to the graph. Looks like it was passing directional
	   data (eg 0-16 ) and the graph is expecting compass dirs. 
	   added calculation to ordinal positions position * 22.5 = compass dir
	   Still need good algorythm to smooth north data when it flopps nne-nnw
	   
	   	   
 Modified by Pete Flaherty 05/12/02
 Changes to allow OWW weather station to be standalone using the 
  OWW software by Simon Melhuish available at http://www.simon.melhuish.net/projects/oww/
    this runs on Linux/Unix and windows other platforms ???/
  I run the software in the daemon mode and pickup on it's broadcasts for MH usage
  Noticed data was offset by 1 
  Added commnets all around

 11/23/02
 Added owwserver_host_port to .ini file config parameter
 so the server can be on another machine (anywhere)
  if set it will try to use the ini setting otherwise
  it will default to the localhost

 Data Format is consistant with Henriksen format (below)

This version should work with all Henriksen WServer versions from December on

21.4 22.2 20.3 0.0 0.0 2.1 2 2 0.500 0.500 16.38 6.49
21.5 22.2 20.3 0.0 0.0 0.0 -1 0 0.000 0.000 16.38 6.49
21.5 22.2 20.3 0.0 0.0 2.1 2 2 0.500 0.500 16.38 6.49
21.7 23.6 19.4 0.0 0.4 2.1 1 1 0.000 0.000 16.44 6.41

The following are the variables transmitted from the Henriksen WServer:
current_tempC, max_tempC, min_tempC, current_speedMS, peak_speedMS,
max_speedMS, current_dir, max_dir, rain_rateI, rain_todayI, rain_weekI,rain_monthI

where
	0	current_tempC		is current temp in C
	1	max_tempC		is today's high in C
	2	min_tempC		is today's low in C
	3	current_speedMS		is current wind speed in meters/sec
	4	gusts_speedMS		is peak wind speed in meters/sec
	5	max_speedMS		is today's hi in meters/sec
	6	current_dir		is the current wind direction
	7	wind_dir		is the 10 minute average wind direction
	8	rain_rateI 		is the current Rain Rate in inches
	9	rain_todayI		is today's Rain in inches
	10	rain_weekI		is week's rain in inches
	11	rain_monthI		is month's Rain in inches
	12	current_humidity	is current humiity percent
	13	max_humidity		is maximum humiity percent
	14	min humidity		is minimum humiity percent

Wind directions are enumerated 0 through 15 corresponding to the 16 compass directions
 N  NNE  NE   ENE  E    ESE  SE   SSE  S    SSW  SW   WSW  W    WNW  NW   NNW.
 0  1    2    3    4    5    6    7    8    9    10   11   12   13   14   15 

The positonis equate to 22.5 degrees each starting at North=0 
so position * 22.5 is the rrd graph direction ( assuming it's linier )

"
=cut

#
# in order to get the initialization of the socket to work correctly
# here we must force misterhouse to keep all of this code out of the loop
# body. Otherwise the new Socket line will be moved out of the loop body
# but the config_parms lines are in the loop body which happens afterwards.
# Without this you must have a definition of the port in an .ini file
# as the default here gets applied too late. 
#

# noloop=start
my $owwhost = $config_parms{owwserver_host_port};
$owwhost = "localhost:8888" unless $owwhost ;
$ibws   = new  Socket_Item(undef, undef, $owwhost, 'ibws', 'tcp', 'raw');
# noloop=stop

$ibws_v = new  Voice_Cmd "[Start,Stop,Speak] the ibutton weather station client";
$ibws_v-> set_info('Connects to the ibutton weather station server');

# REF var refs        0           1               2              3         4             5             6       7          8        9         10       11        12        13
my @weather_vars = qw(TempOutdoor TempOutdoorHigh TempOutdoorLow WindSpeed WindGustSpeed WindSpeedHigh WindDir WindAvgDir RainRate RainToday RainWeek RainMonth WindChill WindGustDir);
# Ref dir nos   0       1                  2            3                 4      5                 6            7                  8       9                  10           11                12     13                14           15           
my @direction=("North","North North East","North East","East North East","East","East South	 East","South East","South South East","South","South South West","South West","West South West","West","West North West","North West","North North West");
my @directionshort=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");

my $freezing = new Weather_Item 'TempOutdoor', '<', 32;
my $chill = 0;
my $pchill = 0;
my $chillwthresh = 3; 	# thresholds for calculating wind chill 
my $chilltthresh = 50;
my $i = 0 ;



set $ibws_v 'Start' if $Startup;

if (time_cron '31 9-23 * * *') {
	run_voice_cmd 'Start the ibutton weather station client';
}

#if (time_cron '0,15,30,45 7-21 * * *') {
#	run_voice_cmd 'Speak the ibutton weather station client';
#}

if (my $data = said $ibws) {
# print_log "ibws server said: $data";
  my @data = split /\s+/, $data;			# Split up the individual Data elements

# ----------------------------------------------------------------------------
#                               ------ COLLECT and Sort the Data -------
   for ($i = -1; $i < 14; $i++) {			# ???????? -1 ???????????
#     print_log "Processing data at $i which is $weather_vars[$i] value of $data[$i]";
      my $key = $weather_vars[$i];			# Get the Name of the data key

      if ($i < 3) {					# 0-TempOutdoor 1-TempOutdoorHigh 2-TempOutdoorLow
        $Weather{$key} = convert_c2f $data[$i];	        # I still like to hear these in F
      }

      if (($i > 2) && ($i < 6)) {			# 3-WindSpeed 4-WindSpeedPeak 5-WindSpeedHigh
        $Weather{$key} = $data[$i] * 2.237415;          # I still like to hear these in mph
        $Weather{$key} = sprintf("%.0f",$Weather{$key});
      }

      if (($i == 6)||($i == 7)) {			# 6-WindDir 7-WindAvgDir
	    
        $Weather{$key} = $data[$i];
#       print "key = $Weather{$key},data = $data[$i], i= $i \n" ;
      }

      if (($i > 7) && ($i <= 11)) {			# 8-RainRate 9-RainToday 10-RainWeek 11-RainMonth
        						# least significant bits are too annoying in spoken form
						        # 10.000 should be 10.0
        $Weather{$key} = $data[$i];
        $Weather{$key} = sprintf("%.2f",$Weather{$key});
      }
  }
  
  $Weather{WindAvgDir} = ( $Weather{WindDir} * 22.5 ); #convert to rrd degrees
  $Weather{WindGustDir} = $Weather{WindAvgDir} ;	# Because rrd wants this and we dont have it
#  print "Weather Dir $Weather{WindAvgDir}\n";
# } else {
#   print_log "Bad ibws data, $i datapoints";
#   }
}
# ----------------------------------------------------------------------------

#  print  "Out $Weather{TempOutdoor} / Out Hi $Weather{TempOutdoorHigh} / OutLow $Weather{TempOutdoorLow} F";
#  print  "WindDirAv $direction[$Weather{WindDirAvg}] Wind $Weather{WindAvgSpeed} / Peak $Weather{WindSpeedPeak} mph \n";
  
  							# Update the Web Page Data

# this is the standard short summary for the web interfaces
$Weather{Summary_Short} = "$Weather{TempOutdoor} F ";

# Calculate wind chill if applicable
# print "\n\n Calculating WindChill for $Weather{TempOutdoor} at $Weather{WindAvgSpeed} \n";
$chill = $Weather{TempOutdoor};			# assume no chill to begin with

if ( $Weather{TempOutdoor} <= $chilltthresh ) {
    #print "Temp is low Enough at $Weather{TempOutdoor} \n";

    if  ( $Weather{WindAvgSpeed} >= $chillwthresh ) {
	#print " Wind Speed is high enough at $Weather{WindAvgSpeed} \n";
	# REF OLD Formula  T(wc) = 0.0817 (3.71V**0.5 + 5.81 -0.25V) (T - 91.4) + 91.4
	# the New Formula  = 35.74 + 0.6215T - 35.75V (**0.16) + 0.4275TV(**0.16)
	
	$pchill = ( 35.74 +  0.6215 * $Weather{TempOutdoor} -  35.75 * ( $Weather{WindGustSpeed} ** 0.16 ) + 0.4275 * $Weather{TempOutdoor} * ( $Weather{WindSpeedPeak} ** 0.16 )) ;
	$chill  = ( 35.74 +  0.6215 * $Weather{TempOutdoor} -  35.75 * ( $Weather{WindAvgSpeed}     ** 0.16 ) + 0.4275 * $Weather{TempOutdoor} * ( $Weather{WindAvgSpeed}     ** 0.16 )) ;
	# Update the chill data if we have one
	$chill = int($chill);
	$pchill = int($pchill);
	# print " Wind Chill calculates to be $chill \n";
	$Weather{Summary_Short} = "$Weather{TempOutdoor} F ($chill/$pchill F)";

    }
}

$Weather{WindChill} = $chill;


#$Weather{WindAvgDir}=$Weather{WindDir};
$Weather{Wind} = " $Weather{WindAvgSpeed}/$Weather{WindSpeedHigh} $directionshort[$Weather{WindDir}]";

&tk_entry("temp",\$Weather{TempOutdoor},"Wind ",\$Weather{Wind}, "Wchill ",\$chill );


  
if ($state = said $ibws_v) {
  print_log "${state}ing the ibutton weather station client";

  if ($state eq 'Start') {
    unless (active $ibws) {
    print_log 'Starting a connection to ibws';
    start $ibws;
  }

} elsif ($state eq 'Stop' and active $ibws) {
  print_log "closing ibws";
  stop $ibws;

  } elsif ($state eq 'Speak') {
    my $msg = "\nThe Current temperature is $Weather{TempOutdoor}\nA high of $Weather{TempOutdoorHigh}\nA low of $Weather{TempOutdoorLow}.\n";
    $msg .= "Current Wind Speed is $Weather{WindAvgSpeed} miles per hour\nGusts of $Weather{WindSpeedPeak}\nHigh of $Weather{WindSpeedHigh}.\nWind Direction is $direction[$Weather{WindDir}]\nWind direction average $direction[$Weather{WindAvgDir}].\n";
#   $msg .= "The Current Rainfall Rate is $Weather{RainRate} inches per hour.\nToday's total rainfall is $Weather{RainToday} inches\n$Weather{RainWeek} inches for the week\n$Weather{RainMonth} inches for the month.\n";
    if (state_now $freezing) {
      $msg .= "Temperature is below freezing.";
    }
    print_log $msg;
    speak $msg;
  }
}



