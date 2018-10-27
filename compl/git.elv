# Git completion, ported from the official bash completion script
# https://github.com/git/git/blob/master/contrib/completion/git-completion.bash.
#
# License is the same as the bash script, i.e. GPLv2.

# WIP. Currently supports:
# * Global flags (e.g. --version)
# * Some subcommands; see subcmd-completer below for a up-to-date list.
# * All other commands fall back to filename completion.

use re
use str

# Configurations

# When completing "git checkout", whether to propose branches that exist in
# exactly one remote, which will do an implicit "--track <remote>/<branch>".
checkout-propose-remote-branch = $true

# General utilities. Maybe some of those should be builtins eventually.

fn in [x xs]{ has-value $xs $x }
fn len [x]{ count $x }
fn inc [x]{ + $x 1 }
fn dec [x]{ - $x 1 }

fn has-file [path]{ put ?(test -e $path) }
fn has-dir  [path]{ put ?(test -d $path) }

fn dedup {
  m = [&]
  each [x]{ m[$x] = $true }
  keys $m
}

fn without [@exclude]{
  each [x]{ if (not (in $x $exclude)) { put $x } }
}

fn dir-file [p]{
  i = (+ 1 (str:last-index $p /)) # i = 0 if there is no / in $p
  put $p[:$i $i':']
}

fn find-any [haystack needles fallback]{
  for p $needles {
    if (in $p $haystack) {
      put $p
      return
    }
  }
  put $fallback
}

fn has-any [haystack needles]{
  fb = { } # Closures are always unique
  not-eq $fb (find-any $haystack $needles $fb)
}

fn find-any-prefix [s prefixes]{
  for p $prefixes {
    if (has-prefix $s $p) {
      put $p
      return
    }
  }
  put $false
}

# Completion utilities.

# Set at the beginning of complete-git.
git-dir git-cd repo-path cur = '' '' '' ''

fn call-git [&no-quote=$false @a]{
  flags = []
  if (not-eq $git-dir '') { @flags = $@flags --git-dir $git-dir }
  if (not-eq $git-cd '') { @flags = $@flags -C $git-cd }
  if $no-quote { @flags = $@flags -c core.quotePath=false }
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
complete-filename-after-doubledash~ = [words]{
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

# Used to complete:
# <branch>, <commit> and <tree-ish> of git checkout
#
# TODO(xiaq): Support &remote
fn complete-refs [seed &track=$false]{
  if (has-prefix $seed '^') {
    put '^'(complete-refs-inner &track=$track)
  } else {
    complete-refs-inner $seed &track=$track
  }
}

fn complete-heads {
  call-git for-each-ref --format='%(refname:strip=2)' 'refs/heads/*'{,'/**'}
}

# Used to complete:
# <pathspec> of git add
#
# TODO(xiaq): This doesn't support the signature syntax of pathspec.
fn complete-index-file [seed ls-files-opts]{
  dir _ = (dir-file $seed)
  git-cd=$dir call-git &no-quote ls-files --exclude-standard $@ls-files-opts |
    each [p]{ re:replace '/.*$' '' $p} | dedup | put $dir(all)
}

fn complete-committable-file [seed]{
  dir _ = (dir-file $seed)
  git-cd=$dir call-git &no-quote diff-index --name-only --relative HEAD
}

# Used to complete:
# <tree-ish> of git archive
#
# TODO(xiaq): Maybe this should be called complete-tree-ish instead?
fn complete-revlist-file [seed]{
  @a = (splits : &max=2 $seed)
  if (and (eq (len $a) 2) (not-eq $a[0] '')) {
    # Complete <rev>:<path>
    if (str:contains $a[0] ..) {
      # <rev> cannot be range. The bash script implicitly fall backs to
      # filename in this case, which doesn't seem to be intended
      return
    }
    rev path = $@a
    dir _ = (dir-file $path)
    call-git ls-tree $rev':'$dir | each [line]{
      filename = (splits "\t" &max=2 $line | drop 1)
      put $rev':'$dir$filename
    }
  } elif (str:contains $seed ..) {
    prefix seed = '' ''
    if (str:contains $seed ...) {
      rev1 rev2 = (splits ... &max=2 $seed)
      prefix seed = $rev1... $rev2
    } else {
      rev1 rev2 = (splits .. &max=2 $seed)
      prefix seed = $rev1.. $rev2
    }
    put $prefix(complete-refs $seed)
  } else {
    complete-refs $seed
  }
}

fn complete-remotes {
  # TODO
}

fn complete-flags-or-refs [subcmd cur]{
  if (has-prefix $cur --) {
    complete-flags $subcmd
  } else {
    complete-refs $cur
  }
}

# Subcommand completers.

fn complete-add [@words]{
  if (has-prefix $cur --) {
    complete-flags checkout
  } else {
    @ls-files-opts = --others --modified --directory --no-empty-directory
    if (has-any $words[:-1] [-u --update]) {
      @ls-files-opts = --modified
    }
    complete-index-file $cur $ls-files-opts
  }
}

@whitespace-opts = --whitespace={nowarn warn error error-all fix}

fn complete-am [@words]{
  if (has-dir (repo-path)/rebase-apply ) {
    put --skip --continue --resolved --abort --quit --show-current-path
    return
  }

  if (has-prefix $cur --whitespace=) {
    put $@whitespace-opts
  } elif (has-prefix $cur --) {
    complete-flags am
  } else {
    edit:complete-filename $cur
  }
}

fn complete-apply [@words]{
  if (has-prefix $cur --whitespace=) {
    put $@whitespace-opts
  } elif (has-prefix $cur --) {
    complete-flags am
  } else {
    edit:complete-filename $cur
  }
}

fn complete-archive [@words]{
  if (has-prefix $cur --format=) {
    put --format=(git archive --list)
  } elif (has-prefix $cur --remote=) {
    put --remote=(complete-remotes)
  } elif (has-prefix $cur --) {
    # It's not clear why complete-flags is not used here.
    put --format= --list --verbose --prefix= --remote= --exec= --output
  } else {
    complete-revlist-file $cur
  }
}

@bisect-subcmds = start bad good skip reset visualize replay log run

fn complete-bisect [@words]{
  complete-filename-after-doubledash $words[:-1]
  subcmd = (find-any $words[:-1] $bisect-subcmds $false)
  if $subcmd {
    if (in $subcmd [bad good reset skip start]) {
      complete-refs $words[-1]
    } else {
      edit:complete-filename $words[-1]
    }
  } else {
    if (has-file (repo-path)/BISECT_START) {
      put $@bisect-subcmds
    } else {
      put replay start
    }
  }
}

fn complete-branch [@words]{
  opt = --set-upstream-to=
  if (has-prefix $cur $opt) {
    put $opt(complete-refs $cur[(len $opt):])
  } elif (has-prefix $cur --) {
    complete-flags branch
  } else {
    local  = (has-any $words[:-1] [-d --delete -m --move])
    remote = (has-any $words[:-1] [-r --remotes])
    if (and $local (not $remote)) {
      complete-heads
    } else {
      complete-refs $cur
    }
  }
}

fn complete-bundle [@words]{
  n = (len $words)
  if (eq $n 3) {
    put create list-heads verify unbundle
  } elif (eq $n 4) {
    edit:complete-filename $words[-1]
  } elif (> $n 4) {
    if (eq $words[2] create) {
      complete-revlist-file $words[-1]
    }
  }
}

fn complete-checkout [@words]{
  complete-filename-after-doubledash $words[:-1]
  if (has-prefix $cur --conflict=) {
    put --conflict={diff3 merge}
  } elif (has-prefix $cur --) {
    complete-flags checkout
  } else {
    track = (and $checkout-propose-remote-branch \
                 (not (has-any $words [--track --no-track --no-guess])))
    complete-refs $cur &track=$track
  }
}

fn complete-cherry [@words]{
  complete-flags-or-refs cherry $words[-1]
}

@cherry-pick-in-progress-options = --continue --quit --abort

fn complete-cherry-pick [@words]{
  if (has-file (repo-path)/CHERRY_PICK_HEAD) {
    put $@cherry-pick-in-progress-options
  }
  if (has-prefix $cur --) {
    complete-flags cherry-pick &exclude=$cherry-pick-in-progress-options
  } else {
    complete-refs $cur
  }
}

fn complete-clean [@words]{
  if (has-prefix $cur --) {
    complete-flags clean
  } else {
    complete-index-file $cur [--others --directory]
  }
}

fn complete-clone [@words]{
  if (has-prefix $cur --) {
    complete-flags clone
  } else {
    edit:complete-filename $cur
  }
}

fn complete-commit [@words]{
  if (in $words[-2] [-c -C]) {
    complete-refs $words[-1]
    return
  }
  ref-opt = (find-any-prefix $cur [--re{use,edit}-message= --fixup= --squash=])
  if $ref-opt {
    put $ref-opt(complete-refs $cur[(len $ref-opt):])
  } elif (has-prefix $cur --cleanup=) {
    put --cleanup={default,scissors,strip,verbatim,whitespace}
  } elif (has-prefix $cur --untracked-files=) {
    put --untracked-files={all,no,normal}
  } elif (has-prefix $cur --) {
    complete-flags commit
  } else {
    if ?(call-git rev-parse --verify --quite HEAD > /dev/null) {
      complete-index-file $cur [--committable]
    } else {
      # This is the first commit
      complete-index-file $cur [--cached]
    }
  }
}

fn complete-config [@words]{
  # TODO
}

fn complete-describe [@words]{
  complete-flags-or-refs describe $words[-1]
}

diff-common-options = [
  --stat --numstat --shortstat --summary --patch-with-stat --name-only
  --name-status --color --no-color --color-words --no-renames --check
  --full-index --binary --abbrev --diff-filter= --find-copies-harder
  --ignore-cr-at-eol --text --ignore-space-at-eol --ignore-space-change
  --ignore-all-space --ignore-blank-lines --exit-code --quiet --ext-diff
  --no-ext-diff --no-prefix --src-prefix= --dst-prefix= --inter-hunk-context=
  --patience --histogram --minimal --raw --word-diff --word-diff-regex=
  --dirstat --dirstat= --dirstat-by-file --dirstat-by-file= --cumulative
  --diff-algorithm= --submodule --submodule= --ignore-submodules]

fn complete-diff [@words]{
  # TODO
}

mergetools-common = [
  diffuse diffmerge ecmerge emerge kdiff3 meld opendiff tkdiff vimdiff
  gvimdiff xxdiff araxis p4merge bc codecompare]

fn complete-difftool [@words]{
  complete-filename-after-doubledash
  if (has-prefix $cur --tool=) {
    put --tool={$@mergetools-common,kompare}
  } elif (has-prefix $cur --) {
    complete-flags difftool &extra=[
      $@diff-common-options --base --cached --ours --theirs --pickaxe-all
      --pickaxe-regex --relative --staged]
  } else {
    complete-revlist-file
  }
}

subcmd-completer = [
  &add=         $complete-add~
  &am=          $complete-am~
  &apply=       $complete-apply~
  &archive=     $complete-archive~
  &bisect=      $complete-bisect~
  &branch=      $complete-branch~
  &bundle=      $complete-bundle~
  &checkout=    $complete-checkout~
  &cherry=      $complete-cherry~
  &cherry-pick= $complete-cherry-pick~
  &clean=       $complete-clean~
  &clone=       $complete-clone~
  &commit=      $complete-commit~
  &describe=    $complete-describe~
  &difftool=    $complete-difftool~
]

fn has-subcmd [subcmd]{ has-key $subcmd-completer $subcmd }

# The main completer.

fn complete-git [@words]{
  git-dir git-cd repo-path = '' '' ''
  command = ''
  cur = $words[-1]

  # Look at previous words to determine some environment.
  i = 1
  while (< $i (- (len $words) 1)) {
    word = $words[$i]
    if (has-prefix $word --git-dir=) {
      git-dir = $word[(len --git-dir=):]
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
