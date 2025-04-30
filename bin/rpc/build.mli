(** Sends a command to an RPC server to build the specified targets and wait
    for the build to complete or fail. In the case of a failure, a diagnostic
    message is printed. *)
val build
  :  wait:bool
  -> Dune_rpc_private.Where.t
  -> Dune_lang.Dep_conf.t list
  -> unit Fiber.t

(** dune rpc build command *)
val cmd : unit Cmdliner.Cmd.t
