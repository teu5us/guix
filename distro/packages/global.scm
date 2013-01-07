;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013 Ludovic Courtès <ludo@gnu.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (distro packages global)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module (guix licenses)
  #:use-module (distro packages ncurses)
  #:use-module (distro packages autotools)
  #:use-module (distro))

(define-public global                             ; a global variable
  (package
    (name "global")
    (version "6.2.7")
    (source
     (origin
      (method url-fetch)
      (uri (string-append "mirror://gnu/global/global-"
                          version ".tar.gz"))
      (sha256
       (base32
        "1dr250kz65wqpbms4lhz857mzmvmpmiaxgyqxvxkb4b0s840i14i"))))
    (build-system gnu-build-system)
    (inputs `(("ncurses" ,ncurses)
              ("libtool" ,libtool)))
    (arguments
     `(#:configure-flags
       (list (string-append "--with-ncurses="
                            (assoc-ref %build-inputs "ncurses")))))
    (home-page "http://www.gnu.org/software/global/")
    (synopsis "GNU GLOBAL source code tag system")
    (description
     "GNU GLOBAL is a source code tagging system that works the same way
across diverse environments (Emacs, vi, less, Bash, web browser, etc).
You can locate specified objects in source files and move there easily.
It is useful for hacking a large project containing many
subdirectories, many #ifdef and many main() functions.  It is similar
to ctags or etags but is different from them at the point of
independence of any editor.  It runs on a UNIX (POSIX) compatible
operating system like GNU and BSD.")
    (license "GPLv3+")))
