open Import
open Dune_rpc

(** Internal RPC requests *)

module Build_request : sig
  type t

  val create : targets:string list -> promote:Dune_engine.Clflags.Promote.t option -> t
  val targets : t -> string list
  val promote : t -> Dune_engine.Clflags.Promote.t option
end

module Build_outcome_with_diagnostics : sig
  type t =
    | Success
    | Failure of Dune_engine.Compound_user_error.t list

  val sexp : (t, Conv.values) Conv.t
end

module Status : sig
  module Menu : sig
    type t =
      | Uninitialized
      | Menu of (string * int) list

    val sexp : (t, Conv.values) Conv.t
  end

  type t = { clients : (Id.t * Menu.t) list }

  val sexp : (t, Conv.values) Conv.t
end

val build : (Build_request.t, Build_outcome_with_diagnostics.t) Decl.Request.t
val status : (unit, Status.t) Decl.Request.t
