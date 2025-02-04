open Import

type nonrec t =
  { opam_file : OpamFile.OPAM.t
  ; package : OpamPackage.t
  ; loc : Loc.t
  ; dune_build : bool
  }

let dune_build t = t.dune_build
let loc t = t.loc
let package t = t.package
let opam_file t = t.opam_file

let set_url t url =
  let opam_file = OpamFile.OPAM.with_url (OpamFile.URL.create url) t.opam_file in
  { t with opam_file }
;;

let add_opam_package_to_opam_file package opam_file =
  opam_file
  |> OpamFile.OPAM.with_version (OpamPackage.version package)
  |> OpamFile.OPAM.with_name (OpamPackage.name package)
;;

let read_opam_file package ~opam_file_path ~opam_file_contents =
  Opam_file.read_from_string_exn ~contents:opam_file_contents opam_file_path
  |> add_opam_package_to_opam_file package
;;

let git_repo package ~opam_file ~opam_file_contents =
  let opam_file_path = Path.of_local opam_file in
  let opam_file = read_opam_file package ~opam_file_path ~opam_file_contents in
  let loc = Loc.in_file opam_file_path in
  { dune_build = false; loc; package; opam_file }
;;

let local_fs package ~dir ~opam_file_path =
  let opam_file_path = Path.append_local dir opam_file_path in
  let opam_file =
    let opam_file_contents = Io.read_file ~binary:true opam_file_path in
    read_opam_file package ~opam_file_path ~opam_file_contents
  in
  let loc = Loc.in_file opam_file_path in
  { dune_build = false; loc; package; opam_file }
;;

let dune_package loc opam_file opam_package =
  let opam_file = add_opam_package_to_opam_file opam_package opam_file in
  let package = OpamFile.OPAM.package opam_file in
  { dune_build = true; opam_file; package; loc }
;;
