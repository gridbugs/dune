open! Import
module Pkg_dev_tool = Dune_rules.Pkg_dev_tool

let ocamllsp_exe_path = Path.build @@ Pkg_dev_tool.exe_path Ocamllsp
let ocamllsp_exe_name = Pkg_dev_tool.exe_name Ocamllsp
let compiler_package_name = Package_name.of_string "ocaml"

module Fallback = struct
  module Reason = struct
    type t =
      | Not_in_dune_project
      | No_lock_dir_for_context of Context_name.t
      | No_ocaml_lockfile_in_lock_dir of { lock_dir_path : Path.Source.t }

    let to_string = function
      | Not_in_dune_project -> "you don't appear to be inside a dune project"
      | No_lock_dir_for_context context_name ->
        sprintf
          "the current dune project lacks a lockdir associated with the context %S"
          (Context_name.to_string context_name)
      | No_ocaml_lockfile_in_lock_dir { lock_dir_path } ->
        sprintf
          "the lockdir %S lacks a lockfile for the %S package"
          (Path.Source.to_string lock_dir_path)
          (Package_name.to_string compiler_package_name)
    ;;
  end

  let message verb reason =
    let verb_string =
      match verb with
      | `Run -> "run"
      | `Install -> "install"
    in
    User_message.make
      ([ Pp.textf
           "Unable to %s %s as a dev-tool because %s."
           verb_string
           ocamllsp_exe_name
           (Reason.to_string reason)
       ; Pp.nop
       ; Pp.textf
           "To %s %s as a dev-tool, the following conditions mest be met:"
           verb_string
           ocamllsp_exe_name
       ; Pp.text " - You must be inside a dune project."
       ; Pp.text " - The dune project must have a lockdir."
       ; Pp.textf
           " - The lockdir must contain a lockfile for the package %S."
           (Package_name.to_string compiler_package_name)
       ; Pp.nop
       ; Pp.textf
           "This is because %s must be compiled with the same version of the ocaml \
            compiler as the project it's analyzing, and without a lockfile for the ocaml \
            compiler package (ie. %S) the appropriate version of the compiler to use to \
            compile %s is not known."
           ocamllsp_exe_name
           (Package_name.to_string compiler_package_name)
           ocamllsp_exe_name
       ]
       @
       match verb with
       | `Run ->
         [ Pp.nop
         ; Pp.textf
             "Dune will now attempt to run %s from your %s."
             ocamllsp_exe_name
             Env_path.var
         ; Pp.nop
         ]
       | `Install -> [])
  ;;

  (* Print a message explaining why dune can't run ocamllsp as a
     dev-tool and then attempt to replace the current dune process
     with ocamllsp from the user's PATH. *)
  let run reason env ~args =
    Console.print_user_message (message `Run reason);
    match Bin.which ~path:(Env_path.path env) ocamllsp_exe_name with
    | None ->
      User_error.raise
        [ Pp.concat
            ~sep:Pp.space
            [ Pp.textf "Unable to find %s not in your %s." ocamllsp_exe_name Env_path.var
            ]
        ]
    | Some path ->
      let path_string = Path.to_string path in
      Console.print_user_message
        (User_message.make
           [ Pp.concat
               ~sep:Pp.space
               [ Pp.tag User_message.Style.Success (Pp.textf "Running")
               ; User_message.command (String.concat ~sep:" " (path_string :: args))
               ]
           ]);
      Console.finish ();
      Proc.restore_cwd_and_execve path_string (path_string :: args) ~env
  ;;
end

(* Replace the current dune process with ocamllsp. *)
let run_ocamllsp common ~args =
  let exe_path_string = Path.to_string ocamllsp_exe_path in
  Console.print_user_message
    (Dune_rules.Pkg_build_progress.format_user_message
       ~verb:"Running"
       ~object_:
         (User_message.command (String.concat ~sep:" " (ocamllsp_exe_name :: args))));
  Console.finish ();
  restore_cwd_and_execve common exe_path_string (exe_path_string :: args) Env.initial
;;

let build_ocamllsp common =
  let open Fiber.O in
  let+ result =
    Build_cmd.run_build_system ~common ~request:(fun _build_system ->
      Action_builder.path ocamllsp_exe_path)
  in
  match result with
  | Error `Already_reported -> raise Dune_util.Report_error.Already_reported
  | Ok () -> ()
;;

(* Ocamllsp needs to be compiled with the same version of the ocaml
   compiler as the code it's analyzing, so look up the version of the
   ocaml compiler in the lockdir so it can be added to the constraints
   when solving ocamllsp's lockdir. *)
let locked_ocaml_compiler_version context =
  let open Memo.O in
  let* result = Dune_rules.Lock_dir.get context in
  match result with
  | Error _ -> Memo.return @@ Error (Fallback.Reason.No_lock_dir_for_context context)
  | Ok { packages; _ } ->
    (match Package_name.Map.find packages compiler_package_name with
     | None ->
       let+ lock_dir_path = Dune_rules.Lock_dir.get_path context >>| Option.value_exn in
       Error (Fallback.Reason.No_ocaml_lockfile_in_lock_dir { lock_dir_path })
     | Some pkg -> Memo.return @@ Ok pkg.info.version)
;;

let is_in_dune_project builder =
  Workspace_root.create
    ~default_is_cwd:(Common.Builder.default_root_is_cwd builder)
    ~specified_by_user:(Common.Builder.root builder)
  |> Result.is_ok
;;

let term =
  let+ builder = Common.Builder.term
  and+ install_only =
    Arg.(
      value
      & flag
      & info
          [ "install-only" ]
          ~doc:
            {|Make sure ocamllsp is installed in _build but do not run it. Without this \
             flag, ocamllsp will be built (if necessary) and then run. If this command \
             is being invoked by an editor the editor's LSP client will be unresponsive \
             while ocamllsp is being built. This flag can be used to explicitly tell \
             dune to compile ocamllsp so it can be prepared before running an editor.|})
  and+ args = Arg.(value & pos_all string [] (info [] ~docv:"ARGS")) in
  let context =
    (* Dev tools are only ever built with the default context *)
    Context_name.default
  in
  let which_ocamllsp =
    match is_in_dune_project builder with
    | false -> `Fallback Fallback.Reason.Not_in_dune_project
    | true ->
      let common, config = Common.init builder in
      Scheduler.go ~common ~config (fun () ->
        let open Fiber.O in
        locked_ocaml_compiler_version context
        |> Memo.run
        >>= function
        | Error fallback_reason -> Fiber.return @@ `Fallback fallback_reason
        | Ok ocaml_compiler_version ->
          let* () = Lock_dev_tool.lock_ocamllsp ~ocaml_compiler_version in
          let+ () = build_ocamllsp common in
          `Dev_tool common)
  in
  match install_only with
  | false ->
    (match which_ocamllsp with
     | `Fallback fallback_reason -> Fallback.run fallback_reason Env.initial ~args
     | `Dev_tool common -> run_ocamllsp common ~args)
  | true ->
    (match which_ocamllsp with
     | `Fallback fallback_reason ->
       Console.print_user_message (Fallback.message `Install fallback_reason);
       Console.finish ()
     | `Dev_tool _ -> ())
;;

let info =
  let doc = "Run ocamllsp, installing it if necessary" in
  Cmd.info "ocamllsp" ~doc
;;

let command = Cmd.v info term
