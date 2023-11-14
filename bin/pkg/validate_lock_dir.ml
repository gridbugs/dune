open! Import
open Pkg_common
module Package_universe = Dune_pkg.Package_universe
module Lock_dir = Dune_pkg.Lock_dir
module Opam_repo = Dune_pkg.Opam_repo
module Package_version = Dune_pkg.Package_version
module Opam_solver = Dune_pkg.Opam_solver

let info =
  let doc = "Validate that a lockdir contains a solution for local packages" in
  let man = [ `S "DESCRIPTION"; `P doc ] in
  Cmd.info "validate-lockdir" ~doc ~man
;;

let enumerate_lock_dirs_by_path ~context_name_arg ~all_contexts_arg =
  let open Fiber.O in
  let+ per_contexts =
    Per_context.choose ~context_name_arg ~all_contexts_arg ~version_preference_arg:None
  in
  List.filter_map per_contexts ~f:(fun { Per_context.lock_dir_path; _ } ->
    if Path.exists (Path.source lock_dir_path)
    then (
      try Some (lock_dir_path, Lock_dir.read_disk lock_dir_path) with
      | User_error.E e ->
        User_warning.emit
          [ Pp.textf
              "Failed to parse lockdir %s:"
              (Path.Source.to_string_maybe_quoted lock_dir_path)
          ; User_message.pp e
          ];
        None)
    else None)
;;

let validate_lock_dir ~context_name_arg ~all_contexts_arg =
  let open Fiber.O in
  let+ lock_dirs_by_path = enumerate_lock_dirs_by_path ~context_name_arg ~all_contexts_arg
  and+ local_packages = find_local_packages
  and+ project = find_project in
  ()
;;

let term =
  let+ builder = Common.Builder.term
  and+ context_name =
    context_term ~doc:"Validate the lockdir associated with this context"
  and+ all_contexts =
    Arg.(value & flag & info [ "all-contexts" ] ~doc:"Validate all lockdirs")
  in
  let builder = Common.Builder.forbid_builds builder in
  let common, config = Common.init builder in
  Scheduler.go ~common ~config
  @@ fun () ->
  validate_lock_dir ~context_name_arg:context_name ~all_contexts_arg:all_contexts
;;

let command = Cmd.v info term
