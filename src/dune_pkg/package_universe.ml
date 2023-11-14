open! Import

type t =
  { local_packages : Local_package.t Package_name.Map.t
  ; lock_dir : Lock_dir.t
  }

let validate ~local_packages (lock_dir : Lock_dir.t) =
  let solver_env =
    Solver_stats.Expanded_variable_bindings.to_solver_env
      lock_dir.expanded_solver_variable_bindings
  in
  let _ =
    Resolve_opam_formula.filtered_formula_to_package_names ~stats_updater:None solver_env
  in
  ()
;;
