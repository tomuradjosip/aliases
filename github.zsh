#### GitHub CLI aliases

# Create pull request
function pull() {
  local current default base arg explicit_base=0
  current=$(git branch --show-current) || return
  [[ -z "$current" ]] && { echo "Detached HEAD; check out a branch first." >&2; return 1; }

  # An explicit base needs no inference, so hand it straight to gh rather than
  # risk failing on a default branch we never use.
  for arg in "$@"; do
    [[ "$arg" == -B || "$arg" == -B?* || "$arg" == --base || "$arg" == --base=* ]] \
      && explicit_base=1
  done
  (( explicit_base )) && { gh pr create --fill "$@"; return; }

  git fetch --quiet --prune origin 2>/dev/null \
    || echo "Could not reach origin; picking a base from cached refs." >&2

  default=$(_default_branch) \
    || { echo "Could not determine the default branch." >&2; return 1; }
  [[ "$current" == "$default" ]] \
    && { echo "Refusing to create a pull request from the default branch '$default'." >&2; return 1; }

  base=$(_pr_base) \
    || { echo "Could not determine a base branch; pass '--base <branch>'." >&2; return 1; }

  echo "Creating PR into ${base}…"
  gh pr create --fill --base "$base" "$@"
}
# View pull request
alias brpr="gh pr view --web"
# Merge pull request, then return to and refresh its base branch
function merge() {
  local arg info number base state strategy=0
  for arg in "$@"; do
    case "$arg" in
      -m|--merge|-r|--rebase|-s|--squash) strategy=1 ;;
    esac
  done

  # Identify this branch's pull request up front, since merging can take the
  # branch away and with it the ability to look any of this up.
  info=$(gh pr view --json number,baseRefName -q '[.number, .baseRefName] | @tsv' 2>/dev/null)
  IFS=$'\t' read -r number base <<< "$info"

  # Repositories with a merge queue are not supported: gh rejects --delete-branch
  # outright there, and says so clearly, because the queue needs the branch.
  (( strategy )) || set -- --merge "$@"
  gh pr merge --delete-branch "$@" || return

  # Nothing here proves the pull request merged: --auto may have only enabled
  # auto-merge, a PR given by number is usually somebody else's, and gh leaves
  # the local branch alone whenever it is named differently from the remote one.
  # So ask rather than infer, and stay put until the merge is real.
  [[ -n "$number" ]] && state=$(gh pr view "$number" --json state -q .state 2>/dev/null)
  [[ "$state" == MERGED ]] || return 0

  _sync_and_prune "$base"
}
# Browse repository
alias browse="gh browse"
