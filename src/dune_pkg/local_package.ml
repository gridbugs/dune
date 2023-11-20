open! Import
module Package_constraint = Dune_lang.Package_constraint

type t =
  { name : Package_name.t
  ; version : Package_version.t option
  ; dependencies : Package_dependency.t list
  ; loc : Loc.t
  }

module Dependency_set = struct
  type t = Package_constraint.Set.t Package_name.Map.t

  let empty = Package_name.Map.empty

  let of_list =
    List.fold_left ~init:empty ~f:(fun acc { Package_dependency.name; constraint_ } ->
      Package_name.Map.update acc name ~f:(fun existing ->
        match existing, constraint_ with
        | None, None -> Some Package_constraint.Set.empty
        | None, Some constraint_ -> Some (Package_constraint.Set.singleton constraint_)
        | Some existing, None -> Some existing
        | Some existing, Some constraint_ ->
          Some (Package_constraint.Set.add existing constraint_)))
  ;;

  let union =
    Package_name.Map.union ~f:(fun _name a b -> Some (Package_constraint.Set.union a b))
  ;;

  let union_all = List.fold_left ~init:empty ~f:union

  let package_dependencies =
    Package_name.Map.to_list_map ~f:(fun name constraints ->
      let constraint_ =
        if Package_constraint.Set.is_empty constraints
        then None
        else Some (Package_constraint.And (Package_constraint.Set.to_list constraints))
      in
      { Package_dependency.name; constraint_ })
  ;;

  let encode_for_hash t =
    package_dependencies t |> Dune_lang.Encoder.list Package_dependency.encode
  ;;

  let hash_hex_or_empty t =
    if Package_name.Map.is_empty t
    then Error `Empty
    else Ok (encode_for_hash t |> Dune_sexp.to_string |> Sha512.string |> Sha512.to_hex)
  ;;
end

module For_solver = struct
  type t =
    { name : Package_name.t
    ; dependencies : Package_dependency.t list
    }

  let to_opam_file { name; dependencies } =
    OpamFile.OPAM.empty
    |> OpamFile.OPAM.with_name (Package_name.to_opam_package_name name)
    |> OpamFile.OPAM.with_depends
         (Package_dependency.list_to_opam_filtered_formula dependencies)
  ;;

  let opam_filtered_dependency_formula { dependencies; _ } =
    Package_dependency.list_to_opam_filtered_formula dependencies
  ;;
end

let for_solver { name; version = _; dependencies; loc = _ } =
  { For_solver.name; dependencies }
;;
