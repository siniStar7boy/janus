# Copyright (C) 2007-2008 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Commands::Chat;
use strict;
use warnings;

&Janus::command_add({
	cmd => 'chatto',
	help => 'Send a message to all opers on a specific network',
	details => [
		"Syntax: \002CHATTO\002 network|* message",
		'Note: The command /chatops, if available, may be relayed to all networks',
	],
	acl => 1,
	code => sub {
		my($src,$dst,$nname, @args) = @_;
		my $net = $Janus::nets{$nname};
		my $msg = join ' ', @args;
		return &Janus::jmsg($dst, "Could not find that network") unless $net || $1 eq '*';
		&Janus::append(+{
			type => 'CHATOPS',
			src => $src,
			msg => $msg,
			sendto => ($1 eq '*' ? $Janus::global : [ $net ]),
		});
	},
});

1;
