# -----------------------------------------------------------------------------
# $Id: Alias.pm,v 1.10 2004/02/23 02:46:19 topia Exp $
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Log::ChannelList;
use strict;
use warnings;
use base qw(Module);
use Template;
use Mask;
use NumericReply;
use RunLoop;
use IO::File;
use Unicode::Japanese;
use Tools::DateConvert;
use Module::Use qw(Tools::DateConvert);

sub new {
  my $class = shift;
  my $this = $class->SUPER::new;
  $this->{networks} = [];
  $this->{unijp} = Unicode::Japanese->new;

  $this->_init;
}

sub _init {
    my $this = shift;

    foreach ($this->config->networks('all')) {
	my ($filename,$mask,$block) = split /\s+/;
	if (!defined($filename) || $filename eq '' ||
		!defined($mask) || $mask eq '' ||
		    !defined($block) || $block eq '') {
	    die "Illegal definition in __PACKAGE__/networks : $_\n";
	}
	push @{$this->{networks}},[$filename,$mask,$block];
    }

    return $this;
}

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Server')) {
	if ($type eq 'out' &&
		$msg->command eq 'LIST' &&
		    !defined $msg->param(0)) {
	    $io->remark('fetching-list', 1);
	    my $network = $this->_search_network($io->network_name);
	    if (defined $network) {
		my $config = $this->config->get($network->[2], 'block');
		if (defined $config &&
			defined $config->template && $config->template ne '') {
		    my $template = Template->new($config->template);
		    if (defined $template) {
			$io->remark(__PACKAGE__."/template", $template);
			$io->remark(__PACKAGE__."/config", $config);
		    }
		}
	    }
	} elsif ($type eq 'in' &&
		     $msg->command eq RPL_LIST) {
	    my $template = $io->remark(__PACKAGE__."/template");
	    my $config = $io->remark(__PACKAGE__."/config");
	    if (defined $template) {
		if (Mask::match_array([
		    Mask::array_or_default(
			'*',
			$config->mask('all'),
		       )], $msg->param(1))) {
		    $template->channel->expand(
			name => $this->_output_filter(
			    $config->charset,
			    $msg->param(1)),
			users => $this->_output_filter(
			    $config->charset,
			    $msg->param(2)),
		       );
		    if ($msg->param(2) ne '') {
			$template->channel->topic->expand(
			    topic => $this->_output_filter(
				$config->charset,
				$msg->param(3)),
			   );
			$template->channel->topic->add;
		    }
		    $template->channel->add;
		    if (!defined $io->remark(__PACKAGE__."/starttime")) {
			$io->remark(__PACKAGE__."/starttime", time());
		    }
		}
	    }
	} elsif ($type eq 'in' &&
		     $msg->command eq RPL_LISTEND) {
	    $io->remark('fetching-list', undef, 'delete');
	    if ($io->remark(__PACKAGE__."/template")) {
		my $network = $this->_search_network($io->network_name);
		my $template = $io->remark(__PACKAGE__."/template");
		my $config = $io->remark(__PACKAGE__."/config");
		if (defined $network && defined $template) {
		    $template->expand(
			fetch_starttime =>
			    $this->_output_filter(
				$config->charset,
				Tools::DateConvert::replace(
				    $config->fetch_starttime || '',
				    $io->remark(__PACKAGE__."/starttime") || time,
				   )),
			fetch_endtime =>
			    $this->_output_filter(
				$config->charset,
				Tools::DateConvert::replace(
				    $config->fetch_endtime || '',
				   )),
		       );
		    my $mode = do {
			my $mode_conf = $config->mode;
			if (defined $mode_conf) {
			    oct('0'.$mode_conf);
			}
			else {
			    0600;
			}
		    };
		    my $fh = IO::File->new($network->[0], O_CREAT | O_WRONLY, $mode);
		    $fh->print($template->str);
		    $fh->truncate($fh->tell);
		    $fh->close;
		}
		$io->remark(__PACKAGE__."/template", undef, 'delete');
		$io->remark(__PACKAGE__."/config", undef, 'delete');
		$io->remark(__PACKAGE__."/starttime", undef, 'delete');
	    }
	}
    }
    return $msg;
}

sub _output_filter {
    my ($this, $charset, $str) = @_;

    $str =~ s/>/&gt;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/&/&amp;/g;
    return $this->{unijp}->set($str)->$charset;
}

sub _search_network {
    my ($this, $network_name) = @_;

    foreach my $network (@{$this->{networks}}) {
	if (Mask::match($network->[1], $network_name)) {
	    return $network;
	}
    }
    return undef;
}

1;

=pod
info: チャンネルリストをテンプレートに沿って HTML 化します。
default: off

# list コマンドが実行された際に動作します。

# 出力したいファイル名、ネットワーク名、使う設定のブロックを指定します。。
networks: ircnet.html ircnet ircnet


ircnet {
  # テンプレートファイルを指定します。
  template: channellist.html.tmpl

  # 出力とテンプレートファイルの文字コードを指定します。
  charset: euc

  # 取得を開始/終了した時刻のフォーマットを指定します。
  fetch-starttime: %Y年%m月%d日 %H時%M分(日本時間)
  fetch-endtime: %Y年%m月%d日 %H時%M分(日本時間)

  # 表示するチャンネルの mask を指定します。
  mask: *
  mask: -re:^\&(AUTH|SERVICES|LOCAL|HASH|SERVERS|NUMERICS|CHANNEL|KILLS|NOTICES|ERRORS)

  # 出力するファイルのモードを指定します。
  mode: 644
}
=cut
