open! Import

(** All of the packages in a dune project including local packages and packages
    in a lockdir. The lockdir is guaranteed to contain a valid dependency
    solution for the local packages. *)
type t

module Error : sig
  type t =
    | Duplicate_package_between_local_packages_and_lock_dir of
        { local_package : Local_package.t
        ; locked_package : Lock_dir.Pkg.t
        }
    | Local_package_dependencies_unsatisfied_by_lock_dir of
        { local_package : Local_package.t
        ; hints : Resolve_opam_formula.Unsatisfied_formula_hint.t list
        }
    | Unneeded_packages_in_lock_dir of Lock_dir.Pkg.t list

  val to_user_message : t -> User_message.t
end

val create : Local_package.t Package_name.Map.t -> Lock_dir.t -> (t, Error.t) result

val opam_package_dependencies_of_package
  :  t
  -> Package_name.t
  -> which:[ `All | `Non_test | `Test_only ]
  -> traverse:[ `Immediate | `Transitive ]
  -> OpamPackage.t list
