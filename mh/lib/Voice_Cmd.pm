
package Voice_Cmd;
@Voice_Cmd::ISA = ('Generic_Item');

use strict;
my ($cmd_num);
my (%cmd_by_num, %cmd_state_by_num, %cmd_num_by_text, %cmd_text_by_num, %cmd_text_by_vocab);
my (%cmd_word_list, %cmd_vocabs);
my ($Vcmd_ms, $Vmenu_ms, $Vcmd_viavoice);
my ($last_cmd_time, $last_cmd_num, $last_cmd_num_confirm, $last_cmd_flag, $noise_this_pass );

my $confirm_timer = &Timer::new();

sub init {

    if ($main::config_parms{voice_cmd} =~ /ms/i and $main::OS_win) {
        print "Creating MS VR object\n";
        $Win32::OLE::Warn = 1;   # Warn if ole fails
#       $Win32::OLE::Warn = 3;   # Die  if ole fails
        $Vcmd_ms  = &create_voice_command_object;
        $Vmenu_ms = &create_voice_command_menu_object('application' => 'House Menu', 'state' => 'Main State') if $Vcmd_ms;
    }
    if ($main::config_parms{voice_cmd} =~ /viavoice/i) {
        my $port = "$main::config_parms{viavoice_host}:$main::config_parms{viavoice_port}";
        print "Creating Viavoice command object on $port\n";
        $Vcmd_viavoice = new  main::Socket_Item(undef, undef, $port, 'viavoice');
#       buffer $Vcmd_viavoice 1;
        start $Vcmd_viavoice;

                                # Defined an empty vocab ... will use addtovocab for all phrases
        &definevocab('mh');
                                # Defined the confirmation vocab
        &definevocab('mh_confirm', 'yes', 'no');
        &disablevocab('mh_confirm');
        &mic('on');
    }

}

sub reset {
    if ($Vcmd_viavoice) {
                                # Allow for new phrases to be added
        $Vcmd_viavoice->set("addtovocab");
        select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
        $Vcmd_viavoice->set("mh");
        undef %cmd_text_by_vocab; # Only add new commands on reload
    }
    else {
        undef %cmd_num_by_text;
        undef %cmd_by_num;
#       &remove_voice_cmds;  No need ... only reloading code here
    }
}

sub is_active {
    return $Vmenu_ms->{Active};
}

sub activate {
    if ($Vcmd_ms) {
        $Vmenu_ms->{Active} = 1;	# Called after all voice commands are added
        $Vcmd_ms->{CommandSpoken} = 0;	# In case any lingering command was there
    }
    if ($Vcmd_viavoice) {
                                # Close the addtovocab session
                                #  - vocabularies are enabled by default, so no need to enable
        $Vcmd_viavoice->set("");

                                # Add words from other, non-default vocabularies
        for my $vocab (sort keys %cmd_text_by_vocab) {
                                # Only need to define a new vocab once per session
            unless ($cmd_vocabs{$vocab}) {
                &definevocab($vocab);
                $cmd_vocabs{$vocab}++;
            }

            my $count = @{$cmd_text_by_vocab{$vocab}};
            print "Adding $count words for vocab=$vocab\n";
            &addtovocab($vocab, @{$cmd_text_by_vocab{$vocab}});

            &disablevocab($vocab);  # Disabled by default
        }
    }
}

sub deactivate {
    return unless $Vcmd_ms;
    $Vmenu_ms->{Active} = 0;	# Called after all voice commands are added
}

sub create_voice_command_object {

    return unless $main::OS_win;

#   print "Creating MS voice VR object\n";

    $Vcmd_ms = Win32::OLE->new('Speech.VoiceCommand');

    unless ($Vcmd_ms) {
        print "\n\nError, could not create Speech VR object.  ", Win32::OLE->LastError(), "\n\n";
        return;
    }

    $Vcmd_ms->Register("Local PC");
    if (Win32::OLE->LastError()) {
        print "\n\nError, could not Register ms Speech VR object\n";
        delete $main::config_parms{voice_cmd}; # Disable for future reloads 
        return;
    }

    print "Awakeing speech command.  Currently it is at ", $Vcmd_ms->{Awake}, "\n" if $main::config_parms{debug} eq 'voice';
    $Vcmd_ms->{Awake} = 1;
    return $Vcmd_ms;
}

sub create_voice_command_menu_object {
    my(%parms) = @_;            

# From speech.h file:
#/ dwFlags parameter of IVoiceCmd::MenuCreate
#define  VCMDMC_CREATE_TEMP     0x00000001
#define  VCMDMC_CREATE_NEW      0x00000002
#define  VCMDMC_CREATE_ALWAYS   0x00000004
#define  VCMDMC_OPEN_ALWAYS     0x00000008
#define  VCMDMC_OPEN_EXISTING   0x00000010
#   $Vmenu_ms = $Vcmd_ms->MenuCreate($parms{'application'}, $parms{'state'}, 1033, "US English", hex(1)) or 
    unless ($Vmenu_ms = $Vcmd_ms->MenuCreate($parms{'application'}, $parms{'state'}, 1033, "US English", 4)) {
        print "\nError, could not create Vmenu:", Win32::OLE->LastError(), "\n";
        return;
    }

    $Vmenu_ms->{Active} = 0;	# Needs to be off when we first add commands

    return $Vmenu_ms;
}


sub check_for_voice_cmd {


                                # Turn on VR, if text is done speaking
#    if ($Vcmd_ms) {
#        print ($Vmenu_ms->{Active}) ? '.' : '-';
#        if ($Vmenu_ms->{Active} and &Voice_Text::is_speaking) {
#            print "db vr off\n";
#            $Vmenu_ms->{Active} = 0;
#        }
#        if (!$Vmenu_ms->{Active} and !&Voice_Text::is_speaking) {
#            print "db vr on\n";
#            $Vmenu_ms->{Active} = 1;
#        }
#       $Vmenu_ms->{Active} = 1 unless $Vmenu_ms->{Active};
#    }

    my ($ref, $number, $said, $cmd_heard, $cmd, $action);
    $noise_this_pass = 0;

    if ($Vcmd_ms) {
        $number = $Vcmd_ms->CommandSpoken;
    }
#   if ($Vcmd_viavoice and my $text = said $Vcmd_viavoice) {
    if ($Vcmd_viavoice and my $text = said $Vcmd_viavoice) {
                                # If we get a lot of stuff, throw it away
                                # ... probably just stored up junk
#       return if length($text) > 100;

        $text = substr($text, 1); # Drop the leading 00 byte (not sure why we get that)

        $noise_this_pass = $text;
#       ($cmd_heard) = $text =~ /^Said: (.+)/;
        ($cmd_heard) = $text =~ /Said: (.+)/; # Patch from the list ... not sure why this is needed

        if (defined $cmd_heard) {
            $noise_this_pass = 0;
            $number = $cmd_num_by_text{$cmd_heard};


                                # Check to see if we are confirming a previous command
            if (&Timer::active($confirm_timer) and $last_cmd_num_confirm) {
                undef $number;
                if ($cmd_heard eq 'yes') {
                    &main::speak("Command confirmed");
                    $number = $last_cmd_num_confirm;
                }
                elsif ($cmd_heard eq 'no') {
                    &main::speak("Command aborted");
                }
                else {
                    &main::speak("Error in the confirm vocabulary.  Tell Bruce.");
                }
                $last_cmd_num_confirm = 0;
                &Timer::unset($confirm_timer);
                &disablevocab('mh_confirm');
                &enablevocab('mh');
            }

                                # Check for confirm yes/no request
            elsif ($cmd_by_num{$number}->{confirm}) {
                &main::speak("Confirm with a yes or a no");
                &disablevocab('mh'); # Should change this to @current_vocab
                &enablevocab('mh_confirm');
                $action  = "&Voice_Cmd::disablevocab('mh_confirm'); ";
                $action .= "&Voice_Cmd::enablevocab('mh'); ";
                $action .= "&main::speak('Confirmation timed out'); ";
                &Timer::set($confirm_timer, 10, $action);
                $last_cmd_num_confirm = $number;
                $number = 0;
            }

        }
        print "db vv: n=$number cmd=$cmd_heard text=$text.\n" if $main::config_parms{debug} eq 'voice';
    }

                                # Set states, if a command was triggered
    $last_cmd_flag = 0;
    if ($number) {
        $ref = $cmd_by_num{$number};
        $said  = $cmd_state_by_num{$number};
        $cmd = $ref->{text};
        $cmd = 'unknown command' unless $cmd;
        print "Voice cmd num=$number ref=$ref said=$said cmd=$cmd\n" if $main::config_parms{debug} eq 'voice';
        $said  = 1 unless defined $said; 

                                # This could be set for either the current or next pass ... next pass is easier
        &Generic_Item::set_states_for_next_pass($ref, $said);
#       $ref->{said}  = $said;
#       $ref->{state} = $said;

        $Vcmd_ms->{CommandSpoken} = 0 if $Vcmd_ms;
        $last_cmd_time = &main::get_tickcount;
        $last_cmd_num  = $number;
        $last_cmd_flag = $number;

                                # Echo command response
        my $response = $cmd_by_num{$number}->{response};
        if (defined $response) {
                                # Allow for something like: 'Ok, I turned it %STATE%'
            $response =~ s/%STATE%/$said/g;
                                # Allow for something like: 'Ok, I turned it $v_indoor_fountain->{said}'
            package main;       # Avoid having to prefix vars with main::
            eval "\$response  = qq[$response]";
            package Voice_Cmd;
            &main::speak($response) if $response;
        }
        else {
            &main::speak("I heard " . $cmd_heard) if $cmd_heard;
        }


    }
}

                                # This will set voice items for the NEXT pass ... do not want it active
                                # for the current pass, because we do not know where we are in the user code loop
sub set {
    my ($self, $state) = @_;
    &Generic_Item::set_states_for_next_pass($self, $state);
    print "db1 set voice cmd $self to $state\n" if $main::config_parms{debug} eq 'voice';
}

sub remove_voice_cmds {

    if ($Vmenu_ms) {
        $Vmenu_ms->{Active} = 0;
        my ($vitems_removed, $number);
        $vitems_removed = 0;
        print "Removing voice items ... ";
        foreach $number (keys %cmd_by_num) {
            $Vmenu_ms->Remove($number);
            $vitems_removed++;
            delete $cmd_by_num{$number};
        }
        $cmd_num = 0;	# Reset cmd num counter
        print "$vitems_removed voice command were removed\n";
    }
    if ($Vcmd_viavoice) {
        print "Undefineing the misterhouse viavoice vocabulary\n";
        &mic('off');
        $Vcmd_viavoice->set("undefinevocab");
        select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
        $Vcmd_viavoice->set("mh");
        select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
        undef %cmd_by_num;
        undef %cmd_num_by_text;
    }

}

#    $Vmenu_ms->{Active} = 0;
#    $Vmenu_ms->{Active} = 1;
#    $Vcmd_ms->{CommandSpoken} = 0;

sub voice_item_by_text {
    my ($text) = @_;
    $text = &_clean_text_string($text);
    my $cmd_num = $cmd_num_by_text{$text};
#   print "dbvc text=$text cn=$cmd_num ref=$cmd_by_num{$cmd_num} cs=$cmd_state_by_num{$cmd_num}\n";
    if ($cmd_num) {
        my $ref = $cmd_by_num{$cmd_num};
        return ($ref, $cmd_state_by_num{$cmd_num}, $ref->{vocab});
    }
    else {
        return undef;
    }
}

sub voice_items {
    my ($vocab) = @_;

    $vocab = 'mh' unless $vocab; # Default

    my @cmd_list = sort {$cmd_num_by_text{$a} <=> $cmd_num_by_text{$b}} keys %cmd_num_by_text;
                                # Add the filename to the list, so we can do better grep searches
    my @cmd_list2;
    for my $cmd (@cmd_list) {
        my ($ref, $said, $vocab_cmd) = &voice_item_by_text($cmd);
        next unless $vocab eq $vocab_cmd;
#       my $filename  = $ref->{filename};
        my $category  = $ref->{category};
        push(@cmd_list2, "$category: $cmd");
    }
    return @cmd_list2;
}

sub new {
    my ($class, $text, $response, $confirm, $vocab) = @_;
    $vocab = 'mh' unless $vocab; # default
    my $self = {text => $text, response => $response, confirm => $confirm, vocab => $vocab, state => ''};
    &_register($self);
    bless $self, $class;
    return $self;
}

my (@data, $index1, $index2, $index_last);
sub _register {
    my ($self) = @_;
    my $text  = $self->{text};
    my $vocab = $self->{vocab};
    my $info  = $self->{info};  # Dang, info gets set AFTER we define the object :(
    $info = '' unless $info;
    $vocab = "mh" unless $vocab;
    my $description = "$text: $info\n";
#   print "Voice_Cmd text: $text\n";

                                # Break phrase into [] {} chunks
    my ($index_state, $i);
    undef @data;
    $i = 0;
    while ($text =~ /([\[\{]?)([^\[\{\]\}]+)([\]\}]?)/g) {
        my ($l, $m, $r) = ($1, $2, $3);
        print "Warning, unmatched brackets in Voice_Cmd text: text=$text l=$l m=$m r=$r\n" if
            $l and !$r or !$l and $r;
        @{$data[$i]{text}} = ($l) ? split(',', $m) : ($m);
        $data[$i]{last}    = scalar @{$data[$i]{text}} - 1;
        if ($l eq '[') {
            print "Warning, more than one [] state bracket in Voice_Cmd text: i=$i l=$l r=$r text=$text\n" if $index_state;
            $index_state = $i;
        }
        $i++;
    }

                                # Itterate over all [] () groups
    $index_last = $i - 1;
    $index1 = $index2 = 0;
    $i = 0;
    while (1) {
        my $cmd = '';
        for my $j (0 .. $index_last) {
            $data[$j]{index} = 0 unless $data[$j]{index};
            $cmd .= $data[$j]{text}[$data[$j]{index}];
        }
        my $state = $data[$index_state]{text}[$data[$index_state]{index}] if defined $index_state;

                                # These commands have no real states ... there is no enumeration
                                #  - avoid saving the whole name as state.  Too much for state_log displays
        $state = 1 if !$state or $state eq $cmd;

        my $cmd_num = &_register2($self, $cmd, $vocab, $description);
        $cmd_state_by_num{$cmd_num} = $state;

#	    print "cmd_num=$cmd_num cmd=$cmd state=$state\n";
        last if &_increment_indexes > $index_last;
    }
}

sub _increment_indexes {
                                # Check if we are done with this group
    if ($data[$index1]{index} < $data[$index1]{last}) {
                                # Increment the next entry in this group
        $data[$index1]{index}++;
    }
    else {
                                # Check if we need to increment index2
        if ($index1 == $index2) {
                                # Reset indexes and increment index2
            for my $k (0 .. $index1) {
                $data[$k]{index} = 0;
            }
            $index1 = 0;
                                # Find the next unused index2 group entry
            while (1) {
                last if ++$index2 > $index_last;
                last if $data[$index2]{index} < $data[$index2]{last};
            }
            $data[$index2]{index}++;
        }
        else {
                                # Find the next unused index1 group entry
            while (1) {
                last if ++$index1 > $index_last;
                last if $data[$index1]{index} < $data[$index1]{last};
            }
            $index2 = $index1 if $index1 > $index2;
                                # Reset indexes and index1
            $data[$index1]{index}++;
            for my $k (0 .. $index1-1) {
                $data[$k]{index} = 0;
            }
            $index1 = 0;
        }
    }
    return $index2;
}    


sub _register2 {
    my($self, $text, $vocab, $des) = @_;
    $text = &_clean_text_string($text);
    push(@{$self->{texts}}, $text);

                                # With viavoice, only add at startup or when adding a new command
                                #  - point to new Voice_Cmd object pointer
    if ($Vcmd_viavoice and $cmd_num_by_text{$text}) {
        $cmd_by_num{$cmd_num_by_text{$text}} = $self;
        return;
    }

#   return $cmd_num_by_text{$text} if $cmd_num_by_text{$text};
    $cmd_num++;
    if ($cmd_num_by_text{$text}) {
        my $cmd = $cmd_by_num{$cmd_num_by_text{$text}};
        print "\n\nWarning, duplicate Voice_Cmd Text: $text   Cmd: $$cmd{text}\n\n";
    }
    print "db cmd=$cmd_num text=$text vocab=$vocab.\n" if $main::config_parms{debug} eq 'voice';

#   $cmd_file_by_text{$main::item_file_name} = $cmd_num;	# Yuck!
#   if ($Vmenu_ms and $Vmenu_ms->Add($cmd_num, $text, $vocab, $des)) {

                                # Always re-add the ms voice cmd
    if ($Vmenu_ms) {
#	    print "Voice cmd num=$cmd_num text=$text v=$vocab des=$des\n";
        $Vmenu_ms->Add($cmd_num, $text, $vocab, $des) if $text;
        print Win32::OLE->LastError() if Win32::OLE->LastError(0);
    }
                                # If it is not in the default vocabulary, save it and add it later
    if ($Vcmd_viavoice and $Vcmd_viavoice->active) {
        if ($vocab eq '' or $vocab eq 'mh') {
            $Vcmd_viavoice->set($text);
            select undef, undef, undef, .01; # Need this for now to avoid viavoice_server 'no data' error
        }
        else {
            push(@{$cmd_text_by_vocab{$vocab}}, $text);
        }
                                # We need beter handshaking here ... not a delay!
#       select undef, undef, undef, .05;
    }

    $cmd_num_by_text{$text} = $cmd_num;
    $cmd_text_by_num{$cmd_num} = $text;
    $cmd_by_num{$cmd_num} = $self;

                                # Create a word list we can use for command list searches
    for my $word (split(' ', $text)) {
        $cmd_word_list{$word}++;
    }
    
    return $cmd_num;
}

sub _clean_text_string {
    my ($text) = @_;
    $text = lc($text);
    $text =~ s/[\'\"]//g;	# Deletes quotes
    $text =~ s/^ +//;		# Delete leading  blanks
    $text =~ s/ $//;		# Delete trailing blanks
    return $text;
}

sub set_order {
    return unless $main::Reload;
    my ($self, $order) = @_;
    $self->{order} = $order;
}

sub get_last_cmd_time {
    return $last_cmd_time;
}
sub get_last_cmd {
    return $last_cmd_num;
}
sub said_this_pass {
    return $last_cmd_flag;
}
sub noise_this_pass {
    return $noise_this_pass;
}

sub text_by_num {
    my ($num) = @_;
    return $cmd_text_by_num{$num};
}

sub word_list {
    return sort keys %cmd_word_list;
}

sub mic {
    return unless $Vcmd_viavoice;
    my($state) = @_;

#   return if $main::Save{vr_mic} eq $state;
#   $main::Save{vr_mic} = $state;

#   &main::print_log("Mike $state");
    unless ($state eq 'on' or $state eq 'off') {
        &main::print_log("Error, Voice_Cmd::mic must be set to on or off: $state");
        return;
    }
    $Vcmd_viavoice->set("mic" . $state);
}

sub definevocab {
    return unless $Vcmd_viavoice;
    my($vocab, @phrases) = @_;
    $Vcmd_viavoice->set("definevocab");
    select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
    $Vcmd_viavoice->set($vocab);
    select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
    for my $phrase (@phrases) {
        $Vcmd_viavoice->set($phrase);
    }
    select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
    $Vcmd_viavoice->set('');
}
sub addtovocab {
    return unless $Vcmd_viavoice;
    my($vocab, @phrases) = @_;
    $Vcmd_viavoice->set("addtovocab");
    select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
    $Vcmd_viavoice->set($vocab);
    for my $phrase (@phrases) {
        $Vcmd_viavoice->set($phrase);
    }
    select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
    $Vcmd_viavoice->set('');
}
sub enablevocab {
    return unless $Vcmd_viavoice;
    my($vocab) = @_;
    $Vcmd_viavoice->set("enablevocab");
    select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
    $Vcmd_viavoice->set($vocab);
    select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
    $Vcmd_viavoice->set('');
}
sub disablevocab {
    return unless $Vcmd_viavoice;
    my($vocab) = @_;
    $Vcmd_viavoice->set("disablevocab");
    select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
    $Vcmd_viavoice->set($vocab);
    select undef, undef, undef, .1; # Need this for now to avoid viavoice_server 'no data' error
    $Vcmd_viavoice->set('');
}

    
1;

#
# $Log$
# Revision 1.23  2000/08/19 01:22:36  winter
# - 2.27 release
#
# Revision 1.22  2000/06/24 22:10:54  winter
# - 2.22 release.  Changes to read_table, tk_*, tie_* functions, and hook_ code
#
# Revision 1.21  2000/04/09 18:03:19  winter
# - 2.13 release
#
# Revision 1.20  2000/03/10 04:09:01  winter
# - Add Ibutton support and more web changes
#
# Revision 1.19  2000/02/20 04:47:54  winter
# -2.01 release
#
# Revision 1.18  2000/02/12 06:11:37  winter
# - commit lots of changes, in preperation for mh release 2.0
#
# Revision 1.17  2000/01/27 13:43:46  winter
# - update version number
#
# Revision 1.17  2000/01/13 13:39:03  winter
# - add %STATE% option
#
# Revision 1.16  1999/12/13 00:02:05  winter
# - numerous changes for viavoice.  Add cmd_word_list.
#
# Revision 1.15  1999/11/08 02:21:06  winter
# - add viavoice option
#
# Revision 1.14  1999/07/21 21:14:50  winter
# - add state method
#
# Revision 1.13  1999/06/27 20:13:04  winter
# - make debug conditional on 'voice'
#
# Revision 1.12  1999/02/21 00:26:46  winter
# - add $OS_win
#
# Revision 1.11  1999/02/16 02:06:23  winter
# - add filename to cmd_list2
#
# Revision 1.10  1999/02/04 14:20:40  winter
# - switch to new OLE calls.  Start on  VR 'deactivae on speech' code
#
# Revision 1.9  1999/01/30 19:50:31  winter
# - fix bug with cmd_by_num
#
# Revision 1.8  1999/01/22 02:42:43  winter
# - allow for linux by loading Win32 conditionally.  Allow for blank states.
#
# Revision 1.7  1999/01/10 02:29:16  winter
# - allow for 'check for voice command' loop, even with no $Vcmd, so web works without VR.
#
# Revision 1.6  1999/01/09 21:42:24  winter
# - improve error messages when ole steps fail
#
# Revision 1.5  1999/01/08 14:23:56  winter
# - add _clean_text_string to allow for leading/trailing blanks
#
# Revision 1.4  1999/01/07 01:54:18  winter
# - add 'set' method
#
# Revision 1.3  1998/12/07 14:35:14  winter
# - change warn level so we do not die
#
# Revision 1.2  1998/09/12 22:14:19  winter
# - add voice_items and {texts}
#
#
