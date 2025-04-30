open! Import

(** Sends a command to an RPC server to build the specified targets and wait
    for the build to complete or fail. *)
val build
  :  wait:bool
  -> promote:Dune_engine.Clflags.Promote.t option
  -> Dune_rpc_private.Where.t
  -> Dune_lang.Dep_conf.t list
  -> ( Dune_rpc_impl.Decl.Build_outcome_with_diagnostics.t
       , Dune_rpc.Response.Error.t )
       result
       Fiber.t

(** dune rpc build command *)
val cmd : unit Cmdliner.Cmd.t
