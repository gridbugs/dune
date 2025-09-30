open! Import
include Dune_pkg.Dev_tool

let install_path_base_dir_name = ".dev-tool"

let install_path_base =
  lazy
    (let dev_tool_context_name = Dune_engine.Context_name.default in
     Path.Build.L.relative
       Private_context.t.build_dir
       [ Dune_engine.Context_name.to_string dev_tool_context_name
       ; install_path_base_dir_name
       ])
;;

let universe_install_path t =
  Path.Build.relative
    (Lazy.force install_path_base)
    (Package.Name.to_string @@ package_name t)
;;

let package_install_path t =
  Path.Build.relative (universe_install_path t) (Package.Name.to_string @@ package_name t)
;;

let exe_path t =
  Path.Build.L.relative
    (universe_install_path t)
    ("target" :: exe_path_components_within_package t)
;;

let lib_path t = Path.Build.L.relative (package_install_path t) [ "target"; "lib" ]

let install_path_base' =
  lazy
    (let dev_tool_context_name = Dune_engine.Context_name.default in
     Path.Build.L.relative
       Private_context.t.build_dir
       [ Dune_engine.Context_name.to_string dev_tool_context_name; ".pkg" ])
;;

let package_install_path' t slug =
  assert (
    Dune_pkg.Package_name.equal (package_name t) (Dune_pkg.Lock_dir.Pkg_slug.name slug));
  Path.Build.relative
    (Lazy.force install_path_base')
    (Dune_pkg.Lock_dir.Pkg_slug.to_string slug)
;;

let exe_path' t slug =
  Path.Build.L.relative
    (package_install_path' t slug)
    ("target" :: exe_path_components_within_package t)
;;
