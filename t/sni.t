#!perl

use strict;
use warnings;
use Net::SSLeay;
use Socket;
use IO::Socket::SSL;
do './testlib.pl' || do './t/testlib.pl' || die "no testlib";

if ( ! IO::Socket::SSL->can_server_sni() ) {
    print "1..0 # skipped because no server side SNI support - openssl/Net::SSleay too old\n";
    exit;
}

if ( ! IO::Socket::SSL->can_client_sni() ) {
    print "1..0 # skipped because no client side SNI support - openssl/Net::SSleay too old\n";
    exit;
}

print "1..17\n";
my $server = IO::Socket::SSL->new(
    LocalAddr => '127.0.0.1',
    Listen => 2,
    ReuseAddr => 1,
    SSL_server => 1,
    SSL_ca_file => "certs/test-ca.pem",
    SSL_cert_file => {
	'server.local' => 'certs/server-cert.pem',
	'server2.local' => 'certs/server2-cert.pem',
	'smtp.mydomain.local' => "certs/server-wildcard.pem",
	'' => "certs/server-wildcard.pem",
    },
    SSL_key_file => {
	'server.local' => 'certs/server-key.pem',
	'server2.local' => 'certs/server2-key.pem',
	'smtp.mydomain.local' => "certs/server-wildcard.pem",
	'' => "certs/server-wildcard.pem",
    },
);

warn "\$!=$!, \$\@=$@, S\$SSL_ERROR=$SSL_ERROR" if ! $server;
print "not ok\n", exit if !$server;
print "ok # Server Initialization\n";
my $saddr = $server->sockhost.':'.$server->sockport;

# www13.other.local should match default ''
# all other should match the specific entries
my @tests = qw(
    server.local
    server2.local
    smtp.mydomain.local
    www13.other.local
);

defined( my $pid = fork() ) || die $!;
if ( $pid == 0 ) {
    close($server);

    for my $host (@tests) {
	my $client = IO::Socket::SSL->new(
	    PeerAddr => $saddr,
	    Domain => AF_INET,
	    SSL_verify_mode => 1,
	    SSL_hostname => $host,
	    SSL_ca_file => 'certs/test-ca.pem',
	) || print "not ";
	print "ok # client ssl connect $host\n";

	$client->verify_hostname($host,'http') or print "not ";
	print "ok # client verify hostname in cert $host\n";
	# Shutdown TLS properly. Otherwise TLSv1.3 $server->accept() fails with
	# ECONNRESET when a client disconnects too early.
	$client->close('SSL_fast_shutdown' => 0);
    }
    exit;
}

# If the server dies, a client can get stuck in read(2) while Perl interpreter
# is collecting children status in the die handler using wait4(2).
$SIG{__DIE__} = sub {
    STDERR->print("Server died. Killing client with $pid PID.\n");
    kill(9, $pid);
};
for my $host (@tests) {
    my $csock = $server->accept;
    if (!$csock) {
        print "not ok # server accept SSL_ERROR='$SSL_ERROR', errno='$!'";
    } else {
        print "ok # server accept\n";
    }
    my $name = $csock->get_servername;
    print "not " if ! $name or $name ne $host;
    print "ok # server got SNI name $host\n";
    # Shutdown TLS properly. Otherwise TLSv1.3 $server->accept() fails with
    # ECONNRESET when a client disconnects too early.
    $csock->close('SSL_fast_shutdown' => 0);
}
wait;
