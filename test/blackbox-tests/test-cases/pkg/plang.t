  $ cat > dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name x)
  >  (allow_empty)
  >  (depends_plang
  >   foo
  >   (bar (and (>= 1.5) (= %{os} linux)))
  >   (any baz qux)))
  > EOF

  $ dune build
