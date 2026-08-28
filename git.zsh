#### Git functions and aliases

# Print origin's default branch (e.g. main), offline when possible.
function _default_branch() {
  local default
  default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  # Some clones have no origin/HEAD; one network call sets it for good.
  [[ -z "$default" ]] && git remote set-head origin --auto >/dev/null 2>&1 \
    && default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  [[ -z "$default" ]] && return 1
  printf '%s\n' "${default#origin/}"
}

# Print the closest remote branch this one was built on, so stacked branches get
# their parent instead of the default branch. Falls back to the default branch.
function _pr_base() {
  local current push upstream default short count rank best
  current=$(git branch --show-current) || return
  [[ -z "$current" ]] && return 1

  # A branch can never be its own base, so drop whatever this one publishes to.
  # @{push} is unresolvable under push.default=simple when the local and remote
  # names differ, which is exactly when it matters, so consult both.
  push=$(git rev-parse --abbrev-ref '@{push}' 2>/dev/null)
  upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  default=$(_default_branch) || return
  [[ "$current" == "$default" ]] && return 1

  # Only true ancestors are considered: a diverged branch is just as likely to
  # be a child as a parent, and origin/<default> stops being an ancestor as soon
  # as anyone else pushes to it.
  # lstrip=2 rather than :short, which renders refs/remotes/origin/HEAD as "origin".
  best=$(
    git for-each-ref --format='%(refname:lstrip=2)' refs/remotes/origin/ \
      | while read -r short; do
          [[ "$short" == "origin/HEAD" || "$short" == "origin/$current" \
             || "$short" == "$push" || "$short" == "$upstream" ]] && continue
          git merge-base --is-ancestor "$short" HEAD 2>/dev/null || continue
          count=$(git rev-list --count "$short..HEAD" 2>/dev/null) || continue
          (( ${count:-0} > 0 )) || continue
          printf '%s\t%s\t%s\n' "$count" \
            "$([[ "$short" == "origin/$default" ]] && echo 0 || echo 1)" "${short#origin/}"
        done \
      | sort -t$'\t' -k1,1n -k2,2n -k3,3 | head -n1
  )
  [[ -z "$best" ]] && { printf '%s\n' "$default"; return 0; }
  IFS=$'\t' read -r count rank short <<< "$best"
  printf '%s\n' "$short"
}

# Checkout a branch, refresh it, and delete local branches gone on remote
function _sync_and_prune() {
  local branch=$1
  [[ -z "$branch" ]] && { echo "No branch to sync." >&2; return 1; }
  # "*" marks the current branch and "+" one checked out in another worktree;
  # neither is deletable, and passing either to git branch -D is an error.
  git checkout "$branch" && git pull && git fetch --prune \
    && git branch -vv | awk '$1 !~ /^[*+]$/ && /: gone]/ {print $1}' | xargs -r -n 1 git branch -D
}

# Run pre-commit if a config exists in the current dir or the repo root
function _run_precommit_if_configured() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -f .pre-commit-config.yaml ]; then
    pre-commit run -a
  elif [ -n "$repo_root" ] && [ -f "$repo_root/.pre-commit-config.yaml" ]; then
    (cd "$repo_root" && pre-commit run -a)
  fi
}

# Add all files, commit with message
function ac() {
  _run_precommit_if_configured
  git add .
  git commit -m $1
}

# Add all files, commit with message, push
function acp() {
  _run_precommit_if_configured
  git add .
  git commit -m $1 && git push
}

# Commit with message, push
function gcp() {
  _run_precommit_if_configured
  git commit -m $1 && git push
}

# Add all files, commit with message, force push
function acpf() {
  _run_precommit_if_configured
  git add .
  git commit -m $1 && git push --force-with-lease --force-if-includes
}

# Add all files, commit with message, push a new branch
function acpn() {
  _run_precommit_if_configured
  git add .
  git commit -m $1 && git push --set-upstream origin $(git branch --show-current)
}

# Amend but don't change the commit message, force push with lease
function amend() {
  _run_precommit_if_configured
  git add .
  git commit --no-edit --amend && git push --force-with-lease --force-if-includes
}

# Amend but change the commit message, force push with lease
function amendm() {
  _run_precommit_if_configured
  git add .
  git commit --no-edit --amend -m "$1" && git push --force-with-lease --force-if-includes
}


#### Git aliases

# Push
alias gp="git push"
# Push force with lease
alias gpf="git push --force-with-lease --force-if-includes"
# Push force
alias gpf!="git push --force"
# Pull
alias gl="git pull"
# Status
alias gs="git status"
# Add
alias ga="git add"
# Commit
alias gc="git commit"
# Checkout
alias gcb="git checkout -b"
# Switch
alias gsw="git switch"
# Stash
alias gsta="git stash"
# Pop
alias gstp="git stash pop"
# Push a new branch to remote
alias new="git push --set-upstream origin \$(git branch --show-current)"
# Squash all commits since the branch's base into one; pass a base to override it
function squash() {
  local current default base base_ref candidate fork= resolved=0
  local -a base_refs
  (( $# <= 1 )) || { echo "Usage: squash [base]" >&2; return 1; }

  current=$(git branch --show-current) || return
  [[ -z "$current" ]] && { echo "Detached HEAD; check out a branch first." >&2; return 1; }
  # Empty when origin/HEAD is unavailable, which only blocks inferring a base.
  default=$(_default_branch)
  [[ -n "$default" && "$current" == "$default" ]] \
    && { echo "Refusing to squash the default branch '$default'." >&2; return 1; }

  if [[ -n "${1:-}" ]]; then
    base=$1
  else
    [[ -n "$default" ]] \
      || { echo "Could not determine the default branch; run 'squash <base>'." >&2; return 1; }
    base=$(_pr_base) \
      || { echo "Could not determine a base branch; run 'squash <base>'." >&2; return 1; }
  fi

  if [[ "$base" == origin/* ]]; then
    base_refs=("$base")
  else
    base_refs=("$base" "origin/$base")
  fi

  # A local branch and its remote counterpart can disagree. Take whichever
  # forked from HEAD most recently: a stale local copy would squash commits that
  # belong to the base, and one that is ahead would swallow its unpushed work.
  for base_ref in $base_refs; do
    git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null || continue
    resolved=1
    candidate=$(git merge-base "$base_ref" HEAD 2>/dev/null) || continue
    if [[ -z "$fork" ]] || git merge-base --is-ancestor "$fork" "$candidate" 2>/dev/null; then
      fork=$candidate
    fi
  done
  (( resolved )) || { echo "Unknown base branch '$base'." >&2; return 1; }
  [[ -n "$fork" ]] \
    || { echo "Base '$base' has no common ancestor with HEAD." >&2; return 1; }
  git reset --soft "$fork"
}
# Undo the last commit
alias undo="git reset HEAD~"
# Switch to the default branch, refresh it, and delete branches gone on remote
function cleanup() {
  _sync_and_prune "$(_default_branch)"
}
