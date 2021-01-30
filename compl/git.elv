# Git completion, ported from the official bash completion script
# https://github.com/git/git/blob/master/contrib/completion/git-completion.bash.
#
# License is the same as the bash script, i.e. GPLv2.
#
# Use with:
#   use github.com/xiaq/edit.elv/compl/git
#   git:apply

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
    if (str:has-prefix $s $p) {
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
    } elif (str:has-prefix $word !) {
      # Shell command alias, skip
    } elif (str:has-prefix $word -) {
      # Option, skip
    } elif (has-value $word '=') {
      # Environment, skip
    } elif (eq $word git) {
      # Git itself, skip
    } elif (eq $word '()') {
      # Function definition, skip
    } elif (eq $word :) {
      # Nop, skip
    } elif (str:has-prefix $word "'") {
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

# The do-* functions are not declared with fn: the "return" within will exit
# the calling fn.

do-filename-after-doubledash~ = [words]{
  if (has-value $words --) {
    edit:complete-filename $words[-1]
    return
  }
}

do-opt-cb~ = [opt cb]{
  if (str:has-prefix $cur $opt) {
    put $opt($cb $cur[(len $opt):])
    return
  }
}

do-opt~ = [opt @values]{
  if (str:has-prefix $cur $opt) {
    put $opt$@values
    return
  }
}

# Internal completers.

fn complete-subcmd {
  # This commands outputs each command in its own line, so the output is
  # directly usable in completers.
  git --list-cmds=list-mainporcelain,others,nohelpers,alias,list-complete,config
}

fn complete-flag [subcmd &extra=[] &exclude=[]]{
  {
    call-git $subcmd --git-completion-helper | str:trim-space (all) | splits ' ' (all)
    all $extra
  } | without -- $@exclude
}

do-flag~ = [subcmd &extra=[] &exclude=[]]{
  if (str:has-prefix $cur --) {
    complete-flag $subcmd &extra=$extra &exclude=$exclude
    return
  }
}

@HEADs = HEAD FETCH_HEAD ORIG_HEAD MERGE_HEAD REBASE_HEAD

# TODO(xiaq): Deduplicate. The most common scenerio is that HEAD can appear
# twice, once from the expansion of HEADs, once from refs/remotes/origin/HEAD.
fn complete-ref-inner [seed &track=$false]{
  format = ''
  if (or (eq $seed refs) (str:has-prefix $seed refs/)) {
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
fn complete-ref [seed &track=$false]{
  if (str:has-prefix $seed '^') {
    put '^'(complete-ref-inner &track=$track)
  } else {
    complete-ref-inner $seed &track=$track
  }
}

fn complete-head {
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
    put $prefix(complete-ref $seed)
  } else {
    complete-ref $seed
  }
}

fn complete-remote {
  # TODO
}

fn complete-remote-or-refspec {
  # TODO
}

# Subcommand completers.

fn complete-add [@words]{
  do-flag add
  @ls-files-opts = --others --modified --directory --no-empty-directory
  if (has-any $words[:-1] [-u --update]) {
    @ls-files-opts = --modified
  }
  complete-index-file $cur $ls-files-opts
}

@whitespace-opts = nowarn warn error error-all fix

do-whitespace-opt~ = { do-opt --whitespace= $@whitespace-opts }

fn complete-am [@words]{
  if (has-dir (repo-path)/rebase-apply ) {
    put --skip --continue --resolved --abort --quit --show-current-path
    return
  }

  do-whitespace-opt
  do-flag am
  edit:complete-filename $cur
}

fn complete-apply [@words]{
  do-whitespace-opt
  do-flag apply
  edit:complete-filename $cur
}

fn complete-archive [@words]{
  do-opt-cb --format= [_]{ git archive --list }
  do-opt-cb --remote= [_]{ complete-remote }

  if (str:has-prefix $cur --) {
    # It's not clear why complete-flag is not used here.
    put --format= --list --verbose --prefix= --remote= --exec= --output
  } else {
    complete-revlist-file $cur
  }
}

@bisect-subcmds = start bad good skip reset visualize replay log run

fn complete-bisect [@words]{
  do-filename-after-doubledash $words[:-1]
  subcmd = (find-any $words[:-1] $bisect-subcmds $false)
  if $subcmd {
    if (in $subcmd [bad good reset skip start]) {
      complete-ref $words[-1]
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
  do-opt-cb --set-upstream-to= [seed]{ complete-ref $seed }
  do-flag branch

  local  = (has-any $words[:-1] [-d --delete -m --move])
  remote = (has-any $words[:-1] [-r --remotes])
  if (and $local (not $remote)) {
    complete-head
  } else {
    complete-ref $cur
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
  do-filename-after-doubledash $words[:-1]
  do-opt --conflict= diff3 merge
  do-flag checkout
  track = (and $checkout-propose-remote-branch \
               (not (has-any $words [--track --no-track --no-guess])))
  complete-ref $cur &track=$track
}

fn complete-cherry [@words]{
  do-flag cherry
  complete-ref $cur
}

@cherry-pick-in-progress-options = --continue --quit --abort

fn complete-cherry-pick [@words]{
  if (has-file (repo-path)/CHERRY_PICK_HEAD) {
    put $@cherry-pick-in-progress-options
  }
  do-flag cherry-pick &exclude=$cherry-pick-in-progress-options
  complete-ref $cur
}

fn complete-clean [@words]{
  do-flag clean
  complete-index-file $cur [--others --directory]
}

fn complete-clone [@words]{
  do-flag clone
  edit:complete-filename $cur
}

fn complete-commit [@words]{
  if (in $words[-2] [-c -C]) {
    complete-ref $words[-1]
    return
  }
  ref-opt = (find-any-prefix $cur [--re{use,edit}-message= --fixup= --squash=])
  if $ref-opt {
    put $ref-opt(complete-ref $cur[(len $ref-opt):])
    return
  }
  do-opt --cleanup= default scissors strip verbatim whitespace
  do-opt --untracked-files= all no normal
  do-flag commit

  if ?(call-git rev-parse --verify --quite HEAD > /dev/null) {
    complete-committable-file $cur
  } else {
    # This is the first commit
    complete-index-file $cur [--cached]
  }
}

fn complete-config [@words]{
  # TODO
}

fn complete-describe [@words]{
  do-flag describe
  complete-ref $cur
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

mergetools-common = [
  diffuse diffmerge ecmerge emerge kdiff3 meld opendiff tkdiff vimdiff
  gvimdiff xxdiff araxis p4merge bc codecompare]

fn complete-diff [@words]{
  # TODO
}

fn complete-difftool [@words]{
  do-filename-after-doubledash $words[:-1]
  do-opt --tool= $@mergetools-common kompare
  do-flag difftool &extra=[
    $@diff-common-options --base --cached --ours --theirs --pickaxe-all
    --pickaxe-regex --relative --staged]
  complete-revlist-file $cur
}

fn complete-fetch [@words]{
  do-opt --recurse-submodules yes on-demand no
  do-flag fetch
  complete-remote-or-refspec # TODO
}

fn complete-format-patch [@words]{
  do-opt --thread deep shallow
  do-flag format-patch # The bash completer uses a hardcoded list
  complete-revlist-file
}

fn complete-fsck [@words]{
  do-flag fsck
  edit:complete-filename $words[-1]
}

fn complete-grep [@words]{
  do-filename-after-doubledash $words[:-1]
  do-flag grep
  if (or (eq 3 (len $words)) (str:has-prefix $words[-2] -)) {
    # complete-symbol # TODO
  }
  complete-ref $words[-1]
}

fn complete-help [@words]{
  do-flag help
  git --list-cmds=main,nohelpers,alias,list-guide
  put gitk
}

fn complete-init [@words]{
  do-opt --shared= false true umask group all world everybody
  do-flag init
  edit:complete-filename $words[-1]
}

fn complete-ls-files [@words]{
  do-flag ls-files
  complete-index-file $words[-1] [--cached]
}

subcmd-completer = [
  &add=          $complete-add~
  &am=           $complete-am~
  &apply=        $complete-apply~
  &archive=      $complete-archive~
  &bisect=       $complete-bisect~
  &branch=       $complete-branch~
  &bundle=       $complete-bundle~
  &checkout=     $complete-checkout~
  &cherry=       $complete-cherry~
  &cherry-pick=  $complete-cherry-pick~
  &clean=        $complete-clean~
  &clone=        $complete-clone~
  &commit=       $complete-commit~
  &describe=     $complete-describe~
  &diff=         $complete-diff~
  &difftool=     $complete-difftool~
  &fetch=        $complete-fetch~
  &format-patch= $complete-format-patch~
  &fsck=         $complete-fsck~
  &grep=         $complete-grep~
  &help=         $complete-help~
  &init=         $complete-init~
  &ls-files=     $complete-ls-files~
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
    if (str:has-prefix $word --git-dir=) {
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
    } elif (str:has-prefix $word -) {
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
    if (str:has-prefix $cur --) {
      all [--paginate --no-pager --git-dir= --bare --version
               --exec-path --exec-path= --html-path --man-path --info-path
               --work-tree= --namespace= --no-replace-objects --help]
    } else {
      complete-subcmd
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
