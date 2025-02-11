open Stdune

type source =
  | Path of Path.t
  | Content of string

let source_equal a b =
  match a, b with
  | Path a, Path b -> Path.equal a b
  | Content a, Content b -> String.equal a b
  | Path _, Content _ | Content _, Path _ -> false
;;

type t =
  { original : source
  ; local_file : Path.Local.t
  }

let equal { original; local_file } t =
  source_equal original t.original && Path.Local.equal local_file t.local_file
;;
