
#Category=News

#@ Check incoming email and announce big breaking news from CNN:
#@  - subscribe here:  http://www.cnn.com/EMAIL/
#@ Requires internet_mail.pl

                                # get_email_scan_file and $p_get_email are created by internet_mail.pl
if (done_now $p_get_email and -e $get_email_scan_file) {
    for my $line (file_read $get_email_scan_file) {
        my ($from, $to, $subject, $body) = $line =~ /From:(.+?) To:(.+?) Subject:(.+?) Body:(.+)/;
        if ($subject =~ /CNN breaking news/i or $subject =~ /News Alert/i) {
#           print "dbx1 s=$subject body=$body\nline=$line\n";
            $body =~ s/.+BREAKING NEWS from CNN.com//i;
            $body =~ s/For complete coverage.+//i;
            $body =~ s/Full story on .+//i;
            $body =~ s/Watch CNN .+//i;
            $body =~ s/Log on to .+//i;
            $body =~ s/\*+/\*/g;  # In case we somehow miss a line of these
            my $msg = "Notice, just received news item: $subject.\n  $body";
            display $msg, 0;
            speak   rooms => 'all', text => substr $msg, 0, 200;
        }
    }
}

#  BREAKING NEWS from CNN.com CNN has confirmed that convicted spy Edmond Pope has been released from a Russian prison.  of this story visit: http:

=for comment

From:    BreakingNews@CNN.COM
Subject: CNN Breaking News
Body: 
BREAKING NEWS from CNN.com

-- Vice President Al Gore withdraws from race; George W.Bush
becomes president-elect

For complete coverage of this story visit:
http://www.CNN.com


-- German court sentences ...
Watch CNN or log on to http://CNN.com /AOL Keyword: CNN for the latest news.

*******************************************************************
JOIN THE CONVERSATION - Click here and try 4 Risk-FREE
issues of TIME magazine & get a FREE Gift!
https://subs.timeinc.net/CampaignHandler/tdcnn?source_id=15
*******************************************************************


To unsubscribe from CNN.com's Breaking News E-Mail Alert, log on to:
http://cnn.com/EMAIL/breakingnews.html, go to http://cnn.com/email to
sign up for additional e-mail products




=cut
