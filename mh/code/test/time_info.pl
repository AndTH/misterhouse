# Category=Informational


				# Let button 4 of various X10 consoles be the Time button
$request_time        = new  Serial_Item('XH4');
$request_time       -> add             ('XJ4');
$request_time       -> add             ('XK4');
$request_time       -> add             ('XM4');
$request_time       -> add             ('XN4');
$request_time       -> add             ('XO4');
$request_time       -> add             ('XP4');

speak "rooms=$request_time->{room} It is $Time_Now" if state_now $request_time;

$v_what_time = new  Voice_Cmd('{What time is it,Tell me the time}', 0);
$v_what_time-> set_info('Says the Time and Date');
#$v_what_time = new Voice_Cmd("{Please, } tell me the time");

if (said $v_what_time) {
    my $temp = "It is $Holiday" if $Holiday;
    speak "It is $Time_Now on $Date_Now_Speakable. $temp";
}

$v_sun_set = new  Voice_Cmd('When will the sun set', 0);
$v_sun_set-> set_info("Calculates sunrise and sunset for latitude=$config_parms{latitude}, longitude=$config_parms{longitude}");
speak "Sunrise today is at $Time_Sunrise, sunset is at $Time_Sunset." if said $v_sun_set;

speak "Notice, the sun is now rising at $Time_Sunrise" if time_now $Time_Sunrise and !$Save{sleeping_parents};
speak "rooms=all Notice, the sun is now seting at $Time_Sunset"  if time_now $Time_Sunset;



$v_moon_info1 = new Voice_Cmd "When is next [new,full] moon";
$v_moon_info2 = new Voice_Cmd "When was the last [new,full] moon";
$v_moon_info3 = new Voice_Cmd "What is the phase of the moon";
$v_moon_info3-> set_info('Phase will be: New, One-Quarter Waxing, Half Waxing, Three-Quarter Waxing, Full, etc for Waning');

if ($state = said $v_moon_info1) {
    my $days = &time_diff($Moon{"time_$state"}, $Time);
    speak qq[The next $state moon is in $days, on $Moon{$state}];
}

if ($state = said $v_moon_info2) {
    my $days = &time_diff($Moon{"time_${state}_prev"}, $Time);
    speak qq[The last $state moon was $days ago, on $Moon{"${state}_prev"}];
}

if ($state = said $v_moon_info3) {
    speak qq[The moon is $Moon{phase}, $Moon{brightness}% bright, and $Moon{age} days old];
}

$full_moon = new File_Item("$config_parms{data_dir}/remarks/full_moon.txt");
if ($Moon{phase} eq 'Full' and time_random('* 8-22 * * *', 240)) {
    speak "rooms=all Notice, tonight is a full moon.  " . (read_next $full_moon);
}


