type t =
  | Success
  | Error
  | Signal

val all : t list
val info : t -> Climate_cmdliner.Cmd.Exit.info
val code : t -> int
