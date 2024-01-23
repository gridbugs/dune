open! Stdune

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
