# Category=Appliances

$v_fountain = new  Voice_Cmd('Fountain [on,off]');
$v_fountain-> set_info('Controls the backyard fountain');

set $fountain $state if $state = said $v_fountain;
#set $fountain   ON if $Season eq 'Summer' and time_cron('00 20 * * *');
#set $fountain   ON if $Season eq 'Summer' and time_cron('00 08 * * *');
set $fountain  OFF if time_cron('00,30 22,23 * * *');
set $fountain  OFF if time_cron('00,30 09    * * *');

if (state_now $toggle_fountain) {
    $state = (ON eq state $fountain) ? OFF : ON;
    set $fountain $state;
    speak("rooms=family The fountain was toggled to $state");
}

#$v_dishwasher = new  Voice_Cmd('Dishwasher [on,off]');
#set $dishwasher $state if $state = said $v_dishwasher;

#v_indoor_fountain = new  Voice_Cmd 'Indoor fountain [on,off]', 'Ok, I turned it $v_indoor_fountain->{said}';
$v_indoor_fountain = new  Voice_Cmd 'Indoor fountain [on,off]', 'Ok, I turned it to %STATE%';
$v_indoor_fountain-> set_info('Controls the small indoor fountain by the piano');

set $indoor_fountain $state if $state = said $v_indoor_fountain;
set $indoor_fountain  OFF if time_cron('00,30 10 * * *');
set $indoor_fountain  ON  if time_cron('30 6 * * 1-5');
set $indoor_fountain  OFF if time_cron('30 8 * * 1-5');


$v_family_tv = new  Voice_Cmd('{Family room,downstairs} TV [on,off]');
$v_family_tv-> set_info('This old Family room TV (no IR control)');

set $family_tv $state if $state = said $v_family_tv;

