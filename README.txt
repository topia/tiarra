
====================================
Tiarra ����̂�������(for Windows)
====================================
(rev.003 2009/02/02) (ja.sjis)

... �ڎ� ...
1. ActivePerl �������.
2. �ݒ�t�@�C���̏���.
3. tiarra����̋N��.
4. IRC �N���C�A���g����Ȃ���.
5. �u���E�U����Ȃ���.
6. �ݒ��������.

1. ActivePerl �������.
-----------------------

1-1. ����ɕK�v�ȃc�[���Ȃ̂ł���܂�.
     �z�z���͂�����.(�p��̃T�C�g�����ǁ����B)
       http://www.activestate.com/Products/activeperl/
     (���[���邳��ɂ����Ă����̂�����b)
1-2. �wGet ActivePerl�x�̃����N��i��
1-3. �wDownload�x�̃����N��i��(�w��(Purchase)�̂��ׂɂ��邯�ǂ��ɂ���)
1-4. �wContact Details�x����Ă˂��Ă��邯��ǁA
     ���ڂ͓���Ȃ��Ă�OK(These fields are optional)�Ȃ̂�
     �C�ɂ����wContinue�x
1-5. �_�E�����[�h�y�[�W�ɂ���̂ŁA
     Download ActivePerl 5.8.8.822 for Windows (x86):
     ���_�E�����[�h�B
     AS package �� MSI �͂ǂ��炩��OK�B
     �C���X�g�[���̌`���Ⴄ�����Œ��g�͈ꏏ�B

1-6. ���ʂɃ_�u���N���b�N�ŃC���X�g�[���������߂�B
1-7. �������ʂɏI���Ǝv��.
     �r��������Ǝ��Ԃ����邩��.
     (�C���X�g�[���̓r���o�߂͂��Ƃŏ����c��������Ȃ�)

2. �ݒ�t�@�C���̏���.
----------------------

2-1. tiarra-r<rev>.zip ��W�J.
     (==> tiarra-r<rev> �Ƃ����t�H���_���ł��܂�)
     (�����̕����͐V�����Ȃ�Ƒ����܂�)
2-2. ����� C:\tiarra �Ƀ��l�[��.
     (���Ƃǂ��ł���������ǋ󔒂��܂܂Ȃ��ꏊ����������)
2-3. mini.conf �� tiarra.conf �Ƀ��l�[��.
     ���ꂪ�ݒ�t�@�C���ɂȂ�܂�.

2-4. tiarra.conf ���G�f�B�^(�������Ƃ�)�ŊJ��.
     �擪�̕��ɂ���
       # ���[�U�[���B�ȗ��s�\�ł��B
       nick: tiarra
       user: tiarra
       name: Tiarra the "Aeon"
     ���Ă����Ƃ����������ۂ���������.
     nick �����i�����閼�O.
     (user/name��whois�����Ƃ��Ɍ����镔��)

2-5. IRC�N���C�A���g�ڑ��p�X���[�h�̐���.
     (2-4)�ŏ���������������, �R�����g�ɖ������
       tiarra-password: sqPX2TZEectPk
     �Ƃ����s������܂�.
     make-password.bat ���_�u���N���b�N�����
       Please enter raw password:
     �ƕ������̂œ��͂��ăG���^�[.
       XXXXXXXXXXXXX is your encoded password.
       Use this for the general/tiarra-password entry.
       cleanup TerminateManager...done.
       ���s����ɂ͉����L�[�������Ă������� . . .
     �Ƃ����������ɏo�͏o��̂�,
       tiarra-password: XXXXXXXXXXXXX
     �Ƃ����ӂ��ɐݒ�t�@�C�������������܂�.

     �Ⴆ�� test �Ƃ����p�X���[�h���g���Ƃ��ɂ�,
     >>>>��������>>>>
       'svnversion' �́A�����R�}���h�܂��͊O���R�}���h�A
       ����\�ȃv���O�����܂��̓o�b�` �t�@�C���Ƃ��ĔF������Ă��܂���B
       Tiarra encrypts your raw password to use it for config file.
       
       
       Please enter raw password: test
       
       QJprAoiCPxwfY is your encoded password.
       Use this for the general/tiarra-password entry.
       ���s����ɂ͉����L�[�������Ă������� . . .
     <<<<�����܂�<<<<
     �Ƃ������ӂ��ɂł�̂�, ���̏ꍇ�� tiarra.conf �ɂ�
       tiarra-password: QJprAoiCPxwfY
     �ƋL�q���܂�.
     (���ۂ̈Í����p�X���[�h�͎��s���閈�ɈႤ���̂��\������܂�)

     ����) ���̃p�X���[�h�ł�8������蒷�������͖�������܂�.

2-6. Web�u���E�U�ڑ��p�X���[�h.
     + System::WebClient �u���b�N��(120�s��)��
     auth: :basic ircweb ircpass
     �Ƃ����s������܂�.
     auth: :basic <���[�U��> <�p�X���[�h>
     �Ƃ����`���œK���ȃ��[�U���y�уp�X���[�h�ɕύX���Ă�������.
     (���̍s�ł�make-password.bat���g���K�v�͂���܂���)
     (make-password.bat���g�����ꍇ�ɂ� {CRYPT}XXXX �ƋL�q����Η��p�ł��܂�)

2-7. �Y�ꂸ�ɕۑ����Đݒ芮��.

3. tiarra����̋N��
-------------------
3-1. run-tiarra.bat ���_�u���N���b�N�ŋN�����܂�.
3-2. �N�������
       C:\tiarra>perl tiarra  >> tiarra.log 2>&1
     �Ƃ����\������܂�(�ł܂��Ă�ۂ��Ă�OK).

3-3. ���s�̃��O�� tiarra.log �ɏo�͂���܂�.

     �t�@�C���̍Ō�̕���,
       [pid:1896 2008/04/08 01:37:06] Tiarra started listening 6667/tcp. (IPv4)
     �݂����ȍs���łĂ���΂����Ƒ��v�ł�.
     6667 �̕������|�[�g�ԍ��ɂȂ�܂�.

(�G���[�f�f1)
  ��ʂ�
    �v���Z�X�̓t�@�C���ɃA�N�Z�X�ł��܂���B�ʂ̃v���Z�X���g�p���ł��B
  �Əo�Ă�����, �����N���ς݂��ۂ��ł�.
  �������@:
    �����N�����Ă邩�炻��ȏ�N�����Ȃ��Ă����͂�.
    �G�f�B�^�ɂ���Ă̓��O�t�@�C�����J���Ă��炱�ꂪ�ł邩������܂���.

(�G���[�f�f2)
    C:\tiarra>pause
    ���s����ɂ͉����L�[�������Ă������� . . .
  �Əo����, �����N���Ɏ��s���Ă��܂�.
  tiarra.log ���m�F���Ă݂Ă�������.
  �������@(1):
      Usage: tiarra [--config=config-file] [options]
    �Ƃ�
      cleanup TerminateManager...done.
    �݂����ȍs�������, mini.conf �� tiarra.conf �ɃR�s�[����̂�
    �킷��Ă��܂�.
  �������@(2):
      'perl' �́A�����R�}���h�܂��͊O���R�}���h�A
      ����\�ȃv���O�����܂��̓o�b�` �t�@�C���Ƃ��ĔF������Ă��܂���B
    �݂��ȍs����������, ActivePerl �̃C���X�g�[���Ɏ��s���Ă���ۂ��ł�.
    ���꒼������Ȃ��邩���H


4. IRC �N���C�A���g����Ȃ���.
--------------------------------
4-1. ���ʂ�irc�T�[�o�̑����,
       server: localhost
       port:   6667
     �ɂȂ��܂�.

     ��, LimeChat 2(Windows) �̏ꍇ
     ���j���[����A "�T�[�o(S)" �� "�T�[�o��ǉ�(S)..." �_�C�A���O��
     �ݒ薼 �� �Ă��Ƃ��ɉ��ł�OK
     �z�X�g�� �� localhost
     �|�[�g�ԍ� �� 6667
     �T�[�o�p�X���[�h���g�� �� [2-5] �� tiarra-password
     �j�b�N�l�[�� �� [2-4] �� nick
     ���O�C���� �� [2-4] �� user
     ���O �� �i����Ȃ��̂łȂ�ł��j

4-2. �q�����OK.
     ���Ƃ͕��ʂƈꏏ.

     Tiarra ����o�R�Őڑ�����ƁA�`�����l�����̌��� "@ircnet" �Ƃ���
     �����񂪒ǉ�����ĕ\������܂�.
     �Ƃ肠�����C�ɂ��Ȃ��ł��������E���E
     (����� Tiarra ���񂪕����̃T�[�o�ɐڑ��ł���̂�, �ǂ̃T�[�o���
      �`�����l��������ʂ��邽�߂̂��̂ł�)

(�G���[�f�f1)
  * IRC�N���C�A���g����Tiarra����ɂȂ���Ȃ�.
    >> [3] ���m�F.
(�G���[�f�f2)
  * �p�X���[�h���Ⴄ�Ƃ�����
    >> [2-5] �� [4-1] ���m�F.
       IRC �N���C�A���g�Őݒ肷��̂̓p�X���[�h���̂���,
       tiarra.conf �� tiarra-password �ɋL�q����͈̂Í������ꂽ
       �p�X���[�h�Ȃ̂Ŏ��ۂɓ���(�ݒ�)����l�͕ʂ̕�����ɂȂ�܂�.
(�G���[�f�f3)
  * Tiarra ����ɂ͂Ȃ����Ă��`�����l���ɓ���Ȃ�.
    >> Tiarra���񂩂�IRC�T�[�o�̐ڑ����ł��ĂȂ��Ƃ������܂�.
       �ڑ����O�� tiarra.log �Ŋm�F�ł��܂�.

    �ڑ��J�n�̃��O(�܂��ڑ��r��)::
      [pid:5065 2009/01/26 21:38:28] network/ircnet: Connecting to irc.nara.wide.ad.jp(192.244.23.4)/6667 (IPv4)
      [pid:5065 2009/01/26 21:38:29] network/ircnet: Opened connection to irc.nara.wide.ad.jp(192.244.23.4)/6667 (IPv4).
      [pid:5065 2009/01/26 21:38:29] network/ircnet: Server replied 020(RPL_HELLO). Please wait.

    �ڑ������̃��O::
      [pid:5065 2009/01/26 21:39:19] network/ircnet: Logged-in successfuly into irc.nara.wide.ad.jp(192.244.23.4)/6667 (IPv4).

    �ڑ����s�̃��O(1)::
      ERROR :Closing Link: xxx[yyy@zzz.zzz.zzz.zzz] (Too many host connections (global))

    �ڑ����s�̃��O(2)::
      ERROR :Closing Link: xxx[yyy@zzz.zzz.zzz.zzz] (Too many host connections (local))

5. �u���E�U����Ȃ���.
------------------------
5-0. mini.conf ���g�����ꍇ�f�t�H���g�ł��̐ݒ肪�����Ă��܂�.
     ����ȊO�̏ꍇ�ɂ� System::WebClient ��K�؂ɐݒ肵�Ă�������.
5-1. �u���E�U��
       http://127.0.0.1:8668/irc/
     ���J��.
     �p�X���[�h��mini.conf�̂܂܂���
       user: ircweb
       pass: ircpass
     2-6 �ŕύX�����ꍇ�͂���.

(�G���[�f�f1)
  * �q����Ȃ�.
  �������@:
    (���Ƃł���)
    �Ƃ肠���� + Sytem::WebClient �̂Ȃ���
      debug: 1
    �������� tiarra.log �ɂ��낢��łĂ��܂�.


6. �ݒ��������.
----------------
6-1. tiarra.conf ��K���ɂ�����܂�.
6-2. �ł����ʂ�Windows/Mac���[�U�ɂ͗D�����Ȃ��ł������B
     (�e�L�X�g�`���̐ݒ�t�@�C���𒼐ڂ��������x�̔\�͂��K�v)
6-3. ���W���[��(�ǉ��@�\)�̈ꗗ��
      http://svn.coderepos.org/share/lang/perl/tiarra/trunk/doc/module-toc.html
     �ɂ���̂ŎQ�l��(���{��T�C�g).
6-4. sample.conf �Ƃ� all.conf ���Q�l�ɂȂ邩���H
     (�����Ă��邱�Ƃ͈ꉞ�ꏏ������)
6-5. �������߂̃��W���[����
     + Log::Channel   �`�����l����priv�̃��O����郂�W���[���B
     + Auto::Oper     ����̕�����𔭌������l��+o����B
     + Auto::Reply    ����̔����ɔ������Ĕ��������܂��B
     ������.
     �ݒ��ς�����̔��f���@��
     + System::Reload
     ���Q��( /load ���Ă�����������).

6-6. ���ӎ���
     ���W���[���̍X�V�Ɛݒ�̕ύX�𓯎��ɍs�����ꍇ,
     ���W���[���̍X�V���s���܂���.
     (���������̕ύX��������)
     ���̏ꍇ���W���[���̉���/�ēo�^���s����, �t�@�C���̃^�C���X�^���v��
     �X�V���邩����K�v������܂�.

     ���W���[���̉���/�ēo�^��, ���W���[���̖��O�� Sample::Module �������Ƃ����
     1. tiarra.conf �� + Sample::Module { �� - Sample Module { 
        �ɂ��ă����[�h(/load)
     2. tiarra.conf �� - Sample::Module { �� + Sample Module { 
        �ɖ߂��čēx�����[�h(/load)
     �ōs���܂�.

�X�V����.
rev.003 2009/02/02 LimeChat 2�ł̐ݒ������M.
                   �ڑ��ł��Ȃ��ۂ̃`�F�b�N�����M.
                   �p�X���[�h�̐ݒ���@�ɂ��ĉ��M.
rev.002 2008/05/31 �����ɒ���.
rev.001 2008/04/08 ����
[EOF]
