;; -*- emacs-lisp -*-
;; ----------------------------------------------------------------------------
;; $Id$
;; ----------------------------------------------------------------------------
;; tiarra.conf�Խ��ѥ⡼�ɡ�
;; ----------------------------------------------------------------------------

;; �����ޥå�
(defvar tiarra-conf-mode-map
  (let ((map (make-keymap)))
    (define-key map "\M-n" 'tiarra-conf-next-block)
    (define-key map "\M-p" 'tiarra-conf-prev-block)
    (define-key map [?\C-c?\C-.] 'tiarra-conf-jump-to-block)
    (define-key map "\C-c." 'tiarra-conf-jump-to-block)
    map)
  "Keymap for tiarra conf mode.")

;; ��ʸ���
(defvar tiarra-conf-mode-syntax-table nil
  "Syntax table used while in tiarra conf mode.")
(if tiarra-conf-mode-syntax-table
    ()   ; ��ʸ�ơ��֥뤬��¸�ʤ���ι����ʤ�
  (setq tiarra-conf-mode-syntax-table (make-syntax-table))
  (modify-syntax-entry ?{ "(}")
  (modify-syntax-entry ?} "){"))

;; ά�����
(defvar tiarra-conf-mode-abbrev-table nil
  "Abbrev table used while in tiarra conf mode.")
(define-abbrev-table 'tiarra-conf-mode-abbrev-table ())

;; �եå�
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

  ;; �ե���ȥ�å�������
  (make-local-variable 'font-lock-defaults)
  (setq tiarra-conf-font-lock-keywords
	(list '("^[\t ]*#.*$"
		. font-lock-comment-face) ; ������
	      '("^[\t ]*@.*$"
		. font-lock-warning-face) ; @ʸ
	      '("^[\t ]*\\+[\t ]+.+$"
		. font-lock-type-face) ; + �⥸�塼��
	      '("^[\t ]*-[\t ]+.+$"
		. font-lock-constant-face) ; - �⥸�塼�� 
	      '("^[\t ]*\\([^:\n]+\\)\\(:\\).*$"
		(1 font-lock-variable-name-face) ; key
		(2 font-lock-string-face)) ; ':'
	      '("^[\t ]*[^{}\n]+"
		. font-lock-function-name-face))) ; �֥�å�̾
  (setq font-lock-defaults '(tiarra-conf-font-lock-keywords t))

  ;; mmm-mode������
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
  "�����ȥХåե��θ��ߤΥ���������֤��鼡�Υȡ������õ�����֤���
��������Ϥ��Υȡ�����ν��Ϥ�ΰ��֤ذ�ư���롣

�֤����Τϼ��Τ䤦�ʥꥹ�ȤǤ��롣
\(\"�ȡ�����\" '����)
����:
  pair       -> �������ͤΥڥ�
  label      -> �֥�å��Υ�٥�
  blockstart -> �֥�å��γ��ϵ���
  blockend   -> �֥�å��ν�λ����

�ȡ�����̵�����nil���֤���"
  (catch 'tiarra-conf-next-token
    ;; �ޤ��϶���ȥ����Ȥ����Ф���
    ;; @ʸ��%PRE��%CODE�����Ф���
    ;; �ġĤ������ֺǾ����ספλȤؤʤ�Elisp-Regex��
    ;; �ɤ���Ĥ�%PRE�˰��פ�������Τ���ʬ����ʤ���
    ;; �����ơ�
    (or (re-search-forward "^\\([\n\t ]\\|#.*\\|@.*\\)*" nil t 1)
	(throw 'tiarra-conf-next-token nil))
    
    ;; "����: ��"�η����Ǥ���С��Ԥν��Ϥ�ޤǤ��ȡ�����
    (let* ((keychar "[^{}:\n\t ]") ; �����Ȥ��Ƶ������ʸ��
	   (pair (concat keychar "+[\t ]*:.*")) ; �������ͤΥڥ�
	   
	   ;; Ϣ��������ĤΥ����ϡ�����Ȥ��ƥ�٥�̾�˵�����
	   (labelchar "\\([^-{}\n\t ]\\|::\\)") ; �֥�å�̾�Ȥ��Ƶ������ʸ��
	   (label (concat "\\(\\(\\+\\|-\\)[\t ]+\\)?" labelchar "+")) ;; �֥�å��Υ�٥�
	   
	   (blockstart "{") ;; �֥�å��γ���
	   (blockend "}") ;; �֥�å��ν�λ
	   
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
  "������n���ܤΥ֥�å��ΰ��֤إ���������ư���롣
n�Ͼ�ά��ǽ�ǡ���ά���줿����`1'��
�֥�å������դ��Ĥ����ϡ����Υ�٥�γ��ϰ��֤��֤���"
  (interactive "p")
  (catch 'tiarra-conf-next-block
    (setq n (if (numberp n) n 1))
    
    (if (< n 0)
	(throw 'tiarra-conf-next-block (tiarra-conf-prev-block (* -1 n))))
    (if (= n 0)
	(throw 'tiarra-conf-next-block nil))
    
    ;; ���������Ԥ���Ƭ�ذ�ư��
    (beginning-of-line)
    
    (let (result token)
      ;; label���Ԥ�ޤǥȡ������õ����
      (while (progn
	       (setq token (tiarra-conf-next-token))
	       ;; token��nil�ޤ���label�ʤ齪λ��
	       (if (or (null token)
		       (eq (cadr token) 'label))
		   nil
		 ;; label�ʳ��Υȡ�����ʤΤǡ�����������
		 t)))
      (if (null token)
	  ;; �ȡ�����̵���������ǽ��Ϥꡣ
	  nil
	(setq result (point))
	;; "{"�μ��������ʸ���ذ�ư��
	(re-search-forward "{" nil t 1)
	(re-search-forward "[^\n\t ]" nil t 1)
	(backward-char)
	
	;; n��2�ʾ���ä���⤦���١�
	(if (> n 1)
	    (tiarra-conf-next-block (1- n))
	  result)))))

(defun tiarra-conf-prev-block (&optional n)
  "������n���ܤΥ֥�å��ΰ��֤إ���������ư���롣
n�Ͼ�ά��ǽ�ǡ���ά���줿����`1'��
�֥�å������դ��Ĥ����ϡ����Υ�٥�γ��ϰ��֤��֤���"
  (interactive "p")
  (catch 'tiarra-conf-prev-block
    (setq n (if (numberp n) n 1))
    (setq n (1+ n))
    
    (if (< n 0)
	(throw 'tiarra-conf-prev-block (tiarra-conf-next-block (* -1 n))))

    ;; �ޤż��Υ֥�å���õ���ơ����ΰ��֤�Ͽ���롣nil�ʤ�nil���ɤ���
    (let ((next-block-pos
	   (save-excursion (tiarra-conf-next-block)))
	  current-block-pos)
      ;; ��ԤŤĥ�������������ᤷ�Ĥġ��ּ��Ρץ֥�å���õ���Ƥߤ롣
      ;; next-block-pos��������¸�ߤ���֥�å����դ����顢�����ǻߤ�롣
      (while (progn
	       (beginning-of-line)
	       (if (= (point) (point-min))
		   ;; ����ʾ����ˤ����ʤ���
		   nil
		 ;; �ޤ����롣
		 (previous-line)
		 (setq current-block-pos
		       (save-excursion (tiarra-conf-next-block)))
		 ;; �ǽ�˸��դ����ּ��Ρץ֥�å���nil���Ĥ��ꡢ
		 ;; ���Ÿ��դ����ּ��Ρץ֥�å��Ⱥǽ�Τ��줬�ۤĤƤ𤿤ꤹ���
		 ;; ������֤��ƽ�λ���롣�Ǥʤ����Ʊ�������֤���
		 (eq current-block-pos next-block-pos))))

      ;; n��2�ʾ���Ĥ���⤦���١�
      (if (> n 1)
	  ;; ����������֤���Ƭ���᤹
	  (progn (beginning-of-line)
		 (tiarra-conf-prev-block (- n 2)))
	;; ���������Ŭ�ڤʰ��֤ذ�ư������ત�����
	;; tiarra-conf-next-block��Ƥ֡�
	(tiarra-conf-next-block)
	current-block-pos))))

(defun tiarra-conf-join (delimitor sequence)
  "perl��join(delimitor, sequence)��Ʊ����"
  (let (result join)
    (setq join (lambda (elem)
		 (setq result (if (null result)
				  elem
				(concat result delimitor elem)))))
    (mapcar join sequence)
    result))

(defun tiarra-conf-jump-to-block ()
  "����conf��ˤ���֥�å���̾�������Ϥ������ξ��˥����פ��륳�ޥ�ɡ�"
  (interactive)
  (let (comp-list ;; competing-read�ǻȤ�alist ("�֥�å�̾" . label�ȡ������ľ��ΰ���)
	parsing-block-stack ;; ("�֥�å�̾" ...)
	blockname-to-jump
	point-to-jump)
    (save-excursion
      ;; ���������ե��������Ƭ��
      (goto-char (point-min))
      ;; ��ĤŤĥȡ�����򸫤ƹԤ���label�򸫤��鵭Ͽ���롣
      (while (let (token type blockname)
	       (setq token (tiarra-conf-next-token))
	       (if (null token)
		   ;; �⤦�ȡ�����̵����
		   nil
		 (setq type (cadr token))
		 (cond ((eq type 'label)
			;; �̎ގێ���(���ώ�)������
			(setq blockname (car token))
			(if (string-match "^[-+][\t ]+" blockname) ; +��-�ϼ�롣
			    (setq blockname (replace-match "" nil nil blockname)))
			(push blockname parsing-block-stack)
			(setq comp-list
			      (append comp-list
				      (list (cons
					     (tiarra-conf-join " - " (reverse parsing-block-stack))
					     (point))))))
		       ((eq type 'blockend)
			;; �̎ގێ���(������)�������؎���
			(pop parsing-block-stack)))
		 t)))
      ;; �֥�å�̾��ʹ����
      (let ((completion-ignore-case t)) ; ���Ū�ˤ������ˤ�t�ˡ�ưŪ�������פ��������͡ġ�
	(setq blockname-to-jump (completing-read
				 "�����פ���֥�å�: "
				 comp-list nil t)))
      (setq point-to-jump (cdr (assoc blockname-to-jump comp-list))))
    (if point-to-jump
	;; Ŭ�ڤʰ��֤إ���������ư
	(progn
	  (goto-char point-to-jump)
	  (beginning-of-line)
	  (tiarra-conf-next-block)))))
      
	
