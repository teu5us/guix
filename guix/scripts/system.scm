;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2014, 2015 Ludovic Courtès <ludo@gnu.org>
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

(define-module (guix scripts system)
  #:use-module (guix config)
  #:use-module (guix ui)
  #:use-module (guix store)
  #:use-module (guix gexp)
  #:use-module (guix derivations)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (guix monads)
  #:use-module (guix profiles)
  #:use-module (guix scripts build)
  #:use-module (guix build utils)
  #:use-module (gnu build install)
  #:use-module (gnu system)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system vm)
  #:use-module (gnu system grub)
  #:use-module (gnu packages grub)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-19)
  #:use-module (srfi srfi-26)
  #:use-module (srfi srfi-37)
  #:use-module (ice-9 match)
  #:export (guix-system
            read-operating-system))


;;;
;;; Operating system declaration.
;;;

(define %user-module
  ;; Module in which the machine description file is loaded.
  (make-user-module '((gnu system)
                      (gnu services)
                      (gnu system shadow))))

(define (read-operating-system file)
  "Read the operating-system declaration from FILE and return it."
  (load* file %user-module))



;;;
;;; Installation.
;;;

;; TODO: Factorize.
(define references*
  (store-lift references))
(define topologically-sorted*
  (store-lift topologically-sorted))


(define* (copy-item item target
                    #:key (log-port (current-error-port)))
  "Copy ITEM to the store under root directory TARGET and register it."
  (mlet* %store-monad ((refs (references* item)))
    (let ((dest  (string-append target item))
          (state (string-append target "/var/guix")))
      (format log-port "copying '~a'...~%" item)

      ;; Remove DEST if it exists to make sure that (1) we do not fail badly
      ;; while trying to overwrite it (see <http://bugs.gnu.org/20722>), and
      ;; (2) we end up with the right contents.
      (when (file-exists? dest)
        (delete-file-recursively dest))

      (copy-recursively item dest
                        #:log (%make-void-port "w"))

      ;; Register ITEM; as a side-effect, it resets timestamps, etc.
      ;; Explicitly use "TARGET/var/guix" as the state directory, to avoid
      ;; reproducing the user's current settings; see
      ;; <http://bugs.gnu.org/18049>.
      (unless (register-path item
                             #:prefix target
                             #:state-directory state
                             #:references refs)
        (leave (_ "failed to register '~a' under '~a'~%")
               item target))

      (return #t))))

(define* (copy-closure item target
                       #:key (log-port (current-error-port)))
  "Copy ITEM and all its dependencies to the store under root directory
TARGET, and register them."
  (mlet* %store-monad ((refs    (references* item))
                       (to-copy (topologically-sorted*
                                 (delete-duplicates (cons item refs)
                                                    string=?))))
    (sequence %store-monad
              (map (cut copy-item <> target #:log-port log-port)
                   to-copy))))

(define (install-grub* grub.cfg device target)
  "This is a variant of 'install-grub' with error handling, lifted in
%STORE-MONAD"
  (let* ((gc-root      (string-append %gc-roots-directory "/grub.cfg"))
         (temp-gc-root (string-append gc-root ".new"))
         (delete-file  (lift1 delete-file %store-monad))
         (make-symlink (lift2 switch-symlinks %store-monad))
         (rename       (lift2 rename-file %store-monad)))
    (mbegin %store-monad
      ;; Prepare the symlink to GRUB.CFG to make sure that it's a GC root when
      ;; 'install-grub' completes (being a bit paranoid.)
      (make-symlink temp-gc-root grub.cfg)

      (munless (false-if-exception (install-grub grub.cfg device target))
        (delete-file temp-gc-root)
        (leave (_ "failed to install GRUB on device '~a'~%") device))

      ;; Register GRUB.CFG as a GC root so that its dependencies (background
      ;; image, font, etc.) are not reclaimed.
      (rename temp-gc-root gc-root))))

(define* (install os-drv target
                  #:key (log-port (current-output-port))
                  grub? grub.cfg device)
  "Copy the closure of GRUB.CFG, which includes the output of OS-DRV, to
directory TARGET.  TARGET must be an absolute directory name since that's what
'guix-register' expects.

When GRUB? is true, install GRUB on DEVICE, using GRUB.CFG."
  (define (maybe-copy to-copy)
    (with-monad %store-monad
      (if (string=? target "/")
          (begin
            (warning (_ "initializing the current root file system~%"))
            (return #t))
          (begin
            ;; Make sure the target store exists.
            (mkdir-p (string-append target (%store-prefix)))

            ;; Copy items to the new store.
            (copy-closure to-copy target #:log-port log-port)))))

  ;; Make sure TARGET is root-owned when running as root, but still allow
  ;; non-root uses (useful for testing.)  See
  ;; <http://lists.gnu.org/archive/html/guix-devel/2015-05/msg00452.html>.
  (if (zero? (geteuid))
      (chown target 0 0)
      (warning (_ "not running as 'root', so \
the ownership of '~a' may be incorrect!~%")
               target))

  (chmod target #o755)
  (let ((os-dir   (derivation->output-path os-drv))
        (format   (lift format %store-monad))
        (populate (lift2 populate-root-file-system %store-monad)))

    (mbegin %store-monad
      ;; Copy the closure of GRUB.CFG, which includes OS-DIR, GRUB's
      ;; background image and so on.
      (maybe-copy grub.cfg)

      ;; Create a bunch of additional files.
      (format log-port "populating '~a'...~%" target)
      (populate os-dir target)

      (mwhen grub?
        (install-grub* grub.cfg device target)))))


;;;
;;; Reconfiguration.
;;;

(define %system-profile
  ;; The system profile.
  (string-append %state-directory "/profiles/system"))

(define-syntax-rule (save-environment-excursion body ...)
  "Save the current environment variables, run BODY..., and restore them."
  (let ((env (environ)))
    (dynamic-wind
      (const #t)
      (lambda ()
        body ...)
      (lambda ()
        (environ env)))))

(define* (switch-to-system os
                           #:optional (profile %system-profile))
  "Make a new generation of PROFILE pointing to the directory of OS, switch to
it atomically, and then run OS's activation script."
  (mlet* %store-monad ((drv    (operating-system-derivation os))
                       (script (operating-system-activation-script os)))
    (let* ((system     (derivation->output-path drv))
           (number     (+ 1 (generation-number profile)))
           (generation (generation-file-name profile number)))
      (symlink system generation)
      (switch-symlinks profile generation)

      (format #t (_ "activating system...~%"))

      ;; The activation script may change $PATH, among others, so protect
      ;; against that.
      (return (save-environment-excursion
               ;; Tell 'activate-current-system' what the new system is.
               (setenv "GUIX_NEW_SYSTEM" system)

               (primitive-load (derivation->output-path script))))

      ;; TODO: Run 'deco reload ...'.
      )))

(define-syntax-rule (unless-file-not-found exp)
  (catch 'system-error
    (lambda ()
      exp)
    (lambda args
      (if (= ENOENT (system-error-errno args))
          #f
          (apply throw args)))))

(define (seconds->string seconds)
  "Return a string representing the date for SECONDS."
  (let ((time (make-time time-utc 0 seconds)))
    (date->string (time-utc->date time)
                  "~Y-~m-~d ~H:~M")))

(define* (previous-grub-entries #:optional (profile %system-profile))
  "Return a list of 'menu-entry' for the generations of PROFILE."
  (define (system->grub-entry system number time)
    (unless-file-not-found
     (call-with-input-file (string-append system "/parameters")
       (lambda (port)
         (match (read port)
           (('boot-parameters ('version 0)
                              ('label label) ('root-device root)
                              ('kernel linux)
                              rest ...)
            (menu-entry
             (label (string-append label " (#"
                                   (number->string number) ", "
                                   (seconds->string time) ")"))
             (linux linux)
             (linux-arguments
              (cons* (string-append "--root=" root)
                     #~(string-append "--system=" #$system)
                     #~(string-append "--load=" #$system "/boot")
                     (match (assq 'kernel-arguments rest)
                       ((_ args) args)
                       (#f       '()))))          ;old format
             (initrd #~(string-append #$system "/initrd"))))
           (_                                     ;unsupported format
            (warning (_ "unrecognized boot parameters for '~a'~%")
                     system)
            #f))))))

  (let* ((numbers (generation-numbers profile))
         (systems (map (cut generation-file-name profile <>)
                       numbers))
         (times   (map (lambda (system)
                         (unless-file-not-found
                          (stat:mtime (lstat system))))
                       systems)))
    (filter-map system->grub-entry systems numbers times)))


;;;
;;; Action.
;;;

(define* (system-derivation-for-action os action
                                       #:key image-size full-boot? mappings)
  "Return as a monadic value the derivation for OS according to ACTION."
  (case action
    ((build init reconfigure)
     (operating-system-derivation os))
    ((vm-image)
     (system-qemu-image os #:disk-image-size image-size))
    ((vm)
     (system-qemu-image/shared-store-script os
                                            #:full-boot? full-boot?
                                            #:disk-image-size image-size
                                            #:mappings mappings))
    ((disk-image)
     (system-disk-image os #:disk-image-size image-size))))

(define* (maybe-build drvs
                      #:key dry-run? use-substitutes?)
  "Show what will/would be built, and actually build DRVS, unless DRY-RUN? is
true."
  (with-monad %store-monad
    (>>= (show-what-to-build* drvs
                              #:dry-run? dry-run?
                              #:use-substitutes? use-substitutes?)
         (lambda (_)
           (if dry-run?
               (return #f)
               (built-derivations drvs))))))

(define* (perform-action action os
                         #:key grub? dry-run?
                         use-substitutes? device target
                         image-size full-boot?
                         (mappings '()))
  "Perform ACTION for OS.  GRUB? specifies whether to install GRUB; DEVICE is
the target devices for GRUB; TARGET is the target root directory; IMAGE-SIZE
is the size of the image to be built, for the 'vm-image' and 'disk-image'
actions.  FULL-BOOT? is used for the 'vm' action; it determines whether to
boot directly to the kernel or to the bootloader."
  (mlet* %store-monad
      ((sys       (system-derivation-for-action os action
                                                #:image-size image-size
                                                #:full-boot? full-boot?
                                                #:mappings mappings))
       (grub      (package->derivation grub))
       (grub.cfg  (operating-system-grub.cfg os
                                             (if (eq? 'init action)
                                                 '()
                                                 (previous-grub-entries))))
       (drvs   -> (if (and grub? (memq action '(init reconfigure)))
                      (list sys grub grub.cfg)
                      (list sys)))
       (%         (maybe-build drvs #:dry-run? dry-run?
                               #:use-substitutes? use-substitutes?)))

    (if dry-run?
        (return #f)
        (begin
          (for-each (cut format #t "~a~%" <>)
                    (map derivation->output-path drvs))

          ;; Make sure GRUB is accessible.
          (when grub?
            (let ((prefix (derivation->output-path grub)))
              (setenv "PATH"
                      (string-append  prefix "/bin:" prefix "/sbin:"
                                      (getenv "PATH")))))

          (case action
            ((reconfigure)
             (mbegin %store-monad
               (switch-to-system os)
               (mwhen grub?
                 (install-grub* (derivation->output-path grub.cfg)
                                device "/"))))
            ((init)
             (newline)
             (format #t (_ "initializing operating system under '~a'...~%")
                     target)
             (install sys (canonicalize-path target)
                      #:grub? grub?
                      #:grub.cfg (derivation->output-path grub.cfg)
                      #:device device))
            (else
             ;; All we had to do was to build SYS.
             (return (derivation->output-path sys))))))))


;;;
;;; Options.
;;;

(define (show-help)
  (display (_ "Usage: guix system [OPTION] ACTION FILE
Build the operating system declared in FILE according to ACTION.\n"))
  (newline)
  (display (_ "The valid values for ACTION are:\n"))
  (newline)
  (display (_ "\
   reconfigure      switch to a new operating system configuration\n"))
  (display (_ "\
   build            build the operating system without installing anything\n"))
  (display (_ "\
   vm               build a virtual machine image that shares the host's store\n"))
  (display (_ "\
   vm-image         build a freestanding virtual machine image\n"))
  (display (_ "\
   disk-image       build a disk image, suitable for a USB stick\n"))
  (display (_ "\
   init             initialize a root file system to run GNU.\n"))

  (show-build-options-help)
  (display (_ "
      --on-error=STRATEGY
                         apply STRATEGY when an error occurs while reading FILE"))
  (display (_ "
      --image-size=SIZE  for 'vm-image', produce an image of SIZE"))
  (display (_ "
      --no-grub          for 'init', do not install GRUB"))
  (display (_ "
      --share=SPEC       for 'vm', share host file system according to SPEC"))
  (display (_ "
      --expose=SPEC      for 'vm', expose host file system according to SPEC"))
  (display (_ "
      --full-boot        for 'vm', make a full boot sequence"))
  (newline)
  (display (_ "
  -h, --help             display this help and exit"))
  (display (_ "
  -V, --version          display version information and exit"))
  (newline)
  (show-bug-report-information))

(define (specification->file-system-mapping spec writable?)
  "Read the SPEC and return the corresponding <file-system-mapping>."
  (let ((index (string-index spec #\=)))
    (if index
        (file-system-mapping
         (source (substring spec 0 index))
         (target (substring spec (+ 1 index)))
         (writable? writable?))
        (file-system-mapping
         (source spec)
         (target spec)
         (writable? writable?)))))

(define %options
  ;; Specifications of the command-line options.
  (cons* (option '(#\h "help") #f #f
                 (lambda args
                   (show-help)
                   (exit 0)))
         (option '(#\V "version") #f #f
                 (lambda args
                   (show-version-and-exit "guix system")))
         (option '("on-error") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'on-error (string->symbol arg)
                               result)))
         (option '("image-size") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'image-size (size->number arg)
                               result)))
         (option '("no-grub") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'install-grub? #f result)))
         (option '("full-boot") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'full-boot? #t result)))

         (option '("share") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'file-system-mapping
                               (specification->file-system-mapping arg #t)
                               result)))
         (option '("expose") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'file-system-mapping
                               (specification->file-system-mapping arg #f)
                               result)))

         (option '(#\n "dry-run") #f #f
                 (lambda (opt name arg result)
                   (alist-cons 'dry-run? #t result)))
         (option '(#\s "system") #t #f
                 (lambda (opt name arg result)
                   (alist-cons 'system arg
                               (alist-delete 'system result eq?))))
         %standard-build-options))

(define %default-options
  ;; Alist of default option values.
  `((system . ,(%current-system))
    (substitutes? . #t)
    (build-hook? . #t)
    (max-silent-time . 3600)
    (verbosity . 0)
    (image-size . ,(* 900 (expt 2 20)))
    (install-grub? . #t)))


;;;
;;; Entry point.
;;;

(define (guix-system . args)
  (define (parse-sub-command arg result)
    ;; Parse sub-command ARG and augment RESULT accordingly.
    (if (assoc-ref result 'action)
        (alist-cons 'argument arg result)
        (let ((action (string->symbol arg)))
          (case action
            ((build vm vm-image disk-image reconfigure init)
             (alist-cons 'action action result))
            (else (leave (_ "~a: unknown action~%") action))))))

  (define (match-pair car)
    ;; Return a procedure that matches a pair with CAR.
    (match-lambda
     ((head . tail)
      (and (eq? car head) tail))
     (_ #f)))

  (define (option-arguments opts)
    ;; Extract the plain arguments from OPTS.
    (let* ((args   (reverse (filter-map (match-pair 'argument) opts)))
           (count  (length args))
           (action (assoc-ref opts 'action)))
      (define (fail)
        (leave (_ "wrong number of arguments for action '~a'~%")
               action))

      (unless action
        (format (current-error-port)
                (_ "guix system: missing command name~%"))
        (format (current-error-port)
                (_ "Try 'guix system --help' for more information.~%"))
        (exit 1))

      (case action
        ((build vm vm-image disk-image reconfigure)
         (unless (= count 1)
           (fail)))
        ((init)
         (unless (= count 2)
           (fail))))
      args))

  (with-error-handling
    (let* ((opts     (parse-command-line args %options
                                         (list %default-options)
                                         #:argument-handler
                                         parse-sub-command))
           (args     (option-arguments opts))
           (file     (first args))
           (action   (assoc-ref opts 'action))
           (system   (assoc-ref opts 'system))
           (os       (if file
                         (load* file %user-module
                                #:on-error (assoc-ref opts 'on-error))
                         (leave (_ "no configuration file specified~%"))))

           (dry?     (assoc-ref opts 'dry-run?))
           (grub?    (assoc-ref opts 'install-grub?))
           (target   (match args
                       ((first second) second)
                       (_ #f)))
           (device   (and grub?
                          (grub-configuration-device
                           (operating-system-bootloader os))))

           (store    (open-connection)))
      (set-build-options-from-command-line store opts)

      (run-with-store store
        (mbegin %store-monad
          (set-guile-for-build (default-guile))
          (perform-action action os
                          #:dry-run? dry?
                          #:use-substitutes? (assoc-ref opts 'substitutes?)
                          #:image-size (assoc-ref opts 'image-size)
                          #:full-boot? (assoc-ref opts 'full-boot?)
                          #:mappings (filter-map (match-lambda
                                                  (('file-system-mapping . m)
                                                   m)
                                                  (_ #f))
                                                 opts)
                          #:grub? grub?
                          #:target target #:device device))
        #:system system))))

;;; system.scm ends here
