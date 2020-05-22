/*
 * Copyright © 2017-2019 Eric Matthews,  Lesley Shannon
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Initial code developed under the supervision of Dr. Lesley Shannon,
 * Reconfigurable Computing Lab, Simon Fraser University.
 *
 * Author(s):
 *             Eric Matthews <ematthew@sfu.ca>
 */

import taiga_config::*;
import riscv_types::*;
import taiga_types::*;

module load_store_unit (
        input logic clk,
        input logic rst,
        input load_store_inputs_t ls_inputs,
        unit_issue_interface.unit issue,

        input logic dcache_on,
        input logic clear_reservation,
        tlb_interface.mem tlb,

        input logic gc_fetch_flush,
        input logic gc_issue_flush,

        l1_arbiter_request_interface.master l1_request,
        l1_arbiter_return_interface.master l1_response,
        input sc_complete,
        input sc_success,

        axi_interface.master m_axi,
        avalon_interface.master m_avalon,
        wishbone_interface.master m_wishbone,

        local_memory_interface.master data_bram,

        //ID Management
        output logic store_complete,
        output id_t store_id,

        //Writeback-Store Interface
        writeback_store_interface.ls wb_store,

        input instruction_id_t oldest_id,
        output logic load_store_exception_clear,
        output instruction_id_t load_store_exception_id,
        input logic potential_exception,

        input logic[31:0] csr_rd,
        input instruction_id_t csr_id,
        input logic csr_done,

        output exception_packet_t ls_exception,
        output logic ls_exception_valid,
        input logic ls_exception_ack,

        output unit_writeback_t wb
        );

    localparam NUM_SUB_UNITS = USE_D_SCRATCH_MEM+USE_BUS+USE_DCACHE;
    localparam NUM_SUB_UNITS_W = (NUM_SUB_UNITS == 1) ? 1 : $clog2(NUM_SUB_UNITS);

    localparam BRAM_ID = 0;
    localparam BUS_ID = USE_D_SCRATCH_MEM;
    localparam DCACHE_ID = USE_D_SCRATCH_MEM+USE_BUS;

    //Should be equal to pipeline depth of longest load/store subunit + 1 (for changing between subunits)
    localparam ATTRIBUTES_DEPTH = USE_DCACHE ? 3 : 2;

    data_access_shared_inputs_t shared_inputs;
    ls_sub_unit_interface #(.BASE_ADDR(SCRATCH_ADDR_L), .UPPER_BOUND(SCRATCH_ADDR_H), .BIT_CHECK(SCRATCH_BIT_CHECK)) bram();
    ls_sub_unit_interface #(.BASE_ADDR(BUS_ADDR_L), .UPPER_BOUND(BUS_ADDR_H), .BIT_CHECK(BUS_BIT_CHECK)) bus();
    ls_sub_unit_interface #(.BASE_ADDR(MEMORY_ADDR_L), .UPPER_BOUND(MEMORY_ADDR_H), .BIT_CHECK(MEMORY_BIT_CHECK)) cache();

    logic units_ready;
    logic unit_switch_stall;
    logic ready_for_issue;
    logic issue_request;
    logic load_complete;

    logic [31:0] virtual_address;

    logic [31:0] unit_muxed_load_data;
    logic [31:0] aligned_load_data;
    logic [31:0] final_load_data;

    logic [31:0] unit_data_array [NUM_SUB_UNITS-1:0];
    logic [NUM_SUB_UNITS-1:0] unit_ready;
    logic [NUM_SUB_UNITS-1:0] unit_data_valid;
    logic [NUM_SUB_UNITS-1:0] last_unit;
    logic [NUM_SUB_UNITS-1:0] current_unit;

    logic unaligned_addr;
    logic [NUM_SUB_UNITS-1:0] sub_unit_address_match;

    logic unit_stall;

    typedef struct packed{
        logic [2:0] fn3;
        logic [1:0] byte_addr;
        instruction_id_t instruction_id;
        logic [NUM_SUB_UNITS_W-1:0] subunit_id;
    } load_attributes_t;
    load_attributes_t  load_attributes_in, stage2_attr;

    logic [3:0] be;
    //FIFOs
    fifo_interface #(.DATA_WIDTH($bits(load_attributes_t))) load_attributes();

    load_store_queue_interface lsq();

    logic [31:0] compare_addr;
    logic address_conflict;

    ////////////////////////////////////////////////////
    //Implementation
    ////////////////////////////////////////////////////


    ////////////////////////////////////////////////////
    //Alignment Exception
    instruction_id_t exception_id;
    logic exception_is_store;

generate if (ENABLE_M_MODE) begin
    assign load_store_exception_clear = issue.new_request;
    assign load_store_exception_id = issue.instruction_id;

    always_comb begin
        case(ls_inputs.fn3)
            LS_H_fn3 : unaligned_addr = virtual_address[0];
            L_HU_fn3 : unaligned_addr = virtual_address[0];
            LS_W_fn3 : unaligned_addr = |virtual_address[1:0];
            default : unaligned_addr = 0;
        endcase
    end

   assign ls_exception.valid = unaligned_addr & issue.new_request;
   assign ls_exception.code = ls_inputs.store ? STORE_AMO_ADDR_MISSALIGNED : LOAD_ADDR_MISSALIGNED;
   assign ls_exception.pc = ls_inputs.pc;
   assign ls_exception.tval = virtual_address;
   assign ls_exception.id = issue.instruction_id;

    always_ff @ (posedge clk) begin
        if (ls_exception.valid) begin
            exception_is_store <= ls_inputs.store;
            exception_id <= issue.instruction_id;
        end
    end
end
endgenerate
    ////////////////////////////////////////////////////
    //TLB interface
    assign virtual_address = ls_inputs.rs1 + 32'(signed'(ls_inputs.offset));

    assign tlb.virtual_address = virtual_address;
    assign tlb.new_request = issue_request;
    assign tlb.execute = 0;
    assign tlb.rnw = ls_inputs.load & ~ls_inputs.store;

    ////////////////////////////////////////////////////
    //Byte enable generation
    //Only set on store
    //  SW: all bytes
    //  SH: upper or lower half of bytes
    //  SB: specific byte
    always_comb begin
        be = 0;
        case(ls_inputs.fn3[1:0])
            LS_B_fn3[1:0] : be[virtual_address[1:0]] = 1;
            LS_H_fn3[1:0] : begin
                be[virtual_address[1:0]] = 1;
                be[{virtual_address[1], 1'b1}] = 1;
            end
            default : be = '1;
        endcase
        be &= {4{~ls_inputs.load}};
    end

    ////////////////////////////////////////////////////
    //Load Store Queue
    assign lsq.addr = virtual_address;
    assign lsq.fn3 = ls_inputs.fn3;
    assign lsq.be = be;
    assign lsq.data_in = ls_inputs.rs2;
    assign lsq.load = ls_inputs.load;
    assign lsq.store = ls_inputs.store;
    assign lsq.id = issue.instruction_id;
    assign lsq.forwarded_store = ls_inputs.forwarded_store;
    assign lsq.data_id = ls_inputs.store_forward_id;

    assign lsq.possible_issue = issue.possible_issue & ~unaligned_addr;
    assign lsq.new_issue = issue.new_request & ~unaligned_addr;

    logic [MAX_INFLIGHT_COUNT-1:0] wb_hold_for_store_ids;
    load_store_queue lsq_block (.*, .writeback_valid(wb_store.forwarding_data_ready), .writeback_data(wb_store.forwarded_data));
    assign shared_inputs = lsq.transaction_out;

    assign lsq.accepted = lsq.transaction_ready & ready_for_issue;

    ////////////////////////////////////////////////////
    //ID Management
    assign store_complete = (lsq.accepted & lsq.transaction_out.store) | (ls_exception_ack & exception_is_store);
    assign store_id = $clog2(MAX_IDS)'(wb_store.commit_id);

    ////////////////////////////////////////////////////
    //Writeback-Store interface
    assign wb_store.id_needed_at_issue = ls_inputs.store_forward_id;
    assign wb_store.id_needed_at_commit = lsq.id_needed_by_store;
    assign wb_store.commit_id = ls_exception_ack ? exception_id : lsq.transaction_out.id;
    assign wb_store.commit = (lsq.accepted & lsq.transaction_out.store) | (ls_exception_ack & exception_is_store);
    assign wb_store.hold_for_store_ids = wb_hold_for_store_ids;
    ////////////////////////////////////////////////////
    //Unit tracking
    assign current_unit = sub_unit_address_match;

    initial last_unit = BRAM_ID;
    always_ff @ (posedge clk) begin
        if (load_attributes.push)
            last_unit <= sub_unit_address_match;
    end

    //When switching units, ensure no outstanding loads so that there can be no timing collisions with results
    assign unit_stall = (current_unit != last_unit) && load_attributes.valid;
    set_clr_reg_with_rst #(.SET_OVER_CLR(1), .WIDTH(1), .RST_VALUE(0)) unit_switch_stall_m (
      .clk, .rst,
      .set(issue_request && (current_unit != last_unit) && load_attributes.valid),
      .clr(~load_attributes.valid),
      .result(unit_switch_stall)
    );

    ////////////////////////////////////////////////////
    //Primary Control Signals
    assign units_ready = &unit_ready;
    assign load_complete = |unit_data_valid;

    assign ready_for_issue = units_ready & (~unit_switch_stall);

    assign issue.ready = lsq.ready;
    assign issue_request = lsq.accepted;

    ////////////////////////////////////////////////////
    //Load attributes FIFO
    one_hot_to_integer #(NUM_SUB_UNITS) sub_unit_select (.*, .one_hot(sub_unit_address_match), .int_out(load_attributes_in.subunit_id));
    taiga_fifo #(.DATA_WIDTH($bits(load_attributes_t)), .FIFO_DEPTH(ATTRIBUTES_DEPTH)) attributes_fifo (.fifo(load_attributes), .*);
    assign load_attributes_in.fn3 = shared_inputs.fn3;
    assign load_attributes_in.byte_addr = shared_inputs.addr[1:0];
    assign load_attributes_in.instruction_id = shared_inputs.id;

    assign load_attributes.data_in = load_attributes_in;
    assign load_attributes.push = issue_request & shared_inputs.load;
    assign load_attributes.pop = load_complete;
    assign load_attributes.supress_push = 0;

    assign stage2_attr = load_attributes.data_out;

    ////////////////////////////////////////////////////
    //Unit Instantiation
    generate if (USE_D_SCRATCH_MEM) begin
            assign sub_unit_address_match[BRAM_ID] = bram.address_range_check(shared_inputs.addr);
            assign bram.new_request = sub_unit_address_match[BRAM_ID] & issue_request;

            assign unit_ready[BRAM_ID] = bram.ready;
            assign unit_data_valid[BRAM_ID] = bram.data_valid;

            dbram d_bram (.*, .ls_inputs(shared_inputs), .ls(bram), .data_out(unit_data_array[BRAM_ID]));
        end
    endgenerate

    generate if (USE_BUS) begin
            assign sub_unit_address_match[BUS_ID] = bus.address_range_check(shared_inputs.addr);
            assign bus.new_request = sub_unit_address_match[BUS_ID] & issue_request;

            assign unit_ready[BUS_ID] = bus.ready;
            assign unit_data_valid[BUS_ID] = bus.data_valid;

            if(BUS_TYPE == AXI_BUS)
                axi_master axi_bus (.*, .ls_inputs(shared_inputs), .size({1'b0,shared_inputs.fn3[1:0]}), .m_axi(m_axi), .ls(bus), .data_out(unit_data_array[BUS_ID])); //Lower two bits of fn3 match AXI specification for request size (byte/halfword/word)
            else if (BUS_TYPE == WISHBONE_BUS)
                wishbone_master wishbone_bus (.*, .ls_inputs(shared_inputs), .m_wishbone(m_wishbone), .ls(bus), .data_out(unit_data_array[BUS_ID]));
            else if (BUS_TYPE == AVALON_BUS)  begin
                avalon_master avalon_bus (.*, .ls_inputs(shared_inputs), .m_avalon(m_avalon), .ls(bus), .data_out(unit_data_array[BUS_ID]));
            end
        end
    endgenerate

    generate if (USE_DCACHE) begin
            assign sub_unit_address_match[DCACHE_ID] = cache.address_range_check(shared_inputs.addr);
            assign cache.new_request = sub_unit_address_match[DCACHE_ID] & issue_request;

            assign unit_ready[DCACHE_ID] = cache.ready;
            assign unit_data_valid[DCACHE_ID] = cache.data_valid;

            dcache data_cache (.*, .ls_inputs(shared_inputs), .ls(cache), .amo(ls_inputs.amo), .data_out(unit_data_array[DCACHE_ID]));
        end
    endgenerate

    ////////////////////////////////////////////////////
    //Output Muxing
    assign unit_muxed_load_data = unit_data_array[stage2_attr.subunit_id];

    //Byte/halfword select: assumes aligned operations
    always_comb begin
        aligned_load_data[31:16] = unit_muxed_load_data[31:16];
        aligned_load_data[15:0] = stage2_attr.byte_addr[1] ? unit_muxed_load_data[31:16] : unit_muxed_load_data[15:0];
        //select halfword first then byte
        aligned_load_data[7:0] = stage2_attr.byte_addr[0] ? aligned_load_data[15:8] : aligned_load_data[7:0];
    end

    //Sign extending
    always_comb begin
        case(stage2_attr.fn3)
            LS_B_fn3 : final_load_data = 32'(signed'(aligned_load_data[7:0]));
            LS_H_fn3 : final_load_data = 32'(signed'(aligned_load_data[15:0]));
            LS_W_fn3 : final_load_data = aligned_load_data;
                //unused 011
            L_BU_fn3 : final_load_data = 32'(unsigned'(aligned_load_data[7:0]));
            L_HU_fn3 : final_load_data = 32'(unsigned'(aligned_load_data[15:0]));
                //unused 110
                //unused 111
            default : final_load_data = aligned_load_data;
        endcase
    end

    ////////////////////////////////////////////////////
    //Output bank
    assign wb.rd = csr_done ? csr_rd : final_load_data;
    assign wb.done = csr_done | load_complete | (ls_exception_ack & ~exception_is_store);
    assign wb.id = csr_done ? csr_id : (ls_exception_ack ? exception_id : stage2_attr.instruction_id);

    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    always_ff @ (posedge clk) begin
        assert ((issue_request & |sub_unit_address_match) || (!issue_request)) else $error("invalid L/S address");
        assert ((issue_request & ready_for_issue) || (!issue_request)) else $error("L/S internal request issued without subunits ready");
    end

endmodule
