Having an invalid package dependency should give a good user message rather than raising
an uncaught exception. It is very likely that users will type foo.1.2.3 for a package
version due to the convention in opam. In this case we could also give a hint how to write
it in a dune-project file.

  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name invalid)
  >  (depends foo.1.2.3))
  > EOF

  $ dune pkg lock
  Error: Package name "foo.1.2.3" is not a valid opam package name.
  Package names can contain letters, numbers, '-', '_' and '+', and need to
  contain at least a letter.
  [1]
