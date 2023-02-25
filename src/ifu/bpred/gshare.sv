///////////////////////////////////////////
// gshare.sv
//
// Written: Ross Thompson
// Email: ross1728@gmail.com
// Created: 16 March 2021
// Adapted from ssanghai@hmc.edu (Shreya Sanghai)
// Modified: 20 February 2023
//
// Purpose: gshare and Global History Branch predictors
// 
// A component of the CORE-V-WALLY configurable RISC-V project.
// 
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file 
// except in compliance with the License, or, at your option, the Apache License version 2.0. You 
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the 
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
// either express or implied. See the License for the specific language governing permissions 
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

`include "wally-config.vh"

module gshare #(parameter k = 10,
                parameter integer TYPE = 1) (
  input logic             clk,
  input logic             reset,
  input logic             StallF, StallD, StallE, StallM, StallW,
  input logic             FlushD, FlushE, FlushM, FlushW,
  output logic [1:0]      DirPredictionF, 
  output logic            DirPredictionWrongE,
  // update
  input logic [`XLEN-1:0] PCNextF, PCF, PCD, PCE, PCM, PCW,
  input logic             BPBranchF, BranchD, BranchE, BranchM, BranchW, PCSrcE
);

  logic                    MatchF, MatchD, MatchE, MatchM, MatchW;
  logic                    MatchX, MatchXF;

  logic [1:0]              TableDirPredictionF, DirPredictionD, DirPredictionE, ForwardNewDirPredictionF, ForwardDirPredictionF;
  logic [1:0]              NewDirPredictionE, NewDirPredictionM, NewDirPredictionW;

  logic [k-1:0]            IndexNextF, IndexF, IndexD, IndexE, IndexM, IndexW;

  logic [k-1:0]            GHRF, GHRD, GHRE, GHRM;
  logic [k-1:0]            GHRNextM, GHRNextF;
  logic                    PCSrcM;

  if(TYPE == 1) begin
	assign IndexNextF = GHRNextF ^ {PCNextF[k+1] ^ PCNextF[1], PCNextF[k:2]};
	assign IndexF = GHRF ^ {PCF[k+1] ^ PCF[1], PCF[k:2]};
	assign IndexD = GHRD ^ {PCD[k+1] ^ PCD[1], PCD[k:2]};
	assign IndexE = GHRE ^ {PCE[k+1] ^ PCE[1], PCE[k:2]};
	assign IndexM = GHRM ^ {PCM[k+1] ^ PCM[1], PCM[k:2]};
  end else if(TYPE == 0) begin
	assign IndexNextF = GHRNextF;
	assign IndexF = GHRF;
	assign IndexD = GHRD;
	assign IndexE = GHRE;
	assign IndexM = GHRM;
  end

  flopenrc #(k) IndexWReg(clk, reset, FlushW, ~StallW, IndexM, IndexW);

  //assign MatchF = BPBranchF & ~FlushD & (IndexNextF == IndexF);
  assign MatchD = BranchD & ~FlushE & (IndexF == IndexD);
  assign MatchE = BranchE & ~FlushM & (IndexF == IndexE);
  assign MatchM = BranchM & ~FlushW & (IndexF == IndexM);
  assign MatchW = BranchW & ~FlushW & (IndexF == IndexW);
  assign MatchX = MatchD | MatchE | MatchM | MatchW;

//  flopenr #(1) MatchReg(clk, reset, ~StallF, MatchNextX, MatchXF);

  assign ForwardNewDirPredictionF = MatchD ? {2{DirPredictionD[1]}} :
                                   MatchE ? {NewDirPredictionE} :
                                   MatchM ? {NewDirPredictionM} :
								   NewDirPredictionW ;
  
  //flopenr #(2) ForwardDirPredicitonReg(clk, reset, ~StallF, ForwardNewDirPrediction, ForwardDirPredictionF);

  assign DirPredictionF = MatchX ? ForwardNewDirPredictionF : TableDirPredictionF;

  ram2p1r1wbe #(2**k, 2) PHT(.clk(clk),
    .ce1(~StallF), .ce2(~StallM & ~FlushM),
    .ra1(IndexNextF),
    .rd1(TableDirPredictionF),
    .wa2(IndexM),
    .wd2(NewDirPredictionM),
    .we2(BranchM),
    .bwe2(1'b1));

  flopenrc #(2) PredictionRegD(clk, reset,  FlushD, ~StallD, DirPredictionF, DirPredictionD);
  flopenrc #(2) PredictionRegE(clk, reset,  FlushE, ~StallE, DirPredictionD, DirPredictionE);

  satCounter2 BPDirUpdateE(.BrDir(PCSrcE), .OldState(DirPredictionE), .NewState(NewDirPredictionE));
  flopenrc #(2) NewPredictionRegM(clk, reset,  FlushM, ~StallM, NewDirPredictionE, NewDirPredictionM);
  flopenrc #(2) NewPredictionRegW(clk, reset,  FlushW, ~StallW, NewDirPredictionM, NewDirPredictionW);

  assign DirPredictionWrongE = PCSrcE != DirPredictionE[1] & BranchE;

  assign GHRNextF = BPBranchF ? {DirPredictionF[1], GHRF[k-1:1]} : GHRF;
  assign GHRF = BranchD  ? {DirPredictionD[1], GHRD[k-1:1]} : GHRD;
  assign GHRD = BranchE ? {PCSrcE, GHRE[k-1:1]} : GHRE;
  assign GHRE = BranchM ? {PCSrcM, GHRM[k-1:1]} : GHRM;

  assign GHRNextM = {PCSrcM, GHRM[k-1:1]};

  flopenr #(k) GHRReg(clk, reset, ~StallW & ~FlushW & BranchM, GHRNextM, GHRM);
  flopenrc #(1) PCSrcMReg(clk, reset, FlushM, ~StallM, PCSrcE, PCSrcM);
    
endmodule
