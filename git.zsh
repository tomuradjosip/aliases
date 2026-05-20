#### Git functions and aliases

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
# Squash all commits on the current branch into one
alias squash="git reset --soft \$(git merge-base  \$(git remote show origin | grep \"HEAD branch\" | awk \"{print \\\$3}\") HEAD)"
# Undo the last commit
alias undo="git reset HEAD~"
# Cleanup branches that are already merged or gone on remote
alias cleanup="git checkout \$(git remote show origin | grep \"HEAD branch\" | awk \"{print \\\$3}\") && git pull && git fetch --prune && git branch -vv | awk \"/: gone]/{print \\\$1}\" | xargs -r -n 1 git branch -D"
