# -----------------------------------------------------------------------------
# Iterator for the perl
# -----------------------------------------------------------------------------
# $Id: Iterator.pm,v 1.1 2002/11/14 08:45:50 admin Exp $
# -----------------------------------------------------------------------------
# STLに似せて作られたイテレータです。
# イテレータは次の操作が可能です。
# -----------------------------------------------------------------------------
# $ite->get
# イテレータが現在指している値を返します。
# 例えば$iteが現在IO::Fileのオブジェクトを指している場合、
# $ite->get->close;のような操作が可能です。
#
# この値取得メソッドは、そのイテレータが既に終端に達していた場合、
# つまりもう返すべき値が無くなっている場合はundefを返します。
# (ただし後述するようにイテレータがRoundIteratorだった場合は、
# 要素が一つも無かった場合を除いて決してundefを返しません。
# -----------------------------------------------------------------------------
# $ite++
# $ite--
# それぞれイテレータに次と前の値を指させます。
# ただし前者はForwardIterator、後者はBackwardIteratorを
# それぞれインプリメントしていなければ使えません。(無理に使おうとすると実行時エラーになります)
# 両方の操作が出来るイテレータはBidirectionalIteratorをインプリメントしています。
# 既に先端または終端に来ており$ite->get()がundefを返すような状態のイテレータに対し
# これらの操作を行なって限界からさらに外れようとした場合、そのイテレータが
# RoundIteratorを実装していた場合は逆の位置へ行きますが、そうでない場合はdieします。
# 
# $ite + 1
# $ite - 2
# それぞれこのイテレータの次の値と前の前の値を指すイテレータを生成して返します。
# ただしこれらはRandomAccessIteratorをインプリメントしていなければ使えません。
# これらの操作によって限界を突破した場合は、RoundIteratorを実装していれば
# 反対側へ行きますが、そうでなければdieします。
# -----------------------------------------------------------------------------
# このクラスは全てのイテレータを表わす抽象クラスです。
# インスタンスを生成する事は出来ません。
# -----------------------------------------------------------------------------
package Iterator;
use strict;
use warnings;

sub get {
    die "Iterator has to override get().\n";
}

1;
