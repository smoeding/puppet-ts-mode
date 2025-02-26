;;; indent-test.el --- Unit Test Suite  -*- lexical-binding: t; -*-

;; Copyright (c) 2024, 2025 Stefan Möding

;; Author: Stefan Möding
;; Created: <2024-04-28 16:54:55 stm>
;; Updated: <2025-02-23 14:34:57 stm>

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

;; Unit test suite for puppet-ts-mode

;; Most test cases are taken from the original puppet-mode.

;;; Code:

(message "Running Emacs %s with tests from %s"
         emacs-version (file-relative-name load-file-name))


;;; Requirements
(require 'ert)

(declare-function puppet-test-with-temp-buffer (content &rest body))
(declare-function puppet-test-indent (code))


;;; Indentation

(ert-deftest indent/argument-list ()
  (puppet-test-indent "
class foo {
  $foo = bar(1,2)
  $foo = bar(
    1,
    2
  )
  $foo = bar(
    1,
    2)
  $foo = bar(1,
             2
  )
  $foo = bar(1,
             2)

  foo { 'foo':
    foo => bar(1,2),
    foo => bar(
      1,
      2,
    ),
    foo => bar(
      1,
      2),
    foo => bar(1,
               2,
    ),
    foo => bar(1,
               2),
    foo => 0;
  }
}
"))

(ert-deftest indent/array ()
  (puppet-test-indent "
class foo {
  $foo = [
    $bar,
  ]
  $foo = [
    $bar]
  $foo = [$bar,
    $bar,
  ]
  $foo = [$bar,
    $bar]
  foo { 'foo':
    bar => [
      $bar,
      $bar,
    ],
    bar => [$bar,
      $bar,
    ],
    bar => [$bar,
      $bar],
    bar => $bar;
  }
}
"))

(ert-deftest indent/class ()
  (puppet-test-with-temp-buffer
      "class test (
$foo = $title,
  ) {
$bar = 'hello'
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "class test (
  $foo = $title,
) {
  $bar = 'hello'
}"
))))

(ert-deftest indent/class-inherits ()
  (puppet-test-with-temp-buffer
      "class test (
$foo = $title,
  ) inherits ::something::someting:dark::side {
$bar = 'hello'
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "class test (
  $foo = $title,
) inherits ::something::someting:dark::side {
  $bar = 'hello'
}"
))))

(ert-deftest indent/class-no-parameters ()
  (puppet-test-with-temp-buffer
      "class test () {
$bar = 'hello'
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "class test () {
  $bar = 'hello'
}"
))))

(ert-deftest indent/class-no-parameters-2 ()
  (puppet-test-with-temp-buffer
      "class foobar {
class { 'test':
omg => 'omg',
lol => {
asd => 'asd',
fgh => 'fgh',
}
}
}
"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "class foobar {
  class { 'test':
    omg => 'omg',
    lol => {
      asd => 'asd',
      fgh => 'fgh',
    }
  }
}
"
))))

(ert-deftest indent/class-no-parameters-inherits ()
  (puppet-test-with-temp-buffer
      "class test () inherits ::something::someting:dark::side {
$bar = 'hello'
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "class test () inherits ::something::someting:dark::side {
  $bar = 'hello'
}"
))))

(ert-deftest indent/class-paramaters-no-inherits ()
  (puppet-test-with-temp-buffer
      "
class foo (
String $foo,
) {
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
class foo (
  String $foo,
) {
}"
))))

(ert-deftest indent/class-paramaters-inherits ()
  (puppet-test-with-temp-buffer
      "
class foo::bar (
String $foo,
) inherits foo {
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
class foo::bar (
  String $foo,
) inherits foo {
}"
))))

(ert-deftest indent/class-parameter-list ()
  (puppet-test-indent "
class foo::bar1 ($a, $b,
  $c, $d,
) {
  $foo = $bar
}

class foo::bar2 ($a, $b,
  $c, $d)
{
  $foo = $bar
}

class foo::bar3 ($a, $b,
  $c, $d,
)
{
  $foo = $bar
}

class foo::bar4 ($a, $b)
{
  $foo = $bar
}

class foo::bar5 ($a, $b) {
  $foo = $bar
}
"))

(ert-deftest indent/comments-change-indentation-level ()
  (puppet-test-with-temp-buffer
      "
if $foo {
# {
# (
# :
# ;
# }
# )
#
}
"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
if $foo {
  # {
  # (
  # :
  # ;
  # }
  # )
  #
}
"
))))

(ert-deftest indent/function ()
  (puppet-test-with-temp-buffer
      "
function foo::bar (
String $foo,
) >> String {
$foo
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "
function foo::bar (
  String $foo,
) >> String {
  $foo
}"
))))

(ert-deftest indent/define ()
  (puppet-test-with-temp-buffer
      "
define foo::bar (
$foo = $title,
) {
$bar = 'hello'
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "
define foo::bar (
  $foo = $title,
) {
  $bar = 'hello'
}"
))))

(ert-deftest indent/define-lonely-opening-paren ()
  (puppet-test-with-temp-buffer
   "
define foo::bar
(
$foo = $title,
) {
$bar = 'hello'
}"
   (indent-region (point-min) (point-max))
   (should (string= (buffer-string)
                    "
define foo::bar
(
  $foo = $title,
) {
  $bar = 'hello'
}"
))))

(ert-deftest indent/resource-collector ()
  (puppet-test-with-temp-buffer
      "
Foo <<| tag == 'foo'|>> {
foo => true,
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "
Foo <<| tag == 'foo'|>> {
  foo => true,
}"
))))

(ert-deftest indent/extra-indent-after-colon ()
  (puppet-test-with-temp-buffer
      "
class foo {
# no extra indent after this:
bar {
'extra indent after this':
foo => 'bar';
}
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
class foo {
  # no extra indent after this:
  bar {
    'extra indent after this':
      foo => 'bar';
  }
}"
))))

(ert-deftest indent/case ()
  (puppet-test-with-temp-buffer
      "
case $foo {
'foo': {
#
}
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
case $foo {
  'foo': {
    #
  }
}"
))))

(ert-deftest indent/selector ()
  (puppet-test-with-temp-buffer
      "
$foo ? {
'foo'   => 1,
default => 2,
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
$foo ? {
  'foo'   => 1,
  default => 2,
}"
))))

(ert-deftest indent/case-continued ()
  (puppet-test-with-temp-buffer
      "
case $foo {
'foo',
'bar': {
#
}
}"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
case $foo {
  'foo',
  'bar': {
    #
  }
}"
))))

(ert-deftest indent/if ()
  (puppet-test-with-temp-buffer
      "
class foo {
if $foo {
$foo = 'bar'
}
}
"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
class foo {
  if $foo {
    $foo = 'bar'
  }
}
"
))))

(ert-deftest indent/if-elsif-else ()
  (puppet-test-with-temp-buffer
      "
class foo {
if $foo == 'foo' {
$bar = 'foo1'
}
elsif $foo == 'bar' {
$bar = 'foo2'
}
else {
$bar = 'foo3'
}
}
"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
class foo {
  if $foo == 'foo' {
    $bar = 'foo1'
  }
  elsif $foo == 'bar' {
    $bar = 'foo2'
  }
  else {
    $bar = 'foo3'
  }
}
"
))))

(ert-deftest indent/if-statement-with-no-newline-after-closing-braces ()
  (puppet-test-with-temp-buffer
      "
class foo {
if $foo == 'foo' {
$bar = 'foo1'
} elsif $foo == 'bar' {
$bar = 'foo2'
} else {
$bar = 'foo3'
}
}
"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
      "
class foo {
  if $foo == 'foo' {
    $bar = 'foo1'
  } elsif $foo == 'bar' {
    $bar = 'foo2'
  } else {
    $bar = 'foo3'
  }
}
"
))))

(ert-deftest indent/nested-hash ()
  (puppet-test-with-temp-buffer
      "
class foo {
$x = {
'foo' => {
'bar' => 1,
},
'spam' => {
'eggs' => 1,
},
}
}
"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "
class foo {
  $x = {
    'foo' => {
      'bar' => 1,
    },
    'spam' => {
      'eggs' => 1,
    },
  }
}
"
))))

(ert-deftest indent/nested-hash-inside-array ()
  (puppet-test-with-temp-buffer
      "
$shadow_config_settings = [
{
section => 'CROS',
setting => 'dev_server',
value   => join($dev_server, ','),
require => Package['foo'],
},
]
"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "
$shadow_config_settings = [
  {
    section => 'CROS',
    setting => 'dev_server',
    value   => join($dev_server, ','),
    require => Package['foo'],
  },
]
"
))))

(ert-deftest indent/nested-hash-inside-array-inside-hash ()
  (puppet-test-with-temp-buffer
      "
class openvpn::config {
$defaultRules = [
{
'destination' => '192.168.540.162',
'netmask' => '255.255.255.255',
'protocol' => 'udp',
'ports' => '53',
},
{
'destination' => '192.168.540.163',
'netmask' => '255.255.255.255',
'protocol' => 'udp',
'ports' => '53',
},
]
}
"
    (indent-region (point-min) (point-max))
    (should (string= (buffer-string)
                     "
class openvpn::config {
  $defaultRules = [
    {
      'destination' => '192.168.540.162',
      'netmask' => '255.255.255.255',
      'protocol' => 'udp',
      'ports' => '53',
    },
    {
      'destination' => '192.168.540.163',
      'netmask' => '255.255.255.255',
      'protocol' => 'udp',
      'ports' => '53',
    },
  ]
}
"
))))

(ert-deftest indent/arrow-after-block ()
  (puppet-test-with-temp-buffer
   "
class foo {
file { '/tmp/testdir':
ensure => directory,
} ->
file { '/tmp/testdir/somefile1':
ensure => file,
} ~>
file { '/tmp/testdir/somefile2':
ensure => file,
}
}
"
   (indent-region (point-min) (point-max))
   (should (string= (buffer-string)
                    "
class foo {
  file { '/tmp/testdir':
    ensure => directory,
  } ->
  file { '/tmp/testdir/somefile1':
    ensure => file,
  } ~>
  file { '/tmp/testdir/somefile2':
    ensure => file,
  }
}
"))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; indent-test.el ends here
