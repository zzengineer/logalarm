use strict;
use warnings;
use Sys::Hostname;

my @buffer;
my $timeout = 10;
my $overrun = 0;
my $lastmail = 0;
my $countdown = 0;
my $linelimit = 10;
my $linecount = 0;
my $hostname = hostname;

my $to = 'your@mail.com';
my $from = "logalarm\@$hostname";
my $subject = 'http log errors';

for(;;) {

eval {
	local $SIG{ALRM} = sub { die "alarm\n" };

	while (<STDIN>) {
		$linecount++;
		push @buffer, $_;

		if (!$countdown) {
			$countdown = 1;
			alarm $timeout;
		}
		
		# we have enuf lines lets send mail
		last if (scalar @buffer == $linelimit && !$overrun);

		# wait for timeout and 
		# delete old lines in linelimit batches
		# linelimit * 2 - max lines stored
		if ($overrun && scalar @buffer == $linelimit * 2) {
			@buffer = grep { defined $_ } @buffer[ -$linelimit .. -1 ];
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

	my $message = join('', @buffer);

	my $postfix = "";
	my $skipped = $linecount - $linelimit;
	$postfix.= "- CRITICAL OVERRUN ($skipped lines skipped)" if ($overrun);

	open(MAIL, "|/usr/sbin/sendmail -t");
	# Email Header
	print MAIL "To: $to\n";
	print MAIL "From: $from\n";
	print MAIL "Subject: $subject$postfix\n\n";
	# Email Body
	print MAIL $message;
	
	close(MAIL);
	
	# print "Email Sent Successfully\n";
	
	$linecount = 0;
	$lastmail = time;
	$overrun = 0;
	@buffer = ();
}
