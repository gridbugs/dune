
  $ . ./helpers.sh

  $ mkrepo

  $ mkpkg linux-only <<EOF
  > install: [ "echo" "linux-only" ]
  > EOF

  $ mkpkg macos-only <<EOF
  > install: [ "echo" "macos-only" ]
  > EOF

  $ cat >dune-workspace <<EOF
  > (lang dune 3.13)
  > (lock_dir
  >  (path dune.macos.lock)
  >  (repositories mock)
  >  (solver_env
  >   (os macos)))
  > (lock_dir
  >  (path dune.linux.lock)
  >  (repositories mock)
  >  (solver_env
  >   (os linux)))
  > (lock_dir
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (source "file://$(pwd)/mock-opam-repository"))
  > (context
  >  (default
  >   (lock_dir (cond
  >    ((= %{system} macosx) dune.macos.lock)
  >    ((= %{system} linux) dune.linux.lock)))))
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name foo)
  >  (depends
  >   (macos-only (= :os macos))
  >   (linux-only (= :os linux))))
  > EOF

Generate both lockdirs:
  $ dune pkg lock dune.macos.lock
  Solution for dune.macos.lock:
  - macos-only.0.0.1
  $ dune pkg lock dune.linux.lock
  Solution for dune.linux.lock:
  - linux-only.0.0.1

Demonstrate that the correct lockdir is being chosen by building packages that
are only dependen on on certain systems.

Build macos package on macos:
  $ dune clean
  $ DUNE_CONFIG__OS=macos dune build _build/_private/default/.pkg/macos-only/target/
  macos-only

Build linux package on macos (will fail):
  $ dune clean
  $ DUNE_CONFIG__OS=macos dune build _build/_private/default/.pkg/linux-only/target/
  macos-only
  Error: Unknown package "linux-only"
  [1]

Build macos package on linux (will fail):
  $ dune clean
  $ DUNE_CONFIG__OS=linux dune build _build/_private/default/.pkg/macos-only/target/
  linux-only
  Error: Unknown package "macos-only"
  [1]

Build linux package on linux:
  $ dune clean
  $ DUNE_CONFIG__OS=linux dune build _build/_private/default/.pkg/linux-only/target/
  linux-only

Try setting the os to one which doesn't have a corresponding lockdir:
  $ dune clean
  $ DUNE_CONFIG__OS=windows dune build _build/_private/default/.pkg/linux-only/target/
  File "dune-workspace", line 20, characters 3-82:
  20 |    ((= %{system} macosx) dune.macos.lock)
  21 |    ((= %{system} linux) dune.linux.lock)))))
  Error: None of the conditions matched so no lockdir could be chosen.
  [1]
