# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# use shell notify-icon
# based on win32::TaskTray.pm (超ベータVer) by Noboruhi
# -----------------------------------------------------------------------------
package System::NotifyIcon::Win32;
use strict;
use warnings;
use base qw(Module);
use Win32::GUI (); # non-default
use RunLoop;
use Timer;
use Tiarra::Encoding;
our $AUTOLOAD;
my $can_use_win32api;
BEGIN {
    eval q{ use Win32::API; };
    $can_use_win32api = ($@) ? 0 : 1;
}
my $tooltip_length = 64;

my $event_handler_prefix = 'Win32Event_';

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);

    # 日本語等を使うためには文字コード変換しないといけないと思います。
    # 気をつけてください。

    # メインウィンドウ(現時点ではダミー)
    $this->_event_handler_init;
    $this->{main_window} = Win32::GUI::Window->new(
	-name => __PACKAGE__ . '::MainWindow',
	-text => 'Tiarra GUI',
	-width => 200,
	-height => 200);

    # コンテキストメニュー
    $this->event_handler_register('NotifyIcon_Popup_exit_Click');
    $this->event_handler_register('NotifyIcon_Popup_reload_Click');
    $this->{popup_menu} = Win32::GUI::Menu->new(
	"" => __PACKAGE__ . '::NotifyIcon_Popup',
	" > &Exit" => { -name => __PACKAGE__ . '::NotifyIcon_Popup_exit' },
	" > -" => 0,
	" > Re&load" => { -name => __PACKAGE__ . '::NotifyIcon_Popup_reload', -default => 1 },
       );

    $this->{window_stat} = 1; # start with show
    $this->{console_window} = Win32::GUI::GetPerlWindow();

    # タスクトレイ登録
    if (defined $this->config->iconfile) {
	$this->{icon} = new Win32::GUI::Icon($this->config->iconfile);
    }
    $this->event_handler_register('NotifyIcon_Click');
    $this->event_handler_register('NotifyIcon_RightClick');
    $this->{notify_icon} = $this->{main_window}->AddNotifyIcon(
	-name => __PACKAGE__ . '::NotifyIcon',
	(defined $this->{icon} ? (-icon => $this->{icon}) : ()));

    if (defined $this->config->hide_console_on_load &&
	    $this->config->hide_console_on_load) {
	$this->Win32Event_NotifyIcon_Click();
    }

    if ($can_use_win32api) {
	$this->{notifyicondata_version} = $this->init_win32_api();
	::debug_printmsg(__PACKAGE__.": use notify_icondata version ".
			     $this->{notifyicondata_version});
    }

    $this->modify_notifyicon_tooltip();
    $this->{set_nick_hook} = RunLoop::Hook->new(
	sub {
	    my ($hook) = shift;

	    $this->modify_notifyicon_tooltip();
	})->install('set-current-nick');

    return $this;
}

sub modify_notifyicon_tooltip {
    my ($this, $tooltip) = @_;
    $tooltip = (defined $tooltip ? "$tooltip - " : "");
    $tooltip .= sprintf("Tiarra #%s\n%s@%d\n",
			::version(),
			RunLoop->shared_loop->current_nick,
			Configuration->shared_conf->get('general')->tiarra_port,
		       );
    if (defined RunLoop->shared_loop->sysmsg_prefix(qw(system))) {
	$tooltip .= RunLoop->shared_loop->sysmsg_prefix(qw(system));
    }
    if (length($tooltip) >= $tooltip_length) {
	substr($tooltip,$tooltip_length - 1) = '';
    }
    if (!$can_use_win32api || $this->{notifyicondata_version} <= 1) {
	# This is internal API!
	Win32::GUI::NotifyIcon::Modify($this->{notify_icon}->{-handle},
				       -id => $this->{notify_icon}->{-id},
				       -tip => $tooltip);
    } else {
	my ($struct,$ret);

	# setversion
	$struct = Win32::API::Struct->new($this->{struct}->{NOTIFYICONDATA});
	$struct->{cbSize} = $struct->sizeof;
	$struct->{hWnd} = $this->{notify_icon}->{-handle};
	$struct->{uID} = $this->{notify_icon}->{-id};
	$struct->{uTimeout_or_Version} = $this->{define}->{NOTIFYICON_VERSION};
	$ret = $this->{func}->{Shell_NotifyIcon}->Call(
	    $this->{define}->{NIM_SETVERSION},
	    $struct);
	if (!$ret) {
	    ::debug_printmsg('Shell_NotifyIcon setversion return error:'.
				 sprintf('%x',$ret));
	};

	# modify
	use Data::Dumper;
	::debug_printmsg(Dumper([$tooltip, substr($tooltip,0,64)]));
	$struct = Win32::API::Struct->new($this->{struct}->{NOTIFYICONDATA});
	$struct->{cbSize} = $struct->sizeof;
	$struct->{hWnd} = $this->{notify_icon}->{-handle};
	$struct->{uID} = $this->{notify_icon}->{-id};
	$struct->{uFlags} |= $this->{define}->{NIF_TIP};
	if ($this->{is_unicode}) {
	    $tooltip = Tiarra::Encoding->new($tooltip,'utf8')->utf16;
	    # reverse endian
	    $tooltip = pack('n*', unpack('v*', $tooltip));
	}
	$struct->{szTip} = $tooltip;
	$struct->{uFlags} |= $this->{define}->{NIF_STATE};
	$struct->{dwState} = $this->{define}->{NIS_SHAREDICON};
	$struct->{dwStateMask} = $this->{define}->{NIS_SHAREDICON};
	#$struct->{uFlags} |= $this->{define}->{NIF_ICON};
	#$struct->{hIcon} = $this->{icon}->{-handle};
	#::debug_printmsg(Data::Dumper->Dump([$struct->Pack], [qw(struct)]));
	$ret = $this->{func}->{Shell_NotifyIcon}->Call(
	    $this->{define}->{NIM_MODIFY},
	    $struct);
	if (!$ret) {
	    ::debug_printmsg('Shell_NotifyIcon setversion return error:'.
				 sprintf('%x',$ret));
	};
    }
}

sub destruct {
    my $this = shift;

    $this->uninstall_hook('set_nick_hook');
    undef $this->{main_window}->{-notifyicons}{$this->{notify_icon}->{-id}};
    undef $this->{main_window}->{$this->{notify_icon}->{-name}};
    undef $this->{notify_icon};
    # This is internal API! but WIn32::GUI doesn't call this...(commented out)
    eval { Win32::GUI::DestroyWindow($this->{main_window}->{-handle}) };
    undef $this->{main_window};
    undef $this->{popup_menu};
    undef $this->{icon};
    # 終了時にはかならず表示させる
    Win32::GUI::Show($this->{console_window});
    undef $this->{shell_notifyicon_func};
    $this->_event_handler_destruct;
}

sub _event_handler_init {
    my $this = shift;

    # 先に定義を必要とするのか、うまく動かない
    my $autoload = sub {
	my (@args) = @_;

	if ($AUTOLOAD =~ /::DESTROY$/) {
	    # DESTROYは伝達させない。
	    return;
	}

	(my $method = $AUTOLOAD) =~ s/.+?:://g;

	# define method
	$this->event_handler_register($method);

	no strict 'refs';
	goto &$AUTOLOAD;
    };
    *AUTOLOAD = $autoload;

    $this->{timer} = Timer->new(
	Repeat => 1,
	After => ((defined $this->config->interval) ? $this->config->interval : 2),
	Code => sub {
	    my $timer = shift;
	    # noop
	})->install;
    $this->{hook} = RunLoop::Hook->new(
	sub {
	    my $hook = shift;

	    no warnings;
	    Win32::GUI::DoEvents();
	    $this->{timer}->reset();
	}
       )->install('after-select');

    return $this;
}

# uninstall hook or timer
sub uninstall_hook {
    my ($this, $name) = @_;

    if (defined $this->{$name}) {
	$this->{$name}->uninstall;
	delete $this->{$name};
    }
}

sub event_handler_register {
    my $this = shift;

    map {
	my $method = $_;
	if ($method =~ /^\Q$event_handler_prefix\E/) {
	    warn ("$method is already have $event_handler_prefix prefix.");
	    next;
	}
	$this->{registered_event_handlers}->{$method} = 1;
	#::debug_printmsg(__PACKAGE__ . '/register_event_handler: ' . $method);
	my $sub = sub {
	    no strict 'refs';
	    unshift(@_, $this);
	    eval "$event_handler_prefix$method(\@_)";
	};
	eval "*$method = \$sub";
    } @_;

    return $this;
}

sub event_handler_unregister {
    my $this = shift;

    foreach my $name (@_) {
	if (exists $this->{registered_event_handlers}->{$_}) {
	    eval "undef *$name";
	    delete $this->{registered_event_handlers}->{$_};
	}
    };

    return $this;
}

sub _event_handler_destruct {
    my $this = shift;

    $this->event_handler_unregister(keys %{$this->{registered_event_handlers}});
    $this->{registered_event_handlers} = {};
    undef *AUTOLOAD;

    $this->uninstall_hook('timer');
    $this->uninstall_hook('hook');
}


# NotifyIcon 用のイベントハンドラ
sub Win32Event_NotifyIcon_Click {
    my $this = shift;

    $this->{window_stat} = $this->{window_stat} ? 0 : 1;
    if ($this->{window_stat}) {
	Win32::GUI::Show( $this->{console_window} ); #コンソールをを出す
    } else {
	Win32::GUI::Hide( $this->{console_window} ); #コンソールを隠す
    }
    return -1;
};

sub Win32Event_NotifyIcon_RightClick {
    my $this = shift;
    my($x, $y) = Win32::GUI::GetCursorPos();

    $this->{main_window}->TrackPopupMenu(
	$this->{popup_menu}->{__PACKAGE__ . '::NotifyIcon_Popup'},
	$x,$y);

    return -1;
}

sub Win32Event_NotifyIcon_Popup_exit_Click {
    ::shutdown;
    return -1;
}

sub Win32Event_NotifyIcon_Popup_reload_Click {
    Timer->new(
	After => 0,
	Code => sub {
	    ReloadTrigger->reload_conf_if_updated;
	    ReloadTrigger->reload_mods_if_updated;
	}
       )->install;

    return -1;
}

sub init_win32_api {
    my ($this) = shift;

    # Shell 6.0 or above
    Win32::API::Type->typedef(qw(HRESULT LONG));

    $this->{is_unicode} = Win32::API::IsUnicode();
    $this->{is_unicode} = 1; #FIXME:DEBUG
    Win32::API::Type->typedef('TCHAR',
			      $this->{is_unicode} ? 'WCHAR' : 'CHAR');
    my @base_v1 = qw{
		     DWORD cbSize;
		     HWND hWnd;
		     UINT uID;
		     UINT uFlags;
		     UINT uCallbackMessage;
		     HICON hIcon;
		 };
    my @base_v2 = (@base_v1, qw{
		     TCHAR   szTip[128];
		     DWORD dwState;
		     DWORD dwStateMask;
		     TCHAR   szInfo[256];
		     UINT  uTimeout_or_Version;
		     TCHAR   szInfoTitle[64];
		     DWORD dwInfoFlags;
		 });
    Win32::API::Struct->typedef(
	'NOTIFYICONDATA_V1',
	    @base_v1,
	    qw{
	       TCHAR   szTip[64];
	   });
    Win32::API::Struct->typedef(
	'NOTIFYICONDATA_V2', @base_v2);
    Win32::API::Struct->typedef(
	'NOTIFYICONDATA_V3',
	    @base_v2,
	    qw{
	       DWORD guidItem1;
	       DWORD guidItem2;
	   });

    my $use_notifyicondata_version = 1;
    do {
	Win32::API::Struct->typedef(
	    'DLLVERSIONINFO',
		qw{
		   DWORD cbSize;
		   DWORD dwMajorVersion;
		   DWORD dwMinorVersion;
		   DWORD dwBuildNumber;
		   DWORD dwPlatformID;
	       });
	# ULONGLONG(Quad Octet) is not portable; can't use DLLVERSIONINFO2.
	my $dvi_func = Win32::API->new(
	    'shell32', 'HRESULT DllGetVersion(LPDLLVERSIONINFO dvi)',
	   );
	if (defined $dvi_func) {
	    my $dvi = Win32::API::Struct->new('DLLVERSIONINFO');
	    $dvi->{cbSize} = $dvi->sizeof;
	    my $ret = $dvi_func->Call($dvi);
	    if ($ret == 0) { # NOERROR
		if ($dvi->{dwMajorVersion} >= 6) {
		    $use_notifyicondata_version = 3;
		} elsif ($dvi->{dwMajorVersion} >= 5) {
		    $use_notifyicondata_version = 2;
		} else {
		    $use_notifyicondata_version = 1;
		}
	    } else {
		::debug_printmsg('DllGetVersion return error:' . sprintf('%x',$ret));
	    }
	} else {
	    ::debug_printmsg('cant load DllGetVersion');
	}
    };
    if ($use_notifyicondata_version >= 2) {
	$tooltip_length = 128;
    }
    # init
    my $define = $this->{define} = {};
    my $struct = $this->{struct} = {};
    my $func = $this->{func} = {};
    $struct->{NOTIFYICONDATA} =
	'NOTIFYICONDATA_V'.$use_notifyicondata_version;
    $func->{Shell_NotifyIcon} = Win32::API->new(
	'shell32',
	join('',
	     'BOOL Shell_NotifyIcon',
	     ($this->{is_unicode} ? 'W' : 'A'),
	     '(DWORD dwMessage, ',
	     ' LP'.$struct->{NOTIFYICONDATA}.' lpdata)'),
	#'shell32', 'Shell_NotifyIcon', [qw(L S)], 'C'
       );
    do {
	my @temp = qw(ADD MODIFY DELETE SETFOCUS SETVERSION);
	foreach (0 .. $#temp) {
	    $define->{'NIM_'.$temp[$_]} = $_;
	}
    };
    do {
	my @temp = qw(MESSAGE ICON TIP STATE INFO GUID);
	foreach (0 .. $#temp) {
	    $define->{'NIF_'.$temp[$_]} = 2 ** $_;
	}
    };
    do {
	my @temp = qw(HIDDEN SHAREDICON);
	foreach (0 .. $#temp) {
	    $define->{'NIS_'.$temp[$_]} = $_;
	}
    };
    $define->{NIIF_NONE} = 0x00;
    $define->{NIIF_INFO} = 0x01;
    $define->{NIIF_WARNING} = 0x02;
    $define->{NIIF_ERROR} = 0x03;
    $define->{NIIF_ICON_MASK} = 0x0F;
    $define->{NIIF_NOSOUND} = 0x10;
    $define->{NOTIFYICON_VERSION} = 3;
    return $use_notifyicondata_version;
}

1;
=pod
info: タスクトレイにアイコンを表示する。
default: off
section: important

# タスクトレイにアイコンを表示します。
# クリックすると表示非表示を切り替えることができ、右クリックすると
# Reload と Exit ができるコンテキストメニューを表示します。
# 多少反応が鈍いかもしれませんがちょっと待てば出てくると思います。

# Win32::GUI を必要とします。
# コンテキストメニューは表示している間処理をブロックしています。

# Win32 イベントループを処理する最大間隔を指定します。
-interval: 2

# 通知領域に表示するアイコンを指定します。
# Win32::GUI の制限でちゃんとしたアイコンファイルしか指定できません。
iconfile: guiperl.ico

# モジュールが読み込まれたときにコンソールウィンドウを隠すかどうかを
# 指定します。
hide-console-on-load: 1
=cut
