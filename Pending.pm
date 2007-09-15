# Copyright (C) 2007 Daniel De Graaf
# Released under the Affero General Public License
# http://www.affero.org/oagpl.html
package Pending;
use strict;
use warnings;
use Persist;

our($VERSION) = '$Rev$' =~ /(\d+)/;

my @buffer   :Persist('buffer');
my @delegate :Persist('delegate');
my @peer     :Persist('peer')    :Arg('peer');

sub _init {
	my $net = shift;
	my($addr,$port) = $Conffile::inet{addr}->($peer[$$net]);
	print "Pending connection from $addr:$port\n";
	# TODO authenticate these
}

sub id {
	my $net = shift;
	'PEND#'.$$net;
}

sub parse {
	my($pnet, $line) = @_;
	my $rnet = $delegate[$$pnet];
	return $rnet->parse($line) if $rnet;

	push @{$buffer[$$pnet]}, $line;
	if ($line =~ /SERVER (\S+)/) {
		for my $id (keys %Conffile::netconf) {
			my $nconf = $Conffile::netconf{$id};
			if ($nconf->{server} && $nconf->{server} eq $1) {
				&Janus::delink($Janus::nets{$id}, 'Replaced by new connection') if $Janus::nets{$id};
				my $type = $nconf->{type};
				$rnet = eval "use $type; return ${type}->new(id => \$id)";
				next unless $rnet;
				print "Shifting new connection to $type network $id\n";
				$rnet->intro($nconf, 1);
				&Janus::insert_full({
					type => 'NETLINK',
					net => $rnet,
				});
				last;
			}
		}
		my $q = delete $Janus::netqueues{$pnet->id()};
		if ($rnet) {
			$delegate[$$pnet] = $rnet;
			$$q[3] = $rnet;
			$Janus::netqueues{$rnet->id()} = $q;
			for my $l (@{$buffer[$$pnet]}) {
				&Janus::in_socket($rnet, $l);
			}
		}
	} elsif ($line =~ /^<InterJanus /) {
		my $q = delete $Janus::netqueues{$pnet->id()};
		&Janus::load('Server::InterJanus');
		my $ij = Server::InterJanus->new();
		print "Shifting new connection to InterJanus link\n";
		my @out = $ij->parse($line);
		if (@out && $out[0]{type} eq 'InterJanus') {
			$$q[3] = $ij;
			$Janus::netqueues{$ij->id()} = $q;
			$ij->intro($Conffile::netconf{$ij->id()}, 1);
		}
		return @out;
	}
	();
}

sub dump_sendq { '' }

1;
