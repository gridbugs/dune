open! Import

type t =
  { local_packages : Local_package.t Package_name.Map.t
  ; lock_dir : Lock_dir.t
  }

module Error = struct
  type t =
    | Duplicate_package_between_local_packages_and_lock_dir of Package_name.t
    | Local_package_dependencies_unsatisfied_by_lock_dir of
        { local_package : Local_package.t
        ; hints : Resolve_opam_formula.Unsatisfied_formula_hint.t list
        }
    | Unneeded_packages_in_lock_dir of Package_name.Set.t
end

let version_by_package_name t =
  let from_local_packages =
    Package_name.Map.map t.local_packages ~f:(fun local_package ->
      Option.value local_package.version ~default:Lock_dir.Pkg_info.default_version)
  in
  let from_lock_dir =
    Package_name.Map.map t.lock_dir.packages ~f:(fun pkg -> pkg.info.version)
  in
  let exception Duplicate_package of Package_name.t in
  try
    Ok
      (Package_name.Map.union
         from_local_packages
         from_lock_dir
         ~f:(fun duplicate_package_name _ _ ->
           raise (Duplicate_package duplicate_package_name)))
  with
  | Duplicate_package duplicate_package_name ->
    Error
      (Error.Duplicate_package_between_local_packages_and_lock_dir duplicate_package_name)
;;

let all_non_local_dependencies_of_local_packages t version_by_package_name =
  let open Result.O in
  let solver_env =
    Solver_stats.Expanded_variable_bindings.to_solver_env
      t.lock_dir.expanded_solver_variable_bindings
  in
  let+ all_dependencies_of_local_packages =
    Package_name.Map.values t.local_packages
    |> List.map ~f:(fun local_package ->
      Local_package.opam_filtered_dependency_formula local_package
      |> Resolve_opam_formula.filtered_formula_to_package_names
           ~stats_updater:None
           ~with_test:true
           solver_env
           version_by_package_name
      |> Result.map_error ~f:(function `Formula_could_not_be_satisfied hints ->
        Error.Local_package_dependencies_unsatisfied_by_lock_dir { local_package; hints })
      |> Result.map ~f:Package_name.Set.of_list)
    |> Result.List.all
    |> Result.map ~f:Package_name.Set.union_all
  in
  Package_name.Set.diff
    all_dependencies_of_local_packages
    (Package_name.Set.of_keys t.local_packages)
;;

let check_for_unnecessary_packges_in_lock_dir
  t
  all_non_local_dependencies_of_local_packages
  =
  let locked_transitive_closure_of_local_package_dependencies =
    match
      Lock_dir.dependency_transitive_closure
        t.lock_dir
        all_non_local_dependencies_of_local_packages
    with
    | Ok x -> x
    | Error (`Missing_packages missing_packages) ->
      (* Resolving the dependency formulae would have failed if there were any missing packages in the lockdir. *)
      Code_error.raise
        "Missing packages from lockdir after confirming no missing packages in lockdir"
        [ "missing package", Package_name.Set.to_dyn missing_packages ]
  in
  let all_locked_packages = Package_name.Set.of_keys t.lock_dir.packages in
  let unneeded_packages_in_lock_dir =
    Package_name.Set.diff
      all_locked_packages
      locked_transitive_closure_of_local_package_dependencies
  in
  if Package_name.Set.is_empty unneeded_packages_in_lock_dir
  then Ok ()
  else Error (Error.Unneeded_packages_in_lock_dir unneeded_packages_in_lock_dir)
;;

let validate t =
  let open Result.O in
  version_by_package_name t
  >>= all_non_local_dependencies_of_local_packages t
  >>= check_for_unnecessary_packges_in_lock_dir t
;;

let create local_packages lock_dir =
  let open Result.O in
  let t = { local_packages; lock_dir } in
  let+ () = validate t in
  t
;;
