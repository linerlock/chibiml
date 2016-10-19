(*
 * Chibiml
 * Copyright (c) 2015-2016 Takahisa Watanabe <linerlock@outlook.com> All rights reserved.
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *)
open Syntax
open Type
open TypeScheme
open Pretty
open Source
open Source.Position

let rec subst_tpe th t =
  match t.it with
  | TyVar x0 when List.mem_assoc x0 th ->
     subst_tpe th @@ List.assoc x0 th
  | TyFun (t00, t01) ->
     let t00' = subst_tpe th t00 in
     let t01' = subst_tpe th t01 in
    TyFun (t00', t01') @@@ t.at
  | _ -> t

let rec compose_substitution th1 th0 =
  let th0' = List.map (fun (id, t) -> (id, subst_tpe th1 t)) th0 in
  let th1' = List.fold_left begin fun th -> fun (x, t) ->
      if Env.mem x th0 then th else (x, t) :: th
  end th0' th1 in th1'

let (@.) th1 th0 = compose_substitution th0 th1

let rename_tpe_scheme (TyScheme (xs0, t0)) =
  let xs1 = List.map (fun _ -> Type.gen_tyvar_sym ()) xs0 in
  let th0 = List.fold_left compose_substitution [] @@
    List.map2 (fun x0 x1 -> [(x0, TyVar x1 @@@ nowhere)]) xs0 xs1 in
  TyScheme (xs1, subst_tpe th0 t0)

let subst_tpe_scheme th ts =
  let TyScheme (xs0, t0) = rename_tpe_scheme ts in
  TyScheme (xs0, subst_tpe th t0)

let subst_tpe_scheme_env th te =
  List.fold_left (fun te (id, ts) ->
    Env.extend id (subst_tpe_scheme th ts) te) Env.empty te

let subst_tpe_constraint th (t0, t1) =
  let t0' = subst_tpe th t0 in
  let t1' = subst_tpe th t1 in
  (t0', t1')

module S = Set.Make (struct
  type t = Type.var
  let compare = Pervasives.compare
end)

let rec fv_tpe t =
  match t.it with
  | TyFun (t00, t01) -> S.union (fv_tpe t00) (fv_tpe t01)
  | TyVar x0         -> S.singleton x0
  | _                -> S.empty

let fv_tpe_scheme (TyScheme (xs0, t0)) =
  S.diff (fv_tpe t0) @@ List.fold_left (fun s x -> S.union s @@ S.singleton x) S.empty xs0

let fv_tpe_scheme_env te =
  List.fold_left (fun fvs (_, ts) -> S.union fvs @@ fv_tpe_scheme ts) S.empty te

let closure t te =
  let xs0 = S.elements @@ S.diff (fv_tpe t) (fv_tpe_scheme_env te) in
  TyScheme (xs0, t)

let rec occur t0 t1 =
  t0 = t1 || (match it t0 with | TyFun (t00, t01) -> occur t00 t1 || occur t01 t1 | _ -> false)

let rec unify th = function
  | [] -> th
  | (t0, t1) :: cs -> begin
      match t0.it, t1.it with
      | (TyInt, TyInt) -> unify th cs
      | (TyBool, TyBool) -> unify th cs
      | (TyUnit, TyUnit) -> unify th cs
      | (TyFun (t00, t01), TyFun (t10, t11)) ->
         unify th @@ (t00, t10) :: (t01, t11) :: cs
      | (TyVar x0, TyVar x1) when x0 = x1 ->
         unify th cs
      | (TyVar x0, _) ->
         if occur t0 t1 then error (Printf.sprintf "infinite type (%s, %s)" (pp_tpe t0) (pp_tpe t1)) @@ t0.at;
         unify ([(x0, t1)] @. th) @@ List.map (subst_tpe_constraint [(x0, t1)]) cs
      | (_, TyVar x1) ->
         if occur t0 t1 then error (Printf.sprintf "infinite type (%s, %s)" (pp_tpe t0) (pp_tpe t1)) @@ t0.at;
         unify ([(x1, t0)] @. th) @@ List.map (subst_tpe_constraint [(x1, t0)]) cs
      | _ ->
         error (Printf.sprintf "unification error (%s, %s)" (pp_tpe t0) (pp_tpe t1)) @@ at t0
    end
let unify cs = unify [] cs

let rec f te e =
  match e.it with
  | Var x0 when Env.mem x0 te ->
    let (TyScheme (_, t0)) = rename_tpe_scheme (Env.lookup x0 te) in
    (te, [], t0)
  | Var x0 ->
     let t0 = Type.gen_tyvar () in
     let ts0 = TypeScheme.of_tpe t0 in
     let te0 = Env.extend x0 ts0 te in
     (te0, [], t0)
  | Lit e0 -> begin
      match e0.it with
      | Int _  -> (te, [], TyInt @@@ nowhere)
      | Bool _ -> (te, [], TyBool @@@ nowhere)
      | Unit   -> (te, [], TyUnit @@@ nowhere)
    end
  | If (e0, e1, e2) ->
    let (te0, th0, t0) = f te e0 in
    let t0' = subst_tpe th0 t0 in
    let (te1, th1, t1) = f te0 e1 in
    let (te2, th2, t2) = f te1 e2 in
    let t3 = Type.gen_tyvar () in
    let th3 = unify [(t0', TyBool @@@ nowhere); (t1, t3); (t2, t3)] in
    let th4 = th0 @. th1 @. th2 @. th3 in
    let t3' = subst_tpe th4 t3 in
    let te3 = subst_tpe_scheme_env th4 te2 in
    (te3, th4, t3')
  | LetRec ((x0, t0), xts0, e0, e1) ->
     let ts0 = TypeScheme.of_tpe t0 in
     let te0 = Env.extend x0 ts0 te in
     let te1 = List.fold_right begin fun (x, t) -> fun te ->
       let ts = TypeScheme.of_tpe t in
       Env.extend x ts te
     end xts0 te0 in
     let (te2, th0, t1) = f te1 e0 in
     let t2 = List.fold_right begin fun (_, t00) -> fun t01 ->
        TyFun (t00, t01) @@@ nowhere
     end xts0 t1 in
     let th1 = unify [(t0, t2)] in
     let th2 = th0 @. th1 in
     let t0' = subst_tpe th2 t0 in
     let te3 = List.fold_right (fun (x, _) -> fun te -> Env.remove x te) xts0 te2 in
     let te4 = Env.remove x0 te3 in
     let te5 = Env.extend x0 (closure t0' te4) (subst_tpe_scheme_env th2 te4) in
     let (te6, th3, t3) = f te5 e1 in
     let th4 = th2 @. th3 in
     let te6 = subst_tpe_scheme_env th4 te5 in
     let t3' = subst_tpe th4 t3 in
     (te6, th4, t3')
   | Let ((x0, t0), e0, e1) ->
      let (te0, th0, t1) = f te e0 in
      let t1' = subst_tpe th0 t1 in
      let th1 = unify [(t0, t1')] in
      let th2 = th0 @. th1 in
      let te1 = subst_tpe_scheme_env th2 te0 in
      let te2 = Env.extend x0 (closure t1' te1) te1 in
      let (te3, th3, t2) = f te2 e1 in
      let th4 = th2 @. th3 in
      let te4 = subst_tpe_scheme_env th4 te3 in
      let t2' = subst_tpe th4 t2 in
      (te4, th4, t2')
   | Fun ((x0, t0), e0) ->
      let ts0 = TypeScheme.of_tpe t0 in
      let te0 = Env.extend x0 ts0 te in
      let (te1, th0, t1) = f te0 e0 in
      let t0' = subst_tpe th0 t0 in
      let t1' = subst_tpe th0 t1 in
      let te2 = Env.remove x0 (subst_tpe_scheme_env th0 te1) in
      (te2, th0, TyFun (t0', t1') @@@ nowhere)
   | App (e0, e1) ->
      let (te0, th0, t0) = f te e0 in
      let (te1, th1, t1) = f te0 e1 in
      let th2 = th0 @. th1 in
      let t0' = subst_tpe th2 t0 in
      let t1' = subst_tpe th2 t1 in
      let t2 = Type.gen_tyvar () in
      let th3 = unify [(t0', TyFun (t1', t2) @@@ nowhere)] in
      let th4 = th2 @. th3 in
      let te2 = subst_tpe_scheme_env th4 te1 in
      let t2' = subst_tpe th4 t2 in
      (te2, th4, t2')
   | Add (e0, e1) | Sub (e0, e1) | Mul (e0, e1) | Div (e0, e1) ->
      let (te0, th0, t0) = f te e0 in
      let (te1, th1, t1) = f te0 e1 in
      let th3 = th0 @. th1 in
      let t0' = subst_tpe th3 t0 in
      let t1' = subst_tpe th3 t1 in
      let th4 = unify [(t0', TyInt @@@ nowhere); (t1', TyInt @@@ nowhere)] in
      let th5 = th3 @. th4 in
      let te2 = subst_tpe_scheme_env th5 te1 in
      (te2, th5, TyInt @@@ nowhere)
   | Gt (e0, e1) | Le (e0, e1) ->
      let (te0, th0, t0) = f te e0 in
      let (te1, th1, t1) = f te0 e1 in
      let th3 = th0 @. th1 in
      let t0' = subst_tpe th3 t0 in
      let t1' = subst_tpe th3 t1 in
      let th4 = unify [(t0', TyInt @@@ nowhere); (t1', TyInt @@@ nowhere)] in
      let th5 = th3 @. th4 in
      let te2 = subst_tpe_scheme_env th5 te1 in
      (te2, th5, TyBool @@@ nowhere)
   | Eq (e0, e1) | Ne (e0, e1) ->
      let (te0, th0, t0) = f te e0 in
      let (te1, th1, t1) = f te0 e1 in
      let th3 = th0 @. th1 in
      let t0' = subst_tpe th3 t0 in
      let t1' = subst_tpe th3 t1 in
      let th4 = unify [(t0', t1')] in
      let th5 = th3 @. th4 in
      let te2 = subst_tpe_scheme_env th5 te1 in
      (te2, th5, TyBool @@@ nowhere)
   | Not e0 ->
      let (te0, th0, t0) = f te e0 in
      let t0' = subst_tpe th0 t0 in
      let th1 = unify [t0', TyBool @@@ nowhere] in
      let th2 = th0 @. th1 in
      let te1 = subst_tpe_scheme_env th2 te0 in
      (te1, th2, TyBool @@@ nowhere)
   | Neg e0 ->
      let (te0, th0, t0) = f te e0 in
      let t0' = subst_tpe th0 t0 in
      let th1 = unify [t0', TyInt @@@ nowhere] in
      let th2 = th0 @. th1 in
      let te1 = subst_tpe_scheme_env th2 te0 in
      (te1, th2, TyInt @@@ nowhere)
let f e =
  let (_, _, t0) = f Env.empty e in t0

let rec rename_tyvar_tpe env n t =
  match t.it with
  | Type.TyInt | Type.TyBool | Type.TyUnit ->
     (env, n, t)
  | Type.TyVar x0 when Env.mem x0 env ->
     (env, n, Type.TyVar (Env.lookup x0 env) @@@ t.at)
  | Type.TyVar x0 ->
     let env0 = Env.extend x0 n env in
     (env0, n + 1, Type.TyVar n @@@ t.at)
  | Type.TyFun (t00, t01) ->
     let (env0, n0, t00') = rename_tyvar_tpe env n t00 in
     let (env1, n1, t01') = rename_tyvar_tpe env0 n0 t01 in
     (env1, n1, Type.TyFun (t00', t01') @@@ t.at)

let rec rename_tyvar_exp env n e =
  match e.it with
  | Syntax.Var _ | Syntax.Lit _ -> (env, n, e)
  | Syntax.Fun ((x0, t0), e0) ->
     let (env0, n0, t0') = rename_tyvar_tpe env n t0 in
     let (env1, n1, e0') = rename_tyvar_exp env0 n0 e0 in
     (env1, n1, Syntax.Fun ((x0, t0'), e0') @@@ e.at)
  | Syntax.Let ((x0, t0), e0, e1) ->
     let (env0, n0, t0') = rename_tyvar_tpe env n t0 in
     let (env1, n1, e0') = rename_tyvar_exp env0 n0 e0 in
     let (env2, n2, e1') = rename_tyvar_exp env1 n1 e1 in
     (env2, n2, Syntax.Let ((x0, t0'), e0', e1') @@@ e.at)
  | Syntax.LetRec ((x0, t0), params, e0, e1) ->
     let (env0, n0, t0') = rename_tyvar_tpe env n t0 in
     let (env1, n1, params') = List.fold_left begin fun (env, n, params) (x, t) ->
       let (env', n', t') = rename_tyvar_tpe env n t in
       (env', n', t' :: params)
     end (env0, n0, []) (List.rev params) in
     let (env2, n2, e0') = rename_tyvar_exp env1 n1 e0 in
     let (env3, n3, e1') = rename_tyvar_exp env2 n2 e1 in
     (env3, n3, Syntax.Let ((x0, t0'), e0', e1') @@@ e.at)
  | Syntax.If (e0, e1, e2) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     let (env2, n2, e2') = rename_tyvar_exp env1 n1 e2 in
     (env2, n2, Syntax.If (e0', e1', e2') @@@ e.at)
  | Syntax.App (e0, e1) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     (env1, n1, Syntax.App (e0', e1') @@@ e.at)
  | Syntax.Add (e0, e1) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     (env1, n1, Syntax.Add (e0', e1') @@@ e.at)
  | Syntax.Sub (e0, e1) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     (env1, n1, Syntax.Sub (e0', e1') @@@ e.at)
  | Syntax.Mul (e0, e1) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     (env1, n1, Syntax.Mul (e0', e1') @@@ e.at)
  | Syntax.Div (e0, e1) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     (env1, n1, Syntax.Div (e0', e1') @@@ e.at)
  | Syntax.Eq (e0, e1) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     (env1, n1, Syntax.Eq (e0', e1') @@@ e.at)
  | Syntax.Ne (e0, e1) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     (env1, n1, Syntax.Ne (e0', e1') @@@ e.at)
  | Syntax.Gt (e0, e1) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     (env1, n1, Syntax.Gt (e0', e1') @@@ e.at)
  | Syntax.Le (e0, e1) ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     let (env1, n1, e1') = rename_tyvar_exp env0 n0 e1 in
     (env1, n1, Syntax.Le (e0', e1') @@@ e.at)
  | Syntax.Neg e0 ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     (env0, n0, Syntax.Neg e0' @@@ e.at)
  | Syntax.Not e0 ->
     let (env0, n0, e0') = rename_tyvar_exp env n e0 in
     (env0, n0, Syntax.Not e0' @@@ e.at)