;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2014 Taylan Ulrich Bayirli/Kammer <taylanbayirli@gmail.com>
;;; Copyright © 2013 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2014 Mark H Weaver <mhw@netris.org>
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

(define-module (gnu packages emacs)
  #:use-module (guix licenses)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module (gnu packages)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages ncurses)
  #:use-module (gnu packages texinfo)
  #:use-module (gnu packages gnutls)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages xorg)
  #:use-module (gnu packages lesstif)
  #:use-module (gnu packages image)
  #:use-module (gnu packages giflib)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages version-control)
  #:use-module ((gnu packages compression)
                #:renamer (symbol-prefix-proc 'compression:))
  #:use-module (gnu packages xml)
  #:use-module (gnu packages glib)
  #:use-module (guix utils)
  #:use-module (srfi srfi-1))

(define-public emacs
  (package
    (name "emacs")
    (version "24.3")
    (source (origin
             (method url-fetch)
             (uri (string-append "mirror://gnu/emacs/emacs-"
                                 version ".tar.xz"))
             (sha256
              (base32
               "1385qzs3bsa52s5rcncbrkxlydkw0ajzrvfxgv8rws5fx512kakh"))
             (patches (list (search-patch "emacs-configure-sh.patch")))))
    (build-system gnu-build-system)
    (arguments
     '(#:configure-flags
       (list (string-append "--with-crt-dir=" (assoc-ref %build-inputs "libc")
                            "/lib"))
       #:phases (alist-cons-before
                 'configure 'fix-/bin/pwd
                 (lambda _
                   ;; Use `pwd', not `/bin/pwd'.
                   (substitute* (find-files "." "^Makefile\\.in$")
                     (("/bin/pwd")
                      "pwd")))
                 %standard-phases)))
    (inputs
     `(("gnutls" ,gnutls)
       ("ncurses" ,ncurses)

       ;; TODO: Add the optional dependencies.
       ("xlibs" ,libx11)
       ("gtk+" ,gtk+-2)
       ("libXft" ,libxft)
       ("libtiff" ,libtiff)
       ("giflib" ,giflib)
       ("libjpeg" ,libjpeg-8)

       ;; When looking for libpng `configure' links with `-lpng -lz', so we
       ;; must also provide zlib as an input.
       ("libpng" ,libpng)
       ("zlib" ,compression:zlib)

       ("libXpm" ,libxpm)
       ("libxml2" ,libxml2)
       ("libice" ,libice)
       ("libsm" ,libsm)
       ("alsa-lib" ,alsa-lib)
       ("dbus" ,dbus)))
    (native-inputs
     `(("pkg-config" ,pkg-config)
       ("texinfo" ,texinfo)))
    (home-page "http://www.gnu.org/software/emacs/")
    (synopsis "The extensible, customizable, self-documenting text editor")
    (description
     "GNU Emacs is an extensible and highly customizable text editor.  It is
based on an Emacs Lisp interpreter with extensions for text editing.  Emacs
has been extended in essentially all areas of computing, giving rise to a
vast array of packages supporting, e.g., email, IRC and XMPP messaging,
spreadsheets, remote server editing, and much more.  Emacs includes extensive
documentation on all aspects of the system, from basic editing to writing
large Lisp programs.  It has full Unicode support for nearly all human
languages.")
    (license gpl3+)))

(define-public emacs-no-x-toolkit
  (package (inherit emacs)
    (name "emacs-no-x-toolkit")
    (synopsis "The extensible, customizable, self-documenting text
editor (without an X toolkit)" )
    (inputs (alist-delete "gtk+" (package-inputs emacs)))
    (arguments
     (substitute-keyword-arguments (package-arguments emacs)
       ((#:configure-flags flags)
        `(cons "--with-x-toolkit=no" ,flags))))))


;;;
;;; Emacs hacking.
;;;

(define-public geiser
  (package
    (name "geiser")
    (version "0.6")
    (source (origin
             (method url-fetch)
             (uri (string-append "mirror://savannah/geiser/" version
                                 "/geiser-" version ".tar.gz"))
             (sha256
              (base32 "1mrk0bzqcpfhsw6635qznn47nzfy9ps7wrhkpymswdfpw5mdsry5"))))
    (build-system gnu-build-system)
    (inputs `(("guile" ,guile-2.0)
              ("emacs" ,emacs)))
    (home-page "http://nongnu.org/geiser/")
    (synopsis "Collection of Emacs modes for Guile and Racket hacking")
    (description
     "Geiser is a collection of Emacs major and minor modes that
conspire with one or more Scheme interpreters to keep the Lisp Machine
Spirit alive.  It draws inspiration (and a bit more) from environments
such as Common Lisp’s Slime, Factor’s FUEL, Squeak or Emacs itself, and
does its best to make Scheme hacking inside Emacs (even more) fun.

Or, to be precise, what i consider fun.  Geiser is thus my humble
contribution to the dynamic school of expression, and a reaction against
what i perceive as a derailment, in modern times, of standard Scheme
towards the static camp.  Because i prefer growing and healing to poking
at corpses, the continuously running Scheme interpreter takes the center
of the stage in Geiser.  A bundle of Elisp shims orchestrates the dialog
between the Scheme interpreter, Emacs and, ultimately, the schemer,
giving her access to live metadata.")
    (license bsd-3)))

(define-public magit
  (package
    (name "magit")
    (version "1.2.0")
    (source (origin
             (method url-fetch)
             (uri (string-append "https://github.com/downloads/magit/magit/magit-"
                                 version ".tar.gz"))
             (sha256
              (base32 "1a8vvilhd5y5vmlpsh194qpl4qlg0a1brylfscxcacpfp0cmhlzg"))))
    (build-system gnu-build-system)
    (native-inputs `(("texinfo" ,texinfo)))
    (inputs `(("emacs" ,emacs)
              ("git" ,git)
              ("git:gui" ,git "gui")))
    (arguments
     `(#:modules ((guix build gnu-build-system)
                  (guix build utils)
                  (guix build emacs-utils))
       #:imported-modules ((guix build gnu-build-system)
                           (guix build utils)
                           (guix build emacs-utils))
       #:tests? #f  ; no check target
       #:phases
       (alist-replace
        'configure
        (lambda* (#:key outputs #:allow-other-keys)
          (let ((out (assoc-ref outputs "out")))
            (substitute* "Makefile"
              (("/usr/local") out)
              (("/etc") (string-append out "/etc")))))
        (alist-cons-before
         'build 'patch-exec-paths
         (lambda* (#:key inputs #:allow-other-keys)
           (let ((git (assoc-ref inputs "git"))
                 (git:gui (assoc-ref inputs "git:gui")))
             (emacs-substitute-variables "magit.el"
               ("magit-git-executable" (string-append git "/bin/git"))
               ("magit-gitk-executable" (string-append git:gui "/bin/gitk")))))
         %standard-phases))))
    (home-page "http://magit.github.io/")
    (synopsis "Emacs interface for the Git version control system")
    (description
     "With Magit, you can inspect and modify your Git repositories with Emacs.
You can review and commit the changes you have made to the tracked files, for
example, and you can browse the history of past changes.  There is support for
cherry picking, reverting, merging, rebasing, and other common Git
operations.")
    (license gpl3+)))
