# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# use shell notify-icon
# based on win32::TaskTray.pm (Ķ�١���Ver)
# -----------------------------------------------------------------------------
package System::NotifyIcon::Win32;
use strict;
use warnings;
use base qw(Module);
use Win32::GUI (); # non-default
use Timer;
our $AUTOLOAD;

my $event_handler_prefix = 'Win32Event_';

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;

    # ���ܸ�����Ȥ�����ˤ�ʸ���������Ѵ����ʤ��Ȥ����ʤ��Ȼפ��ޤ���
    # ����Ĥ��Ƥ���������

    # �ᥤ�󥦥���ɥ�(�������Ǥϥ��ߡ�)
    $this->_event_handler_init;
    $this->{main_window} = Win32::GUI::Window->new(
	-name => __PACKAGE__ . '::MainWindow',
	-text => 'Tiarra GUI',
	-width => 200,
	-height => 200);

    # ����ƥ����ȥ�˥塼
    $this->event_handler_register('NotifyIcon_Popup_exit_Click');
    $this->event_handler_register('NotifyIcon_Popup_reload_Click');
    $this->{popup_menu} = Win32::GUI::Menu->new(
	"" => __PACKAGE__ . '::NotifyIcon_Popup',
	" > &Exit" => { -name => __PACKAGE__ . '::NotifyIcon_Popup_exit' },
	" > -" => 0,
	" > &Reload" => { -name => __PACKAGE__ . '::NotifyIcon_Popup_reload', -default => 1 },
       );

    $this->{window_stat} = 1; # start with show
    $this->{console_window} = Win32::GUI::GetPerlWindow();

    # �������ȥ쥤��Ͽ
    if (defined $this->config->iconfile) {
	$this->{icon} = new Win32::GUI::Icon($this->config->iconfile);
    }
    $this->event_handler_register('NotifyIcon_Click');
    $this->event_handler_register('NotifyIcon_RightClick');
    $this->{notify_icon} = $this->{main_window}->AddNotifyIcon(
	-name => __PACKAGE__ . '::NotifyIcon',
	(defined $this->{icon} ? (-icon => $this->{icon}) : ()),
	-tip => 'Tiarra(irc proxy) #' . ::version());

    return $this;
}


sub destruct {
    my $this = shift;

    undef $this->{main_window}->{-notifyicons}{$this->{notify_icon}->{-id}};
    undef $this->{main_window}->{$this->{notify_icon}->{-name}};
    undef $this->{notify_icon};
    # This is internal API! but WIn32::GUI doesn't call this...(commented out)
    eval { Win32::GUI::DestroyWindow($this->{main_window}->{-handle}) };
    undef $this->{main_window};
    undef $this->{popup_menu};
    undef $this->{icon};
    # ��λ���ˤϤ��ʤ餺ɽ��������
    Win32::GUI::Show($this->{console_window});
    undef $this->{shell_notifyicon_func};
    $this->_event_handler_destruct;
}

sub _event_handler_init {
    my $this = shift;

    # ��������ɬ�פȤ���Τ������ޤ�ư���ʤ�
    my $autoload = sub {
	my (@args) = @_;

	if ($AUTOLOAD =~ /::DESTROY$/) {
	    # DESTROY����ã�����ʤ���
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
	eval "undef *$name";
	delete $this->{registered_event_handlers}->{$_};
    };

    return $this;
}

sub _event_handler_destruct {
    my $this = shift;

    $this->event_handler_unregister(keys %{$this->{registered_event_handlers}});
    $this->{registered_event_handlers} = {};
    undef *AUTOLOAD;

    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
	$this->{timer} = undef;
    }
    if (defined $this->{hook}) {
	$this->{hook}->uninstall;
	$this->{hook} = undef;
    }
}


# NotifyIcon �ѤΥ��٥�ȥϥ�ɥ�
sub Win32Event_NotifyIcon_Click {
    my $this = shift;

    $this->{window_stat} = $this->{window_stat} ? 0 : 1;
    if ($this->{window_stat}) {
	Win32::GUI::Show( $this->{console_window} ); #���󥽡�����Ф�
    } else {
	Win32::GUI::Hide( $this->{console_window} ); #���󥽡���򱣤�
    }
    return 1;
};

sub Win32Event_NotifyIcon_RightClick {
    my $this = shift;
    my($x, $y) = Win32::GUI::GetCursorPos();

    $this->{main_window}->TrackPopupMenu(
	$this->{popup_menu}->{__PACKAGE__ . '::NotifyIcon_Popup'},
	$x,$y);

    return 1;
}

sub Win32Event_NotifyIcon_Popup_exit_Click {
    ::shutdown();
}

sub Win32Event_NotifyIcon_Popup_reload_Click {
    Timer->new(
	After => 0,
	Code => sub {
	    ReloadTrigger->reload_conf_if_updated;
	    ReloadTrigger->reload_mods_if_updated;
	}
       )->install;
}

1;
=pod
info: �������ȥ쥤�˥��������ɽ�����롣
default: off

# �������ȥ쥤�˥��������ɽ�����ޤ���
# ����å������ɽ����ɽ�����ڤ��ؤ��뤳�Ȥ��Ǥ���������å������
# Reload �� Exit ���Ǥ��륳��ƥ����ȥ�˥塼��ɽ�����ޤ���
# ¿��ȿ�����ߤ����⤷��ޤ��󤬤���ä��ԤƤнФƤ���Ȼפ��ޤ���

# Win32::GUI ��ɬ�פȤ��ޤ���
# ����ƥ����ȥ�˥塼��ɽ�����Ƥ���ֽ�����֥�å����Ƥ��ޤ���

# Win32 ���٥�ȥ롼�פ�����������ֳ֤���ꤷ�ޤ���
-interval: 2

# �����ΰ��ɽ�����륢���������ꤷ�ޤ���
# Win32::GUI �����¤Ǥ����Ȥ�����������ե����뤷������Ǥ��ޤ���
iconfile: guiperl.ico
=cut
