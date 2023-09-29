module Manpage : sig
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

  val s_name : string
  val s_synopsis : string
  val s_description : string
  val s_examples : string

  type format =
    [ `Auto
    | `Pager
    | `Plain
    | `Groff
    ]

  val print
    :  ?errs:Format.formatter
    -> ?subst:(string -> string option)
    -> format
    -> Format.formatter
    -> t
    -> unit
end

module Term : sig
  type +'a t

  val const : 'a -> 'a t
  val ( $ ) : ('a -> 'b) t -> 'a t -> 'b t
  val with_used_args : 'a t -> ('a * string list) t

  type 'a ret =
    [ `Help of Manpage.format * string option
    | `Error of bool * string
    | `Ok of 'a
    ]

  val ret : 'a ret t -> 'a t
end

module Cmd : sig
  module Env : sig
    type info

    val info : ?doc:string -> string -> info
  end

  module Exit : sig
    type code = int
    type info

    val info : ?doc:string -> code -> info
  end

  type info

  val info
    :  ?man:Manpage.block list
    -> ?envs:Env.info list
    -> ?exits:Exit.info list
    -> ?sdocs:string
    -> ?docs:string
    -> ?doc:string
    -> ?version:string
    -> string
    -> info

  type 'a t

  val v : info -> 'a Term.t -> 'a t
  val group : ?default:'a Term.t -> info -> 'a t list -> 'a t
  val eval_value : ?catch:bool -> 'a t -> (unit, unit) result
  val name : 'a t -> string
  val completions_script : _ t -> string
end

module Arg : sig
  type 'a parser = string -> ('a, string) result
  type 'a printer = Format.formatter -> 'a -> unit
  type 'a conv = 'a parser * 'a printer

  val conv
    :  ?docv:string
    -> (string -> ('a, [ `Msg of string ]) result) * 'a printer
    -> 'a conv

  val conv' : ?docv:string -> (string -> ('a, string) result) * 'a printer -> 'a conv
  val conv_parser : 'a conv -> string -> ('a, [ `Msg of string ]) result
  val conv_printer : 'a conv -> 'a printer
  val some : 'a conv -> 'a option conv

  type 'a t
  type info

  val info
    :  ?docs:string
    -> ?docv:string
    -> ?doc:string
    -> ?env:Cmd.Env.info
    -> string list
    -> info

  val ( & ) : ('a -> 'b) -> 'a -> 'b
  val flag : info -> bool t
  val alias : string list -> info -> bool t
  val alias_opt : (string -> string list) -> info -> bool t
  val opt : ?vopt:'a -> 'a conv -> 'a -> info -> 'a t
  val opt_all : ?vopt:'a -> 'a conv -> 'a list -> info -> 'a list t
  val pos : int -> 'a conv -> 'a -> info -> 'a t
  val pos_all : 'a conv -> 'a list -> info -> 'a list t
  val pos_right : int -> 'a conv -> 'a list -> info -> 'a list t
  val value : 'a t -> 'a Term.t
  val required : 'a option t -> 'a Term.t
  val last : 'a list t -> 'a Term.t
  val man_format : Manpage.format Term.t
  val bool : bool conv
  val float : float conv
  val string : string conv
  val int : int conv
  val enum : (string * 'a) list -> 'a conv
  val file : string conv
  val dir : string conv
  val list : ?sep:char -> 'a conv -> 'a list conv
  val pair : ?sep:char -> 'a conv -> 'b conv -> ('a * 'b) conv
  val doc_alts_enum : (string * 'a) list -> string
end
