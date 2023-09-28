open StdLabels

module String = struct
  include String

  module Set = struct
    include Set.Make (String)
  end

  module Map = struct
    include Map.Make (String)
  end

  let lsplit2 s ~on =
    match index_opt s on with
    | None -> None
    | Some i -> Some (sub s ~pos:0 ~len:i, sub s ~pos:(i + 1) ~len:(length s - i - 1))
  ;;
end

let strf = Printf.sprintf

module Manpage = struct
  type block =
    [ `S of string
    | `P of string
    | `Pre of string
    | `I of string * string
    | `Noblank
    | `Blocks of block list
    ]

  type title = string * int * string * string * string
  type t = title * block list

  let s_name = "NAME"
  let s_synopsis = "SYNOPSIS"
  let s_description = "DESCRIPTION"
  let s_examples = "EXAMPLES"

  type format =
    [ `Auto
    | `Pager
    | `Plain
    | `Groff
    ]

  let print ?errs ?subst fmt ppf page = print_endline "TODO: manpage print"
end

module Info = struct
  module Arg = struct
    type t = { opt_names : string list }
  end

  module Cmd = struct
    type t =
      { name : string
      ; args : Arg.t list
      ; has_args : bool
      ; children : t list
      }

    let add_args t args = { t with args = List.append t.args args }

    let with_children cmd ~args ~children =
      let has_args, args =
        match args with
        | None -> false, cmd.args
        | Some args -> true, List.append args cmd.args
      in
      { cmd with has_args; args; children }
    ;;
  end
end

module Command_line = struct
  type t = string list

  let opt_arg (t : t) (info : Info.Arg.t) : string option list =
    print_endline (strf "getting arg %s" (List.hd info.opt_names));
    []
  ;;

  let pos_arg (t : t) (info : Info.Arg.t) : string list = []
end

module Term = struct
  type 'a parser =
    Command_line.t
    -> ( 'a
       , [ `Parse_error of string
         | `Error of bool * string
         | `Help of Manpage.format * string option
         ] )
       result

  type 'a t = Info.Arg.t list * 'a parser

  let const x = [], Fun.const (Ok x)

  let ( $ ) ((info_f, parse_f) : 'a t) ((info_a, parse_a) : 'b t) =
    let parse command_line =
      Result.bind (parse_f command_line) (fun f -> Result.map f (parse_a command_line))
    in
    let info = List.append info_f info_a in
    info, parse
  ;;

  let map t ~f = const f $ t

  let map_result ((info, parse) : 'a t) ~f : 'b t =
    let parse command_line = Result.bind (parse command_line) f in
    info, parse
  ;;

  let with_used_args t =
    print_endline "TODO: with_used_args";
    map t ~f:(fun x -> x, [])
  ;;

  type 'a ret =
    [ `Help of Manpage.format * string option
    | `Error of bool * string
    | `Ok of 'a
    ]

  let ret t =
    map_result t ~f:(function
      | `Ok v -> Ok v
      | `Error _ as err -> Error err
      | `Help _ as help -> Error help)
  ;;
end

module Cmd = struct
  module Env = struct
    type info = unit

    let info ?doc var = ()
  end

  module Exit = struct
    type code = int
    type info = unit

    let info ?doc code = ()
  end

  type info = Info.Cmd.t

  let info ?man ?envs ?exits ?sdocs ?docs ?doc ?version name =
    { Info.Cmd.name; has_args = false; args = []; children = [] }
  ;;

  type 'a t =
    | Cmd of info * 'a Term.parser
    | Group of
        { info : info
        ; subcommands : 'a t list
        ; default_parser : 'a Term.parser option
        }

  let v i (args, p) = Cmd (Info.Cmd.add_args i args, p)

  let get_info = function
    | Cmd (info, _) | Group { info; _ } -> info
  ;;

  let get_name t = (get_info t).name

  let group ?default info subcommands =
    let default_args, default_parser =
      match default with
      | None -> None, None
      | Some (args, p) -> Some args, Some p
    in
    let children = List.map ~f:get_info subcommands in
    let info = Info.Cmd.with_children info ~args:default_args ~children in
    Group { info; subcommands; default_parser }
  ;;

  type 'a traverse =
    { info : info
    ; parser : 'a Term.parser
    ; command_line : Command_line.t
    }

  let rec traverse cmd remaining_argv =
    match cmd, remaining_argv with
    | Cmd (info, parser), _ -> Ok { info; parser; command_line = remaining_argv }
    | Group { info; subcommands; default_parser }, argv_first :: argv_rest ->
      let subcommand_opt =
        List.find_opt subcommands ~f:(fun subcommand ->
          String.equal (get_name subcommand) argv_first)
      in
      (match subcommand_opt with
       | Some subcommand -> traverse subcommand argv_rest
       | None ->
         (match default_parser with
          | Some parser -> Ok { info; parser; command_line = argv_rest }
          | None -> Error (strf "no such subcommand: %S" argv_first)))
    | Group { info; default_parser = Some parser; _ }, [] ->
      Ok { info; parser; command_line = [] }
    | Group { info; default_parser = None; _ }, [] ->
      Error (strf "subcommand %S can not be executed" info.name)
  ;;

  let eval_value ?catch cmd =
    print_endline "evaluating";
    match Array.to_list Sys.argv with
    | [] -> Error ()
    | _ :: command_line_without_exe ->
      (match traverse cmd command_line_without_exe with
       | Ok { info; parser; command_line } ->
         (match parser command_line with
          | Ok _ ->
            print_endline "hi";
            Ok ()
          | Error (`Parse_error parse_error) ->
            Printf.eprintf "Error parsing command line arguments: %s" parse_error;
            Error ()
          | Error (`Help _) ->
            Printf.eprintf "<help>";
            Error ()
          | Error (`Error _) ->
            print_endline "generic error";
            Error ())
       | Error message ->
         Printf.eprintf "%s" message;
         Error ())
  ;;

  let name cmd = "todo: name"
end

module Arg = struct
  type 'a parser = string -> ('a, string) result
  type 'a printer = Format.formatter -> 'a -> unit
  type 'a conv = 'a parser * 'a printer

  let conv ?docv (parse, print) =
    let parse s =
      match parse s with
      | Ok v -> Ok v
      | Error (`Msg e) -> Error e
    in
    parse, print
  ;;

  let conv' ?docv (parse, print) = parse, print
  let conv_parser (parse, _) s = Result.map_error (fun e -> `Msg e) (parse s)
  let conv_printer (_, print) = print

  let some (parse, print) =
    let parse s = Result.map Option.some (parse s) in
    let print ppf v =
      match v with
      | None -> Format.pp_print_string ppf ""
      | Some v -> print ppf v
    in
    parse, print
  ;;

  type 'a t = 'a Term.t
  type info = Info.Arg.t

  let info ?docs ?docv ?doc ?env opt_names = { Info.Arg.opt_names }
  let ( & ) f x = f x

  let flag info =
    let parse command_line =
      match Command_line.opt_arg command_line info with
      | [] -> Ok false
      | [ None ] -> Ok true
      | [ Some _ ] -> Error (`Parse_error "value passed to flag argument")
      | _ :: _ -> Error (`Parse_error "flag argument appeared multiple times")
    in
    [ info ], parse
  ;;

  let alias l i =
    print_endline "TODO: alias";
    flag i
  ;;

  let alias_opt l i =
    print_endline "todo: alias";
    flag i
  ;;

  let opt ?vopt (parse, print) default info =
    let parse command_line =
      match Command_line.opt_arg command_line info with
      | [] -> Ok default
      | [ Some value ] -> Result.map_error (fun msg -> `Parse_error msg) (parse value)
      | [ None ] -> Error (`Parse_error "option argument lacks value")
      | _ :: _ -> Error (`Parse_error "option argument appeared multiple times")
    in
    [ info ], parse
  ;;

  let opt_all ?vopt (parse, print) default info =
    let parse command_line =
      let args = Command_line.opt_arg command_line info in
      let rec loop acc = function
        | [] -> Ok (List.rev acc)
        | x :: xs ->
          (match x with
           | None -> Error (`Parse_error "option argument lacks value")
           | Some x ->
             (match parse x with
              | Error msg -> Error (`Parse_error msg)
              | Ok x -> loop (x :: acc) xs))
      in
      Result.map
        (function
         | [] -> default
         | xs -> xs)
        (loop [] args)
    in
    [ info ], parse
  ;;

  let pos index (parse, print) default info =
    let parse command_line =
      match Command_line.pos_arg command_line info with
      | [] -> Ok default
      | [ value ] -> Result.map_error (fun msg -> `Parse_error msg) (parse value)
      | _ :: _ -> Error (`Parse_error "option argument appeared multiple times")
    in
    [ info ], parse
  ;;

  let pos_all (parse, print) default info =
    print_endline "todo: pos_all";
    Term.const []
  ;;

  let pos_right n c v i =
    print_endline "todo: pos_right";
    Term.const []
  ;;

  let value a = a

  let required a =
    Term.map_result a ~f:(function
      | None -> Error (`Parse_error "Required argument is missing")
      | Some x -> Ok x)
  ;;

  let last a =
    Term.map_result a ~f:(function
      | [] -> Error (`Parse_error "can't get last argument as there are no arguments")
      | xs -> Ok (List.nth xs (List.length xs - 1)))
  ;;

  let man_format = Term.const `Auto

  let bool =
    let parse s =
      match bool_of_string_opt s with
      | Some b -> Ok b
      | None -> Error (strf "invalid value: %S (not a bool)" s)
    in
    parse, Format.pp_print_bool
  ;;

  let float =
    let parse s =
      match float_of_string_opt s with
      | Some f -> Ok f
      | None -> Error (strf "invalid value: %S (not a float)" s)
    in
    parse, Format.pp_print_float
  ;;

  let string = Result.ok, Format.pp_print_string

  let int =
    let parse s =
      match int_of_string_opt s with
      | Some i -> Ok i
      | None -> Error (strf "invalid value: %S (not an int)" s)
    in
    parse, Format.pp_print_int
  ;;

  let enum l =
    let all_names = List.map l ~f:fst in
    let duplicate_names =
      List.fold_left
        all_names
        ~init:(String.Set.empty, [])
        ~f:(fun (set, duplicate_names) name ->
          if String.Set.mem name set
          then set, name :: duplicate_names
          else String.Set.add name set, duplicate_names)
      |> snd
      |> List.rev
    in
    if List.length duplicate_names > 0
    then
      failwith
        (strf
           "Duplicate names passed to `enum`: %s"
           (String.concat duplicate_names ~sep:", "));
    let parse s =
      let value_opt =
        List.find_map l ~f:(fun (name, value) ->
          if String.equal name s then Some value else None)
      in
      match value_opt with
      | Some value -> Ok value
      | None ->
        let all_names_string = String.concat ~sep:", " all_names in
        let message =
          strf "invalid value: %S (valid values are: %s)" s all_names_string
        in
        Error message
    in
    let print ppf v =
      let name_opt =
        List.find_map l ~f:(fun (name, value) -> if value == v then Some name else None)
      in
      match name_opt with
      | Some name -> Format.pp_print_string ppf name
      | None ->
        failwith
          (strf
             "Attempted to print value not included in enum list. Enum list is: %s"
             (String.concat ~sep:", " all_names))
    in
    parse, print
  ;;

  let file =
    let parse s =
      if Sys.file_exists s then Ok s else Error (strf "no such file or directory: %s" s)
    in
    parse, Format.pp_print_string
  ;;

  let dir =
    let parse s =
      if Sys.file_exists s
      then
        if Sys.is_directory s
        then Ok s
        else Error (strf "%s exists but is not a directory" s)
      else Error (strf "no such file or directory: %s" s)
    in
    parse, Format.pp_print_string
  ;;

  let list ?(sep = ',') (parse, pp_e) =
    let rec parse_elements acc = function
      | [] -> Ok acc
      | x :: xs ->
        (match parse x with
         | Ok x -> parse_elements (x :: acc) xs
         | Error e -> Error e)
    in
    let parse s = parse_elements [] (String.split_on_char ~sep s) in
    let rec print ppf = function
      | v :: l ->
        pp_e ppf v;
        if l <> []
        then (
          Format.pp_print_char ppf sep;
          print ppf l)
      | [] -> ()
    in
    parse, print
  ;;

  let pair ?(sep = ',') (pa0, pr0) (pa1, pr1) =
    let parse s =
      match String.lsplit2 s ~on:sep with
      | None -> Error (strf "missing pair separator (%c) in %S" sep s)
      | Some (s0, s1) ->
        Result.bind (pa0 s0) (fun v0 -> Result.map (fun v1 -> v0, v1) (pa1 s1))
    in
    let print ppf (v0, v1) = Format.fprintf ppf "%a%c%a" pr0 v0 sep pr1 v1 in
    parse, print
  ;;

  let doc_alts_enum alts = "todo: doc_alts_enum"
end
