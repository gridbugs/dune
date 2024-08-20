open! Import

let enabled = Config.make_toggle ~name:"pkg_build_progress" ~default:`Enabled

module Status = struct
  type t =
    [ `Downloading
    | `Building
    ]

  let to_string = function
    | `Downloading -> "Downloading"
    | `Building -> "Building"
  ;;
end

module Message = struct
  type t =
    { package_name : Package.Name.t
    ; package_version : Package_version.t
    ; status : Status.t
    }

  let user_message { package_name; package_version; status } =
    let status_tag = User_message.Style.Success in
    User_message.make
      [ Pp.concat
          [ Pp.tag status_tag (Pp.textf "%12s" (Status.to_string status))
          ; Pp.textf
              " %s.%s"
              (Package.Name.to_string package_name)
              (Package_version.to_string package_version)
          ]
      ]
  ;;

  let display t =
    match Config.get enabled with
    | `Enabled -> Console.print_user_message (user_message t)
    | `Disabled -> ()
  ;;

  let encode { package_name; package_version; status } =
    Sexp.List
      [ Sexp.Atom (Package.Name.to_string package_name)
      ; Sexp.Atom (Package_version.to_string package_version)
      ; Sexp.Atom (Status.to_string status)
      ]
  ;;
end

module Spec = struct
  type ('path, 'target) t = Message.t

  let name = "progress-action"
  let version = 1
  let is_useful_to ~memoize:_ = true
  let bimap t _f _g = t

  let encode t _ _ =
    Sexp.List [ Sexp.Atom name; Sexp.Atom (Int.to_string version); Message.encode t ]
  ;;

  let action t ~ectx:_ ~eenv:_ =
    let open Fiber.O in
    let+ () = Fiber.return () in
    Message.display t
  ;;
end

let progress_action package_name package_version status =
  let module M = struct
    type path = Path.t
    type target = Path.Build.t

    module Spec = Spec

    let v = { Message.package_name; package_version; status }
  end
  in
  Action.Extension (module M)
;;
