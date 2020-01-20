
;; uses json
;; uses transient

;; TODO
;; - Integrate kube-tramp changes

(defvar-local kubectl--namespace "" "Namespace to pass to kubectl, or empty to pass no namespace")

(defvar-local kubectl--context "" "Context to pass to kubectl, or empty to pass no context")

(defvar-local kubectl--pods-selector "" "Selector to filter pods on, or empty to show all pods")

(defvar kubectl--shell "/bin/bash" "Shell to run when opening a term to a pod")

(defcustom kubectl--tramp-shell "/bin/sh"
  "Shell to run when creating a TRAMP session to a pod"
  :type 'string
  :group 'kubectl)

(defvar kubectl--kubectl "/usr/bin/kubectl" "Path to kubectl to use")

(defun kubectl--run (args)
  "Builds a kubectl commandline that ends with [args], run it,
and return the resulting output as a string"
  (shell-command-to-string (let ((ns (if (string= "" kubectl--namespace) "" (format "--namespace %s" kubectl--namespace) ))
        (ctx (if (string= "" kubectl--context) "" (format "--context %s" kubectl--context) )))
    (message "%s %s %s %s" kubectl--kubectl ns ctx args)
    (format "%s %s %s %s" kubectl--kubectl ns ctx args))))

(defun kubectl--list-args (args)
  "Builds a list of kubectl commandline arguments that ends with [args]"
  (append
   (if (string= "" kubectl--namespace) nil (list "--namespace" kubectl--namespace))
   (if (string= "" kubectl--context) nil (list "--context" kubectl--context))
   args))

(defun kubectl-tramp--running-pods-of (context namespace)
  "Collect kubernetes running pods in given context and namespace.

Return a list of pod names"
  (let* ((kubectl--context context)
         (kubectl--namespace namespace))
    (split-string (kubectl--run "get pods --no-headers=true  | awk '{print $1}'") "\n")))

(defun kubectl--tramp--parse-running-pods-of (&optional contextAndNamespace)
  "Return a list of (user host) tuples. contextAndNamespace is
expected to be a string with the k8s context, a pipe (|), and
then the namespace."
  (let* ((split (split-string contextAndNamespace "|"))
         (context (nth 0 split))
         (namespace (nth 1 split)))
    (cl-loop for name in (kubectl-tramp--running-pods-of context namespace)
             collect (list ""  name))))

(defun kubectl--tramp-method ()
  "Returns the name of the TRAMP method to reach kubernetes pods in the current context and namespace."
  ;; TRAMP doesn't like "-" or "_" in its method names.
  (format "kubectl%s%s" kubectl--context kubectl--namespace))

(defun kubectl--tramp-register-method ()
  "Defines a new TRAMP method that will use kubectl with the current context and namespace."
  (eval-after-load 'tramp
    '(progn
       (let* ((context kubectl--context)
              (namespace kubectl--namespace)
              (method (kubectl--tramp-method))
              (contextAndNamespace (format "%s|%s" kubectl--context kubectl--namespace)))
         (message "Adding tramp method %s" method)
         (add-to-list 'tramp-methods
                    `(,method
                      (tramp-login-program      ,kubectl--kubectl)
                      (tramp-login-args         (nil ("--context" ,context) ("--namespace" ,namespace) ("exec" "-it") ("-u" "%u") ("%h") ("bash")))
                      (tramp-remote-shell       ,kubectl--tramp-shell)
                      (tramp-remote-shell-args  ("-i" "-c"))))
         (setq completions `((kubernetes-tramp--parse-running-containers-of ,contextAndNamespace)))
         (message "  completions: %s" completions)
         ;;can't do the below, since it will check if files actually exist before adding to the list...
         ;;(tramp-set-completion-function method completions)
         (add-to-list 'tramp-completion-function-alist (cons method completions))
         ))))

(defun kubectl--context-names ()
  "Invokes kubectl to get a list of contexts"
  (split-string (shell-command-to-string (format "%s config get-contexts --no-headers=true -o name" kubectl--kubectl)) "\n"))

(defun kubectl-choose-context (context)
  "Select a new context interactively"
  (interactive (list (completing-read "Context: " (kubectl--context-names) nil t)))
  (setq kubectl--context context)
  (call-interactively 'kubectl-choose-namespace))

(defun kubectl--namespace-names ()
  "Invokes kubectl to get a list of namespaces"
  ;; TODO handle failure gracefully, and allow user to just type a namespace then
  (let ((kubectl--namespace ""))
    (split-string (kubectl--run "get namespaces --no-headers=true | awk '{print $1}'") "\n")))

(defun kubectl-choose-namespace (namespace)
  "Select a new namespace interactively"
  (interactive (list (completing-read "Namespace: " (kubectl--namespace-names) nil t)))
  (setq kubectl--namespace namespace)
  (call-interactively (cdr (car (minor-mode-key-binding "g")))))

(defun kubectl--show-yaml (bufname args)
  "Runs kubectl with [args] and shows the resulting yaml, in a buffer called [bufname]"
  (let* (
         (all_args (append args (list "-o" "yaml"))))
    (when (get-buffer bufname)
      (kill-buffer bufname))
    (apply #'call-process kubectl--kubectl nil bufname nil (kubectl--list-args all_args))
    (switch-to-buffer bufname)
    (yaml-mode)
    (read-only-mode)
    (goto-char 1)))

(defun kubectl--refresh (name args columns)
  "Refreshes the current view according to [args] as kubectl
  command line, and [columns] as tabulated list columns. The
  buffer is renamed to include [name]."
  (let ((bufname (if (and (string= "" kubectl--namespace) (string= "" kubectl--context))
                     (format "*k8s %s*" name)
                   (format "*k8s %s %s/%s*" name kubectl--context kubectl--namespace))))
    (unless (string= bufname (buffer-name))
      (when (get-buffer bufname)
        (kill-buffer bufname))
      (rename-buffer bufname)))

  (let ((rows (mapcar (lambda (line)
                        (let ((items (split-string line)))
                          (list (car items) (vconcat items))))
                      (seq-filter (lambda (line) (not (string= "" line)))
                                  (split-string (kubectl--run args) "\n"))))
        (oldpos (point)))
    (setq tabulated-list-format columns)
    (setq tabulated-list-entries rows)

    (tabulated-list-init-header)
    (tabulated-list-print)
    (goto-char oldpos)))

(define-transient-command kubectl--pods-log ()
  "Show console log"
  ["Arguments"
   ("-f" "Follow" "-f")
   ("-p" "Previous" "-p")
   ("-n" "Tail" "--tail=")
   ]
  ["Actions"
   ("l" "Log" kubectl--pods-get-log)])

(defun kubectl--log-kill-process ()
  "Kills the process associated with this buffer"
  (interactive)
  (delete-process (buffer-name)))

(define-minor-mode kubectl-log-mode
  "Minor mode to view log files (potentially while following them)"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "k") 'kubectl--log-kill-process)
            (define-key map (kbd "q") 'kill-this-buffer)
            map))

(defun kubectl--pods-get-log (&optional args)
  "Loads the logs of the selected kubernetes pod into a new buffer, passing [args] to the kubectl command"
  (interactive (list (transient-args 'kubectl--pods-log)))
  (let* ((podname (tabulated-list-get-id))
         (bufname (format "*k8s logs:%s*" podname))
         (process (format "*kubectl logs:%s" podname)))
    (when (get-buffer bufname)
      (kill-buffer bufname))
    (apply #'start-process process bufname kubectl--kubectl "logs" podname (kubectl--list-args args))
    (switch-to-buffer bufname)
    (read-only-mode)
    (kubectl-log-mode)))

(defun kubectl--pods-term ()
  "Opens up a term for the currently selected pod"
  (interactive)
  (let* ((podname (tabulated-list-get-id))
         (termbuf (apply 'make-term
                         (format "*k8s term:%s*" podname)
                         kubectl--kubectl
                         nil
                         (kubectl--list-args (list "exec" "-ti" podname kubectl--shell)))))
    (set-buffer termbuf)
    (term-mode)
    (term-char-mode)
    (switch-to-buffer termbuf)))

(defun kubectl--pods-run (command)
  "Runs [command] on the given pod, outputting its results asynchronously to a new buffer."
  (interactive "M")
  (let* ((podname (tabulated-list-get-id))
         (bufname (format "*k8s exec %s:%s" podname command))
         (process (format "*kubectl exec %s:%s" podname command))
         (args (append (list "exec" podname) (split-string-and-unquote command))))
    (when (get-buffer bufname)
      (kill-buffer bufname))
    (apply #'start-process process bufname kubectl--kubectl (kubectl--list-args args))
    (switch-to-buffer bufname)
    (read-only-mode)))

(defun kubectl--pods-run-custom (&optional args)
  (interactive)
  (call-interactively 'kubectl--pods-run))

(defun kubectl--pods-run-1 ()
  (interactive)
  (kubectl--pods-run "/usr/bin/jstack 1")) ;; we could do (thread-dump-start) after the process completes

(define-transient-command kubectl-pods-run ()
  "Execute a command"
  []
  ["Actions"
   ("1" "Run jstack" kubectl--pods-run-1)
   ("r" "Run custom command" kubectl--pods-run-custom)])

(defun kubectl-pods-refresh ()
  "Refreshes the current kubernetes pods view"
  (interactive)
  (let ((sel (if (string= "" kubectl--pods-selector) "" (format "--selector %s" kubectl--pods-selector) )))
    (kubectl--refresh (format "pods:%s" kubectl--pods-selector)
                    (format "get pods --no-headers=true %s" sel)
                    [("Pod" 66) ("Ready" 10) ("Status" 24) ("Restarts" 11) ("Age" 10)])))

(defun kubectl--pods-inspect ()
  "Shows detail about the currently selected pod"
  (interactive)
  (kubectl--show-yaml
   (format "*k8s pod:%s" (tabulated-list-get-id))
   (list "get" "pod" (tabulated-list-get-id))))

(defun kubectl--pods-dired ()
  "Opens dired in the currently selected pod over TRAMP"
  (interactive)
  (kubectl--tramp-register-method)
  (find-file (format "/%s:%s:" (kubectl--tramp-method) (tabulated-list-get-id))))

(define-minor-mode kubectl-pods-mode
  "A minor mode with a keymap for the kubernetes pod list"
  :keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") 'kubectl-choose-context)
    (define-key map (kbd "s") 'kubectl-choose-namespace)
    (define-key map (kbd "g") 'kubectl-pods-refresh)
    (define-key map (kbd "l") 'kubectl--pods-log)
    (define-key map (kbd "t") 'kubectl--pods-term)
    (define-key map (kbd "r") 'kubectl-pods-run)
    (define-key map (kbd "i") 'kubectl--pods-inspect)
    (define-key map (kbd "q") 'kubectl--list-deployments)
    (define-key map (kbd "d") 'kubectl--pods-dired)
    map))

(defun kubectl--deployments-refresh ()
  "Refreshes the current kubernetes deployments view"
  (interactive)
  (kubectl--refresh "deployments"
                    "get deployments --no-headers=true"
                    [("Deployment" 66) ("Desired" 10) ("Current" 10) ("Up-to-date" 10) ("Age" 10)]))

(defun kubectl--deployments-open ()
  "Opens the deployment currently selected"
  (interactive)
  (kubectl-open-deployment (tabulated-list-get-id)))

(defun kubectl--deployments-inspect ()
  "Shows detail about the currently selected deployment"
  (interactive)
  (kubectl--show-yaml
   (format "*k8s deployment:%s" (tabulated-list-get-id))
   (list "get" "deployment" (tabulated-list-get-id))))

(define-minor-mode kubectl-deployments-mode
  "A minor mode with a keymap for the kubernetes deployments list"
  :keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") 'kubectl-choose-context)
    (define-key map (kbd "s") 'kubectl-choose-namespace)
    (define-key map (kbd "g") 'kubectl--deployments-refresh)
    (define-key map (kbd "o") 'kubectl--deployments-open)
    (define-key map (kbd "RET") 'kubectl--deployments-open)
    (define-key map (kbd "i") 'kubectl--deployments-inspect)
    map))

(defun kubectl-deployments ()
  "Select a context and namespace, and show its deployments"
  (interactive)
  (switch-to-buffer "*kubernetes*")
  (tabulated-list-mode)
  (kubectl-deployments-mode)
  (call-interactively 'kubectl-choose-context))

(defun kubectl--list-deployments ()
  "Switch to the deployment list for the current context and namespace"
  (interactive)
  (switch-to-buffer "*kubernetes*")
  (tabulated-list-mode)
  (kubectl-deployments-mode)
  (kubectl-deployments-refresh))

(defun kubectl-open-deployment (name)
  (let* ((selflink (kubectl--run (format "get deployment.apps %s -o jsonpath={.metadata.selfLink}" name)))
         (json-object-type 'hash-table)
         (json-array-type 'list)
         (json-key-type 'string)
         (scale (json-read-from-string (kubectl--run (format "get --raw %s/scale" selflink))))
         (selector (gethash "selector" (gethash "status" scale)))
         (ns kubectl--namespace)
         (ctx kubectl--context))
    (switch-to-buffer "*kubernetes*")
    (tabulated-list-mode)
    (kubectl-pods-mode)
    (setq kubectl--pods-selector selector)
    (setq kubectl--namespace ns)
    (setq kubectl--context ctx)
    (kubectl-pods-refresh)))

(provide 'kubectl)
