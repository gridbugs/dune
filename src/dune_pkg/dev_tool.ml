open! Import

type t =
  | Ocamlformat
  | Ocamllsp

let all = [ Ocamlformat; Ocamllsp ]

let equal a b =
  match a, b with
  | Ocamlformat, Ocamlformat -> true
  | Ocamllsp, Ocamllsp -> true
  | _ -> false
;;

let package_name = function
  | Ocamlformat -> Package_name.of_string "ocamlformat"
  | Ocamllsp -> Package_name.of_string "ocaml-lsp-server"
;;

let of_package_name package_name =
  match Package_name.to_string package_name with
  | "ocamlformat" -> Ocamlformat
  | "ocaml-lsp-server" -> Ocamllsp
  | other -> User_error.raise [ Pp.textf "No such dev tool: %s" other ]
;;

let exe_name = function
  | Ocamlformat -> "ocamlformat"
  | Ocamllsp -> "ocamllsp"
;;

let exe_path_components_within_package t =
  match t with
  | Ocamlformat -> [ "bin"; exe_name t ]
  | Ocamllsp -> [ "bin"; exe_name t ]
;;
