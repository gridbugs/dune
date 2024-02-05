open! Stdune
open Import

type deferred_concat = Deferred_concat of Value.t list

type expander =
  String_with_vars.t
  -> dir:Path.t
  -> (Value.t list, [ `Undefined_pkg_var of Dune_lang.Package_variable_name.t ]) result
       Memo.t

val eval_multi_located
  :  Slang.t list
  -> dir:Path.t
  -> f:expander
  -> (Loc.t * deferred_concat) list Memo.t

val eval_blang : Slang.blang -> dir:Path.t -> f:expander -> bool Memo.t
