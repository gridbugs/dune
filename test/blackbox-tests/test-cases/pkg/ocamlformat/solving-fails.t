When an OCamlFormat version does not exists, `dune fmt` would fail with a
solving error.

  $ . ../helpers.sh
  $ mkrepo

Update with no dependency on OCamlFormat
  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name foo))
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

Update ".ocamlformat" file with unknown version of OCamlFormat.
  $ cat > .ocamlformat <<EOF
  > version = 0.26.9
  > EOF

An important cleaning here
  $ rm -rf dev-tools.locks/ocamlformat
  $ dune clean

Format, it shows the solving error.
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  Error: Unable to solve dependencies for the following lock directories:
  Lock directory dev-tools.locks/ocamlformat:
  Can't find all required versions.
  Selected: ocamlformat_dev_tool_wrapper.dev
  - ocamlformat -> (problem)
      No known implementations at all
  [1]
