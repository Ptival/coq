(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2016     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

open CErrors
open Util
open Pp
open Names
open Libnames
open Notation_term
open Libobject
open Lib
open Nameops
open Nametab

(* Syntactic definitions. *)

type version = Flags.compat_version option

let syntax_table =
  Summary.ref (KNmap.empty : (interpretation*version) KNmap.t)
    ~name:"SYNTAXCONSTANT"

let add_syntax_constant kn c onlyparse =
  syntax_table := KNmap.add kn (c,onlyparse) !syntax_table

let load_syntax_constant i ((sp,kn),(_,pat,onlyparse)) =
  if Nametab.exists_cci sp then
    user_err ~hdr:"cache_syntax_constant"
      (pr_id (basename sp) ++ str " already exists");
  add_syntax_constant kn pat onlyparse;
  Nametab.push_syndef (Nametab.Until i) sp kn

let is_alias_of_already_visible_name sp = function
  | _,NRef ref ->
      let (dir,id) = repr_qualid (shortest_qualid_of_global Id.Set.empty ref) in
      DirPath.is_empty dir && Id.equal id (basename sp)
  | _ ->
      false

let open_syntax_constant i ((sp,kn),(_,pat,onlyparse)) =
  if not (Int.equal i 1 && is_alias_of_already_visible_name sp pat) then begin
    Nametab.push_syndef (Nametab.Exactly i) sp kn;
    match onlyparse with
    | None ->
      (* Redeclare it to be used as (short) name in case an other (distfix)
	 notation was declared inbetween *)
      Notation.declare_uninterpretation (Notation.SynDefRule kn) pat
    | _ -> ()
  end

let cache_syntax_constant d =
  load_syntax_constant 1 d;
  open_syntax_constant 1 d

let subst_syntax_constant (subst,(local,pat,onlyparse)) =
  (local,Notation_ops.subst_interpretation subst pat,onlyparse)

let classify_syntax_constant (local,_,_ as o) =
  if local then Dispose else Substitute o

let in_syntax_constant
 : bool * interpretation * Flags.compat_version option -> obj =
  declare_object {(default_object "SYNTAXCONSTANT") with
    cache_function = cache_syntax_constant;
    load_function = load_syntax_constant;
    open_function = open_syntax_constant;
    subst_function = subst_syntax_constant;
    classify_function = classify_syntax_constant }

type syndef_interpretation = (Id.t * subscopes) list * notation_constr

(* Coercions to the general format of notation that also supports
   variables bound to list of expressions *)
let in_pat (ids,ac) = (List.map (fun (id,sc) -> (id,(sc,NtnTypeConstr))) ids,ac)
let out_pat (ids,ac) = (List.map (fun (id,(sc,typ)) -> (id,sc)) ids,ac)

let declare_syntactic_definition local id onlyparse pat =
  let _ = add_leaf id (in_syntax_constant (local,in_pat pat,onlyparse)) in ()

let pr_syndef kn = pr_qualid (shortest_qualid_of_syndef Id.Set.empty kn)

let pr_compat_warning (kn, def, v) =
  let pp_def = match def with
    | [], NRef r -> spc () ++ str "is" ++ spc () ++ pr_global_env Id.Set.empty r
    | _ -> strbrk " is a compatibility notation"
  in
  let since = strbrk " since Coq > " ++ str (Flags.pr_version v) ++ str "." in
  pr_syndef kn ++ pp_def ++ since

let warn_compatibility_notation =
  CWarnings.(create ~name:"compatibility-notation"
                    ~category:"deprecated" ~default:Disabled pr_compat_warning)

let verbose_compat kn def = function
  | Some v when Flags.version_strictly_greater v ->
     warn_compatibility_notation (kn, def, v)
  | _ -> ()

let search_syntactic_definition kn =
  let pat,v = KNmap.find kn !syntax_table in
  let def = out_pat pat in
  verbose_compat kn def v;
  def

open Goptions
