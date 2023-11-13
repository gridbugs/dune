(** Frontend the lock directory format *)

open Import

module Source : sig
  type fetch =
    { url : Loc.t * string
    ; checksum : (Loc.t * Checksum.t) option
    }

  type t =
    | External_copy of Loc.t * Path.External.t
    | Fetch of fetch
end

module Pkg_info : sig
  type t =
    { name : Package_name.t
    ; version : Package_version.t
    ; dev : bool
    ; source : Source.t option
    ; extra_sources : (Path.Local.t * Source.t) list
    }

  val default_version : Package_version.t
end

module Pkg : sig
  type t =
    { build_command : Action.t option
    ; install_command : Action.t option
    ; deps : Loc.t Package_name.Map.t
    ; info : Pkg_info.t
    ; exported_env : String_with_vars.t Action.Env_update.t list
    }

  val equal : t -> t -> bool
  val decode : (lock_dir:Path.Source.t -> Package_name.t -> t) Decoder.t
end

module Repositories : sig
  type t
end

type t = private
  { version : Syntax.Version.t
  ; packages : Pkg.t Package_name.Map.t
  (** It's guaranteed that this map will contain an entry for all dependencies
      of all packages in this map. That is, the set of packages is closed under
      the "depends on" relationship between packages. *)
  ; ocaml : (Loc.t * Package_name.t) option
  ; repos : Repositories.t
  ; expanded_solver_variable_bindings : Solver_stats.Expanded_variable_bindings.t
  (** Stores the solver variables that were evaluated while solving
      dependencies. Can be used to determine if a lockdir is compatible
      with a particular system. *)
  }

val remove_locs : t -> t
val equal : t -> t -> bool
val to_dyn : t -> Dyn.t

(** [create_latest_version packages ~ocaml ~repos
    ~expanded_solver_variable_bindings] raises a [Code_error] if [packages] is
    not closed under the "depends on" relationship between packages. Every
    dependency of every package in [packages] must itself have a corresponding
    entry in [packages]. *)
val create_latest_version
  :  Pkg.t Package_name.Map.t
  -> ocaml:(Loc.t * Package_name.t) option
  -> repos:Opam_repo.t list option
  -> expanded_solver_variable_bindings:Solver_stats.Expanded_variable_bindings.t
  -> t

val default_path : Path.Source.t

module Metadata : Dune_sexp.Versioned_file.S with type data := unit

val metadata_filename : Filename.t

module Write_disk : sig
  type lock_dir := t
  type t

  val prepare
    :  lock_dir_path:Path.Source.t
    -> files:File_entry.t Package_name.Map.Multi.t
    -> lock_dir
    -> t

  val commit : t -> unit
end

val read_disk : Path.Source.t -> t

module Make_load (Io : sig
    include Monad.S

    val parallel_map : 'a list -> f:('a -> 'b t) -> 'b list t
    val readdir_with_kinds : Path.Source.t -> (Filename.t * Unix.file_kind) list t
    val with_lexbuf_from_file : Path.Source.t -> f:(Lexing.lexbuf -> 'a) -> 'a t
    val stats_kind : Path.Source.t -> (File_kind.t, Unix_error.Detailed.t) result t
  end) : sig
  val load : Path.Source.t -> t Io.t
end
