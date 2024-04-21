;;; puppet-ts-mode.el --- Major mode for Puppet using Tree-sitter -*- lexical-binding: t; -*-

;; Copyright (c) 2024 Stefan Möding

;; Author: Stefan Möding
;; URL: https://github.com/smoeding/puppet-ts-mode
;; Version: 0.1.0
;; Created: <2024-03-02 13:05:03 stm>
;; Updated: <2024-04-21 17:35:01 stm>
;; Keywords: Puppet Treesitter
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

;;; Commentary:

;; This is puppet-ts-mode, a major mode to edit Puppet files using the
;; tree-sitter parser for Puppet.  You can compile and install the parser
;; using the following Elisp snippet:
;;
;;    (add-to-list
;;     'treesit-language-source-alist
;;     '(puppet "https://github.com/tree-sitter-grammars/tree-sitter-puppet"))
;;    (treesit-install-language-grammar 'puppet)
;;
;; Also consult the Emacs manual: (info "(elisp) Parsing Program Source")
;;
;; Caution: This is work in progress; many details concerning font-lock or
;; indentation might not yet work as expected.  Most convenience functions of
;; the old puppet-mode are not (yet) implemented.

;;; Code:


;;; Requirements

(eval-when-compile
  (require 'rx))

(require 'treesit)


;;; Customization
(defgroup puppet nil
  "Write Puppet manifests in Emacs."
  :prefix "puppet-"
  :group 'languages)

(defcustom puppet-indent-level 2
  "Number of spaces for each indententation step."
  :group 'puppet
  :type 'integer
  :safe 'integerp)

(defcustom puppet-indent-tabs-mode nil
  "Indentation can insert tabs in puppet mode if this is non-nil."
  :group 'puppet
  :type 'boolean
  :safe 'booleanp)

(defface puppet-comment-face
  '((t :inherit font-lock-comment-face))
  "Face for comments in Puppet."
  :group 'puppet)

(defface puppet-string-face
  '((t :inherit font-lock-string-face))
  "Face for strings in Puppet."
  :group 'puppet)

(defface puppet-keyword-face
  '((t :inherit font-lock-keyword-face))
  "Face for keywords in Puppet."
  :group 'puppet)

(defface puppet-resource-type-face
  '((t :inherit font-lock-type-face))
  "Face for resource types in Puppet."
  :group 'puppet)

(defface puppet-builtin-face
  '((t :inherit font-lock-builtin-face))
  "Face for built-in functions in Puppet."
  :group 'puppet)

(defface puppet-constant-face
  '((t :inherit font-lock-constant-face))
  "Face for a constant in Puppet."
  :group 'puppet)

(defface puppet-variable-name-face
  '((t :inherit font-lock-variable-name-face))
  "Face for the name of a variable in Puppet."
  :group 'puppet)

(defface puppet-function-name-face
  '((t :inherit font-lock-function-name-face))
  "Face for the name of a function in Puppet."
  :group 'puppet)

(defface puppet-negation-char-face
  '((t :inherit font-lock-negation-char-face))
  "Face for negation characters."
  :group 'puppet)

(defface puppet-warning-face
  '((t :inherit font-lock-warning-face))
  "Face for language errors found by the parser."
  :group 'puppet)


;;; Settings
(defvar puppet--file-attribute-constants
  '("file" "directory" "link")
  "Constants used for Puppet file resources.")

(defvar puppet--package-attribute-constants
  '("present" "absent" "installed" "latest")
  "Constants used for Puppet package resources.")

(defvar puppet--service-attribute-constants
  '("running" "stopped")
  "Constants used for Puppet service resources.")

;; https://www.puppet.com/docs/puppet/latest/metaparameter.html
(defvar puppet--metaparameters
  '("alias" "audit" "before" "consume" "export" "loglevel" "noop"
    "notify" "require" "schedule" "stage" "subscribe" "tag" "ensure")
  "Puppet metaparameter attributes for all resource types.
Strictly speakting, \"ensure\" is not a real metaparameter, but it
is added here because it is common and important.")

;; https://www.puppet.com/docs/puppet/latest/function.html
(defvar puppet--builtin-functions
  '("abs" "alert" "all" "annotate" "any" "assert_type" "binary_file" "break"
    "call" "camelcase" "capitalize" "ceiling" "chomp" "chop" "compare"
    "contain" "convert_to" "create_resources" "crit" "debug" "defined" "dig"
    "digest" "downcase" "each" "emerg" "empty" "epp" "err" "eyaml_lookup_key"
    "fail" "file" "filter" "find_file" "find_template" "flatten" "floor"
    "fqdn_rand" "generate" "get" "getvar" "group_by" "hiera" "hiera_array"
    "hiera_hash" "hiera_include" "hocon_data" "import" "include" "index"
    "info" "inline_epp" "inline_template" "join" "json_data" "keys" "length"
    "lest" "lookup" "lstrip" "map" "match" "max" "md5" "min"
    "module_directory" "new" "next" "notice" "partition" "realize" "reduce"
    "regsubst" "require" "return" "reverse_each" "round" "rstrip" "scanf"
    "sha1" "sha256" "shellquote" "size" "slice" "sort" "split" "sprintf"
    "step" "strftime" "strip" "tag" "tagged" "template" "then" "tree_each"
    "type" "unique" "unwrap" "upcase" "values" "versioncmp" "warning" "with"
    "yaml_data"
    ;; Bolt: https://puppet.com/docs/bolt/0.x/plan_functions.html
    "apply" "apply_prep" "add_facts" "facts" "fail_plan" "file_upload"
    "get_targets" "puppetdb_fact" "puppetdb_query" "run_command" "run_plan"
    "run_script" "run_task" "set_feature" "set_var" "vars"
    "without_default_logging")
  "Internal functions provided by Puppet.")

;;
;; Regular expressions
;;

(defvar puppet--constants-regex
  (rx-to-string `(seq bos
                      ,(cons 'or (append puppet--file-attribute-constants
                                         puppet--package-attribute-constants
                                         puppet--service-attribute-constants))
                      eos)
                'no-group)
  "Puppet constants for tree-sitter font-locking.")

(defvar puppet--metaparameters-regex
  (rx-to-string `(seq bos
                      ,(cons 'or puppet--metaparameters)
                      eos)
                'no-group)
  "Regex to match Puppet metaparameters.")

(defvar puppet--builtin-functions-regex
  (rx-to-string `(seq bos
                      ,(cons 'or puppet--builtin-functions)
                      eos)
                'no-group)
  "Internal functions provided by Puppet.")


;; Font-Lock
(defvar puppet-ts-mode--feature-list
  ;; Level 1 usually contains only comments and definitions.
  ;; Level 2 usually adds keywords, strings, data types, etc.
  ;; Level 3 usually represents full-blown fontifications, including
  ;; assignments, constants, numbers and literals, etc.
  ;; Level 4 adds everything else that can be fontified: delimiters,
  ;; operators, brackets, punctuation, all functions, properties,
  ;; variables, etc.
  '((comment)
    (keyword resource-type builtin string)
    (constant variable string-interpolation)
    (operator error))
  "`treesit-font-lock-feature-list' for `puppet-ts-mode'.")

(defvar puppet-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :feature 'comment
   :language 'puppet
   '((comment) @puppet-comment-face)

   :feature 'string
   :language 'puppet
   '((string) @puppet-string-face)

   :feature 'string-interpolation
   :language 'puppet
   :override t
   '((string (interpolation) @puppet-variable-name-face))

   :feature 'variable
   :language 'puppet
   '((variable ["$" (name)] @puppet-variable-name-face))

   :feature 'constant
   :language 'puppet
   '(((boolean) @puppet-constant-face)
     ((default) @puppet-constant-face)
     ((undef) @puppet-constant-face))

   :feature 'keyword
   :language 'puppet
   `((if_expression "if" @puppet-keyword-face)
     (elsif_clause "elsif" @puppet-keyword-face)
     (else_clause "else" @puppet-keyword-face)
     (unless_expression "unless" @puppet-keyword-face)
     (case_expression "unless" @puppet-keyword-face)
     (class_definition ["class" "inherits"] @puppet-keyword-face)
     (define_definition "define" @puppet-keyword-face)
     (function_definition "function" @puppet-keyword-face)
     (node_definition "node" @puppet-keyword-face)
     (plan_definition "plan" @puppet-keyword-face)
     (resource ["and" "or" "in"] @puppet-keyword-face))

   :feature 'resource-type
   :language 'puppet
   '((resource_type (name) @puppet-resource-type-face)
     (resource [(virtual) (exported)] @puppet-resource-type-face)
     ;; names of defined classes, defined types, functions, nodes, ...
     (classname (name) @puppet-resource-type-face)
     ;; data and resource reference types
     (type (classref) @puppet-resource-type-face))

   :feature 'builtin
   :language 'puppet
   `((call_function (name) @puppet-builtin-face
                    (:match ,puppet--builtin-functions-regex @puppet-builtin-face))
     (attribute name: (name) @puppet-builtin-face
                (:match ,puppet--metaparameters-regex @puppet-builtin-face))
     (attribute value: (name) @puppet-builtin-face
                (:match ,puppet--constants-regex @puppet-builtin-face)))

   :feature 'operator
   :language 'puppet
   '((resource "!") @puppet-negation-char-face)

   :feature 'error
   :language 'puppet
   :override t
   '((ERROR) @puppet-warning-face))
  "`treesit-font-lock-settings' for `puppet-ts-mode'.")


;; Indentation
(defvar puppet--indent-one-level
  (rx bos
      (or "array" "body" "hash" "selector" "resource" "parameter_list"
          "call_function" "case_expression"  "if_expression" "unless_expression"
          "class_definition" "define_definition" "function_definition"
          "node_definition" "plan_definition")
      eos)
  "Structures that will have their children indented by an additional level.")

(defvar puppet--indent-like-parent
  (rx bos
      (or "else_clause" "elsif_clause")
      eos)
  "Statements that will be indented the same level as their parent.")

(defvar puppet-ts-indent-rules
  `((puppet
     ;; top-level statements start in column zero
     ((parent-is "manifest") parent 0)
     ;; block structures
     ((node-is "}") parent-bol 0)
     ((node-is ")") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ;; compound statements
     ;; ((node-is ,puppet--indent-like-parent) parent-bol 0)
     ;; ((parent-is ,puppet--indent-one-level) parent-bol puppet-indent-level)
     ;; default
     (no-node parent-bol 0)
     (catch-all parent-bol puppet-indent-level)))
  "Indentation rules for `puppet-ts-mode'.")

;; Major mode definition

(defvar puppet-ts-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; our strings
    (modify-syntax-entry ?\' "\"'"  table)
    (modify-syntax-entry ?\" "\"\"" table)
    ;; C-style comments
    (modify-syntax-entry ?/ ". 14b" table)
    (modify-syntax-entry ?* ". 23b" table)
    ;; line comments
    (modify-syntax-entry ?#  "<" table)
    (modify-syntax-entry ?\n ">" table)
    ;; the backslash is our escape character
    (modify-syntax-entry ?\\ "\\" table)
    ;; the dollar sign is an expression prefix for variables
    (modify-syntax-entry ?$ "'" table)
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
    ;;(define-key map (kbd "C-c C-a") #'puppet-align-block)
    map)
  "Keymap for Puppet Mode buffers.")

;;;###autoload
(define-derived-mode puppet-ts-mode prog-mode "Puppet[ts]"
  "Major mode for editing Puppet files, using the tree-sitter library.

\\{puppet-ts-mode-map}"
  :syntax-table puppet-ts-mode-syntax-table

  ;; Comments
  (setq-local comment-start "#")
  (setq-local comment-end "")
  (setq-local comment-start-skip "#+[ \t]*")
  (setq-local parse-sexp-ignore-comments t)

  ;; Indentation
  ;;(setq-local indent-line-function #'puppet-indent-line)
  (setq indent-tabs-mode puppet-indent-tabs-mode)
  (setq-local electric-indent-chars (append '(?\{ ?\}) electric-indent-chars))

  ;; Paragaphs
  (setq-local paragraph-ignore-fill-prefix t)
  (setq-local paragraph-start "\f\\|[ \t]*$\\|#$")
  (setq-local paragraph-separate "\\([ \t\f]*\\|#\\)$")

  ;; Treesitter
  (when (treesit-ready-p 'puppet)
    (treesit-parser-create 'puppet)

    ;; Font-Lock
    (setq-local treesit-font-lock-feature-list puppet-ts-mode--feature-list)
    (setq-local treesit-font-lock-settings puppet-ts-mode--font-lock-settings)

    ;; Indentation
    (setq-local treesit-simple-indent-rules puppet-ts-indent-rules)
    ;;(setq-local treesit--indent-verbose t)

    (treesit-major-mode-setup)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.pp\\'" . puppet-ts-mode))

(provide 'puppet-ts-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; puppet-ts-mode.el ends here
