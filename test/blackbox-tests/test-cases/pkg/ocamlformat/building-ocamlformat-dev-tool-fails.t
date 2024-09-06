With a faulty version of OCamlFormat, $ dune fmt is supposed to stop with the
build error of "ocamlformat".

  $ . ../helpers.sh
  $ mkrepo

Make a fake ocamlformat with a missing ocamlformat.ml file:
  $ mkdir ocamlformat
  $ cd ocamlformat
  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package (name ocamlformat))
  > EOF

  $ cat > dune <<EOF
  > (executable
  >  (public_name ocamlformat))
  > EOF

  $ cd ..
  $ tar -czf ocamlformat.tar.gz ocamlformat
  $ rm -rf ocamlformat

Make a package with the the source coming from $PWD with new checksum.
  $ mkpkg ocamlformat 0.26.4 <<EOF
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
  >  src: "file://$PWD/ocamlformat.tar.gz"
  >  checksum: [
  >   "md5=$(md5sum ocamlformat.tar.gz | cut -f1 -d' ')"
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

Update ".ocamlformat" for known version
  $ cat > .ocamlformat <<EOF
  > version = 0.26.4
  > EOF

It fails during the build because of missing OCamlFormat module.
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  Solution for dev-tools.locks/ocamlformat:
  - ocamlformat.0.26.4
  File "dev-tools.locks/ocamlformat/ocamlformat.pkg", line 4, characters 6-10:
  4 |  (run dune build -p %{pkg-self:name} @install))
            ^^^^
  Error: Logs for package ocamlformat
  File "dune", line 2, characters 14-25:
  2 |  (public_name ocamlformat))
                    ^^^^^^^^^^^
  Error: Module "Ocamlformat" doesn't exist.
  
  [1]
