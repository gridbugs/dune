We want to make sure our OPAM-repository in git support works well.

  $ . ./helpers.sh
  $ mkrepo
  $ mkpkg foo 1.0 <<EOF
  > EOF
  $ cd mock-opam-repository
  $ git init --quiet
  $ git add -A
  $ git commit --quiet -m "foo 1.0"
  $ cd ..

We'll set up a project that uses (only this) this repository, so doesn't use
:standard:

  $ add_mock_repo_if_needed "git+file://$PWD/mock-opam-repository"

We depend on the foo package

  $ cat > dune-project <<EOF
  > (lang dune 3.10)
  > 
  > (package
  >  (name bar)
  >  (depends foo))
  > EOF

Locking should produce the newest package from the repo

  $ mkdir dune-cache
  $ XDG_CACHE_HOME=$PWD/dune-cache dune pkg lock
  Solution for dune.lock:
  - foo.1.0

Now let's assume a new version of foo is released.

  $ mkpkg foo 1.1 <<EOF
  > EOF
  $ cd mock-opam-repository
  $ git add -A
  $ git commit --quiet -m "foo 1.1 -> new version"
  $ cd ..

Locking should update the git repo in our cache folder and give us the newer
version in the lock file

  $ XDG_CACHE_HOME=$PWD/dune-cache dune pkg lock
  Solution for dune.lock:
  - foo.1.1

The git repos support repo should also be able to handle unusual objects in our
tree, which can e.g. happen with submodules.

  $ cd mock-opam-repository
  $ PARENT=$(git rev-parse HEAD)

To make this a bit easier we use some git plumbing commands to reproduce it.
First we create a commit object in the index and write a tree containing this
commit (pointing to nowhere):

  $ git update-index --add --cacheinfo 160000,0000000000000000000000000000000000000001,dangling-commit-in-tree
  $ TREE=$(git write-tree)

Then we create a commit with the tree and our HEAD as a parent commit

  $ CURRENT=$(echo "Added a dangling commit object" | git commit-tree $TREE -p $PARENT)

Then we make this new commit the one that our branch is pointing to.

  $ git reset --hard -q $CURRENT

Thus ls-tree should now also contain a commit object:

  $ git ls-tree -r HEAD | awk '{ printf "%s %s\n",$2,$4; }' | sort
  blob packages/foo/foo.1.0/opam
  blob packages/foo/foo.1.1/opam
  commit dangling-commit-in-tree
  $ cd ..

With this set up in place, locking should still work as the commit is not
relevant

  $ XDG_CACHE_HOME=$PWD/dune-cache dune pkg lock 2> /dev/null && echo "Solution found"
  Solution found
