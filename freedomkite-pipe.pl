#!/usr/bin/perl -w

use strict;
use Sys::Syslog;
use Digest::SHA qw(sha1_hex);
use Redis;

openlog('freedomkite', 'ndelay.pid', 'local1');

my $authdomain = 'freedombox.me';
my $target = '212.232.25.35';
my $redis = Redis->new( server => 'localhost:6379' );

$|=1;
my $line=<>;
chomp($line);

unless($line eq "HELO\t1") {
        print "FAIL\n";
        print STDERR "Received '$line'\n";
        <>;
        exit;
}

print "OK\n";

while(<>)
{
        syslog('debug', "Received: $_");
        chomp();
        my @arr=split(/\t/);
        if (@arr<6) {
                syslog('debug', 'Cannot parse input');
                print "FAIL\n";
                next;
        }

        my ($type,$qname,$qclass,$qtype,$id,$ip) = split(/\t/);

        syslog('debug', "type: $type, qname: $qname, qclass: $qclass, qtype: $qtype");

	$qname = lc($qname);

        if ($qtype eq "A" || $qtype eq "ANY") {

                my $result;

		if ($qname =~ /$authdomain\.$authdomain$/) {

			syslog('debug', "pagekite query");

	                my $pagekitequery = substr($qname, 0, -(length($authdomain)+1));
	                my @parts = split(/\./, $pagekitequery);
	                my $domain = join('.', splice(@parts, 4));
			my ($srand, $token, $sign, $proto) = @parts;
			my $payload = join(':', $proto, $domain, $srand, $token);
			my $salt = substr($sign, 0, 8);
			syslog('debug', "payload: $payload, sign: $sign");

			my $code = $redis->get('pagekite-domain-' . $domain);

			if (! defined $code) {

				$result = '255.255.255.0';
			} else {

				my $calc = sha1_hex($code . $payload . $salt);
				syslog('debug', "salt: $salt, calc: $calc");

				$result = (substr($calc, 0, 28) eq substr($sign, 8, 28)) ? '255.255.254.255' : '255.255.255.1';
			}
		} elsif ($qname =~ /$authdomain$/) {

			syslog('debug', "normal query");

			my $lookup = $qname;
			my $exists;

			while (length($lookup) > length($authdomain)) {

				$exists = $redis->exists('pagekite-domain-' . $lookup);
				syslog('debug', "lookup $lookup exists: $exists");

				last if $exists;
				$lookup = substr($lookup, index($lookup, '.') + 1);
			}

			$result = $target if $exists;
		} else {

			$result = undef;
		}

		if (defined $result) {

			syslog('debug', "result: $result");
			print "DATA	$qname	$qclass	A	3600	-1	$result\n";
		}
        }

        print "END\n";
}

