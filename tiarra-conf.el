;; -*- emacs-lisp -*-
;; ----------------------------------------------------------------------------
;; $Id$
;; ----------------------------------------------------------------------------
;; tiarra.conf編集用モード。
;; ----------------------------------------------------------------------------

;; キーマップ
(defvar tiarra-conf-mode-map
  (let ((map (make-keymap)))
    (define-key map "\M-n" 'tiarra-conf-next-block)
    (define-key map "\M-p" 'tiarra-conf-prev-block)
    (define-key map [?\C-c?\C-.] 'tiarra-conf-jump-to-block)
    (define-key map "\C-c." 'tiarra-conf-jump-to-block)
    map)
  "Keymap for tiarra conf mode.")

;; 構文定義
(defvar tiarra-conf-mode-syntax-table nil
  "Syntax table used while in tiarra conf mode.")
(if tiarra-conf-mode-syntax-table
    ()   ; 構文テーブルが既存ならば變更しない
  (setq tiarra-conf-mode-syntax-table (make-syntax-table))
  (modify-syntax-entry ?{ "(}")
  (modify-syntax-entry ?} "){"))

;; 略語定義
(defvar tiarra-conf-mode-abbrev-table nil
  "Abbrev table used while in tiarra conf mode.")
(define-abbrev-table 'tiarra-conf-mode-abbrev-table ())

;; フック
(defvar tiarra-conf-mode-hook nil
  "Normal hook runs when entering tiarra-conf-mode.")

(defun tiarra-conf-mode ()
  "Major mode for editing tiarra conf file.
\\{tiarra-conf-mode-map}
Turning on tiarra-conf-mode runs the normal hook `tiarra-conf-mode-hook'."
  (interactive)
  (kill-all-local-variables)
  (use-local-map tiarra-conf-mode-map)
  (set-syntax-table tiarra-conf-mode-syntax-table)
  (setq local-abbrev-table tiarra-conf-mode-abbrev-table)
  (setq mode-name "Tiarra-Conf")
  (setq major-mode 'tiarra-conf-mode)

  ;; フォントロックの設定
  (make-local-variable 'font-lock-defaults)
  (setq tiarra-conf-font-lock-keywords
	(list '("^[\t ]*#.*$"
		. font-lock-comment-face) ; コメント
	      '("^[\t ]*@.*$"
		. font-lock-warning-face) ; @文
	      '("^[\t ]*\\+[\t ]+.+$"
		. font-lock-type-face) ; + モジュール
	      '("^[\t ]*-[\t ]+.+$"
		. font-lock-constant-face) ; - モジュール 
	      '("^[\t ]*\\([^:\n]+\\)\\(:\\).*$"
		(1 font-lock-variable-name-face) ; key
		(2 font-lock-string-face)) ; ':'
	      '("^[\t ]*[^{}\n]+"
		. font-lock-function-name-face))) ; ブロック名
  (setq font-lock-defaults '(tiarra-conf-font-lock-keywords t))

  ;; mmm-modeの設定
  (if (featurep 'mmm-auto)
      (progn
	(mmm-add-group
	 'embedding-in-tconf
	 '((pre-in-tconf
	    :submode perl
	    :front   "%PRE{"
	    :back    "}ERP%")
	   (code-in-tconf
	    :submode perl
	    :front   "%CODE{"
	    :back    "}EDOC%")))
	(setq mmm-classes 'embedding-in-tconf)
	(mmm-mode-on)))
  
  (run-hooks 'tiarra-conf-mode-hook))

(defun tiarra-conf-next-token ()
  "カレントバッファの現在のカーソル位置から次のトークンを探して返す。
カーソルはそのトークンの終はりの位置へ移動する。

返されるのは次のやうなリストである。
\(\"トークン\" '種類)
種類:
  pair       -> キーと値のペア
  label      -> ブロックのラベル
  blockstart -> ブロックの開始記號
  blockend   -> ブロックの終了記號

トークンが無ければnilを返す。"
  (catch 'tiarra-conf-next-token
    ;; まずは空白とコメントを飛ばす。
    ;; @文も%PREも%CODEも飛ばす。
    ;; ……しかし「最小一致」の使へないElisp-Regexで
    ;; どうやつて%PREに一致させたものだか分からない。
    ;; 助けて。
    (or (re-search-forward "^\\([\n\t ]\\|#.*\\|@.*\\)*" nil t 1)
	(throw 'tiarra-conf-next-token nil))
    
    ;; "キー: 値"の形式であれば、行の終はりまでがトークン。
    (let* ((keychar "[^{}:\n\t ]") ; キーとして許される文字
	   (pair (concat keychar "+[\t ]*:.*")) ; キーと値のペア
	   
	   ;; 連續する二つのコロンは、特例としてラベル名に許す。
	   (labelchar "\\([^-{}\n\t ]\\|::\\)") ; ブロック名として許される文字
	   (label (concat "\\(\\(\\+\\|-\\)[\t ]+\\)?" labelchar "+")) ;; ブロックのラベル
	   
	   (blockstart "{") ;; ブロックの開始
	   (blockend "}") ;; ブロックの終了
	   
	   type)
      (setq type
	    (cond ((looking-at pair) 'pair)
		  ((looking-at label) 'label)
		  ((looking-at blockstart) 'blockstart)
		  ((looking-at blockend) 'blockend)))
      (if (null type)
	  nil
	(prog1 (list (buffer-substring (point) (match-end 0))
		     type)
	  (goto-char (match-end 0)))))))

(defun tiarra-conf-next-block (&optional n)
  "次からn番目のブロックの位置へカーソルを移動する。
nは省略可能で、省略された場合は`1'。
ブロックが見付かつた場合は、そのラベルの開始位置を返す。"
  (interactive "p")
  (catch 'tiarra-conf-next-block
    (setq n (if (numberp n) n 1))
    
    (if (< n 0)
	(throw 'tiarra-conf-next-block (tiarra-conf-prev-block (* -1 n))))
    (if (= n 0)
	(throw 'tiarra-conf-next-block nil))
    
    ;; カーソルを行の先頭へ移動。
    (beginning-of-line)
    
    (let (result token)
      ;; labelが來るまでトークンを探す。
      (while (progn
	       (setq token (tiarra-conf-next-token))
	       ;; tokenがnilまたはlabelなら終了。
	       (if (or (null token)
		       (eq (cadr token) 'label))
		   nil
		 ;; label以外のトークンなので、再度檢索。
		 t)))
      (if (null token)
	  ;; トークンが無い。ここで終はり。
	  nil
	(setq result (point))
	;; "{"の次の非空白文字へ移動。
	(re-search-forward "{" nil t 1)
	(re-search-forward "[^\n\t ]" nil t 1)
	(backward-char)
	
	;; nが2以上だったらもう一度。
	(if (> n 1)
	    (tiarra-conf-next-block (1- n))
	  result)))))

(defun tiarra-conf-prev-block (&optional n)
  "前からn番目のブロックの位置へカーソルを移動する。
nは省略可能で、省略された場合は`1'。
ブロックが見付かつた場合は、そのラベルの開始位置を返す。"
  (interactive "p")
  (catch 'tiarra-conf-prev-block
    (setq n (if (numberp n) n 1))
    (setq n (1+ n))
    
    (if (< n 0)
	(throw 'tiarra-conf-prev-block (tiarra-conf-next-block (* -1 n))))

    ;; まづ次のブロックを探して、その位置を記録する。nilならnilで良い。
    (let ((next-block-pos
	   (save-excursion (tiarra-conf-next-block)))
	  current-block-pos)
      ;; 一行づつカーソルを前に戻しつつ、「次の」ブロックを探してみる。
      ;; next-block-posよりも前に存在するブロックを見付けたら、そこで止める。
      (while (progn
	       (beginning-of-line)
	       (if (= (point) (point-min))
		   ;; これ以上前には戻れない。
		   nil
		 ;; まだ戻れる。
		 (previous-line)
		 (setq current-block-pos
		       (save-excursion (tiarra-conf-next-block)))
		 ;; 最初に見付けた「次の」ブロックがnilだつたり、
		 ;; 今囘見付けた「次の」ブロックと最初のそれが異つてゐたりすれば
		 ;; これを返して終了する。でなければ同じ事を繰返す。
		 (eq current-block-pos next-block-pos))))

      ;; nが2以上だつたらもう一度。
      (if (> n 1)
	  ;; カーソル位置を先頭へ戻す
	  (progn (beginning-of-line)
		 (tiarra-conf-prev-block (- n 2)))
	;; カーソルを適切な位置へ移動させる爲だけに
	;; tiarra-conf-next-blockを呼ぶ。
	(tiarra-conf-next-block)
	current-block-pos))))

(defun tiarra-conf-join (delimitor sequence)
  "perlのjoin(delimitor, sequence)と同じ。"
  (let (result join)
    (setq join (lambda (elem)
		 (setq result (if (null result)
				  elem
				(concat result delimitor elem)))))
    (mapcar join sequence)
    result))

(defun tiarra-conf-jump-to-block ()
  "そのconf中にあるブロックの名前を入力し、その場所にジャンプするコマンド。"
  (interactive)
  (let (comp-list ;; competing-readで使ふalist ("ブロック名" . labelトークンの直後の位置)
	parsing-block-stack ;; ("ブロック名" ...)
	blockname-to-jump
	point-to-jump)
    (save-excursion
      ;; カーソルをファイルの先頭へ
      (goto-char (point-min))
      ;; 一つづつトークンを見て行く。labelを見たら記録する。
      (while (let (token type blockname)
	       (setq token (tiarra-conf-next-token))
	       (if (null token)
		   ;; もうトークンが無い。
		   nil
		 (setq type (cadr token))
		 (cond ((eq type 'label)
			;; ﾌﾞﾛｯｸ(･∀･)ｶｲｼ
			(setq blockname (car token))
			(if (string-match "^[-+][\t ]+" blockname) ; +や-は取る。
			    (setq blockname (replace-match "" nil nil blockname)))
			(push blockname parsing-block-stack)
			(setq comp-list
			      (append comp-list
				      (list (cons
					     (tiarra-conf-join " - " (reverse parsing-block-stack))
					     (point))))))
		       ((eq type 'blockend)
			;; ﾌﾞﾛｯｸ(･Ａ･)ｼｭｳﾘｮｳ
			(pop parsing-block-stack)))
		 t)))
      ;; ブロック名を聞く。
      (let ((completion-ignore-case t)) ; 一時的にこの變數をtに。動的スコープは便利だね…。
	(setq blockname-to-jump (completing-read
				 "ジャンプするブロック: "
				 comp-list nil t)))
      (setq point-to-jump (cdr (assoc blockname-to-jump comp-list))))
    (if point-to-jump
	;; 適切な位置へカーソルを移動
	(progn
	  (goto-char point-to-jump)
	  (beginning-of-line)
	  (tiarra-conf-next-block)))))
      
	
