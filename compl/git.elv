# Git completion, ported from the official bash completion script
# https://github.com/git/git/blob/master/contrib/completion/git-completion.bash.
#
# License is the same as the bash script, i.e. GPLv2.

# WIP. Currently supports:
# * Global flags (e.g. --version)
# * git checkout: flags, refs and filenames after "--"
# * All other commands fall back to filename completion.

use re
use str

# Configurations

# When completing "git checkout", whether to propose branches that exist in
# exactly one remote, which will do an implicit "--track <remote>/<branch>".
checkout-propose-remote-branch = $true

# General utilities. Maybe some of those should be builtins eventually.

fn in [x xs]{ has-value $xs $x }
fn inc [x]{ + $x 1 }
fn dec [x]{ - $x 1 }
fn without [@exclude]{
  each [x]{ if (not (in $x $exclude)) { put $x } }
}

fn has-any-value [xs ps]{
  for p $ps {
    if (has-value $xs p) {
      put $true
      return
    }
  }
  put $false
}

fn has-file [path]{ put ?(test -e $path) }

# Completion utilities.

git-dir git-cd repo-path = '' '' '' # Set at the beginning of complete-git.

fn call-git [@a]{
  flags = []
  if (not-eq $git-dir '') { @flags = $@flags --git-dir $git-dir }
  if (not-eq $git-cd '') { @flags = $@flags -C $git-cd }
  git $@flags $@a
}

fn expand-alias [subcmd]{
  def = ''
  try {
    @def = (call-git config --get alias.$subcmd | re:split '\s+' (all))
  } except _ {
    # Not found
    put $subcmd
    return
  }
  for word $def {
    if (in $word [gitk !gitk]) {
      put gitk
      return
    } elif (has-prefix $word !) {
      # Shell command alias, skip
    } elif (has-prefix $word -) {
      # Option, skip
    } elif (has-value $word '=') {
      # Environment, skip
    } elif (eq $word git) {
      # Git itself, skip
    } elif (eq $word '()') {
      # Function definition, skip
    } elif (eq $word :) {
      # Nop, skip
    } elif (has-prefix $word "'") {
      # Opening quote after sh -c, skip
      # XXX(xiaq): It's not clear how this works.
    } else {
      put $word
      return
    }
  }
  put $subcmd
}

fn repo-path {
  if (eq $repo-path '') {
    repo-path = (call-git rev-parse --absolute-git-dir)
    # TODO: Implement fast paths
  }
  put $repo-path
}

# Not declared with fn: the "return" within will exit the calling fn.
check-doubledash~ = [words]{
  if (has-value $words --) {
    edit:complete-filename $words[-1]
    return
  }
}

# Internal completers.

fn complete-subcmds {
  # This commands outputs each command in its own line, so the output is
  # directly usable in completers.
  git --list-cmds=list-mainporcelain,others,nohelpers,alias,list-complete,config
}

fn complete-flags [subcmd &extra=[] &exclude=[]]{
  {
    call-git $subcmd --git-completion-helper | str:trim-space (all) | splits ' ' (all)
    explode $extra
  } | without -- $@exclude
}

@HEADs = HEAD FETCH_HEAD ORIG_HEAD MERGE_HEAD REBASE_HEAD

# TODO(xiaq): Deduplicate. The most common scenerio is that HEAD can appear
# twice, once from the expansion of HEADs, once from refs/remotes/origin/HEAD.
fn complete-refs-inner [seed &track=$false]{
  format = ''
  if (or (eq $seed refs) (has-prefix $seed refs/)) {
    # The user is spelling out a full refname, so we don't abbreviate.
    format = refname
  } else {
    dir = (repo-path)
    for head $HEADs {
      if (has-file $dir/$head) { put $head }
    }
    format = refname:strip=2
  }
  call-git for-each-ref --format='%('$format')' | without ''
  if $track {
    format = 'refname:strip=3'
    call-git for-each-ref --format='%('$format')' --sort=$format \
      'refs/remotes/*/*'{,'/**'} | uniq -u
  }
}

# TODO(xiaq): Support &remote
fn complete-refs [seed &track=$false]{
  if (has-prefix $seed '^') {
    put '^'(complete-refs-inner &track=$track)
  } else {
    complete-refs-inner $seed &track=$track
  }
}

# Subcommand completers.

fn complete-checkout [@words]{
  check-doubledash $words[:-1]
  cur = $words[-1]
  if (has-prefix $cur --conflict=) {
    put --conflict={diff3 merge}
  } elif (has-prefix $cur --) {
    complete-flags checkout
  } else {
    track = (and $checkout-propose-remote-branch \
                 (not (has-any-value $words [--track --no-track --no-guess])))
    complete-refs $cur &track=$track
  }
}

subcmd-completer = [
  &checkout=$complete-checkout~
]

fn has-subcmd [subcmd]{ has-key $subcmd-completer $subcmd }

# The main completer.

fn complete-git [@words]{
  git-dir git-cd repo-path = '' '' ''
  command = ''

  # Look at previous words to determine some environment.
  i = 1
  while (< $i (- (count $words) 1)) {
    word = $words[$i]
    if (has-prefix $word --git-dir=) {
      git-dir = $word[(count --git-dir=):]
    } elif (eq $word --git-dir) {
      i = (+ $i 1)
      git-dir = $words[$i]
    } elif (eq $word --bare) {
      git-dir = .
    } elif (eq $word --help) {
      command = help
      break
    } elif (in $word [-c --work-tree --namespace]) {
      i = (+ $i 1) # Skip over next word
    } elif (has-prefix $word -) {
      # Ignore other flags for now
    } else {
      command = $word
      break
    }
    i = (+ $i 1)
  }

  if (eq $command '') {
    prev cur = $words[-2] $words[-1]
    if (in $prev [--git-dir -C --work-tree]) {
      edit:complete-filename $cur
      return
    } elif (in $prev [-c --namespace]) {
      # Completion not supported
      return
    }
    if (has-prefix $cur --) {
      explode [--paginate --no-pager --git-dir= --bare --version
               --exec-path --exec-path= --html-path --man-path --info-path
               --work-tree= --namespace= --no-replace-objects --help]
    } else {
      complete-subcmds
    }
    return
  }

  if (not (has-subcmd $command)) {
    command = (expand-alias $command)
  }
  if (has-subcmd $command) {
    $subcmd-completer[$command] $@words
  } else {
    # Fallback to filename completion
    edit:complete-filename $words[-1]
  }
}

fn apply {
  edit:completion:arg-completer[git] = $complete-git~
}
