open! Import

type t =
  { local_packages : Local_package.t Package_name.Map.t
  ; lock_dir : Lock_dir.t
  }

module Error = struct
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

  let to_dyn = function
    | Duplicate_package_between_local_packages_and_lock_dir
        { local_package; locked_package } ->
      Dyn.variant
        "Duplicate_package_between_local_packages_and_lock_dir"
        [ Dyn.record
            [ "local_package", Local_package.to_dyn local_package
            ; "locked_package", Lock_dir.Pkg.to_dyn locked_package
            ]
        ]
    | Local_package_dependencies_unsatisfied_by_lock_dir { local_package; hints } ->
      Dyn.variant
        "Local_package_dependencies_unsatisfied_by_lock_dir"
        [ Dyn.record
            [ "local_package", Local_package.to_dyn local_package
            ; "hints", Dyn.list Resolve_opam_formula.Unsatisfied_formula_hint.to_dyn hints
            ]
        ]
    | Unneeded_packages_in_lock_dir packages ->
      Dyn.variant
        "Unneeded_packages_in_lock_dir"
        (List.map ~f:Lock_dir.Pkg.to_dyn packages)
  ;;

  let to_user_message =
    let hints =
      [ Pp.concat
          ~sep:Pp.space
          [ Pp.text
              "The lockdir no longer contains a solution for the local packages in this \
               project. Regenerate the lockdir by running:"
          ; User_message.command "dune pkg lock"
          ]
      ]
    in
    function
    | Duplicate_package_between_local_packages_and_lock_dir { local_package; _ } ->
      User_message.make
        ~hints
        ~loc:local_package.loc
        [ Pp.textf
            "A package named %S is defined locally but is also present in the lockdir"
            (Package_name.to_string local_package.name)
        ]
    | Local_package_dependencies_unsatisfied_by_lock_dir
        { local_package; hints = unsatisfied_formula_hints } ->
      User_message.make
        ~hints
        ~loc:local_package.loc
        (Pp.textf
           "The dependencies of local package %S could not be satisfied from the lockdir:"
           (Package_name.to_string local_package.name)
         :: List.map
              unsatisfied_formula_hints
              ~f:Resolve_opam_formula.Unsatisfied_formula_hint.pp)
    | Unneeded_packages_in_lock_dir packages ->
      User_message.make
        ~hints
        [ Pp.text
            "The lockdir contains packages which are not among the transitive \
             dependencies of any local package:"
        ; Pp.enumerate packages ~f:(fun (package : Lock_dir.Pkg.t) ->
            Pp.textf
              "%s.%s"
              (Package_name.to_string package.info.name)
              (Package_version.to_string package.info.version))
        ]
  ;;
end

let solver_env t =
  Solver_stats.Expanded_variable_bindings.to_solver_env
    t.lock_dir.expanded_solver_variable_bindings
;;

module Validation = struct
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
      let local_package =
        Package_name.Map.find_exn t.local_packages duplicate_package_name
      in
      let locked_package =
        Package_name.Map.find_exn t.lock_dir.packages duplicate_package_name
      in
      Error
        (Error.Duplicate_package_between_local_packages_and_lock_dir
           { local_package; locked_package })
  ;;

  let concrete_dependencies_of_local_package_with_test
    solver_env
    version_by_package_name
    local_package
    =
    Local_package.opam_filtered_dependency_formula local_package
    |> Resolve_opam_formula.filtered_formula_to_package_names
         ~stats_updater:None
         ~with_test:true
         solver_env
         version_by_package_name
    |> Result.map_error ~f:(function `Formula_could_not_be_satisfied hints ->
      Error.Local_package_dependencies_unsatisfied_by_lock_dir { local_package; hints })
    |> Result.map ~f:Package_name.Set.of_list
  ;;

  let all_non_local_dependencies_of_local_packages t version_by_package_name =
    let open Result.O in
    let solver_env = solver_env t in
    let+ all_dependencies_of_local_packages =
      Package_name.Map.values t.local_packages
      |> List.map
           ~f:
             (concrete_dependencies_of_local_package_with_test
                solver_env
                version_by_package_name)
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
        Lock_dir.transitive_dependency_closure
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
    else
      Error
        (Error.Unneeded_packages_in_lock_dir
           (Package_name.Set.to_list unneeded_packages_in_lock_dir
            |> List.map ~f:(Package_name.Map.find_exn t.lock_dir.packages)))
  ;;

  let validate t =
    let open Result.O in
    version_by_package_name t
    >>= all_non_local_dependencies_of_local_packages t
    >>= check_for_unnecessary_packges_in_lock_dir t
  ;;
end

let create local_packages lock_dir =
  let open Result.O in
  let t = { local_packages; lock_dir } in
  let+ () = Validation.validate t in
  t
;;

let assert_validated f t =
  match f t with
  | Ok x -> x
  | Error e ->
    Code_error.raise
      "Invalid package universe which should have already been validated"
      [ "error", Error.to_dyn e ]
;;

let version_by_package_name = assert_validated Validation.version_by_package_name

let contains_package { local_packages; lock_dir } package_name =
  let in_local_packages = Package_name.Map.mem local_packages package_name in
  let in_lock_dir = Package_name.Map.mem lock_dir.packages package_name in
  in_local_packages || in_lock_dir
;;

let concrete_dependencies_of_local_package_without_test
  solver_env
  version_by_package_name
  local_package
  =
  Local_package.opam_filtered_dependency_formula local_package
  |> Resolve_opam_formula.filtered_formula_to_package_names
       ~stats_updater:None
       ~with_test:true
       solver_env
       version_by_package_name
  |> function
  | Ok x -> Package_name.Set.of_list x
  | Error (`Formula_could_not_be_satisfied hints) ->
    User_error.raise
      (Pp.textf
         "Unable to find dependencies of package %S in lockdir when the solver \
          'with_test' is set to 'false':"
         (Package_name.to_string local_package.name)
       :: List.map hints ~f:Resolve_opam_formula.Unsatisfied_formula_hint.pp)
;;

let transitive_dependency_closure_without_test ({ local_packages; lock_dir } as t) start =
  let concrete_dependencies_of_local_package_without_test =
    concrete_dependencies_of_local_package_without_test
      (solver_env t)
      (version_by_package_name t)
  in
  let local_package_names = Package_name.Set.of_keys t.local_packages in
  let local_transitive_dependency_closure =
    let to_visit = Queue.create () in
    let push_set = Package_name.Set.iter ~f:(Queue.push to_visit) in
    push_set Package_name.Set.(inter local_package_names start);
    let rec loop seen =
      match Queue.pop to_visit with
      | None -> seen
      | Some node ->
        let local_package = Package_name.Map.find_exn t.local_packages node in
        let deps = concrete_dependencies_of_local_package_without_test local_package in
        let local_unseen_deps =
          Package_name.Set.(diff deps seen |> inter local_package_names)
        in
        push_set local_unseen_deps;
        loop (Package_name.Set.union seen local_unseen_deps)
    in
    loop start
  in
  let non_local_transitive_dependency_closure =
    let non_local_dependencies_of_local_transitive_dependency_closure =
      Package_name.Set.to_list local_transitive_dependency_closure
      |> Package_name.Set.union_map ~f:(fun name ->
        let local_package = Package_name.Map.find_exn local_packages name in
        let all_deps =
          concrete_dependencies_of_local_package_without_test local_package
        in
        Package_name.Set.diff all_deps local_package_names)
    in
    Lock_dir.transitive_dependency_closure
      lock_dir
      Package_name.Set.(
        union
          non_local_dependencies_of_local_transitive_dependency_closure
          (diff start local_package_names))
    |> function
    | Ok x -> x
    | Error (`Missing_packages missing_packages) ->
      Code_error.raise
        "Attempted to find non-existent packages in lockdir after validation which \
         should not be possible"
        (Package_name.Set.to_list missing_packages
         |> List.map ~f:(fun p -> "missing package", Package_name.to_dyn p))
  in
  Package_name.Set.union
    local_transitive_dependency_closure
    non_local_transitive_dependency_closure
;;
