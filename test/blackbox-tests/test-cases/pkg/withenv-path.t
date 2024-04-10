Demonstrate what happens if a user attempts to add to modify the PATH variable
using the withenv action.

  $ . ./helpers.sh

This path is system-specific so we need to be able to remove it from the output.
  $ DUNE_PATH=$(dirname $(which dune))

Printing out PATH without setting it:
  $ make_lockdir
  $ cat >dune.lock/test.pkg <<'EOF'
  > (version 0.0.1)
  > (build
  >  (system "echo PATH=$PATH"))
  > EOF
  $ dune clean
  $ PATH=$DUNE_PATH:/bin build_pkg test 2>&1 | sed -e "s#$DUNE_PATH#DUNE_PATH#"
  PATH=DUNE_PATH:/bin

Setting PATH to a specific value:
  $ cat >dune.lock/test.pkg <<'EOF'
  > (version 0.0.1)
  > (build
  >  (withenv
  >   ((= PATH /tmp/bin))
  >   (system "echo PATH=$PATH")))
  > EOF
  $ dune clean
  $ PATH=$DUNE_PATH:/bin build_pkg test 2>&1 | sed -e "s#$DUNE_PATH#DUNE_PATH#"
  PATH=/tmp/bin

Attempting to add a path to PATH replaces the entire PATH:
  $ cat >dune.lock/test.pkg <<'EOF'
  > (version 0.0.1)
  > (build
  >  (withenv
  >   ((+= PATH /tmp/bin))
  >   (system "echo PATH=$PATH")))
  > EOF
  $ dune clean
  $ PATH=$DUNE_PATH:/bin build_pkg test 2>&1 | sed -e "s#$DUNE_PATH#DUNE_PATH#"
  PATH=/tmp/bin

Try adding multiple paths to PATH:
  $ cat >dune.lock/test.pkg <<'EOF'
  > (version 0.0.1)
  > (build
  >  (withenv
  >   ((+= PATH /tmp/bin)
  >    (+= PATH /foo/bin)
  >    (+= PATH /bar/bin))
  >   (system "echo PATH=$PATH")))
  > EOF
  $ dune clean
  $ PATH=$DUNE_PATH:/bin build_pkg test 2>&1 | sed -e "s#$DUNE_PATH#DUNE_PATH#"
  PATH=/bar/bin:/foo/bin:/tmp/bin
