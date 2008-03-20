# Copyright (C) 2007-2008 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Modules::Quarrantine;
use strict;
use warnings;
use Persist;

my @cache :PersistAs(Channel, cache);
our %claim;

&Janus::save_vars(claim => \%claim);

sub resolve {
	my $chan = shift;
	return $cache[$$chan] if defined $cache[$$chan];

	my @list;
	for my $net ($chan->nets()) {
		my $nn = $net->name();
		my $name = $chan->str($net);
		my $reg = $claim{$nn}{$name};
		push @list, $nn if $reg;
	}

	$cache[$$chan] = join ',', @list; # and return it
}


&Janus::command_add({
	cmd => 'claim',
	help => 'Claim network ownership of a channel',
	details => [
		"Syntax: \002CLAIM\002 #channel [network]",
		"Claims network ownership for a channel. Opers and services outside these",
		"networks cannot make mode changes or kicks to this channel.",
		'-',
		"Currently this is not persisted between network restarts.",
		"Restricted to opers because of possible conflict with services.",
	],
	acl => 1,
	code => sub {
		my $nick = shift;
		my($cname, $nname) = $_[0] =~ /(#\S*)(?: (\S+))?/;
		my $chan = $nick->homenet()->chan($cname) or return;
		if ($nname) {
			my $off = ($nname =~ s/^-//);
			return &Janus::jmsg($nick, "Network not found") unless $Janus::nets{$nname};
			$claim{$nname}{$cname} = 1;
			delete $claim{$nname}{$cname} if $off;
			delete $cache[$$chan];
			&Janus::jmsg($nick, "Done");
		} else {
			my $nets = resolve($chan);
			&Janus::jmsg($nick, "Channel $cname is claimed by: $nets");
		}
	},
});

sub acl_ok {
	my $act = shift;
	my $src = $act->{src} or return 1;
	my $chan = $act->{dst};
	my $home = resolve($chan) or return 1;
	my $snet = $src->isa('Network') ? $src : $src->homenet();
	$snet->name() eq $_ and return 1 for split /,/, $home;
	if ($src->isa('Nick')) {
		# this is not a true operoverride check, just makes sure acting users
		# have >= halfop. This is really good enough, if you have halfop you
		# have a trust relationship with chanops, and they can remove it when
		# it is abused.
		for (qw/owner admin op halfop/) {
			return 1 if $chan->has_nmode($_, $src);
		}
	}
	0;
}

&Janus::hook_add(
	MODE => check => sub {
		my $act = shift;
		return undef if acl_ok($act);
		my %nact = %$act;
		delete $nact{src};
		my $net = delete $nact{except};
		map tr/+-/-+/, @{$nact{dirs}};
		$net->send(\%nact);
		1;
	}, KICK => check => sub {
		my $act = shift;
		return undef if acl_ok($act);
		return undef if $act->{nojlink}; # this is a slight hack, prevents reverting kills
		my $net = $act->{except};
		my $chan = $act->{dst};

		my $kicked = $act->{kickee};
		my $khome = $kicked->homenet();
		return undef if $khome eq $net; # I can't stop you kicking your own users

		if ($net->isa('RemoteJanus')) {
			# TODO bouncing a kick of a remote user by a remote user is a bad idea, but
			# should probably still be prevented. This requires sync of claims.
			return undef if $net->jparent($khome->jlink());

			# we have to resync network memberships.
			# If we send connects that we don't need to, it won't matter as
			# they will just be dropped.
			for my $rnet ($chan->nets()) {
				next unless $net->jparent($rnet->jlink());
				$net->send(+{
					type => 'CONNECT',
					dst => $kicked,
					net => $rnet,
				});
			}
		}
		$net->send(+{
			type => 'JOIN',
			src => $kicked,
			dst => $chan,
			mode => $chan->get_nmode($kicked),
		});
		1;
	}, TOPIC => check => sub {
		my $act = shift;
		return undef if acl_ok($act);
		my $net = $act->{except};
		my $chan = $act->{dst};
		return undef unless $chan->get_mode('topic'); # allow if not +t
		$net->send(+{
			type => 'TOPIC',
			dst => $chan,
			topic => $chan->topic(),
			topicts => $chan->topicts(),
			topicset => $chan->topicset(),
		});
		1;
	},
);

1;
