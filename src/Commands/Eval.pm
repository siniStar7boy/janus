# Copyright (C) 2007-2008 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Commands::Eval;
use strict;
use warnings;
use Data::Dumper;

&Janus::command_add({
	cmd => 'eeval',
	# nope. Not existing
	acl => 1,
	secret => 1,
	code => sub {
		my($nick,$expr) = @_;
		return &Janus::jmsg($nick, "Bad syntax") unless $expr =~ s/^(\S+)\s+//;
		return &Janus::jmsg($nick, "Bad syntax") unless $1 && $1 eq $Conffile::netconf{set}{evalpass};
		print "EVAL: $expr\n";
		&Log::audit('EVAL by '.$nick->netnick.': '.$expr);
		$expr =~ /(.*)/; # go around taint mode
		$expr = $1;
		my @r = eval $expr;
		@r = $@ if $@ && !@r;
		if (@r) {
			$_ = eval { Data::Dumper::Dumper(\@r); };
			s/\n//g;
			&Janus::jmsg($nick, $_);
		}
	},
});

1;
