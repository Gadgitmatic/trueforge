#!/usr/bin/env sh
# Fork maintenance for origin (Gadgitmatic/trueforge) against upstream (truefoundry/trueforge).
#
#   scripts/fork-sync.sh sync                     update main, merge upstream into deploy/dokploy, push
#   scripts/fork-sync.sh pr <branch> <commit>...  cherry-pick deploy commits into a PR branch off upstream
#
# Invariants:
#   main          pure mirror of upstream/main, no fork commits, never checked out for work
#   deploy/dokploy  main + fork-only deployment mods; upstream is merged in, never rebased
#
# If `sync` warns that main carries fork commits, move them to deploy/dokploy and rewind main:
#   git branch -f main upstream/main
#   git push origin main:main --force-with-lease
set -eu

UPSTREAM=upstream
ORIGIN=origin
UPSTREAM_BRANCH=main
MAIN=main
DEPLOY=deploy/dokploy

die() { echo "error: $*" >&2; exit 1; }

current_branch() { git symbolic-ref --quiet --short HEAD || die "detached HEAD"; }
require_clean_tree() { [ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit or stash first"; }
repo_slug() { git remote get-url "$1" | sed -e 's#^git@[^:]*:##' -e 's#^https\?://[^/]*/##' -e 's#\.git$##'; }
unmerged_files() { git --no-pager diff --name-only --diff-filter=U; }

fetch_all() {
  git fetch --prune "$UPSTREAM"
  git fetch --prune "$ORIGIN"
}

mirror_main() {
  if git merge-base --is-ancestor "refs/heads/$MAIN" "refs/remotes/$UPSTREAM/$UPSTREAM_BRANCH"; then
    # main is not checked out here, so this only advances the ref, never the worktree.
    git fetch "$UPSTREAM" "refs/heads/$UPSTREAM_BRANCH:refs/heads/$MAIN"
    git push "$ORIGIN" "refs/heads/$MAIN:refs/heads/$MAIN"
    return 0
  fi
  echo "warning: $MAIN carries fork commits, so it is left alone; once nothing deploys from it:" >&2
  echo "  git branch -f $MAIN $UPSTREAM/$UPSTREAM_BRANCH" >&2
  echo "  git push $ORIGIN $MAIN:$MAIN --force-with-lease" >&2
}

merge_upstream() {
  require_clean_tree
  if git merge-base --is-ancestor "refs/remotes/$UPSTREAM/$UPSTREAM_BRANCH" HEAD; then
    echo "$DEPLOY is already current with $UPSTREAM/$UPSTREAM_BRANCH"
    return 0
  fi
  echo "merging $UPSTREAM/$UPSTREAM_BRANCH into $DEPLOY"
  if ! git merge --no-edit "$UPSTREAM/$UPSTREAM_BRANCH"; then
    files=$(unmerged_files)
    # Upstream keeps editing the root compose file that this branch deletes on
    # purpose; that one known conflict is resolved by keeping the deletion.
    # Anything else needs a human, so the merge is left in place.
    if [ "$files" = docker-compose.yml ]; then
      echo "keeping docker-compose.yml deleted (upstream changed the file this branch drops)"
      git rm -q -f docker-compose.yml
      git commit --no-edit
    else
      echo
      echo "conflicts:"
      echo "$files" | sed 's/^/  /'
      echo
      echo "resolve, then: git add <files> && git commit --no-edit && git push $ORIGIN $DEPLOY"
      exit 1
    fi
  fi
  git push "$ORIGIN" "refs/heads/$DEPLOY:refs/heads/$DEPLOY"
  echo "pushed $DEPLOY"
}

cmd_sync() {
  [ "$(current_branch)" = "$DEPLOY" ] || die "run sync from $DEPLOY: git switch $DEPLOY"
  fetch_all
  mirror_main
  merge_upstream
}

cmd_pr() {
  [ $# -ge 2 ] || die "usage: $0 pr <branch> <commit>..."
  branch=$1
  shift
  require_clean_tree
  fetch_all
  git switch --create "$branch" "$UPSTREAM/$UPSTREAM_BRANCH"
  git cherry-pick "$@"
  git push --set-upstream "$ORIGIN" "$branch"
  echo
  echo "open the PR:"
  echo "  gh pr create --repo $(repo_slug "$UPSTREAM") --base $UPSTREAM_BRANCH --head $(repo_slug "$ORIGIN" | cut -d/ -f1):$branch --fill"
}

case "${1:-sync}" in
  sync) cmd_sync ;;
  pr) shift; cmd_pr "$@" ;;
  *) die "usage: $0 [sync|pr <branch> <commit>...]" ;;
esac
