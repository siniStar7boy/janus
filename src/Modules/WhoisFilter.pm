# Copyright (C) 2007-2008 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Modules::WhoisFilter;
use strict;
use warnings;
use Persist;

&Janus::command_add(+{
	cmd => 'whoisfilter',
	help => 'Manages the remote-user /whois notice filter for your account',
	section => 'Account',
	details => [
		"Use: \002WHOISFILTER\002 on|off",
		'By default, if this module is loaded, you are only notified when a',
		'user does /whois nick nick on you. This command disables the filter',
		'for your nick\'s account',
	],
	acl => 'oper',
	code => sub {
		my($src,$dst,$arg) = @_;
		my $on = $arg && $arg !~ /off/;
		if (&Account::set($src, 'whoisfilter', $on)) {
			&Janus::jmsg($dst, 'Whois filtering is now '.($on ? 'on' : 'off').' for your nick');
		} else {
			&Janus::jmsg($dst, 'You must have an account to use this command');
		}
	}
});

&Janus::hook_add(
	MSG => check => sub {
		my $act = shift;
		if ($act->{msgtype} eq 'NOTICE' && $act->{src}->isa('Network')) {
			my $dst = $act->{dst};
			return undef unless $dst->isa('Nick');
			return undef unless $act->{msg} =~ m#^\*\*\* \S+ \(\S+\) did a /\S+ on you.$#;
			return undef if &Account::get($dst, 'whoisfilter');
			return 1;
		}
		undef;
	},
);

1;
