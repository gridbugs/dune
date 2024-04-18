Setting environment variables in actions

  $ . ./helpers.sh

  $ make_lockdir
  $ cat >dune.lock/test.pkg <<'EOF'
  > (version 0.0.1)
  > (build
  >  (withenv
  >   ((= FOO myfoo)
  >    (= XYZ 000)
  >    (+= XYZ 111)
  >    (= BAR xxx)
  >    (+= BAR yyy)
  >    (:= BAR "")
  >    (+= BAR "")
  >    (=: BAZ "aaa")
  >    )
  >   (system "echo XYZ=$XYZ; echo FOO=$FOO; echo BAR=$BAR; echo BAZ=$BAZ")))
  > EOF
  $ build_pkg test
  XYZ=111:000
  FOO=myfoo
  BAR=yyy:xxx
