Exercises end to end, locking and building ocamlformat dev tool.

  $ . ./helpers.sh
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
  > let () = if Sys.file_exists ".ocamlformat-ignore" then print_endline "ignoring some files"
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


With a ".ocamlformat" file, $ dune fmt takes the version mentioned inside ".ocamlformat" file.

Create .ocamlformat file
  $ cat > .ocamlformat <<EOF
  > version = 0.26.2
  > EOF

An important cleaning here
  $ rm -r dev-tools.locks/ocamlformat
  $ dune clean

Format the "foo.ml", $ dune fmt takes the version inside ".ocamlformat".
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

Formating a second time when a ".ml" file has changed, it is not supposed to lock/solve again.

Update "foo.ml" file.
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF

Format "foo.ml".
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

Make sure the format rules depends on ".ocamlformat-ignore" file when it exists.

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

Update "foo.ml" file.
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF

Check without ".ocamlformat-ignore" file and the feature.
  $ dune fmt
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  formatted with version 0.26.2

Create ".ocamlformat-ignore"
  $ touch .ocamlformat-ignore

Check with the feature.
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
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
  $ dune clean

Create "foo.ml" file with unformatted state.
  $ cat > foo.ml <<EOF
  > let ()   = print_endline "Hello, world"
  > EOF

Check without the feature. It should ignore some files
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

An important cleaning here
  $ dune clean
  $ rm .ocamlformat-ignore

Make sure that the "dune-project" does not use the OCamlFormat binary dev-tool.

Build the OCamlFormat binary dev-tool
  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune fmt
  Solution for dev-tools.locks/ocamlformat:
  - ocamlformat.0.26.2
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]

The OCamlFormat binary from the dev-tool.
  $ ./_build/_private/default/.dev-tool/ocamlformat/ocamlformat/target/bin/ocamlformat foo.ml
  formatted with version 0.26.2

Update "dune" and "foo.ml" files
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
  $ cat > foo.ml <<EOF
  > let ()  =  print_endline "Hello, world"
  > EOF

It uses the OCamlFormat binary from the PATH and not the dev-tool one.
  $ dune build
  fake ocamlformat from PATH

Make sure that without the feature $ dune fmt takes the binary from the
"dune-project" dependencies. This is the old behaviour.

  $ echo ocamlformat-0.26.3.tar.gz >> fake-curls
  $ PORT=3

Create again because of the new PORT for the URL.
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

Update "dune-project", "dune", and "foo.ml"
  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name foo)
  >  (depends (ocamlformat (= 0.26.3))))
  > EOF
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF
  $ cat > dune <<EOF
  > (executable
  >  (public_name foo))
  > EOF

An important cleaning here
  $ rm -fr dev-tools.locks/ocamlformat
  $ rm -fr dune.lock
  $ dune clean

Even if ".ocamlformat" exists, that does not change anything
  $ cat .ocamlformat
  version = 0.26.2

Lock and format "foo.ml", it uses the version inside "dune-project".
  $ dune pkg lock
  Solution for dune.lock:
  - ocamlformat.0.26.3
  $ dune fmt
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  formatted with version 0.26.3

Make sure that $ dune fmt does not take the OCamlFormat binary inside the "dune-project" dependencies.

One version for dune-project file another for dev-tool
  $ echo ocamlformat-0.26.3.tar.gz >> fake-curls
  $ PORT_3=4
  $ echo ocamlformat-0.26.2.tar.gz >> fake-curls
  $ PORT_2=5
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
  >  src: "http://127.0.0.1:$PORT_3"
  >  checksum: [
  >   "md5=$(md5sum ocamlformat-0.26.3.tar.gz | cut -f1 -d' ')"
  >  ]
  > }
  > EOF
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
  >  src: "http://127.0.0.1:$PORT_2"
  >  checksum: [
  >   "md5=$(md5sum ocamlformat-0.26.2.tar.gz | cut -f1 -d' ')"
  >  ]
  > }
  > EOF

".ocamlforamt" takes the latest version of OCamlFormat
  $ cat > .ocamlformat <<EOF
  > version = 0.26.3
  > EOF

"dune-project" takes the old version of OCamlFormat
  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name foo)
  >  (depends (ocamlformat (= 0.26.2))))
  > EOF

Update "foo.ml"
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF

An important cleaning here
  $ rm -rf dev-tools.locks/ocamlformat
  $ dune clean

Lock and build the project to make OCamlFormat available.
  $ dune pkg lock
  Solution for dune.lock:
  - ocamlformat.0.26.2
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

Format using the feature, it does not choose the OCamlFormat binary from the project dependencies.
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

The OCamlFormat binary from the dev-tool.
  $ ls _build/_private/default/.dev-tool/ocamlformat/ocamlformat/target/bin/ocamlformat
  _build/_private/default/.dev-tool/ocamlformat/ocamlformat/target/bin/ocamlformat

Update "foo.ml"
  $ cat > foo.ml <<EOF
  > let () = print_endline "Hello, world"
  > EOF

Retry, without the feature and without cleaning, it uses the OCamlFormat binary from the project
dependnecies. This is making sure that the two different binaries does not mix up.
  $ rm -rf dev-tools.locks/ocamlformat
  $ dune fmt
  File "foo.ml", line 1, characters 0-0:
  Error: Files _build/default/foo.ml and _build/default/.formatted/foo.ml
  differ.
  Promoting _build/default/.formatted/foo.ml to foo.ml.
  [1]
  $ cat foo.ml
  formatted with version 0.26.2

When an OCamlFormat version does not exists, $ dune fmt would fail with a
solving error.

Update with no dependency on OCamlFormat
  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name foo))
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
      ocamlformat_dev_tool_wrapper dev requires = 0.26.9
      Rejected candidates:
        ocamlformat.0.26.3: Incompatible with restriction: = 0.26.9
        ocamlformat.0.26.2: Incompatible with restriction: = 0.26.9
  [1]


With a faulty version of OCamlFormat, $ dune fmt is supposed to stop with the
build error of "ocamlformat".

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


Update ".ocamlformat" for known version
  $ cat > .ocamlformat <<EOF
  > version = 0.26.4
  > EOF

An important cleaning here
  $ rm -rf dev-tools.locks/ocamlformat
  $ rm -fr dune.lock
  $ dune clean

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
