///////////////////////////////////////////
//
// Written: James Stine
// Modified: 9/28/2021
//
// Purpose: Main convergence routine for floating point divider/square root unit (Goldschmidt)
// 
// A component of the Wally configurable RISC-V project.
// 
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, 
// modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software 
// is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS 
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT 
// OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
///////////////////////////////////////////

module divconv (
   input logic [52:0] 	d, n,
   input logic [2:0] 	sel_muxa, sel_muxb,
   input logic 		sel_muxr, 
   input logic 		load_rega, load_regb, load_regc, load_regd,
   input logic 		load_regr, load_regs,
   input logic 		P,
   input logic 		op_type,
   input logic 		exp_odd, 
   input logic 		reset,
   input logic 		clk, 
		
   output logic [59:0] 	q1, qp1, qm1,
   output logic [59:0] 	q0, qp0, qm0, 
   output logic [59:0] 	rega_out, regb_out, regc_out, regd_out,
   output logic [119:0] regr_out
);

   logic [59:0] 	muxa_out, muxb_out;
   logic [10:0] 	ia_div, ia_sqrt;
   logic [59:0] 	ia_out;
   logic [119:0] 	mul_out;
   logic [59:0] 	q_out1, qm_out1, qp_out1;
   logic [59:0] 	q_out0, qm_out0, qp_out0;
   logic [59:0] 	mcand, mplier, mcand_q;   
   logic [59:0] 	twocmp_out;
   logic [60:0] 	three;   
   logic [119:0] 	constant, constant2;
   logic [59:0] 	q_const, qp_const, qm_const;
   logic [59:0] 	d2, n2;   
   logic 		muxr_out;
   logic 		cout1, cout2, cout3, cout4, cout5, cout6, cout7;

   // Check if exponent is odd for sqrt
   // If exp_odd=1 and sqrt, then M/2 and use ia_addr=0 as IA
   assign d2 = (exp_odd&op_type) ? {1'b0, d, 6'h0} : {d, 7'h0};
   assign n2 = op_type ? d2 : {n, 7'h0};
   
   // IA div/sqrt
   sbtm_div ia1 (d[52:41], ia_div);
   sbtm_sqrt ia2 (d2[59:48], ia_sqrt);
   assign ia_out = op_type ? {ia_sqrt, {49{1'b0}}} : {ia_div, {49{1'b0}}};
   
   // Choose IA or iteration
   mux6 #(60) mx1 (d2, ia_out, rega_out, regc_out, regd_out, regb_out, sel_muxb, muxb_out);
   mux5 #(60) mx2 (regc_out, n2, ia_out, regb_out, regd_out, sel_muxa, muxa_out);

   // Deal with remainder if [0.5, 1) instead of [1, 2)
   mux2 #(120) mx3a ({~n, {67{1'b1}}}, {{1'b1}, ~n, {66{1'b1}}}, q1[59], constant2);
   // Select Mcand, Remainder/Q''  
   mux2 #(120) mx3 (120'h0, constant2, sel_muxr, constant);
   // Select mcand - remainder should always choose q1 [1,2) because
   //   adjustment of N in the from XX.FFFFFFF
   mux2 #(60) mx4 (q0, q1, q1[59], mcand_q);
   mux2 #(60) mx5 (muxb_out, mcand_q, sel_muxr&op_type, mplier);   
   mux2 #(60) mx6 (muxa_out, mcand_q, sel_muxr, mcand);
   // Q*D - N (reversed but changed in rounder.v to account for sign reversal)
   // Add ulp for subtraction in remainder
   mux2 #(1) mx7 (1'b0, 1'b1, sel_muxr, muxr_out);

   // Constant for Q''
   mux2 #(60) mx8 ({60'h0000_0000_0000_020}, {60'h0000_0040_0000_000}, P, q_const);
   mux2 #(60) mx9 ({60'h0000_0000_0000_0A0}, {60'h0000_0140_0000_000}, P, qp_const);
   mux2 #(60) mxA ({60'hFFFF_FFFF_FFFF_F9F}, {60'hFFFF_FF3F_FFFF_FFF}, P, qm_const);
   
   // CPA (from CSA)/Remainder addition/subtraction 
   assign {cout1, mul_out} = (mcand*mplier) + constant + {119'b0, muxr_out};  
   
   // Assuming [1,2) - q1
   assign {cout2, q_out1} = regb_out + q_const;  
   assign {cout3, qp_out1} = regb_out + qp_const;  
   assign {cout4, qm_out1} = regb_out + qm_const + 1'b1;  
   // Assuming [0.5,1) - q0   
   assign {cout5, q_out0} = {regb_out[58:0], 1'b0} + q_const;  
   assign {cout6, qp_out0} = {regb_out[58:0], 1'b0} + qp_const;  
   assign {cout7, qm_out0} = {regb_out[58:0], 1'b0} + qm_const + 1'b1;    

   // One's complement instead of two's complement (for hw efficiency)
   assign three = {~mul_out[118], mul_out[118], ~mul_out[117:59]};   
   mux2 #(60) mxTC (~mul_out[118:59], three[60:1],  op_type, twocmp_out);

   // regs
   flopenr #(60) regc (clk, reset, load_regc, twocmp_out, regc_out);
   flopenr #(60) regb (clk, reset, load_regb, mul_out[118:59], regb_out);
   flopenr #(60) rega (clk, reset, load_rega, mul_out[118:59], rega_out);
   flopenr #(60) regd (clk, reset, load_regd, mul_out[118:59], regd_out);
   flopenr #(120) regr (clk, reset, load_regr, mul_out, regr_out);
   // Assuming [1,2)
   flopenr #(60) rege (clk, reset, load_regs, {q_out1[59:35], (q_out1[34:6] & {29{~P}}), 6'h0}, q1);   
   flopenr #(60) regf (clk, reset, load_regs, {qm_out1[59:35], (qm_out1[34:6] & {29{~P}}), 6'h0}, qm1);
   flopenr #(60) regg (clk, reset, load_regs, {qp_out1[59:35], (qp_out1[34:6] & {29{~P}}), 6'h0}, qp1);
   // Assuming [0,1)
   flopenr #(60) regh (clk, reset, load_regs, {q_out0[59:35], (q_out0[34:6] & {29{~P}}), 6'h0}, q0);
   flopenr #(60) regj (clk, reset, load_regs, {qm_out0[59:35], (qm_out0[34:6] & {29{~P}}), 6'h0}, qm0);
   flopenr #(60) regk (clk, reset, load_regs, {qp_out0[59:35], (qp_out0[34:6] & {29{~P}}), 6'h0}, qp0);
   
endmodule // divconv