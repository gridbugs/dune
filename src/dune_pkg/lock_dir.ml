open Import

module Pkg_info = struct
  type t =
    { name : Package_name.t
    ; version : Package_version.t
    ; dev : bool
    ; source : Source.t option
    ; extra_sources : (Path.Local.t * Source.t) list
    }

  let equal { name; version; dev; source; extra_sources } t =
    Package_name.equal name t.name
    && Package_version.equal version t.version
    && Bool.equal dev t.dev
    && Option.equal Source.equal source t.source
    && List.equal
         (Tuple.T2.equal Path.Local.equal Source.equal)
         extra_sources
         t.extra_sources
  ;;

  let remove_locs t =
    { t with
      source = Option.map ~f:Source.remove_locs t.source
    ; extra_sources =
        List.map t.extra_sources ~f:(fun (local, source) ->
          local, Source.remove_locs source)
    }
  ;;

  let to_dyn { name; version; dev; source; extra_sources } =
    Dyn.record
      [ "name", Package_name.to_dyn name
      ; "version", Package_version.to_dyn version
      ; "dev", Dyn.bool dev
      ; "source", Dyn.option Source.to_dyn source
      ; "extra_sources", Dyn.list (Dyn.pair Path.Local.to_dyn Source.to_dyn) extra_sources
      ]
  ;;

  let default_version = Package_version.of_string "dev"

  let variables t =
    let module Variable = OpamVariable in
    Package_variable_name.Map.of_list_exn
      [ Package_variable_name.name, Variable.S (Package_name.to_string t.name)
      ; Package_variable_name.version, S (Package_version.to_string t.version)
      ; Package_variable_name.dev, B t.dev
      ]
  ;;
end

module Build_command = struct
  type t =
    | Action of Action.t
    | Dune

  let equal x y =
    match x, y with
    | Dune, Dune -> true
    | Action x, Action y -> Action.equal x y
    | _, _ -> false
  ;;

  let remove_locs = function
    | Dune -> Dune
    | Action a -> Action (Action.remove_locs a)
  ;;

  let to_dyn = function
    | Dune -> Dyn.variant "Dune" []
    | Action a -> Dyn.variant "Action" [ Action.to_dyn a ]
  ;;

  module Fields = struct
    let dune = "dune"
    let build = "build"
  end

  let encode t =
    let open Encoder in
    match t with
    | None -> field_o Fields.build Encoder.unit None
    | Some Dune -> field_b Fields.dune true
    | Some (Action a) -> field Fields.build Action.encode a
  ;;

  let decode =
    let open Decoder in
    fields_mutually_exclusive
      ~default:None
      [ ( Fields.build
        , let+ pkg = Action.decode_pkg in
          Some (Action pkg) )
      ; ( Fields.dune
        , let+ () = return () in
          Some Dune )
      ]
  ;;
end

module Pkg = struct
  type t =
    { build_command : Build_command.t option
    ; install_command : Action.t option
    ; depends : (Loc.t * Package_name.t) list
    ; depexts : string list
    ; info : Pkg_info.t
    ; exported_env : String_with_vars.t Action.Env_update.t list
    }

  let equal { build_command; install_command; depends; depexts; info; exported_env } t =
    Option.equal Build_command.equal build_command t.build_command
    (* CR-rgrinberg: why do we ignore locations? *)
    && Option.equal Action.equal_no_locs install_command t.install_command
    && List.equal (Tuple.T2.equal Loc.equal Package_name.equal) depends t.depends
    && List.equal String.equal depexts t.depexts
    && Pkg_info.equal info t.info
    && List.equal
         (Action.Env_update.equal String_with_vars.equal)
         exported_env
         t.exported_env
  ;;

  let remove_locs { build_command; install_command; depends; depexts; info; exported_env }
    =
    { info = Pkg_info.remove_locs info
    ; exported_env =
        List.map exported_env ~f:(Action.Env_update.map ~f:String_with_vars.remove_locs)
    ; depends = List.map depends ~f:(fun (_, pkg) -> Loc.none, pkg)
    ; depexts
    ; build_command = Option.map build_command ~f:Build_command.remove_locs
    ; install_command = Option.map install_command ~f:Action.remove_locs
    }
  ;;

  let to_dyn { build_command; install_command; depends; depexts; info; exported_env } =
    Dyn.record
      [ "build_command", Dyn.option Build_command.to_dyn build_command
      ; "install_command", Dyn.option Action.to_dyn install_command
      ; "depends", Dyn.list (Dyn.pair Loc.to_dyn_hum Package_name.to_dyn) depends
      ; "depexts", Dyn.list String.to_dyn depexts
      ; "info", Pkg_info.to_dyn info
      ; ( "exported_env"
        , Dyn.list (Action.Env_update.to_dyn String_with_vars.to_dyn) exported_env )
      ]
  ;;

  let compute_missing_checksum t ~pinned =
    let open Fiber.O in
    let+ source =
      match t.info.source with
      | None -> Fiber.return None
      | Some source ->
        Source.compute_missing_checksum source t.info.name ~pinned >>| Option.some
    in
    { t with info = { t.info with source } }
  ;;

  module Fields = struct
    let name = "name"
    let version = "version"
    let install = "install"
    let depends = "depends"
    let depexts = "depexts"
    let source = "source"
    let dev = "dev"
    let exported_env = "exported_env"
    let extra_sources = "extra_sources"
  end

  let decode =
    let open Decoder in
    enter
    @@ fields
    @@ let+ name_parsed = field_o Fields.name Package_name.decode
       and+ version = field Fields.version Package_version.decode
       and+ install_command = field_o Fields.install Action.decode_pkg
       and+ build_command = Build_command.decode
       and+ depends =
         field ~default:[] Fields.depends (repeat (located Package_name.decode))
       and+ depexts = field ~default:[] Fields.depexts (repeat string)
       and+ source = field_o Fields.source Source.decode
       and+ dev = field_b Fields.dev
       and+ exported_env =
         field Fields.exported_env ~default:[] (repeat Action.Env_update.decode)
       and+ extra_sources =
         field
           Fields.extra_sources
           ~default:[]
           (repeat (pair (plain_string Path.Local.parse_string_exn) Source.decode))
       in
       fun ~lock_dir ~name_external ->
         let name =
           match name_parsed, name_external with
           | Some parsed, Some external_ ->
             assert (Package_name.equal parsed external_);
             external_
           | Some name, None | None, Some name -> name
           | None, None -> Code_error.raise "Package is missing name" []
         in
         let info =
           let make_source f =
             Path.source lock_dir
             |> Path.to_absolute_filename
             |> Path.External.of_string
             |> f
           in
           let source = Option.map source ~f:make_source in
           let extra_sources =
             List.map extra_sources ~f:(fun (path, source) -> path, make_source source)
           in
           { Pkg_info.name; version; dev; source; extra_sources }
         in
         { build_command; depends; depexts; install_command; info; exported_env }
  ;;

  let encode_extra_source (local, source) : Dune_sexp.t =
    List
      [ Dune_sexp.atom_or_quoted_string (Path.Local.to_string local)
      ; Source.encode source
      ]
  ;;

  let encode
    ~include_name
    { build_command
    ; install_command
    ; depends
    ; depexts
    ; info = { Pkg_info.name; extra_sources; version; dev; source }
    ; exported_env
    }
    =
    let open Encoder in
    record_fields
      ((if include_name then [ field Fields.name Package_name.encode name ] else [])
       @ [ field Fields.version Package_version.encode version
         ; field_o Fields.install Action.encode install_command
         ; Build_command.encode build_command
         ; field_l Fields.depends Package_name.encode (List.map depends ~f:snd)
         ; field_l Fields.depexts string depexts
         ; field_o Fields.source Source.encode source
         ; field_b Fields.dev dev
         ; field_l Fields.exported_env Action.Env_update.encode exported_env
         ; field_l Fields.extra_sources encode_extra_source extra_sources
         ])
  ;;
end

module Repositories = struct
  type t =
    { complete : bool
    ; used : Opam_repo.Serializable.t list option
    }

  let default = { complete = false; used = None }

  let equal { complete; used } t =
    Bool.equal complete t.complete
    && Option.equal (List.equal Opam_repo.Serializable.equal) used t.used
  ;;

  let to_dyn { complete; used } =
    Dyn.record
      [ "complete", Dyn.bool complete
      ; "used", Dyn.option (Dyn.list Opam_repo.Serializable.to_dyn) used
      ]
  ;;

  let encode_used used =
    let open Encoder in
    List.map ~f:(fun repo -> list sexp @@ Opam_repo.Serializable.encode repo) used
  ;;

  let encode { complete; used } =
    let open Encoder in
    let base = list sexp [ string "complete"; bool complete ] in
    [ base ]
    @
    match used with
    | None -> []
    | Some [] -> [ list sexp [ string "used" ] ]
    | Some used -> [ list sexp (string "used" :: encode_used used) ]
  ;;

  let decode =
    let open Decoder in
    fields
      (let+ complete = field "complete" bool
       and+ used = field_o "used" (repeat (enter Opam_repo.Serializable.decode)) in
       { complete; used })
  ;;
end

module Solution = struct
  type t =
    { packages : Pkg.t Package_name.Map.t
    ; expanded_solver_variable_bindings : Solver_stats.Expanded_variable_bindings.t
    }

  let empty =
    { packages = Package_name.Map.empty
    ; expanded_solver_variable_bindings = Solver_stats.Expanded_variable_bindings.empty
    }
  ;;

  let equal { packages; expanded_solver_variable_bindings } t =
    Package_name.Map.equal packages t.packages ~equal:Pkg.equal
    && Solver_stats.Expanded_variable_bindings.equal
         expanded_solver_variable_bindings
         t.expanded_solver_variable_bindings
  ;;

  let to_dyn { packages; expanded_solver_variable_bindings } =
    Dyn.record
      [ "packages", Package_name.Map.to_dyn Pkg.to_dyn packages
      ; ( "expanded_solver_variable_bindings"
        , Solver_stats.Expanded_variable_bindings.to_dyn expanded_solver_variable_bindings
        )
      ]
  ;;

  let encode { packages; expanded_solver_variable_bindings } =
    let open Encoder in
    let packages =
      Package_name.Map.values packages
      |> List.map ~f:(fun pkg -> Dune_sexp.List (Pkg.encode ~include_name:true pkg))
    in
    [ Dune_sexp.List
        (string "expanded_solver_variable_bindings"
         :: Solver_stats.Expanded_variable_bindings.encode
              expanded_solver_variable_bindings)
    ; Dune_sexp.List (string "packages" :: packages)
    ]
  ;;

  let decode =
    let open Decoder in
    enter
    @@ fields
         (let+ expanded_solver_variable_bindings =
            field
              "expanded_solver_variable_bindings"
              ~default:Solver_stats.Expanded_variable_bindings.empty
              Solver_stats.Expanded_variable_bindings.decode
          and+ packages = field "packages" ~default:[] (repeat Pkg.decode) in
          fun ~lock_dir ->
            let packages =
              Package_name.Map.of_list_map_exn packages ~f:(fun make_package ->
                let package : Pkg.t = make_package ~lock_dir ~name_external:None in
                package.info.name, package)
            in
            { expanded_solver_variable_bindings; packages })
  ;;

  let transitive_dependency_closure t start =
    let missing_packages =
      let all_packages_in_lock_dir = Package_name.Set.of_keys t.packages in
      Package_name.Set.diff start all_packages_in_lock_dir
    in
    match Package_name.Set.is_empty missing_packages with
    | false -> Error (`Missing_packages missing_packages)
    | true ->
      let to_visit = Queue.create () in
      let push_set = Package_name.Set.iter ~f:(Queue.push to_visit) in
      push_set start;
      let rec loop seen =
        match Queue.pop to_visit with
        | None -> seen
        | Some node ->
          let unseen_deps =
            (* Note that the call to find_exn won't raise because [t] guarantees
               that its map of dependencies is closed under "depends on". *)
            Package_name.Set.(
              diff
                (of_list_map (Package_name.Map.find_exn t.packages node).depends ~f:snd)
                seen)
          in
          push_set unseen_deps;
          loop (Package_name.Set.union seen unseen_deps)
      in
      Ok (loop start)
  ;;

  let compute_missing_checksums t ~pinned_packages =
    let open Fiber.O in
    let+ packages =
      Package_name.Map.to_list t.packages
      |> Fiber.parallel_map ~f:(fun (name, pkg) ->
        let pinned = Package_name.Set.mem pinned_packages name in
        let+ pkg = Pkg.compute_missing_checksum pkg ~pinned in
        name, pkg)
      >>| Package_name.Map.of_list_exn
    in
    { t with packages }
  ;;

  let remove_locs t =
    { t with packages = Package_name.Map.map t.packages ~f:Pkg.remove_locs }
  ;;

  let platform_string { expanded_solver_variable_bindings; _ } =
    let get name =
      Solver_stats.Expanded_variable_bindings.get expanded_solver_variable_bindings name
      |> Option.value_exn
      |> Variable_value.to_string
    in
    sprintf "%s-%s" (get Package_variable_name.arch) (get Package_variable_name.os)
  ;;
end

type t =
  { version : Syntax.Version.t
  ; dependency_hash : (Loc.t * Local_package.Dependency_hash.t) option
  ; ocaml : (Loc.t * Package_name.t) option
  ; repos : Repositories.t
  ; solutions : Solution.t list
  }

let remove_locs t =
  { t with
    solutions = List.map t.solutions ~f:Solution.remove_locs
  ; ocaml = Option.map t.ocaml ~f:(fun (_, ocaml) -> Loc.none, ocaml)
  }
;;

let equal { version; dependency_hash; ocaml; repos; solutions } t =
  Syntax.Version.equal version t.version
  && Option.equal
       (Tuple.T2.equal Loc.equal Local_package.Dependency_hash.equal)
       dependency_hash
       t.dependency_hash
  && Option.equal (Tuple.T2.equal Loc.equal Package_name.equal) ocaml t.ocaml
  && Repositories.equal repos t.repos
  && List.equal Solution.equal solutions t.solutions
;;

let to_dyn { version; dependency_hash; ocaml; repos; solutions } =
  Dyn.record
    [ "version", Syntax.Version.to_dyn version
    ; ( "dependency_hash"
      , Dyn.option
          (Tuple.T2.to_dyn Loc.to_dyn_hum Local_package.Dependency_hash.to_dyn)
          dependency_hash )
    ; "ocaml", Dyn.option (Tuple.T2.to_dyn Loc.to_dyn_hum Package_name.to_dyn) ocaml
    ; "repos", Repositories.to_dyn repos
    ; "solutions", Dyn.list Solution.to_dyn solutions
    ]
;;

type missing_dependency =
  { dependant_package : Pkg.t
  ; dependency : Package_name.t
  ; loc : Loc.t
  }

(* [validate_packages packages] returns
   [Error (`Missing_dependencies missing_dependencies)] where
   [missing_dependencies] is a non-empty list with an element for each package
   dependency which doesn't have a corresponding entry in [packages]. *)
let validate_packages packages =
  let missing_dependencies =
    Package_name.Map.values packages
    |> List.concat_map ~f:(fun (dependant_package : Pkg.t) ->
      List.filter_map dependant_package.depends ~f:(fun (loc, dependency) ->
        (* CR-someday rgrinberg: do we need the dune check? aren't
           we supposed to filter these upfront? *)
        if Package_name.Map.mem packages dependency
           || Package_name.equal dependency Dune_dep.name
        then None
        else Some { dependant_package; dependency; loc }))
  in
  if List.is_empty missing_dependencies
  then Ok ()
  else Error (`Missing_dependencies missing_dependencies)
;;

let create_latest_version solutions ~local_packages ~ocaml ~repos =
  List.iter solutions ~f:(fun (solution : Solution.t) ->
    match validate_packages solution.packages with
    | Ok () -> ()
    | Error (`Missing_dependencies missing_dependencies) ->
      List.map missing_dependencies ~f:(fun { dependant_package; dependency; loc = _ } ->
        ( "missing dependency"
        , Dyn.record
            [ "missing package", Package_name.to_dyn dependency
            ; "dependency of", Package_name.to_dyn dependant_package.info.name
            ] ))
      |> Code_error.raise "Invalid package table");
  let version = Syntax.greatest_supported_version_exn Dune_lang.Pkg.syntax in
  let dependency_hash =
    local_packages
    |> Local_package.For_solver.non_local_dependencies
    |> Local_package.Dependency_hash.of_dependency_formula
    |> Option.map ~f:(fun dependency_hash -> Loc.none, dependency_hash)
  in
  let complete, used =
    match repos with
    | None -> true, None
    | Some repos ->
      let used = List.filter_map repos ~f:Opam_repo.serializable in
      let complete = Int.equal (List.length repos) (List.length used) in
      complete, Some used
  in
  { version; dependency_hash; ocaml; repos = { complete; used }; solutions }
;;

let dev_tools_path = Path.Source.(relative root "dev-tools.locks")

let dev_tool_lock_dir_path dev_tool =
  Path.Source.relative
    dev_tools_path
    (Package_name.to_string (Dev_tool.package_name dev_tool))
;;

let default_path = Path.Source.(relative root "dune.lock")
let metadata_filename = "lock.dune"

module Metadata = Dune_sexp.Versioned_file.Make (Unit)

let () = Metadata.Lang.register Dune_lang.Pkg.syntax ()

let single_solution t =
  match t.solutions with
  | [ solution ] -> solution
  | _ -> failwith "lockdirs can only be used when there is a single solution"
;;

let encode_metadata { version; dependency_hash; ocaml; repos; solutions } =
  let open Encoder in
  let base =
    list
      sexp
      [ string "lang"
      ; string (Syntax.name Dune_lang.Pkg.syntax)
      ; Syntax.Version.encode version
      ]
  in
  [ base ]
  @ (match dependency_hash with
     | None -> []
     | Some (_loc, dependency_hash) ->
       [ list
           sexp
           [ string "dependency_hash"
           ; Local_package.Dependency_hash.encode dependency_hash
           ]
       ])
  @ (match ocaml with
     | None -> []
     | Some ocaml -> [ list sexp [ string "ocaml"; Package_name.encode (snd ocaml) ] ])
  @ [ list sexp (string "repositories" :: Repositories.encode repos) ]
  @
  match solutions with
  | [ solution ] ->
    (* TODO to continue supporting lockdirs, fall back to the original
       behaviour when there is only one solution. *)
    if Solver_stats.Expanded_variable_bindings.is_empty
         solution.expanded_solver_variable_bindings
    then []
    else
      [ list
          sexp
          (string "expanded_solver_variable_bindings"
           :: Solver_stats.Expanded_variable_bindings.encode
                solution.expanded_solver_variable_bindings)
      ]
  | _ -> []
;;

let encode t =
  let open Encoder in
  let metadata = encode_metadata t in
  let solutions =
    List.map t.solutions ~f:(fun solution -> Dune_sexp.List (Solution.encode solution))
  in
  metadata @ [ Dune_sexp.List (string "solutions" :: solutions) ]
;;

let decode =
  let open Decoder in
  fields
    (let+ ocaml = field_o "ocaml" (located Package_name.decode)
     and+ dependency_hash =
       field_o "dependency_hash" (located Local_package.Dependency_hash.decode)
     and+ repos = field "repositories" ~default:Repositories.default Repositories.decode
     and+ expanded_solver_variable_bindings =
       (* TODO this field is currently duplicated between here and each
          solution for backwards compatibility with non-portable lockdirs. *)
       field
         "expanded_solver_variable_bindings"
         ~default:Solver_stats.Expanded_variable_bindings.empty
         Solver_stats.Expanded_variable_bindings.decode
     and+ solutions = field "solutions" ~default:[] (repeat Solution.decode) in
     ocaml, dependency_hash, repos, expanded_solver_variable_bindings, solutions)
;;

module Package_filename = struct
  let file_extension = ".pkg"
  let of_package_name package_name = Package_name.to_string package_name ^ file_extension

  let to_package_name package_filename =
    if String.equal (Filename.extension package_filename) file_extension
    then Ok (Filename.remove_extension package_filename |> Package_name.of_string)
    else Error `Bad_extension
  ;;
end

let file_contents_by_path t =
  (metadata_filename, encode_metadata t)
  :: (Package_name.Map.to_list (single_solution t).packages
      |> List.map ~f:(fun (name, pkg) ->
        Package_filename.of_package_name name, Pkg.encode ~include_name:false pkg))
;;

module Write_disk = struct
  (* Checks whether path refers to a valid lock directory and returns a value
     indicating the status of the lock directory. [Ok _] values indicate that
     it's safe to proceed with regenerating the lock directory. [Error _]
     values indicate that it's unsafe to remove the existing directory and lock
     directory regeneration should not proceed. *)
  let check_existing_lock_dir path =
    match Path.stat path with
    | Ok { st_kind = S_DIR; _ } ->
      let metadata_path = Path.relative path metadata_filename in
      (match Path.stat metadata_path with
       | Ok { st_kind = S_REG; _ } ->
         (match Metadata.load metadata_path ~f:(Fun.const decode) with
          | Ok _unused -> Ok `Is_existing_lock_dir
          | Error exn -> Error (`Failed_to_parse_metadata (metadata_path, exn)))
       | _ -> Error `No_metadata_file)
    | Error (Unix.ENOENT, _, _) -> Ok `Non_existant
    | Error _ -> Error `Unreadable
    | Ok _ -> Error `Not_directory
  ;;

  let raise_user_error_on_check_existance path e =
    let error_reason =
      match e with
      | `Unreadable ->
        Pp.textf "Unable to read lock directory (%s)" (Path.to_string_maybe_quoted path)
      | `Not_directory ->
        Pp.textf
          "Specified lock dir path (%s) is not a directory"
          (Path.to_string_maybe_quoted path)
      | `No_metadata_file ->
        Pp.textf "Specified lock dir lacks metadata file (%s)" metadata_filename
      | `Failed_to_parse_metadata (path, exn) ->
        Pp.concat
          ~sep:Pp.cut
          [ Pp.textf
              "Unable to parse lock directory metadata file (%s):"
              (Path.to_string_maybe_quoted path)
            |> Pp.hovbox
          ; Exn.pp exn |> Pp.hovbox
          ]
        |> Pp.vbox
    in
    User_error.raise
      [ Pp.textf
          "Refusing to regenerate lock directory %s"
          (Path.to_string_maybe_quoted path)
      ; error_reason
      ]
  ;;

  (* Removes the existing lock directory at the specified path if it exists and
     is a valid lock directory. Checks the validity of the existing lockdir (if
     any) and raises if it's invalid before constructing the returned thunk, so
     validation can happen separately from executing the side effect that removes
     the directory. *)
  let safely_remove_lock_dir_if_exists_thunk path =
    match check_existing_lock_dir path with
    | Ok `Non_existant -> Fun.const ()
    | Ok `Is_existing_lock_dir -> fun () -> Path.rm_rf path
    | Error e -> raise_user_error_on_check_existance path e
  ;;

  (* Does the same checks as [safely_remove_lock_dir_if_exists_thunk] but it raises an
     error if the lock dir already exists. [dst] is the new file name *)
  let safely_rename_lock_dir_thunk ~dst src =
    match check_existing_lock_dir src, check_existing_lock_dir dst with
    | Ok `Is_existing_lock_dir, Ok `Non_existant -> fun () -> Path.rename src dst
    | Ok `Non_existant, Ok `Non_existant -> Fun.const ()
    | _, Ok `Is_existing_lock_dir ->
      let error_reason_pp =
        Pp.textf
          "Directory %s already exists: can't rename safely"
          (Path.to_string_maybe_quoted src)
      in
      User_error.raise
        [ Pp.textf
            "Refusing to regenerate lock directory %s"
            (Path.to_string_maybe_quoted src)
        ; error_reason_pp
        ]
    | Error e, _ -> raise_user_error_on_check_existance src e
    | _, Error e -> raise_user_error_on_check_existance dst e
  ;;

  type t = unit -> unit

  let prepare_dir ~lock_dir_path:lock_dir_path_src lock_dir =
    let lock_dir_hidden_src =
      (* The original lockdir path with the lockdir renamed to begin with a ".". *)
      let hidden_basename = sprintf ".%s" (Path.Source.basename lock_dir_path_src) in
      Path.Source.relative (Path.Source.parent_exn lock_dir_path_src) hidden_basename
    in
    let lock_dir_hidden_src = Path.source lock_dir_hidden_src in
    let lock_dir_path_external = Path.source lock_dir_path_src in
    let remove_hidden_dir_if_exists () =
      safely_remove_lock_dir_if_exists_thunk lock_dir_hidden_src ()
    in
    let rename_old_lock_dir_to_hidden =
      safely_rename_lock_dir_thunk ~dst:lock_dir_hidden_src lock_dir_path_external
    in
    let build lock_dir_path =
      let lock_dir_path = Result.ok_exn lock_dir_path in
      file_contents_by_path lock_dir
      |> List.iter ~f:(fun (path_within_lock_dir, contents) ->
        let path = Path.relative lock_dir_path path_within_lock_dir in
        Option.iter (Path.parent path) ~f:Path.mkdir_p;
        let cst =
          List.map contents ~f:(fun sexp ->
            Dune_sexp.Ast.add_loc ~loc:Loc.none sexp |> Dune_sexp.Cst.concrete)
        in
        (* TODO the version should be chosen based on the version of the lock
           directory we're outputting *)
        let pp = Dune_lang.Format.pp_top_sexps ~version:(3, 11) cst in
        Format.asprintf "%a" Pp.to_fmt pp |> Io.write_file path);
      rename_old_lock_dir_to_hidden ();
      safely_rename_lock_dir_thunk ~dst:lock_dir_path_external lock_dir_path ();
      remove_hidden_dir_if_exists ()
    in
    match Path.(parent (source lock_dir_path_src)) with
    | Some parent_dir ->
      fun () ->
        Path.mkdir_p parent_dir;
        Temp.with_temp_dir ~parent_dir ~prefix:"dune" ~suffix:"lock" ~f:build
    | None ->
      User_error.raise
        [ Pp.textf "Temporary directory can't be created by deriving the lock dir path" ]
  ;;

  let prepare_file path lock_dir =
    let csts =
      encode lock_dir
      |> List.map ~f:(fun sexp ->
        Dune_sexp.Ast.add_loc ~loc:Loc.none sexp |> Dune_sexp.Cst.concrete)
    in
    (* TODO the version should be chosen based on the version of the lock
       directory we're outputting *)
    let pp = Dune_lang.Format.pp_top_sexps ~version:(3, 11) csts in
    let file_contents = Format.asprintf "%a" Pp.to_fmt pp in
    fun () -> Io.write_file (Path.source path) file_contents
  ;;

  let prepare ~lock_dir_path ~lock_dir_type lock_dir =
    match lock_dir_type with
    | `Dir -> prepare_dir ~lock_dir_path lock_dir
    | `File -> prepare_file lock_dir_path lock_dir
  ;;

  let commit t = t ()
end

module Make_load (Io : sig
    include Monad.S

    val parallel_map : 'a list -> f:('a -> 'b t) -> 'b list t
    val readdir_with_kinds : Path.Source.t -> (Filename.t * Unix.file_kind) list t
    val with_lexbuf_from_file : Path.Source.t -> f:(Lexing.lexbuf -> 'a) -> 'a t
    val stats_kind : Path.Source.t -> (File_kind.t, Unix_error.Detailed.t) result t
  end) =
struct
  let load_file path =
    let open Io.O in
    let+ ( syntax
         , version
         , dependency_hash
         , ocaml
         , repos
         , _expanded_solver_variable_bindings
           (* when loading files this is taken from the solutions list instead *)
         , solutions )
      =
      Io.with_lexbuf_from_file path ~f:(fun lexbuf ->
        Metadata.parse_contents
          lexbuf
          ~f:(fun { Metadata.Lang.Instance.syntax; data = (); version } ->
            let decode =
              let env = Pform.Env.pkg version in
              String_with_vars.set_decoding_env env decode
              |> Syntax.set Dune_lang.Pkg.syntax (Active version)
              |> Syntax.set
                   Dune_lang.Stanza.syntax
                   (Active Dune_lang.Stanza.latest_version)
            in
            let open Decoder in
            let+ ( ocaml
                 , dependency_hash
                 , repos
                 , expanded_solver_variable_bindings
                 , solutions )
              =
              decode
            in
            ( syntax
            , version
            , dependency_hash
            , ocaml
            , repos
            , expanded_solver_variable_bindings
            , solutions )))
    in
    if String.equal (Syntax.name syntax) (Syntax.name Dune_lang.Pkg.syntax)
    then (
      let solutions =
        List.map solutions ~f:(fun make_solution -> make_solution ~lock_dir:path)
      in
      Ok { version; dependency_hash; ocaml; repos; solutions })
    else
      Error
        (User_error.make
           [ Pp.textf
               "In %s, expected language to be %s, but found %s"
               (Path.Source.to_string path)
               (Syntax.name Dune_lang.Pkg.syntax)
               (Syntax.name syntax)
           ])
  ;;

  let load_metadata metadata_file_path =
    let open Io.O in
    let+ syntax, version, dependency_hash, ocaml, repos, expanded_solver_variable_bindings
      =
      Io.with_lexbuf_from_file metadata_file_path ~f:(fun lexbuf ->
        Metadata.parse_contents
          lexbuf
          ~f:(fun { Metadata.Lang.Instance.syntax; data = (); version } ->
            let open Decoder in
            let+ ( ocaml
                 , dependency_hash
                 , repos
                 , expanded_solver_variable_bindings
                 , _packages )
              =
              decode
            in
            ( syntax
            , version
            , dependency_hash
            , ocaml
            , repos
            , expanded_solver_variable_bindings )))
    in
    if String.equal (Syntax.name syntax) (Syntax.name Dune_lang.Pkg.syntax)
    then version, dependency_hash, ocaml, repos, expanded_solver_variable_bindings
    else
      User_error.raise
        [ Pp.textf
            "In %s, expected language to be %s, but found %s"
            (Path.Source.to_string metadata_file_path)
            (Syntax.name Dune_lang.Pkg.syntax)
            (Syntax.name syntax)
        ]
  ;;

  let load_pkg ~version ~lock_dir_path package_name =
    let open Io.O in
    let pkg_file_path =
      Path.Source.relative lock_dir_path (Package_filename.of_package_name package_name)
    in
    let+ sexp =
      Io.with_lexbuf_from_file pkg_file_path ~f:(Dune_sexp.Parser.parse ~mode:Many)
    in
    let parser =
      let env = Pform.Env.pkg version in
      let decode =
        Syntax.set Dune_lang.Pkg.syntax (Active version) Pkg.decode
        |> Syntax.set Dune_lang.Stanza.syntax (Active Dune_lang.Stanza.latest_version)
      in
      String_with_vars.set_decoding_env env decode
    in
    (Decoder.parse parser Univ_map.empty (List (Loc.none, sexp)))
      ~lock_dir:lock_dir_path
      ~name_external:(Some package_name)
  ;;

  let check_path lock_dir_path =
    let open Io.O in
    Io.stats_kind lock_dir_path
    >>| function
    | Ok S_DIR -> Ok `Dir
    | Ok S_REG -> Ok `File
    | Error (Unix.ENOENT, _, _) ->
      Error
        (User_error.make
           ~hints:
             [ Pp.concat
                 ~sep:Pp.space
                 [ Pp.text "Run"
                 ; User_message.command "dune pkg lock"
                 ; Pp.text "to generate it."
                 ]
               |> Pp.hovbox
             ]
           [ Pp.textf "%s does not exist." (Path.Source.to_string lock_dir_path) ])
    | Error e ->
      Error
        (User_error.make
           [ Pp.textf "%s is not accessible" (Path.Source.to_string lock_dir_path)
           ; Pp.textf "reason: %s" (Unix_error.Detailed.to_string_hum e)
           ])
    | _ ->
      Error
        (User_error.make
           [ Pp.textf
               "%s is not a directory or regular file."
               (Path.Source.to_string lock_dir_path)
           ])
  ;;

  let check_packages packages ~lock_dir_path =
    match validate_packages packages with
    | Ok () -> Ok ()
    | Error (`Missing_dependencies missing_dependencies) ->
      List.iter missing_dependencies ~f:(fun { dependant_package; dependency; loc } ->
        User_message.prerr
          (User_message.make
             ~loc
             [ Pp.textf
                 "The package %S depends on the package %S, but %S does not appear in \
                  the lockdir %s."
                 (Package_name.to_string dependant_package.info.name)
                 (Package_name.to_string dependency)
                 (Package_name.to_string dependency)
                 (Path.Source.to_string_maybe_quoted lock_dir_path)
             ]));
      Error
        (User_error.make
           ~hints:
             [ Pp.concat
                 ~sep:Pp.space
                 [ Pp.text
                     "This could indicate that the lockdir is corrupted. Delete it and \
                      then regenerate it by running:"
                 ; User_message.command "dune pkg lock"
                 ]
             ]
           [ Pp.textf
               "At least one package dependency is itself not present as a package in \
                the lockdir %s."
               (Path.Source.to_string_maybe_quoted lock_dir_path)
           ])
  ;;

  let load_dir lock_dir_path =
    let open Io.O in
    let* version, dependency_hash, ocaml, repos, expanded_solver_variable_bindings =
      load_metadata (Path.Source.relative lock_dir_path metadata_filename)
    in
    let+ packages =
      Io.readdir_with_kinds lock_dir_path
      >>| List.filter_map ~f:(fun (name, (kind : Unix.file_kind)) ->
        match kind with
        | S_REG -> Package_filename.to_package_name name |> Result.to_option
        | _ ->
          (* TODO *)
          None)
      >>= Io.parallel_map ~f:(fun package_name ->
        let+ pkg = load_pkg ~version ~lock_dir_path package_name in
        package_name, pkg)
      >>| Package_name.Map.of_list_exn
    in
    check_packages packages ~lock_dir_path
    |> Result.map ~f:(fun () ->
      let solutions = [ { Solution.packages; expanded_solver_variable_bindings } ] in
      { version; dependency_hash; ocaml; repos; solutions })
  ;;

  let load lock_dir_path =
    let open Io.O in
    let* result = check_path lock_dir_path in
    match result with
    | Error e -> Io.return (Error e)
    | Ok `Dir -> load_dir lock_dir_path
    | Ok `File -> load_file lock_dir_path
  ;;

  let load_exn lock_dir_path =
    let open Io.O in
    load lock_dir_path >>| User_error.ok_exn
  ;;
end

module Load_immediate = Make_load (struct
    include Monad.Id

    let stats_kind file =
      Path.source file |> Path.stat |> Result.map ~f:(fun { Unix.st_kind; _ } -> st_kind)
    ;;

    let parallel_map xs ~f = List.map xs ~f

    let readdir_with_kinds path =
      match Path.readdir_unsorted_with_kinds (Path.source path) with
      | Ok entries -> entries
      | Error e ->
        User_error.raise
          [ Pp.text (Dune_filesystem_stubs.Unix_error.Detailed.to_string_hum e) ]
    ;;

    let with_lexbuf_from_file path ~f = Io.with_lexbuf_from_file (Path.source path) ~f
  end)

let read_disk = Load_immediate.load
let read_disk_exn = Load_immediate.load_exn

let compute_missing_checksums t ~pinned_packages =
  let open Fiber.O in
  let+ solutions =
    Fiber.parallel_map
      t.solutions
      ~f:(Solution.compute_missing_checksums ~pinned_packages)
  in
  { t with solutions }
;;

let choose_solution { solutions; _ } ~os ~arch =
  List.find solutions ~f:(fun solution ->
    let get =
      Solver_stats.Expanded_variable_bindings.get
        solution.expanded_solver_variable_bindings
    in
    match get Package_variable_name.os, get Package_variable_name.arch with
    | Some os_, Some arch_ ->
      String.equal (Variable_value.to_string os_) os
      && String.equal (Variable_value.to_string arch_) arch
    | _ -> false)
;;

let choose_solution_exn t ~os ~arch =
  match choose_solution t ~os ~arch with
  | Some solution -> solution
  | None -> User_error.raise [ Pp.textf "No solution for %s on %s" os arch ]
;;
