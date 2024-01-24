open Stdune
open Dune_sexp

type ('expr, 'string) ast =
  | Const of bool
  | Not of ('expr, 'string) ast
  | Expr of 'expr
  | And of ('expr, 'string) ast list
  | Or of ('expr, 'string) ast list
  | Compare of Relop.t * 'string * 'string

module Ast = struct
  type ('expr, 'string) t = ('expr, 'string) ast

  let true_ = Const true
  let false_ = Const false

  let rec equal equal_expr equal_string t1 t2 =
    match t1, t2 with
    | Const b1, Const b2 -> Bool.equal b1 b2
    | Not t1, Not t2 -> equal equal_expr equal_string t1 t2
    | Expr x1, Expr x2 -> equal_expr x1 x2
    | And tl1, And tl2 | Or tl1, Or tl2 ->
      List.equal (equal equal_expr equal_string) tl1 tl2
    | Compare (op1, x1, y1), Compare (op2, x2, y2) ->
      Relop.equal op1 op2 && equal_string x1 x2 && equal_string y1 y2
    | (Const _ | Not _ | Expr _ | And _ | Or _ | Compare _), _ -> false
  ;;

  let rec to_dyn expr_to_dyn string_to_dyn =
    let open Dyn in
    function
    | Const b -> variant "Const" [ bool b ]
    | Not t -> variant "Not" [ to_dyn expr_to_dyn string_to_dyn t ]
    | Expr e -> variant "Expr" [ expr_to_dyn e ]
    | And t -> variant "And" (List.map ~f:(to_dyn expr_to_dyn string_to_dyn) t)
    | Or t -> variant "Or" (List.map ~f:(to_dyn expr_to_dyn string_to_dyn) t)
    | Compare (o, s1, s2) ->
      variant "Compare" [ Relop.to_dyn o; string_to_dyn s1; string_to_dyn s2 ]
  ;;

  let decode decode_expr decode_string =
    let open Decoder in
    let ops =
      List.map Relop.map ~f:(fun (name, op) ->
        ( name
        , let+ x = decode_string
          and+ y = decode_string in
          Compare (op, x, y) ))
    in
    let decode =
      fix (fun t ->
        let decode_term =
          sum
            ~force_parens:true
            (("or", repeat t >>| fun x -> Or x)
             :: ("and", repeat t >>| fun x -> And x)
             :: ("not", Syntax.since Stanza.syntax (3, 2) >>> t >>| fun x -> Not x)
             :: ops)
        in
        decode_term
        <|> let+ v = decode_expr in
            Expr v)
    in
    let+ () = Syntax.since Stanza.syntax (1, 1)
    and+ decode = decode in
    decode
  ;;

  let rec encode encode_expr encode_string t =
    let open Encoder in
    match t with
    | Const true -> string "true"
    | Const false -> string "false"
    | Not t -> List [ string "not"; encode encode_expr encode_string t ]
    | Expr e -> encode_expr e
    | And ts -> List (string "and" :: List.map ts ~f:(encode encode_expr encode_string))
    | Or ts -> List (string "or" :: List.map ts ~f:(encode encode_expr encode_string))
    | Compare (o, s1, s2) -> List [ Relop.encode o; encode_string s1; encode_string s2 ]
  ;;
end

type t = (String_with_vars.t, String_with_vars.t) ast

let true_ = Ast.true_
let false_ = Ast.false_
let to_dyn = Ast.to_dyn String_with_vars.to_dyn String_with_vars.to_dyn
let decode = Ast.decode String_with_vars.decode String_with_vars.decode
let encode = Ast.encode String_with_vars.encode String_with_vars.encode
let equal = Ast.equal String_with_vars.equal String_with_vars.equal
