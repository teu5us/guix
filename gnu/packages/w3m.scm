;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013 Nikita Karetnikov <nikita@karetnikov.org>
;;; Copyright © 2016 Leo Famulari <leo@famulari.name>
;;; Copyright © 2016 Kei Kebreau <kei@openmailbox.org>
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

(define-module (gnu packages w3m)
  #:use-module ((guix licenses) #:select (x11-style))
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages bdw-gc)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages ncurses)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages)
  #:use-module (guix packages)
  #:use-module (guix git-download)
  #:use-module (guix build-system gnu))

(define-public w3m
  (package
    (name "w3m")
    (version "0.5.3+git20161031")
    (source (origin
              (method git-fetch)
              ;; Debian's fork of w3m is the only one that is still
              ;; maintained.
              (uri (git-reference
                    (url "https://anonscm.debian.org/cgit/collab-maint/w3m.git")
                    (commit (string-append "v" version))))
              (file-name (string-append "w3m-" version "-checkout"))
              (sha256
               (base32
                "142vkkmsk76wj9w6r4y2pa1hmy1kkzmc73an9zchx0ikm2z92x6s"))))
    (build-system gnu-build-system)
    (arguments `(#:tests? #f  ; no check target
                 #:phases (alist-cons-before
                           'configure 'fix-perl
                           (lambda _
                             (substitute* '("scripts/w3mmail.cgi.in"
                                            "scripts/dirlist.cgi.in")
                               (("@PERL@") (which "perl"))))
                           %standard-phases)))
    (inputs
     `(("libgc" ,libgc)
       ("ncurses" ,ncurses)
       ("openssl" ,openssl)
       ("zlib" ,zlib)))
    (native-inputs
     `(("gettext" ,gettext-minimal)
       ("perl" ,perl)
       ("pkg-config" ,pkg-config)))
    (home-page "http://w3m.sourceforge.net/")
    (synopsis "Text-mode web browser")
    (description
     "w3m is a text-based web browser as well as a pager like 'more' or
'less'.  With w3m you can browse web pages through a terminal emulator
window.  Moreover, w3m can be used as a text formatting tool which
typesets HTML into plain text.")
    (license (x11-style "file://doc/README"
                        "See 'doc/README' in the distribution."))))
