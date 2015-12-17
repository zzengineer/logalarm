#!/usr/bin/perl
#
# zzenginer (c) 2015 <contact@zzengineer.com>
# https://github.com/zzengineer/logalarm
#
# logalarm - send emails if a watched file gets lines appended
# logalarm will send a mail consisting of a maxlines ( -l, default 23)
# from watched logfiles (X)OR stdin. If less lines then maxlines
# logalarm will wait for the give 'timeout' (in sec) time for more input
# before sending lines it has gathered. if the line buffer is overflown
# logalarm will dispose oldest lines in the period of the 'timeout'
# and send the latest lines to you noting how many lines where disposed.
#
# perl > 5.10.x
# cpan
# install File::Tail
# on freebsd, cpan version is broken beyond repair
# use /usr/ports/devel/p5-File-Tail
#
# example: email last 1024 loglines every 10 minutes if something happens on your site, skipping favicon and /status url
# perl logalarm.pl -F alarm@mymon.com -T private@jinail.com -S "http logfiles for mysite.com" -l 1024 -t 600 -ifavicon -i\\/status /www/log/*.log
#
# MISC:
# - rotated logs are not handled properly


use strict;
use warnings;
use File::Tail;
use Getopt::Std;
use Sys::Hostname;

$Getopt::Std::STANDARD_HELP_VERSION = 1;

my @files;
my @buffer;
my @ignores;
my %options;
my $timeout = 16;
my $overrun = 0;
my $lastmail = 0;
my $usestdin = 1;
my $countdown = 0;
my $linelimit = 32;
my $linecount = 0;
my $user = getpwuid($<);
my $hostname = hostname;

my $to = $user;
my $from = "logalarm\@$hostname";
my $subject = 'logalarm';

parseignores(); # alters @argv
getopts("F:l:T:t:S:", \%options);

$from      = $options{F} if defined $options{F};
$subject   = $options{S} if defined $options{S};
$to        = $options{T} if defined $options{T};
$timeout   = $options{t} if defined $options{t};
$linelimit = $options{l} if defined $options{l};

$usestdin = 0 if(scalar @ARGV > 0);

foreach (@ARGV) {
	push(@files,File::Tail->new(name=>$_,maxinterval=>$timeout,tail=>0));
}

for(;;) {

eval {
        local $SIG{ALRM} = sub { die "alarm\n" };

        if ($usestdin) {

                while (<STDIN>) {
                        last if procline('STDIN: '. $_);
                }

                # exit when pipe is closed and nothing to send in the buffer
                # or wait for the next alarm

                if(eof(STDIN)) {
                        if(scalar @buffer) {
                                sleep $timeout;
                        } else {
                                exit;
                        }
                }

        } else {

                LOOP: for(;;) {
                        my ($nfound,$timeleft,@pending) =
                        File::Tail::select(undef,undef,undef,undef,@files);

                        foreach (@pending) {
                                last LOOP if procline($_->{input}. ': '. $_->read);
                        }
                }
        }

}; # end of eval #

        alarm 0;
        $countdown = 0;

        if ($overrun) {
                @buffer = grep { defined $_ } @buffer[ -$linelimit .. -1 ];
        }

        if((time - $lastmail) < $timeout) {

                # we can wait for more lines as time goes by
                next if(scalar @buffer < $linelimit);

                # or enter overrun mode, here for readabilty
                $overrun = 1; next;
        }

        my $postfix = "";
        my $message = join('', @buffer);
        my $skipped = $linecount - $linelimit;

        $postfix.= " - CRITICAL OVERRUN ($skipped lines skipped)" if ($overrun);

        sendmail($to,$from,"$subject$postfix",$message);

        #print "Email Sent Successfully\n";

        $linecount = 0;
        $lastmail = time;
        $overrun = 0;
        @buffer = ();
}

sub procline
{
        my $line = shift;

	foreach my $ignore ( @ignores ) {
		return if( $line =~ /$ignore/ );
        }
	
        $linecount++;
        push @buffer, $line;

        if (!$countdown) {
                $countdown = 1;
                alarm $timeout;
        }

        # we have enuf lines lets send mail
        return 1 if (scalar @buffer == $linelimit && !$overrun);

        # wait for timeout and
        # delete old lines in linelimit batches
        # linelimit * 2 - max lines stored
        if ($overrun && scalar @buffer == $linelimit * 2) {
                @buffer = grep { defined $_ } @buffer[ -$linelimit .. -1 ];
        }
}

sub sendmail
{
        my $mto = shift;
        my $mfrom = shift;
        my $msubj = shift;
        my $mmsg = shift;

        open(MAIL, "|/usr/sbin/sendmail -t");
        # Email Header
        print MAIL "To: $mto\n";
        print MAIL "From: $mfrom\n";
        print MAIL "Subject: $msubj\n\n";
        # Email Body
        print MAIL $mmsg;

        close(MAIL);
}

sub HELP_MESSAGE
{
print <<USAGE

        -F      Mail From' default 'logalarm@`hostname`'
        -S      Subject, default 'logalarm'
        -T      Mail To, default exec user
        -i      ignore, regex matching lines to ignore
        -t      timout, timeout between mails in seconds
        -l      linelimit, linelimt per mail, discarding other
USAGE
}

# because Getopt::std fkin lacks multiple values for a single switch
# and Getopt::Long seems bloated like an Enterprise framework to me
# parsing "ignores" manualy is the only viable solution. fml!

sub parseignores
{
	my @ARGVCPY;
	while (@ARGV) {
		my $arg = shift @ARGV;

		if ($arg eq '--') {
			push @ARGVCPY, $arg, @ARGV;
			last;
		}

		if ($arg =~ /^-i\s*(.*)/) {
			if ($1) { push @ignores, $1; } 
			else    { push @ignores, shift(@ARGV); }
		} else {
			push @ARGVCPY, $arg;
		}
	}
	@ARGV = @ARGVCPY;
}
