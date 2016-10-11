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
open Source
open Source.Position
open Type

type var = string
type exp  = exp' fragment
 and exp' =
   | Var    of var
   | Lit    of lit
   | Fun    of (var * tpe) * exp
   | Let    of (var * tpe) * exp * exp 
   | LetRec of (var * tpe) * (var * tpe) list * exp * exp
   | If     of exp * exp * exp
   | App    of exp * exp
   | Add    of exp * exp
   | Sub    of exp * exp
   | Mul    of exp * exp
   | Div    of exp * exp
   | Gt     of exp * exp
   | Le     of exp * exp
   | Eq     of exp * exp
   | Ne     of exp * exp
   | Not    of exp
   | Neg    of exp

 and tpe  = Type.tpe
 and tpe' = Type.tpe'

 and lit  = lit' fragment
 and lit' =
   | Int   of int
   | Bool  of bool
   | Unit

let rec show_exp e =
  match it e with
  | Var x0 -> x0
  | Lit l0 -> show_lit l0
  | Fun (y0, e0) ->
     Printf.sprintf "(fun %s -> %s)" (show_parameter y0) (show_exp e0)
  | Let (y0, e0, e1) ->
     Printf.sprintf "(let %s = %s in %s)"
                    (show_parameter y0)
                    (show_exp e0)
                    (show_exp e1)
  | LetRec (y0, ys0, e0, e1) ->
     Printf.sprintf "(let rec %s %s = %s in %s)"
                    (show_parameter y0)
                    (show_parameter_list ys0)
                    (show_exp e0)
                    (show_exp e1)
  | If (e0, e1, e2) ->
     Printf.sprintf "(if %s then %s else %s)"
                    (show_exp e0)
                    (show_exp e1)
                    (show_exp e2)
  | App (e0, e1) ->
     Printf.sprintf "(%s %s)"
                    (show_exp e0)
                    (show_exp e1)
  | Add (e0, e1) ->
     Printf.sprintf "(%s + %s)"
                    (show_exp e0)
                    (show_exp e1)
  | Sub (e0, e1) ->
     Printf.sprintf "(%s - %s)"
                    (show_exp e0)
                    (show_exp e1)
  | Mul (e0, e1) ->
     Printf.sprintf "(%s * %s)"
                    (show_exp e0)
                    (show_exp e1)
  | Div (e0, e1) ->
     Printf.sprintf "(%s / %s)"
                    (show_exp e0)
                    (show_exp e1)
  | Eq (e0, e1) ->
     Printf.sprintf "(%s = %s)"
                    (show_exp e0)
                    (show_exp e1)
  | Ne (e0, e1) ->
     Printf.sprintf "(%s <> %s)"
                    (show_exp e0)
                    (show_exp e1)
  | Gt (e0, e1) ->
     Printf.sprintf "(%s > %s)"
                    (show_exp e0)
                    (show_exp e1)
  | Le (e0, e1) ->
     Printf.sprintf "(%s < %s)"
                    (show_exp e0)
                    (show_exp e1)
  | Neg e0 ->
     "neg" ^ show_exp e0
  | Not e0 ->
     "not " ^ show_exp e0


and show_lit e =
  match it e with
  | Int n0     -> string_of_int n0
  | Bool true  -> "true"
  | Bool false -> "false"
  | Unit       -> "()"

and show_parameter (x0, t0) =
  Printf.sprintf "(%s : %s)" x0 (show_tpe t0)

and show_parameter_list ys =
  String.concat " " @@ List.map show_parameter ys
