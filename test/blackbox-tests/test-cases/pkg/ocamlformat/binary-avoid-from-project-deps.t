If the dev-tool feature is enabled then `dune fmt` should invoke the `ocamlformat`
executable from the dev-tool and not the one from the project's regular package
dependencies.

If the dev-tool feature is not enabled then `dune fmt` should invoke the
`ocamlformat` executable from the project's regular package dependencies.

  $ . ../helpers.sh
  $ mkrepo

Make a fake ocamlformat.0.26.2:
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

Make a fake ocamlformat.0.26.3:
  $ cd ocamlformat
  $ cat > ocamlformat.ml <<EOF
  > let version = "0.26.3"
  > let () = print_endline ("formatted with version "^version)
  > EOF
  $ cd ..
  $ tar -czf ocamlformat-0.26.3.tar.gz ocamlformat
  $ rm -rf ocamlformat

Make a package for the fake OCamlformat 0.26.2:
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

Make a package for the fake OCamlformat 0.26.3:
  $ mkpkg ocamlformat 0.26.3 <<EOF
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
  >  src: "file://$PWD/ocamlformat-0.26.3.tar.gz"
  >  checksum: [
  >   "md5=$(md5sum ocamlformat-0.26.3.tar.gz | cut -f1 -d' ')"
  >  ]
  > }
  > EOF

Make a project that depends on the fake ocamlformat.0.26.2:
  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name foo)
  >  (depends (ocamlformat (= 0.26.2))))
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
  > echo "fake ocamlformat from PATH"
  > EOF
  $ chmod +x .bin/ocamlformat
  $ PATH=$PWD/.bin:$PATH
  $ which ocamlformat
  $TESTCASE_ROOT/.bin/ocamlformat

Lock and build the project to make OCamlFormat from the project dependencies available.
  $ dune pkg lock
  Solution for dune.lock:
  - ocamlformat.0.26.2
Run `dune fmt` without the dev-tools feature enabled. This should invoke the ocamlformat
executable from the package dependencies (ie. ocamlformat.0.26.2).
  $ dune fmt
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  formatted with version 0.26.2

The OCamlFormat binary from the project dependencies.
  $ ls _build/_private/default/.pkg/ocamlformat/target/bin/ocamlformat
  _build/_private/default/.pkg/ocamlformat/target/bin/ocamlformat

Update "foo.ml"
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF

Format using the dev-tools feature, it does not invoke the OCamlFormat binary from
the project dependencies (0.26.2) but instead builds and runs the OCamlFormat binary as a
dev-tool (0.26.3).
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  Solution for dev-tools.locks/ocamlformat:
  - ocamlformat.0.26.3
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  formatted with version 0.26.3

The OCamlFormat binary from the project dependencies.
  $ ls _build/_private/default/.pkg/ocamlformat/target/bin/ocamlformat
  _build/_private/default/.pkg/ocamlformat/target/bin/ocamlformat

Update "foo.ml"
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF

Retry, without dev-tools feature and without cleaning. This time it uses the OCamlFormat
binary from the project dependencies rather than the dev-tool. This exercises the
behavior when OCamlFormat is installed simultaneously as both a dev-tool and as a
regular package dependency.
  $ rm -rf dev-tools.locks/ocamlformat
  $ dune fmt
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  formatted with version 0.26.2
