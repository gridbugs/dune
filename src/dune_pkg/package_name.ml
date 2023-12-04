open! Stdune
include Dune_lang.Package_name

let of_opam_package_name opam_package_name =
  OpamPackage.Name.to_string opam_package_name |> of_string
;;

let to_opam_package_name t =
  if not (is_opam_compatible t)
  then
    (* TODO include the loc in this error *)
    User_error.raise
      [ Pp.textf "Package name %S is not a valid opam package name." (to_string t)
      ; Opam_compatible.description_of_valid_string
      ];
  to_string t |> OpamPackage.Name.of_string
;;
