open Import

let term =
  let+ builder = Common.Builder.term
  and+ context_name =
    Common.context_arg ~doc:(Some "Context used to determine lockdir")
  in
  let builder = Common.Builder.forbid_builds builder in
  let common, config = Common.init builder in
  Scheduler.go_with_rpc_server ~common ~config (fun () ->
    let open Fiber.O in
    let+ result =
      Build.run_build_system ~common ~request:(fun _build_system ->
        Action_builder.of_memo
          (let open Memo.O in
           let+ lock_dir = Dune_rules.Lock_dir.get_exn context_name in
           print_endline
             (sprintf
                "%s"
                (Dune_pkg.Lock_dir.Repositories.to_dyn lock_dir.repos |> Dyn.to_string));
           ()))
    in
    match result with
    | Error `Already_reported -> raise Dune_util.Report_error.Already_reported
    | Ok () -> ())
;;

let info =
  let doc = "Print info to help build the current project without internet access." in
  Cmd.info "offline-info" ~doc
;;

let command = Cmd.v info term
