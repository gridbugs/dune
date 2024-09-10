If the dev-tool feature is enabled then `dune fmt` should invoke the `ocamlformat`
executable from the dev-tool and not the one from PATH.

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
  > (rule
  >  (target none)
  >  (action
  >     (progn
  >       (run ocamlformat foo.ml)
  >       (run touch none))))
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

Add a fake executable in the PATH
  $ mkdir .bin
  $ cat > .bin/ocamlformat <<EOF
  > #!/bin/sh
  > echo "fake ocamlformat from PATH"
  > EOF
  $ chmod +x .bin/ocamlformat
  $ PATH=$PWD/.bin:$PATH
  $ which ocamlformat
  $TESTCASE_ROOT/.bin/ocamlformat

Build the OCamlFormat binary dev-tool
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  Solution for dev-tools.locks/ocamlformat:
  - ocamlformat.0.26.2
  File "dune", line 1, characters 0-0:
  Error: Files _build/default/dune and _build/default/.formatted/dune differ.
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/dune to dune.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]

The OCamlFormat binary from the dev-tool.
  $ ./_build/_private/default/.dev-tool/ocamlformat/ocamlformat/target/bin/ocamlformat foo.ml
  formatted with version 0.26.2

Update "foo.ml" file
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF

When the dev-tool feature is disabled Dune runs the OCamlFormat binary from the
PATH and not the dev-tool one.
  $ dune build
  fake ocamlformat from PATH
