# Copyright (C) 2007 Daniel De Graaf
# Released under the Affero General Public License
# http://www.affero.org/oagpl.html
package Server::BaseUID;
use LocalNetwork;
use Persist 'LocalNetwork';
use strict;
use warnings;
use integer;

our($VERSION) = '$Rev$' =~ /(\d+)/;

my @next_uid :Persist(nextuid);
my @nick2uid :Persist(nickuid);
my @uids     :Persist(uids);
my @gid2uid  :Persist(giduid);

my @letters = (0 .. 9, 'A' .. 'Z');

sub net2uid {
	return '00J' if @_ == 2 && $_[0] eq $_[1];
	my $srv = $_[-1];
	return '00J' if $srv->isa('Interface');
	my $res = ($$srv / 36) . $letters[$$srv % 36] . 'J';
	warn 'you have too many servers' if length $res > 3;
	$res;
}

sub next_uid {
	my($net, $srv) = @_;
	my $pfx = net2uid($srv);
	my $number = $next_uid[$$net]{$pfx}++;
	my $uid = '';
	for (1..6) {
		$uid = $letters[$number % 36].$uid;
		$number /= 36;
	}
	warn if $number;
	$pfx.$uid;
}

sub _init {
	my $net = shift;
	$uids[$$net] = {};
	$nick2uid[$$net] = {};
}

sub nick2uid {
	my($net, $nick) = @_;
	$gid2uid[$$net]{$nick->gid()};
}

sub mynick {
	my($net, $name) = @_;
	my $nick = $uids[$$net]{uc $name};
	unless ($nick) {
		print "UID '$name' does not exist; ignoring\n";
		return undef;
	}
	if ($nick->homenet() ne $net) {
		print "UID '$name' is from network '".$nick->homenet()->id().
			"' but was sourced from network '".$net->id()."'\n";
		return undef;
	}
	return $nick;
}

sub nick {
	my($net, $name) = @_;
	return $uids[$$net]{uc $name} if $uids[$$net]{uc $name};
	print "UID '$name' does not exist; ignoring\n" unless $_[2];
	undef;
}

# use for LOCAL nicks only
sub register_nick {
	my($net, $new, $new_uid) = @_;
	$uids[$$net]{uc $new_uid} = $new;
	$gid2uid[$$net]{$new->gid()} = $new_uid;
	print "Registering $new_uid as $new\n";
	my $name = $new->str($net);
	my $old_uid = delete $nick2uid[$$net]{lc $name};
	unless ($old_uid) {
		$nick2uid[$$net]{lc $name} = $new_uid;
		return ();
	}
	my $old = $uids[$$net]{uc $old_uid} or warn;
	my $tsctl = $old->ts() <=> $new->ts();

	if ($new->info('ident') eq $old->info('ident') && $new->info('host') eq $old->info('host')) {
		# this is a ghosting nick, we REVERSE the normal timestamping
		$tsctl = -$tsctl;
	}
	
	my @rv;
	if ($tsctl >= 0) {
		$nick2uid[$$net]{lc $name} = $new_uid;
		$nick2uid[$$net]{lc $old_uid} = $old_uid;
		if ($old->homenet() eq $net) {
			push @rv, +{
				type => 'NICK',
				dst => $old,
				nick => $old_uid,
				nickts => 1, # this is a UID-based nick, it ALWAYS wins.
			}
		} else {
			push @rv, +{
				type => 'RECONNECT',
				dst => $old,
				killed => 0,
			};
		}
	}
	if ($tsctl <= 0) {
		$nick2uid[$$net]{lc $new_uid} = $new_uid;
		$nick2uid[$$net]{lc $name} = $old_uid;
		push @rv, +{
			type => 'NICK',
			dst => $new,
			nick => $new_uid,
			nickts => 1,
		};
	}
	delete $nick2uid[$$net]{lc $name} if $tsctl == 0;
	@rv;
}

sub _request_nick {
	my($net, $nick, $reqnick, $tagged) = @_;
	$reqnick =~ s/[^0-9a-zA-Z\[\]\\^\-_`{|}]/_/g;
	my $maxlen = $net->nicklen();
	my $given = substr $reqnick, 0, $maxlen;

	$tagged = 1 if exists $nick2uid[$$net]->{lc $given};

	my $tagre = $net->param('force_tag');
	$tagged = 1 if $tagre && $given =~ /$tagre/;
		
	if ($tagged) {
		my $tagsep = $net->param('tag_prefix');
		$tagsep = '/' unless defined $tagsep;
		my $tag = $tagsep . $nick->homenet()->id();
		my $i = 0;
		$given = substr($reqnick, 0, $maxlen - length $tag) . $tag;
		while (exists $nick2uid[$$net]->{lc $given}) {
			my $itag = $tagsep.(++$i).$tag; # it will find a free nick eventually...
			$given = substr($reqnick, 0, $maxlen - length $itag) . $itag;
		}
	}
	$given;
}

# Request a nick on a remote network (CONNECT/JOIN must be sent AFTER this)
sub request_newnick {
	my($net, $nick, $reqnick, $tagged) = @_;
	my $given = _request_nick(@_);
	my $uid = $net->next_uid($nick->homenet());
	print "Registering $nick as uid $uid and nick $given\n";
	$uids[$$net]{uc $uid} = $nick;
	$nick2uid[$$net]{lc $given} = $uid;
	$gid2uid[$$net]{$nick->gid()} = $uid;
	return $given;
}

sub request_cnick {
	my($net, $nick, $reqnick, $tagged) = @_;
	my $given = _request_nick(@_);
	my $current = $nick->str($net);
	$nick2uid[$$net]{lc $given} = delete $nick2uid[$$net]{lc $current};
	$given;
}

# Release a nick on a remote network (PART/QUIT must be sent BEFORE this)
sub release_nick {
	my($net, $req) = @_;
	my $uid = delete $nick2uid[$$net]{lc $req};
	my $nick = delete $uids[$$net]{uc $uid};
	delete $gid2uid[$$net]{$nick->gid()} if $nick;
}

sub all_nicks {
	my $net = shift;
	values %{$uids[$$net]};
}

sub item {
	my($net, $item) = @_;
	return undef unless defined $item;
	return $net->chan($item) if $item =~ /^#/;
	return $uids[$$net]{uc $item} if exists $uids[$$net]{uc $item};
	return $net if $item =~ /\./ || $item =~ /^[0-9]..$/;
	return undef;
}

&Janus::hook_add(
	NETSPLIT => cleanup => sub {
		my $act = shift;
		my $net = $act->{net};
		return unless $net->isa(__PACKAGE__);
		my $tid = $net->id();
		if (%{$uids[$$net]}) {
			my @clean;
			warn "nicks remain after a netsplit, killing...";
			for my $nick ($net->all_nicks()) {
				push @clean, +{
					type => 'KILL',
					dst => $nick,
					net => $net,
					msg => 'JanusSplit',
					nojlink => 1,
				};
			}
			&Janus::insert_full(@clean);
		}
		if (%{$gid2uid[$$net]}) {
			my @clean;
			warn "nicks still remain after netsplit kills, trying again...";
			for my $gid (keys %{$gid2uid[$$net]}) {
				my $nick = $Janus::gnicks{$gid};
				push @clean, +{
					type => 'KILL',
					dst => $nick,
					net => $net,
					msg => 'JanusSplit',
					nojlink => 1,
				};
			}
			&Janus::insert_full(@clean);
		}
	},
);

1;