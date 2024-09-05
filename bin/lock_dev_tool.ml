open Dune_config
open Import

let enabled =
  Config.make_toggle ~name:"lock_dev_tool" ~default:Dune_rules.Setup.lock_dev_tool
;;

let is_enabled =
  lazy
    (match Config.get enabled with
     | `Enabled -> true
     | `Disabled -> false)
;;

(* The solver satisfies dependencies for local packages, but dev tools
   are not local packages. As a workaround, create an empty local package
   which depends on the dev tool package. *)
let make_local_package_wrapping_dev_tool ~dev_tool ~dev_tool_version ~extra_dependencies
  : Dune_pkg.Local_package.t
  =
  let dev_tool_pkg_name = Dune_pkg.Dev_tool.package_name dev_tool in
  let dependency =
    let open Dune_lang in
    let open Package_dependency in
    let constraint_ =
      Option.map dev_tool_version ~f:(fun version ->
        Package_constraint.Uop
          ( Relop.Eq
          , Package_constraint.Value.String_literal (Package_version.to_string version) ))
    in
    { name = dev_tool_pkg_name; constraint_ }
  in
  let local_package_name =
    Package_name.of_string (Package_name.to_string dev_tool_pkg_name ^ "_dev_tool_wrapper")
  in
  { Dune_pkg.Local_package.name = local_package_name
  ; version = None
  ; dependencies = dependency :: extra_dependencies
  ; conflicts = []
  ; depopts = []
  ; pins = Package_name.Map.empty
  ; conflict_class = []
  ; loc = Loc.none
  }
;;

let solve ~local_packages ~lock_dirs =
  let open Fiber.O in
  let* solver_env_from_current_system =
    Dune_pkg.Sys_poll.make ~path:(Env_path.path Stdune.Env.initial)
    |> Dune_pkg.Sys_poll.solver_env_from_current_system
    >>| Option.some
  and* workspace =
    Memo.run
    @@
    let open Memo.O in
    let+ workspace = Workspace.workspace () in
    workspace
  in
  Lock.solve
    workspace
    ~local_packages
    ~project_sources:Dune_pkg.Pin_stanza.DB.empty
    ~solver_env_from_current_system
    ~version_preference:None
    ~lock_dirs
;;

let lock_dev_tool dev_tool version ~extra_dependencies ~force_regenerate =
  let dev_tool_lock_dir = Dune_pkg.Lock_dir.dev_tool_lock_dir_path dev_tool in
  if force_regenerate || not (Path.exists @@ Path.source dev_tool_lock_dir)
  then (
    let local_pkg =
      make_local_package_wrapping_dev_tool
        ~dev_tool
        ~dev_tool_version:version
        ~extra_dependencies
    in
    let local_packages = Package_name.Map.singleton local_pkg.name local_pkg in
    solve ~local_packages ~lock_dirs:[ dev_tool_lock_dir ])
  else Fiber.return ()
;;

let lock_ocamlformat () =
  let version = Dune_pkg.Ocamlformat.version_of_current_project's_ocamlformat_config () in
  lock_dev_tool Ocamlformat version ~extra_dependencies:[] ~force_regenerate:false
;;

let lock_ocamllsp ~ocaml_compiler_version =
  let compiler_package_name = Package_name.of_string "ocaml" in
  let compiler_dependency =
    let open Dune_lang in
    let constraint_ =
      Some
        (Package_constraint.Uop
           (Eq, String_literal (Package_version.to_string ocaml_compiler_version)))
    in
    { Package_dependency.name = compiler_package_name; constraint_ }
  in
  let force_regenerate =
    (* Regenerate the lockdir unless the version of the ocaml compiler
       currently in the lockdir is the same as the one passed in. This
       means that when a user updates the version of the compiler in
       their dune-project, or updates their opam repo and generates their
       lockdir to contain a later version of the compiler, that ocamllsp
       is recompiled with the new compiler. This is necessary because
       ocamllsp only works if it was compiled with the same version of
       the compiler as was used to compile the code being analyzed. *)
    let dev_tool_lock_dir = Dune_pkg.Lock_dir.dev_tool_lock_dir_path Ocamllsp in
    match Dune_pkg.Lock_dir.read_disk dev_tool_lock_dir with
    | Error _ -> true
    | Ok { packages; _ } ->
      (match Package_name.Map.find packages compiler_package_name with
       | None -> true
       | Some { info; _ } ->
         (match Package_version.equal info.version ocaml_compiler_version with
          | true -> false
          | false ->
            Console.print_user_message
              (User_message.make
                 [ Pp.textf
                     "The version of the compiler package (%S) in this project's lockdir \
                      has changed to %s (formerly the compiler version was %s). The \
                      dev-tool %S will be re-locked and rebuilt with this version of the \
                      compiler."
                     (Package_name.to_string compiler_package_name)
                     (Package_version.to_string ocaml_compiler_version)
                     (Package_version.to_string info.version)
                     (Dune_pkg.Dev_tool.package_name Ocamllsp |> Package_name.to_string)
                 ]);
            true))
  in
  lock_dev_tool
    Ocamllsp
    None
    ~extra_dependencies:[ compiler_dependency ]
    ~force_regenerate
;;
