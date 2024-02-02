open! Stdune

(* Decode a [String_with_vars.t] using variables from the lockfile language.
   This is necessary so that opam variables like "os" and "arch" may be used
   here. *)
let decode_string_with_pkg_vars =
  String_with_vars.decode_manually (fun _env pform ->
    let env =
      Pform.Env.pkg (Dune_sexp.Syntax.greatest_supported_version_exn Pkg.syntax)
    in
    Pform.Env.parse env pform)
;;

module Version_spec = struct
  type t =
    { relop : Relop.t
    ; value : String_with_vars.t
    }

  let to_dyn { relop; value } =
    Dyn.record [ "relop", Relop.to_dyn relop; "vaue", String_with_vars.to_dyn value ]
  ;;

  let encode { relop; value } =
    Dune_sexp.List [ Relop.encode relop; String_with_vars.encode value ]
  ;;

  let decode =
    let open Dune_sexp.Decoder in
    enter
      (let+ relop = Relop.decode
       and+ value = decode_string_with_pkg_vars in
       { relop; value })
  ;;

  let equal { relop; value } t =
    Relop.equal relop t.relop && String_with_vars.equal value t.value
  ;;
end

module Blang = struct
  type t = (Version_spec.t, String_with_vars.t) Blang.Ast.t

  let to_dyn = Blang.Ast.to_dyn Version_spec.to_dyn String_with_vars.to_dyn
  let encode = Blang.Ast.encode Version_spec.encode String_with_vars.encode
  let decode = Blang.Ast.decode Version_spec.decode decode_string_with_pkg_vars
  let equal = Blang.Ast.equal Version_spec.equal String_with_vars.equal
end

module Dependency = struct
  type t =
    { package_name : Package_name.t
    ; constraint_ : Blang.t option
    }

  let to_dyn { package_name; constraint_ } =
    Dyn.record
      [ "package_name", Package_name.to_dyn package_name
      ; "constraint_", Dyn.option Blang.to_dyn constraint_
      ]
  ;;

  let decode =
    let open Dune_sexp.Decoder in
    (let+ package_name = Package_name.decode in
     { package_name; constraint_ = None })
    <|> enter
          (let+ package_name = Package_name.decode
           and+ constraint_ = Blang.decode in
           { package_name; constraint_ = Some constraint_ })
  ;;

  let encode { package_name; constraint_ } =
    match constraint_ with
    | None -> Package_name.encode package_name
    | Some constraint_ ->
      Dune_sexp.List [ Package_name.encode package_name; Blang.encode constraint_ ]
  ;;

  let equal { package_name; constraint_ } t =
    Package_name.equal package_name t.package_name
    && Option.equal Blang.equal constraint_ t.constraint_
  ;;
end

type t =
  | Dependency of Dependency.t
  | All of t list
  | Any of t list

let rec to_dyn = function
  | Dependency dependency -> Dyn.variant "Dependency" [ Dependency.to_dyn dependency ]
  | All ts -> Dyn.variant "All" [ Dyn.list to_dyn ts ]
  | Any ts -> Dyn.variant "Any" [ Dyn.list to_dyn ts ]
;;

let decode =
  let open Dune_sexp.Decoder in
  fix
  @@ fun decode ->
  (let+ dependency = Dependency.decode in
   Dependency dependency)
  <|> enter
        (let+ () = keyword "all"
         and+ ts = repeat decode in
         All ts)
  <|> enter
        (let+ () = keyword "any"
         and+ ts = repeat decode in
         Any ts)
;;

let rec encode t =
  let open Dune_sexp.Encoder in
  match t with
  | Dependency dependency -> Dependency.encode dependency
  | All ts -> Dune_sexp.List (string "all" :: List.map ~f:encode ts)
  | Any ts -> Dune_sexp.List (string "any" :: List.map ~f:encode ts)
;;

let rec equal a b =
  match a, b with
  | Dependency a, Dependency b -> Dependency.equal a b
  | All a, All b -> List.equal equal a b
  | Any a, Any b -> List.equal equal a b
  | _ -> false
;;
