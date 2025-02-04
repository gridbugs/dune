open Import

type t

val package : t -> OpamPackage.t
val opam_file : t -> OpamFile.OPAM.t
val loc : t -> Loc.t
val set_url : t -> OpamUrl.t -> t
val dune_build : t -> bool
val git_repo : OpamPackage.t -> opam_file:Path.Local.t -> opam_file_contents:string -> t
val local_fs : OpamPackage.t -> dir:Path.t -> opam_file_path:Path.Local.t -> t
val dune_package : Loc.t -> OpamFile.OPAM.t -> OpamPackage.t -> t
