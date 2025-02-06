open Import

module Solver_result : sig
  type t =
    { solution : Lock_dir.Solution.t
    ; ocaml : (Loc.t * Package_name.t) option
    ; num_expanded_packages : int
    }
end

val solve_lock_dir
  :  Solver_env.t
  -> Version_preference.t
  -> Opam_repo.t list
  -> local_packages:Local_package.For_solver.t Package_name.Map.t
  -> pins:Resolved_package.t Package_name.Map.t
  -> constraints:Dune_lang.Package_dependency.t list
  -> (Solver_result.t, [ `Diagnostic_message of User_message.Style.t Pp.t ]) result
       Fiber.t
