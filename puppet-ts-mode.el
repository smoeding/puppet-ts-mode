;;; puppet-ts-mode.el --- Major mode for Puppet using Tree-sitter -*- lexical-binding: t; -*-

;; Copyright (c) 2024, 2025, 2026  Stefan Möding

;; Author:           Stefan Möding <stm@kill-9.net>
;; Maintainer:       Stefan Möding <stm@kill-9.net>
;; Version:          0.2.1
;; Created:          <2024-03-02 13:05:03 stm>
;; Updated:          <2026-02-23 12:19:41 stm>
;; URL:              https://github.com/smoeding/puppet-ts-mode
;; Keywords:         languages
;; Package-Requires: ((emacs "29.1"))

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;; This file incorporates work covered by the following copyright and
;; permission notice:

;;   Copyright (C) 2013-2014, 2016  Sebastian Wiesner <swiesner@lunaryorn.com>
;;   Copyright (C) 2013, 2014  Bozhidar Batsov <bozhidar@batsov.com>
;;   Copyright (C) 2011  Puppet Labs Inc

;;; Commentary:

;; This package uses a Tree-sitter parser to provide syntax highlighting,
;; indentation, alignment, completion, xref navigation and code checking
;; for the Puppet domain-specific language.
;;
;; Syntax highlighting: Fontification is supported using custom faces for
;;   Puppet syntax elements like comments, strings, variables, constants,
;;   keywords, resource types and their metaparameters.  Syntax errors can be
;;   shown using a warning face by setting `treesit-font-lock-level' to 4.
;;   Some generic syntax elements (comments, strings, numbers,...) use the
;;   default Emacs faces.  This allows other packages like `flyspell' to
;;   spell-check comments and strings without any additional setup.
;;
;; Indentation: Automatic indentation according to the Puppet coding
;;   standards is provided.
;;
;; Alignment: Alignment rules for common Puppet expressions are included.
;;   The function `puppet-ts-align-block' (bound to "C-c C-a") aligns the
;;   current block with respect to "=>" for attributes and hashes or "=" for
;;   parameter lists.  The fat arrow and equal sign are electric and they
;;   perform automatic alignment.  Electricity is controlled by
;;   `puppet-ts-greater-is-electric' and `puppet-ts-equal-is-electric'.
;;
;; Completion: The mode updates the `completion-at-point' component to
;;   complete variable names, resource types and resource parameters.
;;   Tree-sitter is used to extract the local variable names from the
;;   current buffer.
;;
;; Imenu: Navigation to the resource types and variable assignments used in
;;   a file is implemented using the imenu facility.
;;
;; Cross-reference navigation: When point is on an identifier for a class,
;;   defined type, data type or custom function, the definition of that
;;   element can easily be opened with `xref-find-definitions' (bound to
;;   "M-.").  The list of directories that will be searched to locate the
;;   definition is customized in `puppet-ts-module-path'.
;;
;; Code checking: Validate the syntax of the current buffer with
;;   `puppet-ts-validate' (bound to "C-c C-v").  Lint the current buffer for
;;   semantic errors with `puppet-ts-lint' (bound to "C-c C-l").  Apply the
;;   current buffer in noop-mode with `puppet-ts-apply' (bound to "C-c C-c").
;;
;; The package uses a Tree-sitter library to parse Puppet code and you need
;; to install the appropriate parser (which is defined by the constant
;; `puppet-ts-mode-treesit-language-source').  This can be done by using
;; this Elisp code:
;;
;;    (require 'puppet-ts-mode)
;;    (puppet-ts-mode-install-grammar)
;;
;; Note that a C compiler is required for this step.  Using the function
;; provided by the package ensures that a version of the parser matching the
;; package will be installed.  These commands should also be used to update
;; the parser to the correct version when the package is updated.
;;

;;; Code:


;;; Requirements

(require 'treesit)
(require 'align)
(require 'xref)
(require 'seq)

(eval-when-compile
  (require 'cl-lib)
  (require 'skeleton)
  (require 'rx))


;;; Customization

(defgroup puppet-ts nil
  "Write Puppet manifests in Emacs."
  :prefix "puppet-ts-"
  :group 'languages
  :link '(url-link :tag "Repository"
                   "https://github.com/smoeding/puppet-ts-mode"))

(defvar puppet-ts--file-attribute-constants
  '("file" "directory" "link")
  "Attributes for file resources that will be formatted as constants.")

(defvar puppet-ts--package-attribute-constants
  '("present" "absent" "installed" "latest")
  "Attributes for package resources that will be formatted as constants.")

(defvar puppet-ts--service-attribute-constants
  '("running" "stopped")
  "Attributes for service resources that will be formatted as constants.")

;; https://www.puppet.com/docs/puppet/latest/metaparameter.html
(defvar puppet-ts--metaparameters
  '("alias" "audit" "before" "consume" "export" "loglevel" "noop"
    "notify" "require" "schedule" "stage" "subscribe" "tag" "ensure")
  "Metaparameter attributes for all resource types.
Strictly speaking, \"ensure\" is not a real metaparameter, but it
is added here because it is common and important.")

;; https://www.puppet.com/docs/puppet/latest/function.html
(defvar puppet-ts--builtin-functions
  '("abs" "alert" "all" "annotate" "any" "assert_type" "binary_file"
    "break" "call" "camelcase" "capitalize" "ceiling" "chomp" "chop"
    "compare" "convert_to" "create_resources" "defined" "dig" "digest"
    "downcase" "each" "emerg" "empty" "epp" "eyaml_lookup_key" "file"
    "filter" "find_file" "find_template" "flatten" "floor" "fqdn_rand"
    "generate" "get" "getvar" "group_by" "hiera" "hiera_array"
    "hiera_hash" "hiera_include" "hocon_data" "import" "index"
    "inline_epp" "inline_template" "join" "json_data" "keys" "length"
    "lest" "lookup" "lstrip" "map" "match" "max" "md5" "min"
    "module_directory" "new" "next" "partition" "realize" "reduce"
    "regsubst" "return" "reverse_each" "round" "rstrip" "scanf" "sha1"
    "sha256" "shellquote" "size" "slice" "sort" "split" "sprintf"
    "step" "strftime" "strip" "tagged" "template" "then" "tree_each"
    "type" "unique" "unwrap" "upcase" "values" "versioncmp" "with"
    "yaml_data"
    ;; Bolt: https://puppet.com/docs/bolt/0.x/plan_functions.html
    "apply" "apply_prep" "add_facts" "facts" "fail_plan" "file_upload"
    "get_targets" "puppetdb_fact" "puppetdb_query" "run_command"
    "run_plan" "run_script" "run_task" "set_feature" "set_var" "vars"
    "without_default_logging")
  "Internal functions provided by Puppet.")

(defvar puppet-ts--statement-functions
  '("include" "require" "contain" "tag"            ; Catalog statements
    "debug" "info" "notice" "warning" "err" "crit" ; Logging statements
    "fail")                                        ; Failure statements
  "Statement functions provided by Puppet.")

(defcustom puppet-ts-greater-is-electric t
  "Non-nil (and non-null) means a fat arrow should be electric.
Inserting the fat arrow \"=>\" in a hash or an attribute list
will perform automatic alignment if electric."
  :type 'boolean
  :group 'puppet-ts)

(defcustom puppet-ts-equal-is-electric t
  "Non-nil (and non-null) means an equal sign should be electric.
Inserting an equal sign \"=\" in a parameter list will perform
automatic alignment if electric."
  :type 'boolean
  :group 'puppet-ts)

;; Regular expressions

(defvar puppet-ts--constants-regex
  (rx-to-string `(seq bos
                      ,(cons 'or (append puppet-ts--service-attribute-constants
                                         puppet-ts--package-attribute-constants
                                         puppet-ts--file-attribute-constants))
                      eos)
                'no-group)
  "Regex to match Puppet attributes.")

(defvar puppet-ts--metaparameters-regex
  (rx-to-string `(seq bos
                      ,(cons 'or puppet-ts--metaparameters)
                      eos)
                'no-group)
  "Regex to match Puppet metaparameters.")

(defvar puppet-ts--builtin-functions-regex
  (rx-to-string `(seq bos
                      ,(cons 'or (append puppet-ts--builtin-functions
                                         puppet-ts--statement-functions))
                      eos)
                'no-group)
  "Regex to match Puppet internal functions.")

(defvar puppet-ts--statement-functions-regex
  (rx-to-string `(seq bos
                      ,(cons 'or puppet-ts--statement-functions)
                      eos)
                'no-group)
  "Regex to match Puppet statement functions.")


;;; Faces

(defface puppet-ts-keyword
  '((t :inherit font-lock-keyword-face))
  "Face for keywords in Puppet."
  :group 'puppet-ts)

(defface puppet-ts-resource-type
  '((t :inherit font-lock-type-face))
  "Face for resource types in Puppet."
  :group 'puppet-ts)

(defface puppet-ts-builtin
  '((t :inherit font-lock-builtin-face))
  "Face for built-in functions in Puppet."
  :group 'puppet-ts)

(defface puppet-ts-constant
  '((t :inherit font-lock-constant-face))
  "Face for a constant in Puppet."
  :group 'puppet-ts)

(defface puppet-ts-variable-name
  '((t :inherit font-lock-variable-name-face))
  "Face for the name of a variable in Puppet."
  :group 'puppet-ts)

(defface puppet-ts-variable-use
  '((t :inherit font-lock-variable-use-face))
  "Face for the name of a variable being referenced in Puppet."
  :group 'puppet-ts)

(defface puppet-ts-function-name
  '((t :inherit font-lock-function-name-face))
  "Face for the name of a function in Puppet."
  :group 'puppet-ts)

(defface puppet-ts-function-call
  '((t :inherit font-lock-function-call-face))
  "Face for the name of a function being called in Puppet."
  :group 'puppet-ts)


;; Font-Lock

(defvar puppet-ts-mode-feature-list
  ;; Level 1 usually contains only comments and definitions.
  ;; Level 2 usually adds keywords, strings, data types, etc.
  ;; Level 3 usually represents full-blown fontifications, including
  ;; assignments, constants, numbers and literals, etc.
  ;; Level 4 adds everything else that can be fontified: delimiters,
  ;; operators, brackets, punctuation, all functions, properties,
  ;; variables, etc.
  '((comment definition)
    (keyword string regexp resource-type)
    (constant number variable string-interpolation escape-sequence builtin function)
    (operator error))
  "`treesit-font-lock-feature-list' for `puppet-ts-mode'.")

(defvar puppet-ts-mode-font-lock-settings
  `( ;;
    :feature comment
    :language puppet
    ((comment) @font-lock-comment-face)

    :feature string
    :language puppet
    (((double_quoted_string) @font-lock-string-face)
     ((single_quoted_string) @font-lock-string-face)
     ((heredoc_body) @font-lock-string-face))

    :feature regexp
    :language puppet
    ((regex) @font-lock-regexp-face)

    :feature string-interpolation
    :language puppet
    :override t
    ((interpolation) @puppet-ts-variable-use)

    :feature escape-sequence
    :language puppet
    :override t
    ((double_quoted_string (escape_sequence) @font-lock-escape-face)
     (single_quoted_string (escape_sequence) @font-lock-escape-face)
     (heredoc_body (escape_sequence) @font-lock-escape-face))

    :feature variable
    :language puppet
    ((statement :anchor (variable ["$" (name)] @puppet-ts-variable-name))
     (variable ["$" (name)] @puppet-ts-variable-use))

    :feature constant
    :language puppet
    (([(true) (false) (default) (undef)] @puppet-ts-constant))

    :feature number
    :language puppet
    ((number) @font-lock-number-face)

    :feature definition
    :language puppet
    ((class_definition ["class" "inherits"] @puppet-ts-keyword)
     (define_definition "define" @puppet-ts-keyword)
     (node_definition "node" @puppet-ts-keyword)
     (plan_definition "plan" @puppet-ts-keyword)
     (type_alias "type" @puppet-ts-keyword)
     ;; function definitions
     (function_definition "function" @puppet-ts-keyword)
     (function_definition (classname (name) @puppet-ts-function-name))
     ;; names of defined classes, defined types, nodes, ...
     (classname (name) @puppet-ts-resource-type)
     ;; hostnames in a node definition
     (hostname (dotted_name) @puppet-ts-resource-type))

    :feature builtin
    :language puppet
    ((statement_function (name) @puppet-ts-builtin
                         (:match ,puppet-ts--statement-functions-regex
                                 @puppet-ts-builtin))
     (function_call (name) @puppet-ts-builtin
                    (:match ,puppet-ts--builtin-functions-regex
                            @puppet-ts-builtin))
     (named_access (name) @puppet-ts-builtin
                   (:match ,puppet-ts--builtin-functions-regex
                           @puppet-ts-builtin))
     (attribute name: (name) @puppet-ts-builtin
                (:match ,puppet-ts--metaparameters-regex
                        @puppet-ts-builtin))
     (attribute value: (name) @puppet-ts-builtin
                (:match ,puppet-ts--constants-regex
                        @puppet-ts-builtin)))

    :feature function
    :language puppet
    ((function_call (name) @puppet-ts-function-call))

    :feature keyword
    :language puppet
    (((if "if" @puppet-ts-keyword))
     ((elsif "elsif" @puppet-ts-keyword))
     ((else "else" @puppet-ts-keyword))
     ((unless "unless" @puppet-ts-keyword))
     ((case "case" @puppet-ts-keyword))
     (binary operator: ["and" "or" "in"] @puppet-ts-keyword))

    :feature resource-type
    :language puppet
    (((resource_type [(name) (virtual) (exported)] @puppet-ts-resource-type))
     ;; arguments to statement functions
     ((statement_function
       (argument_list (argument (name) @puppet-ts-resource-type))))
     ;; data and resource reference types
     ((type) @puppet-ts-resource-type))

    :feature operator
    :language puppet
    ((unary operator: "!" @font-lock-negation-char-face)
     (unary operator: _  @font-lock-operator-face)
     (binary operator: _ @font-lock-operator-face))

    :feature error
    :language puppet
    :override t
    ((ERROR) @font-lock-warning-face))
  "`treesit-font-lock-settings' for `puppet-ts-mode'.")


;; Indentation

(defcustom puppet-ts-indent-level 2
  "Number of spaces for each indentation step."
  :group 'puppet-ts
  :type 'integer
  :safe 'integerp)

(defcustom puppet-ts-indent-tabs-mode nil
  "Indentation can insert tabs in puppet mode if this is non-nil."
  :group 'puppet-ts
  :type 'boolean
  :safe 'booleanp)

(defvar puppet-ts-indent-rules
  `((puppet
     ;; top-level statements start in column zero
     ((parent-is "manifest") column-0 0)
     ;; blocks
     ((node-is ")") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((node-is "}") parent-bol 0)
     ((parent-is "block") parent-bol puppet-ts-indent-level)
     ;; compound statements
     ((node-is "elsif") parent-bol 0)
     ((node-is "else") parent-bol 0)
     ;; case statement
     ((match nil "case_option" nil 2 nil) first-sibling 0)
     ((parent-is "case") parent-bol puppet-ts-indent-level)
     ;; selector expression
     ((parent-is "selector") parent-bol puppet-ts-indent-level)
     ;; arrays & hashes
     ((parent-is "array") parent-bol puppet-ts-indent-level)
     ((parent-is "hash") parent-bol puppet-ts-indent-level)
     ;; resources & attributes
     ((match "attribute" "attribute_list" nil 2 nil) first-sibling 0)
     ((parent-is "resource_body") parent-bol puppet-ts-indent-level)
     ((parent-is "resource_type") parent-bol puppet-ts-indent-level)
     ((parent-is "resource_reference") parent-bol puppet-ts-indent-level)
     ((parent-is "resource_collector") parent-bol puppet-ts-indent-level)
     ;; class/defined type parameters
     ((parent-is "parameter_list") parent-bol puppet-ts-indent-level)
     ;; function calls
     ((match "argument" "argument_list" nil 2 nil) first-sibling 0)
     ((parent-is "function_call") parent-bol puppet-ts-indent-level)
     ;; default
     (catch-all parent-bol 0)))
  "Indentation rules for `puppet-ts-mode'.")


;; Helper macros & functions

(defmacro puppet-ts-node-type-predicate (&rest type)
  "Return a lambda function to test if a node has type TYPE.
The macro can take more than one argument in which case the node
type must match one of the given type names."
  (let ((regex `(seq bos (or ,@type) eos)))
    `(lambda (node)
       (string-match-p ,(rx-to-string regex t) (treesit-node-type node)))))

(defsubst puppet-ts--parent-resource-type (node)
  "Return the resource type that NODE belongs to."
  (treesit-parent-until node
                        (puppet-ts-node-type-predicate "resource_type")
                        t))

(defun puppet-ts-resource-type (node)
  "Return the resource type that NODE belongs to."
  (if-let* ((resource (puppet-ts--parent-resource-type node))
            (name (treesit-search-subtree resource "\\`name\\'")))
      (treesit-node-text name t)))

(defun puppet-ts-resource-title (node)
  "Return the title of the resource type that NODE belongs to."
  (if-let* ((resource (puppet-ts--parent-resource-type node))
            (body (treesit-search-subtree resource "\\`resource_body\\'"))
            (title (treesit-search-subtree body "\\`resource_title\\'")))
      (treesit-node-text title t)))

(defun puppet-ts-hierarchy (node)
  "Return a list of the node hierarchy for NODE."
  (cl-loop for     n = node
           then    (treesit-node-parent n)
           until   (treesit-node-eq n (treesit-buffer-root-node))
           if      (treesit-node-check n 'named)
           collect (treesit-node-type n)))


;; Imenu

(defun puppet-ts--resource-imenu-name (node)
  "Return the Imenu title for NODE."
  (let ((type (treesit-node-type node)))
    (cond ((string-equal type "resource_type")
           (concat (puppet-ts-resource-type node)
                   " "
                   (puppet-ts-resource-title node)))
          ((string-equal type "statement")
           (let ((lhs (treesit-node-child node 0 t)))
             (if (and lhs (string-equal (treesit-node-type lhs) "variable"))
                 (treesit-node-text lhs t)))))))

(defun puppet-ts--variable-assignment-p (node)
  "Return t if NODE is an assignment to a variable."
  (if (string-equal (treesit-node-type node) "statement")
      (let ((lhs (treesit-node-child node 0 t)))
        (and lhs (string-equal (treesit-node-type lhs) "variable")))))

(defvar puppet-ts-simple-imenu-settings
  '((nil "resource_type" nil puppet-ts--resource-imenu-name)
    ("Variables" "statement"
     puppet-ts--variable-assignment-p puppet-ts--resource-imenu-name))
  "The simple Imenu settings for `puppet-ts-mode'.
It should be a list of (CATEGORY REGEXP PRED NAME-FN).")


;;; Checking

(defcustom puppet-ts-validate-command "puppet parser validate --color=false"
  "Command to validate the syntax of a Puppet manifest."
  :type 'string
  :group 'puppet-ts)

(defcustom puppet-ts-lint-command
  (concat
   "puppet-lint --with-context "
   "--log-format \"%{path}:%{line}: %{kind}: %{message} (%{check})\"")
  "Command to lint a Puppet manifest."
  :type 'string
  :group 'puppet-ts)

(defcustom puppet-ts-apply-command "puppet apply --verbose --noop"
  "Command to apply a Puppet manifest."
  :type 'string
  :group 'puppet-ts)

(defvar-local puppet-ts-last-validate-command nil
  "The last command used for validation.")

(defvar-local puppet-ts-last-lint-command nil
  "The last command used for linting.")

(defvar-local puppet-ts-last-apply-command nil
  "The last command used to apply a manifest.")

(defun puppet-ts-run-check-command (command buffer-name-template)
  "Run COMMAND to check the current buffer.
BUFFER-NAME-TEMPLATE is used to create the buffer name."
  (save-some-buffers (not compilation-ask-about-save) nil)
  (compilation-start command nil (lambda (_)
                                   (format buffer-name-template command))))

(defun puppet-ts-read-command (prompt previous-command default-command)
  "Read a command from minibuffer with PROMPT.
PREVIOUS-COMMAND or DEFAULT-COMMAND are used if set."
  (let* ((buffer-file-name (or (buffer-file-name) ""))
         (filename (or (file-remote-p buffer-file-name 'localname)
                       buffer-file-name)))
    (read-string prompt (or previous-command
                            (concat default-command " "
                                    (shell-quote-argument filename))))))

(defun puppet-ts-validate (command)
  "Validate the syntax of the current buffer with COMMAND.
When called interactively, prompt for COMMAND."
  (interactive (list (puppet-ts-read-command "Validate command: "
                                             puppet-ts-last-validate-command
                                             puppet-ts-validate-command)))
  (setq puppet-ts-last-validate-command command)
  (puppet-ts-run-check-command command "*Puppet Validate: %s*"))

(defun puppet-ts-lint (command)
  "Lint the current buffer with COMMAND.
When called interactively, prompt for COMMAND."
  (interactive (list (puppet-ts-read-command "Lint command: "
                                             puppet-ts-last-lint-command
                                             puppet-ts-lint-command)))
  (setq puppet-ts-last-lint-command command)
  (puppet-ts-run-check-command command "*Puppet Lint: %s*"))

(defun puppet-ts-apply (command)
  "Apply the current manifest with COMMAND.
When called interactively, prompt for COMMAND."
  (interactive (list (puppet-ts-read-command "Apply command: "
                                             puppet-ts-last-apply-command
                                             puppet-ts-apply-command)))
  (setq puppet-ts-last-apply-command command)
  (puppet-ts-run-check-command command "*Puppet Apply: %s*"))


;; Alignment

(add-to-list 'align-sq-string-modes 'puppet-ts-mode)
(add-to-list 'align-dq-string-modes 'puppet-ts-mode)
(add-to-list 'align-open-comment-modes 'puppet-ts-mode)

(defconst puppet-ts-mode-align-rules
  '((puppet-param-default
     (regexp . "\\(\\s-+\\)$[a-z_][a-zA-Z0-9_]*\\(\\s-*\\)=\\(\\s-*\\)")
     (group  . (1 2 3))
     (modes  . '(puppet-ts-mode)))
    (puppet-param-nodefault
     (regexp . "\\(\\s-+\\)$[a-z_][a-zA-Z0-9_]*")
     (modes  . '(puppet-ts-mode)))
    (puppet-resource-arrow
     (regexp . "\\(\\s-*\\)[=+]>\\(\\s-*\\)")
     (group  . (1 2))
     (modes  . '(puppet-ts-mode))
     (separate . entire)))
  "Align rules for Puppet attributes and parameters.")

(defconst puppet-ts-mode-align-exclude-rules
  '((puppet-nested
     (regexp . "\\s-*=>\\s-*\\({[^}]*}\\)")
     (modes  . '(puppet-ts-mode))
     (separate . entire))
    (puppet-comment
     (regexp . "^\\s-*#\\(.*\\)")
     (modes . '(puppet-ts-mode))))
  "Rules for excluding lines from alignment for Puppet.")

(defconst puppet-ts-align-node-types-regex
  (rx bos
      (or "hash" "parameter_list" "resource_type" "resource_reference"
          "resource_collector" "selector")
      eos)
  "List of parser items that can be aligned.")

(defun puppet-ts-find-alignment-node (location)
  "Identify the innermost node of a block that can be aligned.
Walk the parse tree upwards starting from LOCATION and check the
nodes we find.  Terminate the search if we know how to align the
current node.  The constant `puppet-ts-align-node-types-regex'
has the regex of the acceptable node types.

Return the node if it is found or nil otherwise."
  (save-excursion
    (cl-loop for     node = (treesit-node-on location location)
             then    (treesit-node-parent node)
             always  node
             for     type = (treesit-node-type node)
             until   (string-match-p puppet-ts-align-node-types-regex type)
             ;;do    (message "check align node %s" type)
             finally return node)))

(defun puppet-ts-align-block ()
  "Align the innermost block of parameters, attributes or hashpairs."
  (interactive "*")
  (save-excursion
    ;; Skip back over a preceding "}" to perform alignment even when point
    ;; is just behind the closing bracket.
    (if (eq (preceding-char) ?})
        (backward-char))
    (when-let* ((node (puppet-ts-find-alignment-node (point)))
                (beg (treesit-node-start node))
                (end (treesit-node-end node)))
      ;;(message "about to align %S" (treesit-node-type node))
      (cond ((string-match-p "\\`resource_\\(?:collector\\|type\\)\\'"
                             (treesit-node-type node))
             ;; Restrict alignment to the attributes to avoid including
             ;; a variable used as title.  So we start where the first
             ;; attribute subtree begins.
             (if-let* ((attr (treesit-search-subtree node "attribute"))
                       (from (treesit-node-start attr)))
                 (align from end)))
            (t
             ;; Default alignent for all other elements
             (align beg end))))))

(defconst puppet-ts-inhibit-electric-alignment
  (rx bos (or "comment" "single_quoted_string" "double_quoted_string") eos)
  "Node types where electric alignment should not be performed.")

(defun puppet-ts-electric-greater (arg)
  "Insert a greater symbol while considering the prefix ARG.
The function checks if the preceding character is an equal sign
to make the fat arrow \"=>\" special.  Inserting a fat arrow in
a hash or an attribute list performs automatic alignment.  This
can be disabled by customizing `puppet-ts-greater-is-electric'."
  (interactive "*P")
  (self-insert-command (prefix-numeric-value arg))
  (if (and puppet-ts-greater-is-electric
           (memq (char-before (1- (point))) '(?= ?+)))
      (if-let* ((node (treesit-parent-until
                       (treesit-node-at (point))
                       (puppet-ts-node-type-predicate "comment"
                                                      "single_quoted_string"
                                                      "double_quoted_string"
                                                      "attribute_list"
                                                      "resource_collector"
                                                      "resource_reference"
                                                      "resource_type"
                                                      "hash"
                                                      "selector")
                       t))
                (type (treesit-node-type node)))
          (unless (string-match-p puppet-ts-inhibit-electric-alignment type)
            ;; Align only when not inside a comment or string
            (puppet-ts-align-block)
            ;; Move point to the start of the value
            (cond ((looking-at-p " ")
                   (forward-char))
                  ((eolp)
                   (insert " ")))))))

(defun puppet-ts-electric-equal (arg)
  "Insert an equal symbol while considering the prefix ARG."
  (interactive "*P")
  (self-insert-command (prefix-numeric-value arg))
  (if puppet-ts-equal-is-electric
      (if-let* ((node (treesit-parent-until
                       (treesit-node-at (point))
                       (puppet-ts-node-type-predicate "comment"
                                                      "single_quoted_string"
                                                      "double_quoted_string"
                                                      "parameter_list")
                       t))
                (type (treesit-node-type node)))
          (unless (string-match-p puppet-ts-inhibit-electric-alignment type)
            ;; Align only when not inside a comment or string
            (puppet-ts-align-block)
            ;; Move point to the start of the value
            (cond ((looking-at-p " ")
                   (forward-char))
                  ((eolp)
                   (insert " ")))))))


;;; Skeletons

(defun puppet-ts-dissect-filename (file)
  "Return list of file name components for FILE.
The first list element is the basename of FILE and the remaining
elements are the names of each directory from FILE to the root of
the filesystem."
  (cl-loop for path = (file-name-sans-extension file)
           then (directory-file-name (file-name-directory path))
           ;; stop iteration at the root of the directory
           ;; tree (should work for Windows & Unix/Linux)
           until (or (string-suffix-p ":" path)
                     (string-equal (file-name-directory path) path))
           collect (file-name-nondirectory path)))

(defun puppet-ts-filename-parser (file)
  "Return list of file name components for the Puppet manifest FILE.
The first element of the list will be the module name and the
remaining elements are the relative file name components below
the ‘manifests’ subdirectory.  The names of the file name
components are only derived from the file name by using the
Puppet autoloader rules.  FILE must be an absolute file name.

The module name \"unidentified\" is returned if a module name
can't be inferred from the file name.

If the directory name contains characters that are not legal for
a Puppet module name, then all leading characters including the
last illegal character are removed from the module name.  The
function will for example return ‘foo’ as module name even if the
module is using the ‘puppet-foo’ directory (e.g. for module
development in a user's home directory)."
  (if (stringp file)
      (let* ((parts (puppet-ts-dissect-filename file))
             ;; Remove "init" if it is the first element
             (compact (if (string-equal (car parts) "init")
                          (cdr parts)
                        parts)))
        (cons
         ;; module name with illegal prefixes removed or "unidentified" if
         ;; FILE is not compliant with the standard Puppet file hierarchy
         (replace-regexp-in-string
          "^.*[^a-z0-9_]" "" (or (cadr (member "manifests" parts))
                                 "unidentified"))
         ;; remaining file name components
         (cdr (member "manifests" (reverse compact)))))
    '("unidentified")))

(defun puppet-ts-file-module-name (file)
  "Return the module name for the Puppet class in FILE."
  (car (puppet-ts-filename-parser file)))

(defun puppet-ts-file-class-name (file)
  "Return the class name for the Puppet class in FILE."
  (mapconcat #'identity (puppet-ts-filename-parser file) "::"))

(defun puppet-ts-file-type-name (file)
  "Return the Puppet type name for FILE.
FILE must be an absolute file name and should conform to the
standard Puppet module layout.  The Puppet type name is returned
if can be derived from FILE.  Otherwise nil is returned.

If the function is called with the file name of a provider, the
appropriate type name is returned."
  (let ((path (puppet-ts-dissect-filename file)))
    (cond ((and (equal (nth 1 path) "type")
                (equal (nth 2 path) "puppet"))
           (car path))
          ((and (equal (nth 2 path) "provider")
                (equal (nth 3 path) "puppet"))
           (cadr path)))))

(defun puppet-ts-file-provider-name (file)
  "Return the Puppet provider name for FILE.
FILE must be an absolute file name and should conform to the
standard Puppet module layout.  The provider name is returned if
it can be derived from FILE.  Otherwise nil is returned."
  (let ((path (puppet-ts-dissect-filename file)))
    (if (and (equal (nth 2 path) "provider")
             (equal (nth 3 path) "puppet"))
        (car path))))

(define-skeleton puppet-ts-keyword-class
  "Insert \"class\" skeleton."
  nil
  > "class " (puppet-ts-file-class-name (buffer-file-name)) " (" \n
  ") {" > \n
  > _ "}" > \n)

(define-skeleton puppet-ts-keyword-define
  "Insert \"define\" skeleton."
  nil
  > "define " (puppet-ts-file-class-name (buffer-file-name)) " (" \n
  ") {" > \n
  > _ "}" > \n)

(define-skeleton puppet-ts-keyword-node
  "Insert \"node\" skeleton."
  nil
  > "node " - " {" \n
  > _ "}" > \n)

(define-skeleton puppet-ts-type-anchor
  "Insert the \"anchor\" resource type."
  nil
  > "anchor { " - ": }" \n)

(define-skeleton puppet-ts-type-class
  "Insert the \"class\" resource type."
  nil
  > "class { " - ":" \n
  "}" > \n)

(define-skeleton puppet-ts-type-exec
  "Insert the \"exec\" resource type."
  nil
  > "exec { " - ":" \n
  "path => [ '/bin', '/sbin', '/usr/bin', '/usr/sbin', ]," > \n
  "user => 'root'," > \n
  "cwd  => '/'," > \n
  "}" > \n)

(define-skeleton puppet-ts-type-file
  "Insert the \"file\" resource type."
  nil
  > "file { " - ":" \n
  "ensure => file," > \n
  "owner  => 'root'," > \n
  "group  => 'root'," > \n
  "mode   => '0644'," > \n
  "}" > \n)

(define-skeleton puppet-ts-type-group
  "Insert the \"group\" resource type."
  nil
  > "group { " - ":" \n
  "ensure => present," > \n
  "}" > \n)

(define-skeleton puppet-ts-type-host
  "Insert the \"host\" resource type."
  nil
  > "host { " - ":" \n
  "ensure => present," > \n
  "}" > \n)

(define-skeleton puppet-ts-type-notify
  "Insert the \"notify\" resource type."
  nil
  > "notify { " - ": }" \n)

(define-skeleton puppet-ts-type-package
  "Insert the \"package\" resource type."
  nil
  > "package { " - ":" \n
  "ensure => present," > \n
  "}" > \n)

(define-skeleton puppet-ts-type-service
  "Insert the \"service\" resource type."
  nil
  > "service { " - ":" \n
  "ensure => running," > \n
  "enable => true," > \n
  "}" > \n)

(define-skeleton puppet-ts-type-user
  "Insert the \"user\" resource type."
  nil
  > "user { " - ":" \n
  "ensure   => present," > \n
  "shell    => '/bin/bash'," > \n
  "password => '*'," > \n
  "}" > \n)


;; Completion

(defcustom puppet-ts-completion-at-point-functions
  '(puppet-ts-complete-variable-at-point
    puppet-ts-complete-resource-type-at-point
    puppet-ts-complete-resource-type-parameters-at-point)
  "A list of functions to call for `completion-at-point'.
The functions customized here are called in sequence when performing
completion at point."
  :group 'puppet-ts
  :type '(repeat function))

(defcustom puppet-ts-completion-variables
  '("facts" "trusted")
  "A list of non-local variable names used for completion.
These names are candidates for completion of variable names even if they
are not used in the current buffer.  The names are customized here
without the \"$\" prefix."
  :group 'puppet-ts
  :type '(repeat string))

(defcustom puppet-ts-completion-resource-types
  '("class" "exec" "file" "group" "notify" "package" "service" "tidy" "user")
  "A list of resource types used for completion."
  :group 'puppet-ts
  :type '(repeat string))

(defcustom puppet-ts-metaparameters
  '("alias" "audit" "before" "loglevel" "noop" "notify" "require" "schedule"
    "stage" "subscribe" "tag")
  "A list of the Puppet metaparameters used for completion."
  :group 'puppet-ts
  :type '(repeat string))

(defcustom puppet-ts-resource-type-parameters
  '(("exec" . ("command" "creates" "cwd" "environment" "group" "logoutput"
               "onlyif" "path" "refresh" "refreshonly" "returns" "timeout"
               "tries" "try_sleep" "umask" "unless" "user"))
    ("file" . ("path" "ensure" "backup" "checksum" "checksum_value"
               "content" "ctime" "force" "group" "ignore" "links"
               "max_files" "mode" "mtime" "owner" "purge" "recurse"
               "recurselimit" "replace" "selinux_ignore_defaults" "selrange"
               "selrole" "seltype" "seluser" "show_diff" "source"
               "source_permissions" "sourceselect" "staging_location"
               "target" "type" "validate_cmd" "validate_replacement"))
    ("group" . ("name" "ensure" "allowdupe" "attribute_membership"
                "attributes" "auth_membership" "forcelocal" "gid"
                "ia_load_module" "members" "system"))
    ("notify" . ("name" "message" "withpath"))
    ("package" . ("name" "command" "ensure" "adminfile" "allow_virtual"
                  "allowcdrom" "category" "configfiles" "description"
                  "enable_only" "flavor" "install_only" "install_options"
                  "instance" "mark" "package_settings" "platform"
                  "reinstall_on_refresh" "responsefile" "root" "source"
                  "status" "uninstall_options" "vendor"))
    ("resources" . ("name" "purge" "unless_system_user" "unless_uid"))
    ("schedule" . ("name" "period" "periodmatch" "range" "repeat" "weekday"))
    ("service" . ("name" "ensure" "binary" "control" "enable" "flags"
                  "hasrestart" "hasstatus" "logonaccount" "logonpassword"
                  "manifest" "path" "pattern" "restart" "start" "status"
                  "stop" "timeout"))
    ("stage" . ("name"))
    ("tidy" . ("path" "age" "backup" "matches" "max_files" "recurse"
               "rmdirs" "size" "type"))
    ("user" . ("name" "ensure" "allowdupe" "attribute_membership"
               "attributes" "auth_membership" "auths" "comment" "expiry"
               "forcelocal" "gid" "groups" "home" "ia_load_module"
               "iterations" "key_membership" "keys" "loginclass"
               "managehome" "membership" "password" "password_max_age"
               "password_min_age" "password_warn_days" "profile_membership"
               "profiles" "project" "purge_ssh_keys" "role_membership"
               "roles" "salt" "shell" "system" "uid"))
    ("augeas" . ("returns" "changes" "context" "force" "incl" "lens"
                 "load_path" "name" "onlyif" "root" "show_diff"
                 "type_check"))
    ("cron" . ("command" "ensure" "environment" "hour" "minute" "month"
               "special" "target" "user" "weekday" "name"))
    ("host" . ("comment" "ensure" "host_aliases" "ip" "target" "name"))
    ("mailaliase . "("ensure" "file" "recipient" "target" "name"))
    ("mount" . ("atboot" "blockdevice" "device" "dump" "ensure" "fstype"
                "options" "pass" "target" "name" "remounts"))
    ("scheduled_task" . ("arguments" "command" "compatibility" "description"
                         "enabled" "ensure" "trigger" "user" "working_dir"
                         "name" "password"))
    ("selboolean" . ("value" "name" "persistent"))
    ("selmodule" . ("value" "name" "persistent"))
    ("ssh_authorized_key" . ("ensure" "key" "options" "target" "type" "user"
                             "drop_privileges" "name"))
    ("sshkey" . ("ensure" "key" "options" "target" "type" "user"
                 "drop_privileges" "name"))
    ("yumrepo" . ("assumeyes" "bandwidth" "baseurl" "cost"
                  "deltarpm_metadata_percentage" "deltarpm_percentage"
                  "descr" "enabled" "enablegroups" "ensure" "exclude"
                  "failovermethod" "gpgcakey" "gpgcheck" "gpgkey"
                  "http_caching" "include" "includepkgs" "keepalive"
                  "metadata_expire" "metalink" "minrate" "mirrorlist"
                  "mirrorlist_expire" "module_hotfixes" "password"
                  "payload_gpgcheck" "priority" "protect" "proxy"
                  "proxy_password" "proxy_username" "repo_gpgcheck"
                  "retries" "s3_enabled" "skip_if_unavailable" "sslcacert"
                  "sslclientcert" "sslclientkey" "sslverify" "throttle"
                  "timeout" "username" "name" "target"))
    ("zfs" . ("aclinherit" "aclmode" "acltype" "atime" "canmount" "checksum"
              "compression" "copies" "dedup" "defaultuserquota" "devices"
              "ensure" "exec" "logbias" "mountpoint" "nbmand" "overlay"
              "primarycache" "quota" "readonly" "recordsize" "refquota"
              "refreservation" "relatime" "reservation" "secondarycache"
              "setuid" "shareiscsi" "sharenfs" "sharesmb" "snapdir" "sync"
              "version" "volsize" "vscan" "xattr" "zoned" "name"))
    ("zone" . ("autoboot" "dataset" "ensure" "inherit" "ip" "iptype" "path"
               "pool" "shares" "clone" "create_args" "id" "install_args"
               "name" "realhostname" "sysidcfg"))
    ("zpool" . ("ashift" "autoexpand" "cache" "disk" "ensure" "failmode"
                "log" "mirror" "raidz" "spare" "pool" "raid_parity"))
    ;; Additional widely used resource types
    ("concat" . ("backup" "ensure" "ensure_newline" "format" "force" "group"
                 "mode" "order" "owner" "path" "replace"
                 "selinux_ignore_defaults" "selrange" "selrole" "seltype"
                 "seluser" "show_diff" "validate_cmd" "warn"
                 "create_empty_file"))
    ("concat::fragment" . ("content" "order" "source" "target")))
  "An alist of common Puppet resource types and their parameters."
  :group 'puppet-ts
  :type '(alist :key-type string :value-type (repeat string)))

(defun puppet-ts--manifest-variables ()
  "Return a list of the Puppet variable names used in the manifest.
The list can contain duplicates and it is not ordered in any way."
  (flatten-tree
   (treesit-induce-sparse-tree
    (treesit-buffer-root-node 'puppet)
    (lambda (node)
      (and (string= (treesit-node-type node) "variable")
           ;; Filter random things that don't look like a variable when the
           ;; manifests contains a syntax error.  Tree-sitter tries to parse
           ;; almost anything as the next token before signaling an error.
           ;; We don't want to offer that as a completion candidate.
           (string-match-p "$[a-z_][a-zA-Z0-9_]*" (treesit-node-text node t))))
    (lambda (node)
      (substring (treesit-node-text node t) 1)))))

(defun puppet-ts-symbol-at-point ()
  "Return the begin and end positions of the symbol at point."
  (save-excursion
    (let ((pos (point)))
      ;; Skip back to the beginning of the alleged symbol.
      (skip-syntax-backward "w_" (pos-bol))
      ;; Look forwared to find the end of the symbol and make sure that
      ;; point is not behind the end.
      (if (and (looking-at "[a-z_][a-zA-Z0-9_]*\\(::[a-z_][a-zA-Z0-9_]*\\)*")
               (<= pos (match-end 0)))
          (cons (match-beginning 0) (match-end 0))))))

(defun puppet-ts-complete-variable-at-point ()
  "Complete variable names if the symbol at point has a leading \"$\".
The result includes all variables already used in the current manifest
and also all variables customized in `puppet-ts-completion-variables'."
  (let* ((token (puppet-ts-symbol-at-point))
         (beg (or (car token) (point)))
         (end (or (cdr token) (point))))
    (if (save-excursion
          (goto-char beg)
          (looking-back "${?" (pos-bol)))
        (list beg
              end
              (completion-table-dynamic
               (lambda (_)
                 (let ((var (buffer-substring-no-properties beg end))
                       (all (puppet-ts--manifest-variables)))
                   ;; Remove the name we are trying to complete if it is
                   ;; found only once; it will be the variable name at point
                   ;; and it really doesn't make sense to offer that as
                   ;; a candidate.
                   (if (eql (seq-count (lambda (elt) (string= elt var)) all) 1)
                       (setq all (delete var all)))
                   ;; Also add supported global Puppet variables.
                   (append all puppet-ts-completion-variables)))
               t)))))

(defun puppet-ts-complete-resource-type-at-point ()
  "Complete a resource type at point.
See the variable `puppet-ts-completion-resource-types' for
customization."
  (let* ((token (puppet-ts-symbol-at-point))
         (beg (or (car token) (point)))
         (end (or (cdr token) (point)))
         (node (treesit-node-on beg end))
         (types (seq-take (puppet-ts-hierarchy node) 2)))
    (if (or (member (car types) '("manifest" "block"))
            (equal types '("name" "resource_type"))
            (equal types '("name" "statement")))
        (list beg end puppet-ts-completion-resource-types))))

(defun puppet-ts-complete-resource-type-parameters-at-point ()
  "Complete resource type parameters including metaparameters at point.
You can customize the variables `puppet-ts-resource-type-parameters' and
`puppet-ts-metaparameters' to modify the suggestions."
  (let* ((token (puppet-ts-symbol-at-point))
         (beg (or (car token) (point)))
         (end (or (cdr token) (point)))
         (node (treesit-node-on beg end))
         (type (puppet-ts-resource-type node))
         (types (puppet-ts-hierarchy node)))
    (if (or (member (car types) '("resource_body" "resource_type"))
            (equal (seq-take types 2) '("attribute_list" "resource_body"))
            (equal (seq-take types 3) '("name" "ERROR" "resource_type"))
            (equal (seq-take types 4) '("name" "attribute"
                                        "attribute_list" "resource_body")))
        (list beg
              end
              (completion-table-dynamic
               (lambda (_)
                 ;; Return standard metaparameters plus the resource type
                 ;; specific params as completion candidates.
                 (append puppet-ts-metaparameters
                         (cdr (assoc type puppet-ts-resource-type-parameters))))
               t)))))


;; Xref

(defcustom puppet-ts-module-path
  '("/etc/puppetlabs/code/environments/production/modules")
  "Directories to search for modules when resolving cross references.
The variable can hold a list of directories to allow more than
a single search location (for example if you use a personal
directory where you do development).  Every directory should be
a top-level directory where a module has its own subdirectory
using the module name as subdirectory name (see the Puppet
autoloading rules).  The list is searched in order and the search
terminates when the first match is found."
  :group 'puppet-ts
  :type '(repeat directory))

(defun puppet-ts-module-root (file)
  "Return the Puppet module root directory for FILE.
Walk up the directory tree for FILE until a directory is found,
that contains either a \"manifests\", \"types\" or \"lib\"
subdirectory.  Return that directory name or nil if no directory
is found."
  (locate-dominating-file
   file
   (lambda (path)
     (and (file-accessible-directory-p path)
          (or (file-accessible-directory-p (expand-file-name "manifests" path))
              (file-accessible-directory-p (expand-file-name "types" path))
              (file-accessible-directory-p (expand-file-name "lib" path)))))))

(defun puppet-ts-autoload-name (identifier &optional directory extension)
  "Resolve IDENTIFIER into Puppet module and relative autoload name.
Use DIRECTORY as module subdirectory \(defaults to \"manifests\"
and EXTENSION as file extension \(defaults to \".pp\") when
building the name.

Return a cons cell where the first part is the module name and
the second part is a relative file name below that module where
the identifier would be defined according to the Puppet autoload
rules."
  (let* ((components (split-string identifier "::"))
         (module (car components))
         (dirs (cons (or directory "manifests") (butlast (cdr components))))
         (file (if (cdr components)
                   (car (last components))
                 "init")))
    (cons module
          (concat (mapconcat #'file-name-as-directory dirs)
                  file
                  (or extension ".pp")))))

(defun puppet-ts--xref-backend ()
  "The Xref backend for `puppet-ts-mode'."
  'puppet)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql puppet)))
  "Return the Puppet identifier at point."
  (if-let* ((bounds (puppet-ts-symbol-at-point)))
      (buffer-substring-no-properties (car bounds) (cdr bounds))))

(cl-defmethod xref-backend-definitions ((_backend (eql puppet)) identifier)
  "Find the definitions of a Puppet resource IDENTIFIER.
First the location of the visited file is checked.  Then all
directories from `puppet-ts-module-path' are searched for the
module and file according to Puppet's autoloading rules."
  (let* ((resource (downcase (if (string-prefix-p "::" identifier)
                                 (substring identifier 2)
                               identifier)))
         (pupfiles (puppet-ts-autoload-name resource))
         (typfiles (puppet-ts-autoload-name resource "types"))
         (funfiles (puppet-ts-autoload-name resource "functions"))
         (xrefs '()))
    (if pupfiles
        (let* ((module (car pupfiles))
               ;; merged list of relative file names to classes/defines/types
               (pathlist (mapcar #'cdr (list pupfiles typfiles funfiles)))
               ;; list of directories where this module might be
               (moddirs (mapcar (lambda (dir) (expand-file-name module dir))
                                puppet-ts-module-path))
               ;; the regexp to find the resource definition in the file
               (resdef (rx bol
                           (or "class" "define" "function" "type")
                           (1+ whitespace)
                           (literal resource)
                           word-boundary))
               ;; files to visit when searching for the resource
               (files '()))
          ;; Check the current module directory (if the buffer actually
          ;; visits a file) and all module subdirectories from
          ;; `puppet-ts-module-path'.
          (dolist (dir (if buffer-file-name
                           (cons (puppet-ts-module-root buffer-file-name)
                                 moddirs)
                         moddirs))
            ;; Try all relative file names below the module directory that
            ;; might contain the resource; save the file name if the file
            ;; exists and we haven't seen it (we might try to check a file
            ;; twice if the current module is also below one of the dirs in
            ;; `puppet-ts-module-path').
            (dolist (path pathlist)
              (let ((file (expand-file-name path dir)))
                (if (and (not (member file files))
                         (file-readable-p file))
                    (push file files)))))
          ;; Visit all found files to finally locate the resource definition
          (dolist (file files)
            (with-temp-buffer
              (insert-file-contents-literally file)
              (if (re-search-forward resdef nil t)
                  (push (xref-make
                         (match-string-no-properties 0)
                         (xref-make-file-location
                          file (line-number-at-pos (match-beginning 1)) 0))
                        xrefs))))))
    xrefs))


;; Language grammar

(defconst puppet-ts-mode-treesit-language-source
  '(puppet . ("https://github.com/smoeding/tree-sitter-puppet" "v3.0.1"))
  "The language source entry for the associated Puppet language parser.
The value refers to the specific version of the parser that the
mode has been tested with.  Using this mode with either an older
or newer version of the parser might not work as expected.")

(defun puppet-ts-mode-install-grammar ()
  "Install the language grammar for `puppet-ts-mode'.
The function removes existing entries for the Puppet language in
`treesit-language-source-alist' and adds the entry stored in
`puppet-ts-mode-treesit-language-source'."
  (interactive)
  ;; Remove existing entries
  (setq treesit-language-source-alist
        (assq-delete-all 'puppet treesit-language-source-alist))
  ;; Add the correct entry
  (add-to-list 'treesit-language-source-alist
               puppet-ts-mode-treesit-language-source)
  ;; Install the grammar
  (treesit-install-language-grammar 'puppet))


;; User callable functions

(defun puppet-ts-interpolate (suppress)
  "Insert \"${}\" when point is in a double quoted string.
A single \"$\" is inserted if point is not in a double quoted string.
With prefix argument SUPPRESS the braces are always left out."
  (interactive "P*")
  (let ((node (treesit-parent-until
               (treesit-node-on (point) (point))
               (puppet-ts-node-type-predicate "double_quoted_string")
               t)))
    ;; Interpolation should only happen when point is *inside* the string.
    (if (and node (> (point) (treesit-node-start node)))
        ;; We are inside a double quoted string
        (with-undo-amalgamate
          (if mark-active
              ;; region active: enclose in {...}
              (let ((beg (region-beginning))
                    (end (region-end)))
                (goto-char beg)
                (self-insert-command 1)
                (if suppress
                    (goto-char (1+ end))
                  (insert "{")
                  (goto-char (+ end 2))
                  (insert "}")))
            ;; region not active
            (self-insert-command 1)
            (unless suppress
              (insert "{}")
              (forward-char -1))))
      (self-insert-command 1))))

(defun puppet-ts-clear-string ()
  "Clear string at point."
  (interactive "*")
  (if-let* ((node (treesit-parent-until
                   (treesit-node-at (point))
                   (puppet-ts-node-type-predicate "single_quoted_string"
                                                  "double_quoted_string")
                   t))
            (beg (treesit-node-start node))
            (end (treesit-node-end node)))
      (delete-region (1+ beg) (1- end))))


;; Major mode definition

(defvar puppet-ts-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; our strings
    (modify-syntax-entry ?\' "\"'"  table)
    (modify-syntax-entry ?\" "\"\"" table)
    ;; C-style comments (no longer documented since Puppet 7.x)
    (modify-syntax-entry ?/ ". 14b" table)
    (modify-syntax-entry ?* ". 23b" table)
    ;; line comments
    (modify-syntax-entry ?#  "<" table)
    (modify-syntax-entry ?\n ">" table)
    ;; the backslash is our escape character
    (modify-syntax-entry ?\\ "\\" table)
    ;; the dollar sign is an expression prefix for variables
    (modify-syntax-entry ?$ "'" table)
    ;; symbol constituent
    (modify-syntax-entry ?: "_" table)
    ;; various operators and punctionation.
    (modify-syntax-entry ?<  "." table)
    (modify-syntax-entry ?>  "." table)
    (modify-syntax-entry ?&  "." table)
    (modify-syntax-entry ?|  "." table)
    (modify-syntax-entry ?%  "." table)
    (modify-syntax-entry ?=  "." table)
    (modify-syntax-entry ?+  "." table)
    (modify-syntax-entry ?-  "." table)
    (modify-syntax-entry ?\; "." table)
    ;; our parenthesis, braces and brackets
    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    (modify-syntax-entry ?\{ "(}" table)
    (modify-syntax-entry ?\} "){" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    table)
  "Syntax table used in `puppet-ts-mode' buffers.")

(defvar puppet-ts-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Editing
    (keymap-set map "C-c C-a" #'puppet-ts-align-block)
    (keymap-set map "C-c C-;" #'puppet-ts-clear-string)
    (keymap-set map "$" #'puppet-ts-interpolate)
    (keymap-set map ">" #'puppet-ts-electric-greater)
    (keymap-set map "=" #'puppet-ts-electric-equal)
    ;; Apply manifests
    (keymap-set map "C-c C-c" #'puppet-ts-apply)
    ;; Linting and validation
    (keymap-set map "C-c C-v" #'puppet-ts-validate)
    (keymap-set map "C-c C-l" #'puppet-ts-lint)
    ;; Skeletons for types
    (keymap-set map "C-c C-t a" #'puppet-ts-type-anchor)
    (keymap-set map "C-c C-t c" #'puppet-ts-type-class)
    (keymap-set map "C-c C-t e" #'puppet-ts-type-exec)
    (keymap-set map "C-c C-t f" #'puppet-ts-type-file)
    (keymap-set map "C-c C-t g" #'puppet-ts-type-group)
    (keymap-set map "C-c C-t h" #'puppet-ts-type-host)
    (keymap-set map "C-c C-t n" #'puppet-ts-type-notify)
    (keymap-set map "C-c C-t p" #'puppet-ts-type-package)
    (keymap-set map "C-c C-t s" #'puppet-ts-type-service)
    (keymap-set map "C-c C-t u" #'puppet-ts-type-user)
    ;; Skeletons for keywords
    (keymap-set map "C-c C-k c" #'puppet-ts-keyword-class)
    (keymap-set map "C-c C-k d" #'puppet-ts-keyword-define)
    (keymap-set map "C-c C-k n" #'puppet-ts-keyword-node)
    map)
  "Keymap for Puppet Mode buffers.")

;;;###autoload
(define-derived-mode puppet-ts-mode prog-mode "Puppet"
  "Major mode for editing Puppet files, using the Tree-sitter library.
\\<puppet-ts-mode-map>
Syntax highlighting for standard Puppet elements (comments,
strings, variables, keywords, resource types, metaparameters,
functions, operators) is available.  You can customize the
variable `treesit-font-lock-level' to control the level of
fontification.

The function `completion-at-point' can be used for completion.
See the variable `tab-always-indent' on how to enable completion
using the TAB key.
It completes variable names if the symbol at point starts with
the \"$\" character.  The suggestions include variables already
used in the current buffer and all variable names customized in
`puppet-ts-completion-variables'.  Completion of variable names
also works for interpolated variables in a string when the symbol
at point starts with a \"${\" prefix.
Depending on context the function will also complete resource
type names and their parameter names.  The resource types can be
customized with the list `puppet-ts-completion-resource-types'.
The alist `puppet-ts-resource-type-parameters' is used to
customize the completion candidates for a resource type
parameter.  The default metaparameters that will be offered for
completion can be customized in `puppet-ts-metaparameters'.

Attribute and parameter blocks can be aligned with respect to the
\"=>\" and \"=\" symbols by positioning point inside such a block
and calling `puppet-ts-align-block' (bound to \\[puppet-ts-align-block]).

The greater sign is electric when used to insert a fat arrow
\"=>\" in a hash or attribute list and it will perform automatic
alignment of the structure.  You can disable this by customizing
`puppet-ts-greater-is-electric'.

The equal sign is electric when used in a parameter list and it
will perform automatic alignment of the structure.  You can
disable this by customizing `puppet-ts-equal-is-electric'.

Typing a \"$\" character inside a double quoted string will
insert the variable interpolation syntax.  The \"$\" character
will be followed by a pair of braces so that the variable name to
be interpolated can be entered immediately.  If the region is
active when the \"$\" character is entered, it will be used as
the variable name.

With `imenu' (bound to \\[imenu]) you can find the resource types
and variables used the current manifest.  For variables the
location of the initial assignment is used.  Puppet variables are
immutable so this is normally the only place in the file where
the variable is set.

The mode supports the cross-referencing system described in the
Info node `Xref'.  The variable `puppet-ts-module-path' can be
customized to contain a list of directories that are used to find
other Puppet modules.

Calling the function `xref-find-definitions' (\\[xref-find-definitions]) with point on
an identifier (a class, defined type, custom function or data
type) jumps to the file and location where that identifier is
defined.  This works without any sort of database or file that
otherwise might hold stale references.  Instead the Puppet
autoloader rules are used to infer the file name from the
identifier.

By convention a Puppet manifest only has a single definition of
a class, defined type or function.  So the navigation function
`beginning-of-defun' and `end-of-defun' would normally only jump
to the beginning or the end of the buffer.  This does not provide
any benefit and so the mode uses the associated key bindings to go
to the preceding (\\[treesit-beginning-of-defun]) or the following (\\[treesit-end-of-defun]) resource
declaration.  Putting the region around this declaration by
calling the function `mark-defun' (\\[mark-defun]) comes for free.

The manifest in a buffer can be applied in noop-mode (\\[puppet-ts-apply])
and validated (\\[puppet-ts-validate]).  The \"puppet\" executable is required
for this to work.

A manifest can also be linted (\\[puppet-ts-lint]) if the \"puppet-lint\"
utility is available.

A number of skeletons have been implemented to make insertion of
often used code fragments simpler.

The mode needs the Tree-sitter parser for Puppet code.  A parser
suitable for the current package version can be installed using
the function `puppet-ts-mode-install-grammar'.  Development tools
like a C compiler are required for this.  The constant
`puppet-ts-mode-treesit-language-source' contains the location
and version of the parser that should be used for the present
release of the mode.

Indentation, alignment and fontification depend on the concrete
syntax tree returned by the Tree-sitter parser.  Syntax errors
like a missing closing parenthesis or bracket can lead to wrong
indentation or missing fontification.  This is easily resolved by
fixing the particular syntax error.

\\{puppet-ts-mode-map}"
  (setq-local require-final-newline mode-require-final-newline)


  ;; Comments
  (setq-local comment-start              "#"
              comment-end                ""
              comment-start-skip         "#+[ \t]*"
              parse-sexp-ignore-comments t)

  ;; Indentation
  (setq indent-tabs-mode puppet-ts-indent-tabs-mode)
  (setq-local electric-indent-chars '(?\{ ?\} ?\( ?\) ?: ?, ?\n))

  ;; Paragraphs
  (setq-local paragraph-ignore-fill-prefix t
              paragraph-start              "\f\\|[ \t]*$\\|#$"
              paragraph-separate           "\\([ \t\f]*\\|#\\)$")

  ;; Treesitter
  (when (treesit-ready-p 'puppet)
    (treesit-parser-create 'puppet)

    ;; Navigation
    (setq treesit-defun-type-regexp (rx (or "resource_reference"
                                            "resource_type")))

    ;; Font-Lock
    (setq treesit-font-lock-feature-list puppet-ts-mode-feature-list)
    (setq treesit-font-lock-settings (apply #'treesit-font-lock-rules
                                            puppet-ts-mode-font-lock-settings))

    ;; Indentation
    (setq treesit-simple-indent-rules puppet-ts-indent-rules)

    ;; Imenu
    (setq-local treesit-simple-imenu-settings puppet-ts-simple-imenu-settings)

    ;; Alignment
    (setq align-mode-rules-list         puppet-ts-mode-align-rules
          align-mode-exclude-rules-list puppet-ts-mode-align-exclude-rules)

    ;; Xref
    (add-hook 'xref-backend-functions #'puppet-ts--xref-backend)

    ;; Completion
    (dolist (func (reverse puppet-ts-completion-at-point-functions))
      (add-hook 'completion-at-point-functions func nil 'local))

    (treesit-major-mode-setup)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.pp\\'" . puppet-ts-mode))

(provide 'puppet-ts-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; puppet-ts-mode.el ends here
