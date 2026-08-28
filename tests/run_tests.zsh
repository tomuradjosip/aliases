#!/usr/bin/env zsh
#
# Test suite for the git, github and help aliases.
#
#   ./tests/run_tests.zsh            run everything
#   KEEP_TMP=1 ./tests/run_tests.zsh keep the scratch repos for inspection
#
# Everything runs against throwaway git repositories under TMPDIR and a fake
# HOME, so the suite touches nothing outside its own scratch directory and does
# not depend on the machine it runs on. gh is stubbed; no network is used.
# Needs zsh and git 2.32 or newer.

emulate -R zsh

ALIASES=${ALIASES:-${0:A:h:h}}
for f in git.zsh github.zsh help.zsh; do
  [[ -f $ALIASES/$f ]] || { print -u2 -r -- "Cannot find $f in $ALIASES"; exit 2; }
done
source $ALIASES/git.zsh
source $ALIASES/github.zsh

# Keep git away from the user's identity, config and any inherited repository.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE ALIASES_DIR

TMPROOT=$(mktemp -d "${${TMPDIR:-/tmp}%/}/aliases-tests.XXXXXX") || exit 2
_teardown() {
  cd $ALIASES
  if [[ -n ${KEEP_TMP:-} ]]; then
    print -r -- "scratch kept at $TMPROOT"
  else
    rm -rf $TMPROOT
  fi
}
trap _teardown EXIT

PASS=0 FAIL=0
typeset -a FAILURES=()

section() { print -r -- ""; print -r -- "── $1"; }
pass() { print -r -- "  ok    $1"; (( PASS++ )) }
fail() {
  print -r -- "  FAIL  $1"
  (( $# > 1 )) && print -r -- "          want: [$2]"
  (( $# > 2 )) && print -r -- "          got:  [$3]"
  (( FAIL++ ))
  FAILURES+=("$1")
}
eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
match() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "substring: $2" "$3"; fi
}
nomatch() {
  if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "no substring: $2" "$3"; fi
}

# ------------------------------------------------------------------- fixtures

# Commit a unique line so no two commits share a hash.
c() { echo "$1-$RANDOM" >> f.txt; git add -A; git commit -q -m "$1" }

# A bare "remote", a working clone, and a second clone to act as a teammate.
newrepo() {
  local d
  d=$(mktemp -d $TMPROOT/repo.XXXXXX)
  git init --bare -q --initial-branch=main $d/remote
  git init -q --initial-branch=main $d/work
  git clone -q $d/remote $d/peer 2>/dev/null
  cd $d/work
  git remote add origin $d/remote
  c c1
  c c2
  git push -q -u origin main
  git remote set-head origin --auto >/dev/null 2>&1
  REPO=$d
}

# A teammate pushes to main, so origin/main stops being an ancestor of HEAD.
advance_main() {
  ( cd $REPO/peer && git fetch -q origin && git checkout -q main 2>/dev/null \
      && git reset -q --hard origin/main && echo "teammate-$RANDOM" >> g.txt \
      && git add -A && git commit -q -m teammate && git push -q origin main )
  git fetch -q origin
}

prbase() { local o; o=$(_pr_base); print -r -- "$o|$?" }

# gh stub. Records every call, answers the up-front `pr view` for the current
# branch, reports a pull request state by number, and emulates gh deleting the
# local branch on a real merge. GH_PR_STATE is the ground truth merge() consults;
# GH_MERGE_DELETES=0 models gh leaving the local branch alone, which it does when
# the branch is named differently from the pull request's head. The stub
# deliberately lands on the default branch rather than the pull request's base,
# so the tests can tell whether merge() moved us or the stub did.
GHLOG=$TMPROOT/gh.log
GH_VIEW_BASE= GH_PR_NUMBER=42 GH_PR_STATE=MERGED GH_MERGE_RC=0 GH_MERGE_DELETES=1
gh() {
  print -r -- "$*" >> $GHLOG
  if [[ "$1" == pr && "$2" == view ]]; then
    if [[ "$3" == --json ]]; then
      [[ -n "$GH_VIEW_BASE" ]] || return 1
      printf '%s\t%s\n' "$GH_PR_NUMBER" "$GH_VIEW_BASE"
      return 0
    fi
    print -r -- "$GH_PR_STATE"
    return 0
  fi
  if [[ "$1" == pr && "$2" == merge ]]; then
    (( GH_MERGE_RC )) && return $GH_MERGE_RC
    if (( GH_MERGE_DELETES )); then
      local b=$(git branch --show-current)
      [[ -n "$b" && "$b" != main ]] && { git checkout -q main; git branch -q -D "$b" }
    fi
    return 0
  fi
  return 0
}
VIEWCALL="pr view --json number,baseRefName -q [.number, .baseRefName] | @tsv;"
STATECALL="pr view 42 --json state -q .state;"
ghreset() { : > $GHLOG }
ghargs() { tr '\n' ';' < $GHLOG }

# A repository with no origin at all, reused by the "cannot resolve" cases.
NOREMOTE=$TMPROOT/noremote
git init -q --initial-branch=main $NOREMOTE
( cd $NOREMOTE && c x1 )

############################################################## _default_branch
section "_default_branch"
newrepo
eq "reports origin's default branch" "main" "$(_default_branch)"

git remote set-head origin --delete >/dev/null 2>&1
eq "recovers when origin/HEAD is missing" "main" "$(_default_branch)"

cd $NOREMOTE
o=$(_default_branch); rc=$?
eq "fails cleanly with no origin remote" "|1" "$o|$rc"

##################################################################### _pr_base
section "_pr_base"
newrepo
git checkout -q -b feature main; c f1; c f2
eq "plain feature branch -> default branch" "main|0" "$(prbase)"

advance_main
eq "default branch advanced upstream -> still default" "main|0" "$(prbase)"

newrepo
git checkout -q -b stack1 main; c s1; git push -q -u origin stack1
git checkout -q -b stack2 stack1; c s2; git push -q -u origin stack2
eq "stacked branch -> parent branch" "stack1|0" "$(prbase)"

advance_main
eq "stacked branch, default advanced -> parent branch" "stack1|0" "$(prbase)"

git checkout -q stack1; c s1b
eq "parent branch with newer local commit -> default" "main|0" "$(prbase)"

newrepo
git checkout -q -b feature main; c f1; git push -q -u origin feature
git checkout -q -b local-name origin/feature
git branch -q --set-upstream-to=origin/feature local-name >/dev/null 2>&1
c extra
eq "local name != upstream name -> default, not own remote" "main|0" "$(prbase)"
git config push.default upstream
eq "same, with push.default=upstream" "main|0" "$(prbase)"
git config --unset push.default

newrepo
git checkout -q -b other-feature main; c o1; c o2; git push -q -u origin other-feature
git checkout -q -b feature main; c f1
eq "unrelated teammate branch is ignored" "main|0" "$(prbase)"

newrepo
git checkout -q -b dup main; git push -q -u origin dup
git checkout -q -b feature main; c f1
eq "remote branch identical to default -> default wins" "main|0" "$(prbase)"

newrepo
eq "on the default branch -> refuses" "|1" "$(prbase)"

newrepo
git checkout -q -b nothing-yet main
eq "branch with no commits of its own -> default" "main|0" "$(prbase)"

newrepo
git checkout -q --detach >/dev/null 2>&1
eq "detached HEAD -> refuses" "|1" "$(prbase)"

cd $NOREMOTE
eq "no origin remote -> refuses" "|1" "$(prbase)"

####################################################################### squash
section "squash"
newrepo
git checkout -q -b feature main; c f1; c f2
before_tree=$(git rev-parse HEAD^{tree})
squash >/dev/null 2>&1
eq "resets to the fork point" "$(git rev-parse main)" "$(git rev-parse HEAD)"
eq "leaves the work staged" "f.txt" "$(git diff --cached --name-only)"
eq "keeps every change in the index" "$before_tree" "$(git write-tree)"

newrepo
git checkout -q -b stack1 main; c s1; git push -q -u origin stack1
git checkout -q -b stack2 stack1; c s2; c s3
squash >/dev/null 2>&1
eq "squashes down to the stacked parent, not the default" \
  "$(git rev-parse stack1)" "$(git rev-parse HEAD)"

newrepo
git checkout -q -b feature main; c f1; c f2
squash main >/dev/null 2>&1
eq "accepts an explicit base name" "$(git rev-parse main)" "$(git rev-parse HEAD)"

newrepo
git checkout -q -b feature main; c f1
squash origin/main >/dev/null 2>&1
eq "accepts an explicit origin/-prefixed base" "$(git rev-parse main)" "$(git rev-parse HEAD)"

newrepo
git checkout -q -b localbase main; c lb1
git checkout -q -b feature localbase; c f1
squash localbase >/dev/null 2>&1
eq "accepts a local-only base branch" "$(git rev-parse localbase)" "$(git rev-parse HEAD)"

newrepo
git checkout -q -b parent main; c p1; git push -q -u origin parent
c p2                                   # p2 is local only, so origin/parent lags
git checkout -q -b child parent; c ch1
squash parent >/dev/null 2>&1
eq "explicit base ahead of its remote keeps the remote's extra commits" \
  "$(git rev-parse parent)" "$(git rev-parse HEAD)"
eq "  and does not absorb the base's unpushed commits" "0" "$(git rev-list --count HEAD..parent)"

newrepo
git checkout -q -b feature main; c f1; c f2; git push -q -u origin feature
git checkout -q main; git reset -q --hard HEAD~1   # local main is now stale
git checkout -q feature
squash main >/dev/null 2>&1
eq "explicit base behind its remote uses the remote fork point" \
  "$(git rev-parse origin/main)" "$(git rev-parse HEAD)"

newrepo
git checkout -q -b feature main; c f1
out=$(squash nope-not-a-branch 2>&1); rc=$?
match "rejects an unknown base" "Unknown base branch 'nope-not-a-branch'" "$out"
eq "  and exits nonzero" "1" "$rc"
eq "  and leaves HEAD alone" "$(git rev-parse feature)" "$(git rev-parse HEAD)"

out=$(squash a b 2>&1); rc=$?
match "rejects extra arguments" "Usage: squash [base]" "$out"
eq "  and exits nonzero" "1" "$rc"

git checkout -q main
out=$(squash 2>&1); rc=$?
match "refuses on the default branch" "Refusing to squash the default branch 'main'" "$out"
eq "  and exits nonzero" "1" "$rc"

git checkout -q -b feature2 main; c g1
git checkout -q --detach >/dev/null 2>&1
out=$(squash 2>&1); rc=$?
match "refuses on detached HEAD" "Detached HEAD" "$out"
eq "  and exits nonzero" "1" "$rc"

cd $NOREMOTE
git checkout -q -b nrparent 2>/dev/null; c np1
git checkout -q -b nrchild 2>/dev/null; c nc1
out=$(squash 2>&1); rc=$?
match "reports a missing default branch when inferring" "Could not determine the default branch" "$out"
eq "  and exits nonzero" "1" "$rc"
eq "  and leaves HEAD alone" "$(git rev-parse nrchild)" "$(git rev-parse HEAD)"

squash nrparent >/dev/null 2>&1
eq "an explicit base works without a resolvable default branch" \
  "$(git rev-parse nrparent)" "$(git rev-parse HEAD)"

##################################################### _sync_and_prune, cleanup
section "_sync_and_prune / cleanup"
newrepo
git checkout -q -b gone1 main; c x1; git push -q -u origin gone1
git checkout -q -b gone2 main; c x2; git push -q -u origin gone2
git checkout -q -b keep main; c x3; git push -q -u origin keep
git checkout -q main
git push -q origin --delete gone1 gone2
cleanup >/dev/null 2>&1
eq "deletes branches whose upstream is gone" "" "$(git branch --list gone1 gone2)"
match "keeps branches that still exist" "keep" "$(git branch --list keep)"
eq "ends on the default branch" "main" "$(git branch --show-current)"

newrepo
git checkout -q -b wt main; c w1; git push -q -u origin wt
git checkout -q -b alsogone main; c a1; git push -q -u origin alsogone
git checkout -q main
git worktree add -q $REPO/wtdir wt
git push -q origin --delete wt alsogone
out=$(cleanup 2>&1); rc=$?
eq "prunes normally alongside a worktree branch" "" "$(git branch --list alsogone)"
match "leaves the worktree branch in place" "wt" "$(git branch --list wt)"
nomatch "does not try to delete the worktree marker" "branch '+' not found" "$out"
eq "cleanup succeeds" "0" "$rc"

newrepo
git checkout -q -b feature main; c f1
out=$(_sync_and_prune "" 2>&1); rc=$?
match "rejects an empty branch argument" "No branch to sync." "$out"
eq "  and exits nonzero" "1" "$rc"
eq "  and stays put" "feature" "$(git branch --show-current)"

git push -q -u origin feature
git checkout -q -b tracked main
_sync_and_prune feature >/dev/null 2>&1
eq "checks out the requested branch" "feature" "$(git branch --show-current)"

newrepo
git checkout -q -b remote-only main; c r1; git push -q -u origin remote-only
git checkout -q main; git branch -q -D remote-only
_sync_and_prune remote-only >/dev/null 2>&1
eq "creates a local branch from origin when needed" "remote-only" "$(git branch --show-current)"

cd $NOREMOTE
out=$(cleanup 2>&1); rc=$?
match "cleanup reports no branch without an origin" "No branch to sync." "$out"
eq "  and exits nonzero" "1" "$rc"

######################################################################### pull
section "pull"
newrepo
git checkout -q -b feature main; c f1
ghreset; pull >/dev/null 2>&1
eq "passes the detected base to gh" "pr create --fill --base main;" "$(ghargs)"

ghreset; out=$(pull 2>&1)
match "announces the base" "Creating PR into main" "$out"

ghreset; pull --draft >/dev/null 2>&1
eq "forwards extra flags" "pr create --fill --base main --draft;" "$(ghargs)"

ghreset; pull --base develop >/dev/null 2>&1
eq "respects an explicit --base" "pr create --fill --base develop;" "$(ghargs)"

ghreset; pull --base=develop >/dev/null 2>&1
eq "respects --base=value" "pr create --fill --base=develop;" "$(ghargs)"

ghreset; pull -B develop >/dev/null 2>&1
eq "respects -B value" "pr create --fill -B develop;" "$(ghargs)"

ghreset; pull -Bdevelop >/dev/null 2>&1
eq "respects -Bvalue" "pr create --fill -Bdevelop;" "$(ghargs)"

cd $NOREMOTE
git checkout -q -b nrfeature 2>/dev/null
ghreset; out=$(pull --base main 2>&1); rc=$?
eq "an explicit base works without a resolvable default branch" \
  "pr create --fill --base main;" "$(ghargs)"
eq "  and exits zero" "0" "$rc"
nomatch "  and says nothing about the default branch" "default branch" "$out"

newrepo
git checkout -q -b stack1 main; c s1; git push -q -u origin stack1
git checkout -q -b stack2 stack1; c s2
ghreset; pull >/dev/null 2>&1
eq "targets the stacked parent" "pr create --fill --base stack1;" "$(ghargs)"

newrepo
ghreset; out=$(pull 2>&1); rc=$?
match "refuses on the default branch" \
  "Refusing to create a pull request from the default branch 'main'" "$out"
eq "  and calls gh not at all" "" "$(ghargs)"
eq "  and exits nonzero" "1" "$rc"

git checkout -q -b feature main; c f1
git checkout -q --detach >/dev/null 2>&1
ghreset; out=$(pull 2>&1); rc=$?
match "refuses on detached HEAD" "Detached HEAD" "$out"
eq "  and calls gh not at all" "" "$(ghargs)"

newrepo
git checkout -q -b feature main; c f1
git remote set-url origin $TMPROOT/definitely-not-here
ghreset; out=$(pull 2>&1)
match "warns when origin is unreachable" "Could not reach origin" "$out"
eq "  and still proposes a base" "pr create --fill --base main;" "$(ghargs)"

######################################################################## merge
section "merge"
newrepo
git checkout -q -b feature main; c f1; git push -q -u origin feature
GH_VIEW_BASE=main; GH_PR_STATE=MERGED; GH_MERGE_DELETES=1; ghreset
merge >/dev/null 2>&1
eq "identifies the PR, merges, then confirms it landed" \
  "${VIEWCALL}pr merge --delete-branch --merge;${STATECALL}" "$(ghargs)"
eq "returns to the base branch" "main" "$(git branch --show-current)"

stackrepo() {
  newrepo
  git checkout -q -b stack1 main; c s1; git push -q -u origin stack1
  git checkout -q -b stack2 stack1; c s2; git push -q -u origin stack2
  GH_VIEW_BASE=stack1; GH_PR_STATE=MERGED; GH_MERGE_DELETES=1; ghreset
}

stackrepo; merge >/dev/null 2>&1
eq "returns to the PR's own base, not the default" "stack1" "$(git branch --show-current)"

stackrepo; merge --squash >/dev/null 2>&1
eq "a flag-only merge still returns to the stacked base" "stack1" "$(git branch --show-current)"

stackrepo; merge --squash --subject "message" >/dev/null 2>&1
eq "a flag value is not mistaken for a PR selector" "stack1" "$(git branch --show-current)"

stackrepo; merge -t "some title" -b "some body" >/dev/null 2>&1
eq "quoted flag values do not disturb the base" "stack1" "$(git branch --show-current)"

# gh leaves the local branch alone when it is named differently from the pull
# request's head, so branch survival cannot stand in for "did not merge".
stackrepo; GH_MERGE_DELETES=0; merge >/dev/null 2>&1
eq "a merged PR whose local branch survives still refreshes the base" \
  "stack1" "$(git branch --show-current)"
GH_MERGE_DELETES=1

newrepo
git checkout -q -b feature main; c f1; git push -q -u origin feature
# No pull request means gh merges nothing, so it deletes nothing either.
GH_VIEW_BASE=; GH_PR_STATE=MERGED; GH_MERGE_DELETES=0; ghreset
merge >/dev/null 2>&1
eq "no pull request for the branch means no state check" \
  "${VIEWCALL}pr merge --delete-branch --merge;" "$(ghargs)"
eq "  and no branch switch" "feature" "$(git branch --show-current)"
GH_MERGE_DELETES=1

# GH_PR_STATE=OPEN models a pull request that has not merged: pending
# auto-merge, blocked, or simply not the one the arguments pointed at.
newrepo
git checkout -q -b feature main; c f1; git push -q -u origin feature
GH_VIEW_BASE=main; GH_PR_STATE=OPEN; GH_MERGE_DELETES=0; ghreset
merge --squash >/dev/null 2>&1
eq "does not add --merge when --squash is given" \
  "${VIEWCALL}pr merge --delete-branch --squash;${STATECALL}" "$(ghargs)"

ghreset; merge -s >/dev/null 2>&1
eq "does not add --merge when -s is given" \
  "${VIEWCALL}pr merge --delete-branch -s;${STATECALL}" "$(ghargs)"

ghreset; merge --rebase >/dev/null 2>&1
eq "does not add --merge when --rebase is given" \
  "${VIEWCALL}pr merge --delete-branch --rebase;${STATECALL}" "$(ghargs)"

ghreset; merge --admin >/dev/null 2>&1
eq "still adds --merge alongside other flags" \
  "${VIEWCALL}pr merge --delete-branch --merge --admin;${STATECALL}" "$(ghargs)"

ghreset; merge 123 >/dev/null 2>&1
eq "forwards a PR selector unchanged" \
  "${VIEWCALL}pr merge --delete-branch --merge 123;${STATECALL}" "$(ghargs)"

eq "an unmerged PR leaves you in place" "feature" "$(git branch --show-current)"

ghreset; merge --auto --squash >/dev/null 2>&1
eq "a pending auto-merge leaves you in place" "feature" "$(git branch --show-current)"

newrepo
git checkout -q -b feature main; c f1; git push -q -u origin feature
GH_VIEW_BASE=main; GH_PR_STATE=MERGED; GH_MERGE_DELETES=1; ghreset
merge --auto --squash >/dev/null 2>&1
eq "an --auto merge that lands refreshes the base" "main" "$(git branch --show-current)"
eq "  and the branch is gone" "" "$(git branch --list feature)"

newrepo
git checkout -q -b feature main; c f1; git push -q -u origin feature
GH_VIEW_BASE=main; GH_MERGE_RC=1; ghreset
out=$(merge 2>&1); rc=$?
eq "a failed merge exits nonzero" "1" "$rc"
eq "a failed merge does not check state" \
  "${VIEWCALL}pr merge --delete-branch --merge;" "$(ghargs)"
eq "a failed merge does not switch branches" "feature" "$(git branch --show-current)"
GH_MERGE_RC=0

######################################################################### help
section "help"
unset -f gh

# help reads the source lines out of ~/.zshrc, so give it a HOME of its own
# rather than depending on how this machine happens to be set up.
FAKEHOME=$TMPROOT/home
mkdir -p $FAKEHOME/.config
ln -s $ALIASES $FAKEHOME/.config/aliases
for f in $ALIASES/*.zsh; do
  print -r -- "source ~/.config/aliases/${f:t}"
done > $FAKEHOME/.zshrc

helpout=$(HOME=$FAKEHOME zsh -c "source $ALIASES/help.zsh; help" 2>&1 \
  | sed $'s/\033\\[[0-9;]*m//g')
listed() { print -r -- "$helpout" | awk -v n="$1" '$1==n {f=1} END {exit !f}' }

for fn in squash cleanup pull merge ac acp acpf acpn amend amendm gcp new undo brpr browse; do
  if listed $fn; then pass "lists $fn"; else fail "lists $fn"; fi
done
for fn in _pr_base _default_branch _sync_and_prune _run_precommit_if_configured; do
  if ! listed $fn && [[ "$helpout" != *"$fn"* ]]; then
    pass "hides $fn"
  else
    fail "hides $fn"
  fi
done
match "spells GitHub correctly" "GitHub" "$helpout"
nomatch "no comment leaks into the next entry" "Print origin's default branch" "$helpout"

###################################################################### summary
print -r -- ""
print -r -- "═══════════════════════════════════════"
print -r -- "  passed: $PASS    failed: $FAIL"
if (( FAIL )); then
  print -r -- ""
  print -r -- "  failing tests:"
  for f in $FAILURES; do print -r -- "    - $f"; done
fi
print -r -- "═══════════════════════════════════════"

(( FAIL == 0 )) || exit 1
exit 0
