# Copyright (C) 2007 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Modules::Silence;
use strict;
use warnings;

sub service {
	my $n = shift;
	my $srv = $n->info('home_server');
	return 0 unless $srv;
	return 0 if $srv =~ /^services\.qliner/;
	return 1 if $srv =~ /^stats\./;
	return 1 if $srv =~ /^service.*\..*\./;
	return 1 if $srv =~ /^defender.*\..*\./;
	# TODO allow this to be user-specified, probably in network block
}

&Janus::hook_add(
	MSG => check => sub {
		my $act = shift;
		my $src = $act->{src};
		my $dst = $act->{dst};
		return 1 if $act->{msgtype} eq '439' || $act->{msgtype} eq '931';
		return undef unless $src->isa('Nick') && $dst->isa('Nick');
		return 1 if service($src);
		return 1 if service($dst);
		undef;
	}, KILL => check => sub {
		my $act = shift;
		my($src,$nick,$net) = @$act{qw(src dst net)};
		return undef unless $src && $src->isa('Nick');
		return undef unless service $src;
		return undef unless $nick->homenick() eq $nick->str($net);
		&Janus::append(+{
			type => 'RECONNECT',
			src => $src,
			dst => $nick,
			net => $net,
			killed => 1,
		});
		1;
	},
);

1;