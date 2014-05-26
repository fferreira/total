open Syntax

let rec is_kind c = function 
  | Universe _, _ -> true
  | Pi (_,_, e),_ -> is_kind c e
  | Subst _ as e, l -> is_kind c (Norm.whnf c (e, l))
  | _, _ -> false

let ctx_from sigma = (sigma, Ctx.empty_context)

let elab_type_constr sigma x t =
  let ctx = ctx_from sigma in
  let _ = Typing.infer ctx t in
  if not (is_kind ctx t) then
    Error.typing ~loc:(snd t) "expresion @ %t@ is not a kind" (Print.expr ctx t) ;
  Ctx.add_constr x t sigma

let rec constructs_type x = function
  | Pi (_,_,e),_ -> constructs_type x e
  | App ((Const x', _), _),_ when x = x' -> true
  | Const x',_ when x = x' -> true
  | _ -> false

let positive t x = true 	(* TODO implement this! *)

let validate_constrs (sigma : Ctx.signature) 
		 (x : Common.name) 
		 (t : Syntax.expr) 
		 (cs : (Common.name * Syntax.expr) list) =
  let elab sigma (c, t) = 
    let ctx = ctx_from sigma in
    if not (constructs_type x t) then
      Error.typing ~loc:(snd t) 
		   "constructor %s does not construct type %s (%t )" 
		   c x (Print.expr ctx t) ;
    let k = Typing.infer ctx t in
    if not (is_kind ctx k)then
      Error.typing ~loc:(snd t)
    		   "constructor %s does not construct a type (%t has type %t)"
    		   c (Print.expr ctx t) (Print.expr ctx k) ;
    if not (positive t x) then
      Error.typing ~loc:(snd t) "constructor %s is not strictly positive." c;
    Ctx.add_constr c t sigma
  in
  List.fold_left elab sigma cs

let nw = Common.nowhere
(** Computes the induction hypothesis *)
let motive_ty sigma d t = 
  let ctx = ctx_from sigma in
  Print.debug "Building motive for type %s : %t" d (Print.expr ctx t);
  let params,_ = get_telescope t in
  let vars = List.map (fun (n, _) -> var n) params in
  let d' = List.fold_left (fun e v -> nw (App (e, v))) (nw (Const d)) vars in
  let p = List.fold_left 
	    (fun v (x, t) -> nw(Pi (x, t, var_to_db x v))) 
	    (nw (Universe 0)) 
	    ((Common.none_with "D", d')::params)
  in
  Print.debug "Motive for %s is P : %t" d (Print.expr ctx p) ;
  p

let method_ty sigma d t c ct p_nm = 
  let ctx = ctx_from sigma in
  Print.debug "Computing method : %s" c ;
  (* The term that contains P *)
  let p = var p_nm in
  
  (* All the constructor's parameters *)
  let constr_tel, constr = get_telescope ct in
  Print.debug "constr_tel length = %d"  (List.length constr_tel) ;

  let rec is_constr d = function 
    | Const c, l -> c = c
    | App (e, _), l -> is_constr d e
    | _, _ -> false
  in

  (* The parameters that represent a recursive call *)
  let recs = List.filter (fun (x, t) -> is_constr d t) constr_tel in

  let hyps = List.map 
	       (fun (x, t) -> Common.none_with "r", nw (App (p, var x)))
	       recs
  in
  let final_tel = hyps @ constr_tel in

  let result = nw (App (p, List.fold_left (fun e (n, _) -> nw(App(e, nw(Free n)))) (nw (Const c)) constr_tel)) in

  (* Print.debug "constr = %t" (Print.expr ctx constr) ; *)
  (* Print.debug "len(constr_tel) = %d" (List.length constr_tel) ; *)
  let m = List.fold_left
	    (fun v (x, t) -> nw (Pi (Common.none_with "d", t, var_to_db x v)))
	    result
	    final_tel

  in
  Print.debug "For %s method: %t" c (Print.expr ctx m) ;
  m

let elim sigma d t cs =
  let ctx = ctx_from sigma in
  Print.debug "Computing eliminator for %s" d ;
  let targets, _ = get_telescope t in
  let x = Common.none_with "x" in


  let p_nm = Common.none_with "P" in
  let p = motive_ty sigma d t in

  let ms = List.map
	     (fun (c, ct) ->
	      Common.none_with "m", method_ty sigma d t c ct p_nm)
	     cs
  in

  let dest = set_telescope targets (nw (Const d)) (fun v t e -> nw (Pi (v, t, e))) in
  let final_tel = ms @ ((p_nm, p) ::(x, dest) :: targets) in

  let result = List.fold_left
		 (fun v (x, _) -> nw (App(v, var x)))
		 (nw (App(var p_nm, var x)))
		 targets
  in

  Print.debug "Eliminator telescope length: %d" (List.length final_tel) ;
  let _ = List.map (fun (c, t) -> Print.debug "%s : %t" (Print.var c) (Print.expr ctx t)) final_tel in
  Print.debug "result = %t" (Print.expr ctx result) ;

  let elim_ty = set_telescope final_tel result (fun v t e -> nw (Pi (v, t, e))) in

  Ctx.add_constr (d^"-elim") elim_ty sigma


