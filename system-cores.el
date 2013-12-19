;;; system-cores.el --- Find out how many processors and cores you have

;; Copyright (C) 2013 Aaron Miller. All rights reversed.
;; Share and Enjoy!

;; Last revision: Wednesday, December 18, 2013, ca. 19:30.

;; Author: Aaron Miller <me@aaron-miller.me>

;; This file is not part of Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation; either version 2, or (at your
;; option) any later version.

;; This file is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see `http://www.gnu.org/licenses'.

;;; Commentary:

;; Someone on Stack Overflow asked [1] whether there was a
;; platform-independent method of finding out how many processors a
;; given machine has. It turns out there's not, so I wrote one.

;; "Platform-independent" is stretching a point; the best I could come
;; up with was to define a function `system-cores', which uses a
;; lookup table (`system-cores-delegate-alist'), keyed by
;; `system-type' values, to find and invoke a function which knows how
;; to get the processor and core counts for a given platform. This
;; means that some platforms, namely those for which I was able to
;; find reliable instructions on how to obtain processor and core
;; counts, are supported quite well, while others aren't supported at
;; all. On the other hand, no truly platform-independent interface to
;; that information exists at any level, as far as I've been able to
;; find out, so this works about as well as I think anything could be
;; expected to do. (And if you use a system which isn't supported,
;; feel free to write a delegate and submit a pull request on Github,
;; or email me a diff!)

;; To use this code, drop this file into your Emacs load path, then
;; (require 'system-cores), and finally invoke the function
;; `system-cores' to retrieve processor and core count
;; information. See that function's documentation for additional
;; details on its invocation and behavior.

;;; Bugs/TODO:

;; I don't have access to a true BSD system, but only one running
;; Darwin, which is similar but not quite the same. I've therefore
;; been unable to properly test the BSD delegate
;; (`system-cores-sysctl'). If you run BSD and want to use this code,
;; you are strongly advised to investigate your system's sysctl output
;; and modify `system-cores-sysctl' accordingly. (If different BSD
;; variants present the information differently, it may be necessary
;; to write a function which not only checks `system-type', but also
;; examines the value of `system-configuration', in order to identify
;; the variant in use.)

;;; Miscellany:

;; The canonical version of this file is hosted in my Github
;; repository [2]. If you didn't get it from there, great! I'm happy
;; to hear my humble efforts have achieved wide enough interest to
;; result in a fork hosted somewhere else. I'd be obliged if you'd
;; drop me a line to let me know about it.

;; [1]: http://stackoverflow.com/q/20666556/1713079
;; [2]: https://github.com/aaron-em/system-cores.el

(require 'cl)

(put 'system-cores-delegate-error
     'error-conditions '(error system-cores-delegate-error))

(defvar system-cores-delegate-alist
  '((gnu/linux      . system-cores-cpuinfo)
    (cygwin         . system-cores-cpuinfo)
    (windows-nt     . system-cores-wmic)
    (darwin         . system-cores-profiler)
    (berkeley-linux . system-cores-sysctl))
  "An alist whose cars are `system-type' values, and whose cdrs
are the corresponding function to call in order to find out how
many processors and cores a system of that type has
installed. The `system-cores' function uses this to choose which
delegate function to invoke for a given architecture.

  Delegates are expected to return an alist of the form:

  '((cores . #)
    (processors . #))

where '#' represents a number greater than zero. A condition will
be signaled if a delegate returns a value not satisfying this
requirement.

  Currently defined delegates include:

  `system-cores-cpuinfo'

  Obtain processor and core information from /proc/cpuinfo,
typically found on Linux and its relatives (including Cygwin).

  `system-cores-wmic'

  Obtain processor and core information via
the command-line Windows Management Instrumentation query tool,
found on systems of Windows NT derivation (Windows NT, Windows
2000, and all later versions).

  `system-cores-profiler'

  Obtain processor and core information from the output of
/usr/sbin/system_profiler, typically found on OS X (Darwin)
systems.

  `system-cores-sysctl'

  [Note well! This delegate has been tested
on a Darwin system, but not on a BSD system, and it is
consequently uncertain whether the information it returns will
be correct and complete for any BSD derivative. You are
strongly recommended to investigate your system's sysctl output
and modify the definition of `system-cores-sysctl'
accordingly!]

  Obtain processor and core information from the output of
/usr/sbin/sysctl, typically found on BSD and its
derivatives. (This includes Darwin systems, but on at least one
such system the processor counts returned by sysctl do not
agree with those from the Apple System Profiler; since the
latter may reasonably be expected, on an Apple system, to be
more accurate than the former, it is preferred by default on
that architecture.)")

(defun* system-cores (&key (cores nil cores-p)
                           (processors nil processors-p))
  "Return the number of processor cores, and the number of
physical processors, installed on the machine where Emacs is
running.

  Called without arguments, this function returns an alist of the
form:

  '((cores . #)
    (processors . #))

where '#' represents a number greater than zero. Called with one
of the keywords :CORES and :PROCESSORS, the function returns the
corresponding number. (Called with both keywords, the function
signals a WRONG-NUMBER-OF-ARGUMENTS condition.)

  Most of the actual work involved in obtaining this information
is done by one of several delegate functions, selected on the
basis of the system architecture where you are running as
identified by the value of `system-type'. For details on what
delegates are available, and which system types are supported,
see the documentation for `system-cores-delegate-alist'."
  (if (and cores-p processors-p)
      (signal 'wrong-number-of-arguments '(system-cores 2)))
  (let ((delegate (cdr (assoc system-type system-cores-delegate-alist)))
        (result nil))
    (if delegate (setq result (funcall delegate))
      (signal 'system-cores-delegate-error
              (concat "No `system-cores' delegate available for a "
                      (symbol-name system-type) " system")))
    (if (or (equal (cdr (assoc 'cores result)) 0)
            (equal (cdr (assoc 'processors result)) 0))
        (signal 'system-cores-delegate-error
                (concat "`" (symbol-name delegate) "'"
                        " failed to return valid information: "
                        (prin1-to-string result)))
      (cond
       (cores-p
        (cdr (assoc 'cores result)))
       (processors-p
        (cdr (assoc 'processors result)))
       (t
        result)))))

(defun system-cores-cpuinfo ()
  "Return the number of processor cores, and the number of
physical processors, listed in /proc/cpuinfo.

  This function is a `system-cores' delegate."
  (let ((cpuinfo
         (map 'list #'(lambda (line) (split-string line "\\s-*\:\\s-*"))
              (split-string (shell-command-to-string "cat /proc/cpuinfo") "\n")))
        processors cores)
    (setq cores
          (reduce '+
                  (map 'list
                       #'(lambda (a) (if (string= "processor" (car a)) 1 0))
                       cpuinfo)))
    (setq processors
          (length (delete-dups
                   (remove-if 'null
                              (map 'list
                                   #'(lambda (a)
                                       (if (string= "core id" (car a))
                                           (cadr a)
                                         nil))
                                   cpuinfo)))))
    `((cores . ,cores)
      (processors . ,processors))))

(defun system-cores-wmic ()
  "Return the number of processor cores, and the number of
physical processors, listed in the output of a Windows Management
Instrumentation query.

  This function is a `system-cores' delegate."
  (let ((cpuinfo 
         (map 'list
              #'(lambda (s) (split-string s "="))
              (remove-if
               #'(lambda (s) (string= s ""))
               (split-string 
                (shell-command-to-string
                 "wmic cpu get NumberOfCores,NumberOfLogicalProcessors /format:List") 
                "\r\n")))))
    `((cores .
             ,(string-to-number (cadr (assoc "NumberOfCores" cpuinfo))))
      (processors .
                  ,(string-to-number (cadr (assoc "NumberOfLogicalProcessors" cpuinfo)))))))

(defun system-cores-profiler ()
  "Return the number of processor cores, and the number of
physical processors, listed in the output of the Apple System
Profiler.

  This function is a `system-cores' delegate."
  (let ((cpuinfo
         (map 'list
              #'(lambda (s) (split-string s ": "))
              (remove-if 'null
                         (map 'list #'(lambda (s)
                                        (when (string-match "^ +" s)
                                          (replace-match "" t t s)))
                              (split-string (shell-command-to-string "system_profiler SPHardwareDataType")
                                            "\n"))))))
    `((cores .
             ,(string-to-number (cadr (assoc "Total Number of Cores" cpuinfo))))
      (processors .
                  ,(string-to-number (cadr (assoc "Number of Processors" cpuinfo)))))))

(defun system-cores-sysctl ()
  "Return the number of processor cores, and the number of
physical processors, listed in the output of the sysctl command.

  This function is a `system-cores' delegate."
  (let ((cpuinfo
         (map 'list
              #'(lambda (s) (split-string s ": " t))
              (split-string
               (shell-command-to-string "sysctl hw.physicalcpu hw.logicalcpu") "\n" t))))
    `((cores .
             ,(string-to-number (cadr (assoc "hw.physicalcpu" cpuinfo))))
      (processors .
                  ,(string-to-number (cadr (assoc "hw.logicalcpu" cpuinfo)))))))

(provide 'system-cores)

;;; system-cores.el ends here
