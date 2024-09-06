Make sure the format rules depends on ".ocamlformat-ignore" file when it exists.

  $ . ../helpers.sh
  $ mkrepo

Make a fake ocamlformat:
  $ mkdir ocamlformat
  $ cd ocamlformat
  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package (name ocamlformat))
  > EOF
  $ cat > ocamlformat.ml <<EOF
  > let version = "0.26.2"
  > let () =
  >   if Sys.file_exists ".ocamlformat-ignore" then
  >     print_endline "ignoring some files"
  > ;;
  > let () = print_endline ("formatted with version "^version)
  > EOF
  $ cat > dune <<EOF
  > (executable
  >  (public_name ocamlformat))
  > EOF
  $ cd ..
  $ tar -czf ocamlformat-0.26.2.tar.gz ocamlformat
  $ rm -rf ocamlformat

  $ mkpkg ocamlformat 0.26.2 <<EOF
  > build: [
  >   [
  >     "dune"
  >     "build"
  >     "-p"
  >     name
  >     "@install"
  >   ]
  > ]
  > url {
  >  src: "file://$PWD/ocamlformat-0.26.2.tar.gz"
  >  checksum: [
  >   "md5=$(md5sum ocamlformat-0.26.2.tar.gz | cut -f1 -d' ')"
  >  ]
  > }
  > EOF

Make a project that uses the fake ocamlformat:
  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name foo))
  > EOF
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF
  $ cat > dune <<EOF
  > (executable
  >  (public_name foo))
  > EOF
  $ cat > dune-workspace <<EOF
  > (lang dune 3.13)
  > (lock_dir
  >  (path "dev-tools.locks/ocamlformat")
  >  (repositories mock))
  > (lock_dir
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (source "file://$(pwd)/mock-opam-repository"))
  > EOF

Add a fake binary in the PATH
  $ mkdir .bin
  $ cat > .bin/ocamlformat <<EOF
  > #!/bin/sh
  > if [ -f ".ocamlformat-ignore" ]; then
  >   echo "ignoring some files"
  > fi
  > echo "fake ocamlformat from PATH"
  > EOF
  $ chmod +x .bin/ocamlformat
  $ PATH=$PWD/.bin:$PATH
  $ which ocamlformat
  $TESTCASE_ROOT/.bin/ocamlformat

Check without ".ocamlformat-ignore" file and the feature.
  $ dune fmt
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  fake ocamlformat from PATH

Create ".ocamlformat-ignore"
  $ touch .ocamlformat-ignore

Check with the feature when ".ocamlformat-ignore" file exists.
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  Solution for dev-tools.locks/ocamlformat:
  - ocamlformat.0.26.2
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ ls _build/default/.ocamlformat-ignore
  _build/default/.ocamlformat-ignore
  $ cat foo.ml
  ignoring some files
  formatted with version 0.26.2

An important cleaning here
  $ rm -r dev-tools.locks/ocamlformat

Check without the feature when ".ocamlformat-ignore" file exists.
  $ dune fmt
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ ls _build/default/.ocamlformat-ignore
  _build/default/.ocamlformat-ignore
  $ cat foo.ml
  ignoring some files
  fake ocamlformat from PATH
