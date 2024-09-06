Exercises end to end, locking and building ocamlformat dev tool.

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

  $ cd ocamlformat
  $ cat > ocamlformat.ml <<EOF
  > let version = "0.26.3"
  > let () = print_endline ("formatted with version "^version)
  > EOF
  $ cd ..
  $ tar -czf ocamlformat-0.26.3.tar.gz ocamlformat
  $ rm -rf ocamlformat

Add the tar file for the fake curl to copy it:
  $ echo ocamlformat-0.26.2.tar.gz > fake-curls
  $ PORT=1

Make a package for the fake OCamlformat library:
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
  >  src: "http://127.0.0.1:$PORT"
  >  checksum: [
  >   "md5=$(md5sum ocamlformat-0.26.2.tar.gz | cut -f1 -d' ')"
  >  ]
  > }
  > EOF

Add the tar file for the fake curl to copy it:
  $ echo ocamlformat-0.26.3.tar.gz >> fake-curls
  $ PORT=2

Make a package for the lastest version of the fake ocamlformat library:
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
  >  src: "http://127.0.0.1:$PORT"
  >  checksum: [
  >   "md5=$(md5sum ocamlformat-0.26.3.tar.gz | cut -f1 -d' ')"
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

Without a ".ocamlformat" file, $ dune fmt takes the latest version of
OCamlFormat.
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

Create .ocamlformat file
  $ cat > .ocamlformat <<EOF
  > version = 0.26.2
  > EOF

An important cleaning here
  $ rm -r dev-tools.locks/ocamlformat
  $ dune clean

With a ".ocamlformat" file, $ dune fmt takes the version mentioned inside ".ocamlformat"
file.
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  Solution for dev-tools.locks/ocamlformat:
  - ocamlformat.0.26.2
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  formatted with version 0.26.2
