#!/usr/bin/perl
# cpan
# install File::Tail
use strict;
use warnings;
use File::Tail;
use Getopt::Std;
use Sys::Hostname;

my @files;
my @buffer;
my %options;
my $timeout = 10;
my $overrun = 0;
my $lastmail = 0;
my $usestdin = 1;
my $countdown = 0;
my $linelimit = 10;
my $linecount = 0;
my $user = getpwuid($<);
my $hostname = hostname;

my $to = $user;
my $from = "logalarm\@$hostname";
my $subject = 'logalarm';
sub HELP_MESSAGE {
print <<USAGE
	
	-F	Mail From
	-S	Subject
	-T	Mail To
	-t	Timout
	-l	Linelimit
USAGE
}

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
			print "selected\n";
			foreach (@pending) {
				print "pending\n";
				last LOOP if procline($_->{input}. ': '. $_->read);
			}
			#exit;
		}
	}
	
}; # end of eval #
	#print "unset alarm\n";
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
 
sub procline {
print "proc line\n";
	my $line = shift;
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

sub sendmail {

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
