# -----------------------------------------------------------------------------
# $Id: Timer.pm,v 1.7 2004/03/27 10:41:17 admin Exp $
# -----------------------------------------------------------------------------
# RunLoop����Ͽ���졢���ꤵ�줿����˵�ư���륿���ޡ��Ǥ���
# ���ߤμ����Ǥϡ����٤��äȤʤäƤ��ޤ���
# �����ޡ���������ɬ�פʥѥ�᡼���ϡ�1)��ư���륵�֥롼����2)��ư�������ϵ�ư�ޤǤ��ÿ���
# 3)��ư�ޤǤ��ÿ�����ꤷ�����ϵ�ư��˺Ƥӥ����ޡ���RunLoop�˾褻�뤫�ɤ������Ǥ���
#
# ��ư���륵�֥롼����Ȥ��Ƥϡ�CODE�����ͤʤ鲿�Ǥ⹽���ޤ���
# Timer�Ϥ���CODE�ˡ������Ȥ��Ƽ�ʬ���Ȥ��Ϥ��ƥ����뤷�ޤ���
#
# 3�ø��Hello, world!��ɽ�����롣
# my $timer = Timer->new(
#     After => 3,
#     Code => sub { print "Hello, world!"; }
# )->install;
#
# 3�����Hello, world!��ɽ�����롣
# my $timer = Timer->new(
#     After => 3, # Interval�Ǥ��ɤ�
#     Code => sub { print "Hello, world!"; },
#     Repeat => 1
# )->install;
#
# 3�ø��Hello, world!��ɽ�����롣
# my $timer = Timer->new(
#     At => time + 3,
#     Code => sub { print "Hello, world!"; }
# )->install;
# -----------------------------------------------------------------------------
package Timer;
use strict;
use warnings;
use Carp;
use RunLoop;

sub new {
    my ($class,%args) = @_;
    my $obj = {
	fire_time => undef, # ȯư�������Υ��ݥå��á�
	interval => undef, # repeat������ϡ����δֳ֡����ʤ����̤�����
	code => undef, # ���餻�륳����
	runloop => undef, # RunLoop����Ͽ����Ƥ�����ϡ�����RunLoop��
    };
    bless $obj,$class;

    # After��Interval��Ʊ����
    $args{'After'} = $args{'Interval'} if exists($args{'Interval'});

    # At�ǻ��ꤹ�뤫��After�ޤ���Interval�ǻ��ꤹ�뤫�����Τɤ��餫�Ǥʤ���Фʤ�ʤ���
    if (exists($args{'At'}) && exists($args{'After'})) {
	croak "Timer cannot be made with both parameters At and After (or Interval).\n";
    }

    # At����After�ޤ���Interval�������Τɤ��餫��Ĥ�ɬ�ס�
    if (!exists($args{'At'}) && !exists($args{'After'})) {
	croak "Either parameter At or After (or Interval) is required to make Timer.\n";
    }
    
    # Code�Ͼ��ɬ�ס�
    if (!exists($args{'Code'})) {
	croak "Code is always required to make Timer.\n";
    }
    
    # Code��CODE���Ǥʤ����die��
    if (ref($args{'Code'}) ne 'CODE') {
	croak "Parameter Code was not valid CODE ref.\n";
    }

    $obj->{code} = $args{'Code'};
    
    if (defined $args{'At'}) {
	# At�ǵ�ư���郎Ϳ����줿���ϡ�Repeat�Ͻ���ʤ���
	if ($args{'Repeat'}) {
	    carp "Warning: It can't repeat that Timer made with At.\n";
	}

	$obj->{fire_time} = $args{'At'};
    }
    elsif (defined $args{'After'}) {
	# Repeat�����Ǥ���С��ֳ֤�After�ޤ���Interval��Ϳ����줿���ͤȤ��롣
	if ($args{'Repeat'}) {
	    $obj->{interval} = $args{'After'};
	}
	
	$obj->{fire_time} = time + $args{'After'};	
    }

    $obj;
}

sub time_to_fire {
    my ($this, $time) = @_;
    if ($time) {
	$this->{fire_time} = $time;
    }
    $this->{fire_time};
}

sub install {
    # RunLoop�˥��󥹥ȡ��뤹�롣
    # �������ά�������ϥǥե���Ȥ�RunLoop�˥��󥹥ȡ��뤹�롣
    my ($this,$runloop) = @_;

    if (defined $this->{runloop}) {
	# ���˥��󥹥ȡ���Ѥߤ��ä���
	croak "This Timer has been already installed to RunLoop.\n";
    }
    
    $runloop = RunLoop->shared_loop unless defined $runloop;
    $runloop->install_timer($this);
    
    $this->{runloop} = $runloop;
    $this;
}

sub uninstall {
    # ���󥹥ȡ��뤷��RunLoop���顢���Υ����ޡ��򥢥󥤥󥹥ȡ��뤹�롣
    my $this = shift;

    unless (defined $this->{runloop}) {
	# ���󥹥ȡ��뤵��Ƥ��ʤ���
	croak "This Timer hasn't been installed yet\n";
    }
    
    $this->{runloop}->uninstall_timer($this);
    $this->{runloop} = undef;
    $this;
}

sub execute {
    my $this = shift;
    # Code��¹Ԥ���ɬ�פʤ��ԡ��Ȥ��롣
    # RunLoop�Τߤ����Υ᥽�åɤ�Ƥ٤롣
    my ($package_of_caller,undef,undef) = caller;
    unless ($package_of_caller->isa('RunLoop')) {
	croak "Only RunLoop may call method execute of Timer.\n";
    }
    
    $this->{code}->($this);

    if (defined $this->{interval}) {
	$this->{fire_time} += $this->{interval};
    }
    else {
	$this->uninstall;
    }
    
    $this;
}

sub interval {
    # ����Ū��undef���Ϥ��С�interval���������롣
    my ($this,$value) = @_;
    if (defined $value) {
	$this->{interval} = $value;
    }
    elsif (@_ >= 2) {
	$this->{interval} = undef;
    }
    $this->{interval};
}

1;
