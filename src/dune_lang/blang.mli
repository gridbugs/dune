open Dune_sexp

(* Note that this type is defined separately from [_ Ast.t] so that its
   constructors are scoped within the [Blang] module, allowing us to construct
   and pattern-match on them without needing to refer to [Blang.Ast]. *)
type ('expr, 'string) ast =
  | Const of bool
  | Not of ('expr, 'string) ast
  | Expr of 'expr
  | And of ('expr, 'string) ast list
  | Or of ('expr, 'string) ast list
  | Compare of Relop.t * 'string * 'string

type t = (String_with_vars.t, String_with_vars.t) ast

val true_ : t
val false_ : t
val to_dyn : t -> Dyn.t
val decode : t Decoder.t
val encode : t Encoder.t
val equal : t -> t -> bool

module Ast : sig
  type ('expr, 'string) t = ('expr, 'string) ast

  val true_ : ('expr, 'string) t
  val false_ : ('expr, 'string) t
  val to_dyn : 'expr Dyn.builder -> 'string Dyn.builder -> ('expr, 'string) t -> Dyn.t

  (** The [override_decode_bare_literal] argument is an alternative parser that
      if provided, will be used to parse string literals for the [Expr _]
      constructor. This is intended to prevent infinite recursion when parsing
      blangs whose ['string] type is another DSL which is mutually recursive
      with blang (e.g. slang). *)
  val decode : 'expr Decoder.t -> 'string Decoder.t -> ('expr, 'string) t Decoder.t

  val encode : 'expr Encoder.t -> 'string Encoder.t -> ('expr, 'string) t Encoder.t

  val equal
    :  ('expr -> 'expr -> bool)
    -> ('string -> 'string -> bool)
    -> ('expr, 'string) t
    -> ('expr, 'string) t
    -> bool
end
