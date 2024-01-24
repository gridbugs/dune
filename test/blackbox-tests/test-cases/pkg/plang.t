  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name x)
  >  (depends_plang
  >   foo
  >   (bar (>= %{os} linux))
  >   (any baz qux)))
  > EOF

  $ dune build
