open Import

type target_type =
  | File
  | Directory

(** List of all buildable direct targets. This does not include files and
    directories produced under a directory target.

    If argument is [None], load the root, otherwise only load targets from the
    nearest subdirectory. *)
val all_direct_targets : Path.Source.t option -> target_type Path.Build.Map.t Memo.t

val interpret_targets
  :  Workspace_root.t
  -> Dune_config.t
  -> Dune_rules.Main.build_system
  -> Arg.Dep.t list
  -> unit Dune_engine.Action_builder.t

val expand_path_from_root
  :  Workspace_root.t
  -> Dune_rules.Super_context.t
  -> Dune_lang.String_with_vars.t
  -> string Dune_engine.Action_builder.t

val resolve_target_aliases
  :  Workspace_root.t
  -> targets:Dune_lang.Dep_conf.t list
  -> contexts:Context.t list
  -> (Alias.t, 'a Pp.t list) result list
