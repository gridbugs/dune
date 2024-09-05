open! Import

val is_enabled : bool Lazy.t
val lock_ocamlformat : unit -> unit Fiber.t
val lock_ocamllsp : ocaml_compiler_version:Package_version.t -> unit Fiber.t
