type 'a t

val create
  :  lock_timeout:float option
  -> registry:[ `Add | `Skip ]
  -> root:string
  -> handle:(unit Dune_rpc_server.Handler.t -> unit)
       (** register additional requests or notifications *)
  -> Dune_stats.t option
  -> parse_build:(string -> 'a)
  -> 'a t

type 'a build_action =
  { targets : 'a list
  ; outcome_ivar : Dune_engine.Scheduler.Run.Build_outcome.t Fiber.Ivar.t
  ; promote : Dune_engine.Clflags.Promote.t option
  }

type 'a pending_build_action = Build of 'a build_action

val pending_build_action : 'a t -> 'a pending_build_action Fiber.t

(** Stop accepting new rpc connections. Fiber returns when all existing
    connections terminate *)
val stop : _ t -> unit Fiber.t

val ready : _ t -> unit Fiber.t
val run : _ t -> unit Fiber.t
