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

Format for the fist time.
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  Solution for dev-tools.locks/ocamlformat:
  - ocamlformat.0.26.2
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]

Update "foo.ml" file.
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF

Formating a second time when a ".ml" file has changed, it is not supposed to lock/solve again.
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  formatted with version 0.26.2

When "dev-tools.locks" is removed, the solving/lock is renewed
  $ rm -r dev-tools.locks/ocamlformat
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  Solution for dev-tools.locks/ocamlformat:
  - ocamlformat.0.26.2
