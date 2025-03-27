// Author: Stefano Mercogliano 
// Description: 
//  In order to package CVA5 as a Vivado custom IP, we need to remove non-compliant interfaces.
//  It means, interfaces are allowed only if master/slave couple if used

import cva5_types::*;
import riscv_types::*;
import csr_types::*;
import fpu_types::*;

////////////////////////////////
// Branch Predictor Interface //
////////////////////////////////

localparam integer DATA_WIDTH = 32;

typedef struct packed {
    logic [31:0] if_pc;
    id_t if_id;
    logic new_mem_request;
    logic [31:0] next_pc;
    id_t pc_id;
    logic pc_id_assigned;
} branch_predictor_branch_predictor_intf_i;

typedef struct packed {
    logic [31:0] branch_flush_pc;
    logic [31:0] predicted_pc;
    logic use_prediction;
    logic is_return;
    logic is_call;
    logic is_branch;
} branch_predictor_branch_predictor_intf_o;

typedef struct packed {
    logic [31:0] branch_flush_pc;
    logic [31:0] predicted_pc;
    logic use_prediction;
    logic is_return;
    logic is_call;
    logic is_branch;
} branch_predictor_fetch_intf_i;

typedef struct packed {
    logic [31:0] if_pc;
    id_t if_id;
    logic new_mem_request;
    logic [31:0] next_pc;
    id_t pc_id;
    logic pc_id_assigned;
} branch_predictor_fetch_intf_o;

//////////////////////////
// Unit Issue Interface //
//////////////////////////

typedef struct packed {
    logic ready;
} unit_issue_decode_intf_i;

typedef struct packed {
    logic possible_issue;
    logic new_request;
    id_t id;
} unit_issue_decode_intf_o;

typedef struct packed {
    logic ready;
} unit_issue_unit_intf_o;

typedef struct packed {
    logic possible_issue;
    logic new_request;
    id_t id;
} unit_issue_unit_intf_i;

//////////////////////////////
// Unit Writeback Interface //
//////////////////////////////

typedef struct packed {
    logic ack;
    id_t id;
    logic [DATA_WIDTH-1:0] rd;
} unit_writeback_unit_intf_i;

typedef struct packed {
    logic done;
    id_t id;
    logic [DATA_WIDTH-1:0] rd;
} unit_writeback_unit_intf_o;

typedef struct packed {
    logic ack;
    id_t id;
    logic [DATA_WIDTH-1:0] rd;
} unit_writeback_wb_intf_o;

typedef struct packed {
    logic done;
    id_t id;
    logic [DATA_WIDTH-1:0] rd;
} unit_writeback_wb_intf_i;

///////////////////
// RAS Interface //
///////////////////

typedef struct packed {
    logic branch_retired;
} ras_branch_predictor_intf_o;

typedef struct packed {
    logic push;
    logic pop;
    logic [31:0] new_addr;
    logic branch_fetched;
} ras_self_intf_i;

typedef struct packed {
    logic [31:0] addr;
    logic branch_retired;
} ras_self_intf_o;

typedef struct packed {
    logic [31:0] addr;
} ras_fetch_intf_i;

typedef struct packed {
    logic push;
    logic pop;
    logic [31:0] new_addr;
    logic branch_fetched;
} ras_fetch_intf_o;

/////////////////////////
// Exception Interface //
/////////////////////////

typedef struct packed {
    logic valid;
    logic possible;
    exception_code_t code;
    logic [31:0] tval;
    logic [31:0] pc;
    logic discard;
} exception_unit_intf_o;

typedef struct packed {
    logic valid;
    logic possible;
    exception_code_t code;
    logic [31:0] tval;
    logic [31:0] pc;
    logic discard;
} exception_econtrol_intf_i;

////////////////////
// FIFO Interface //
////////////////////

typedef struct packed {
    logic full;
    logic push;
    logic potential_push;
    DATA_TYPE data_in;
} fifo_enqueue_intf_i;

typedef struct packed {
    DATA_TYPE data_in;
    logic push;
    logic potential_push;
} fifo_enqueue_intf_o;

typedef struct packed {
    logic valid;
} fifo_dequeue_intf_i;

typedef struct packed {
    DATA_TYPE data_out;
    logic pop;
} fifo_dequeue_intf_o;

typedef struct packed {
    logic push;
    logic pop;
    DATA_TYPE data_in;
    logic potential_push;
} fifo_structure_intf_i;

typedef struct packed {
    DATA_TYPE data_out;
    logic valid;
    logic full;
} fifo_structure_intf_o;

///////////////////
// MMU Interface //
///////////////////

typedef struct packed {
    logic [31:0] virtual_address;
    logic request;
    logic execute;
    logic rnw;
    logic [21:0] satp_ppn;
    logic mxr;
    logic sum;
    privilege_t privilege;
} mmu_mmu_intf_i;

typedef struct packed {
    logic write_entry;
    logic superpage;
    pte_perms_t perms;
    logic [19:0] upper_physical_address;
    logic is_fault;
} mmu_mmu_intf_o;

typedef struct packed {
    logic write_entry;
    logic superpage;
    pte_perms_t perms;
    logic [19:0] upper_physical_address;
    logic is_fault;
    logic mxr;
    logic sum;
    privilege_t privilege;
} mmu_tlb_intf_i;

typedef struct packed {
    logic request;
    logic [31:0] virtual_address;
    logic execute;
    logic rnw;
} mmu_tlb_intf_o;

typedef struct packed {
    logic [21:0] satp_ppn;
    logic mxr;
    logic sum;
    privilege_t privilege;
} mmu_csr_intf_o;

///////////////////
// TLB Interface //
///////////////////

typedef struct packed {
    logic new_request;
    logic [31:0] virtual_address;
    logic rnw;
} tlb_tlb_intf_i;

typedef struct packed {
    logic ready;
    logic done;
    logic is_fault;
    logic [31:0] physical_address;
} tlb_tlb_intf_o;

typedef struct packed {
    logic new_request;
    logic [31:0] virtual_address;
    logic rnw;
} tlb_requester_intf_o;

typedef struct packed {
    logic ready;
    logic done;
    logic is_fault;
    logic [31:0] physical_address;
} tlb_requester_intf_i;

////////////////////////////////
// Load Store Queue Interface //
////////////////////////////////

typedef struct packed {
    lsq_entry_t data_in;
    logic potential_push;
    logic push;
    logic addr_push;
    lsq_addr_entry_t addr_data_in;
    logic load_pop;
    logic store_pop;
} lsq_queue_intf_i;

typedef struct packed {
    logic full;
    data_access_shared_inputs_t load_data_out;
    data_access_shared_inputs_t store_data_out;
    logic load_valid;
    logic store_valid;
    logic sq_empty;
    logic empty;
} lsq_queue_intf_o;

typedef struct packed {
    lsq_entry_t data_in;
    logic potential_push;
    logic push;
    logic addr_push;
    lsq_addr_entry_t addr_data_in;
    logic load_pop;
    logic store_pop;
} lsq_ls_intf_o;

typedef struct packed {
    logic full;
    data_access_shared_inputs_t load_data_out;
    data_access_shared_inputs_t store_data_out;
    logic load_valid;
    logic store_valid;
    logic sq_empty;
    logic empty;
} lsq_ls_intf_i;

///////////////////////////
// Store Queue Interface //
///////////////////////////

typedef struct packed {
    lsq_entry_t data_in;
    logic push;
    logic pop;
} store_queue_intf_i;

typedef struct packed {
    logic full;
    sq_entry_t data_out;
    logic valid;
    logic empty;
} store_queue_intf_o;

typedef struct packed {
    lsq_entry_t data_in;
    logic push;
    logic pop;
} store_ls_intf_o;

typedef struct packed {
    logic full;
    sq_entry_t data_out;
    logic valid;
    logic empty;
} store_ls_intf_i;

///////////////////////////////
// Memory Sub Unit Interface //
///////////////////////////////

typedef struct packed {
    logic [31:0] addr;
    logic re;
    logic we;
    logic [3:0] be;
    logic [31:0] data_in;
    logic new_request;
} memory_sub_unit_responder_intf_i;

typedef struct packed {
    logic [31:0] data_out;
    logic data_valid;
    logic ready;
} memory_sub_unit_responder_intf_o;

typedef struct packed {
    logic [31:0] addr;
    logic re;
    logic we;
    logic [3:0] be;
    logic [31:0] data_in;
    logic new_request;
} memory_sub_unit_controller_intf_o;

typedef struct packed {
    logic [31:0] data_out;
    logic data_valid;
    logic ready;
} memory_sub_unit_controller_intf_i;


interface cache_functions_interface #(parameter int TAG_W = 8, parameter int LINE_W = 4, parameter int SUB_LINE_W = 2);

    function logic [LINE_W-1:0] xor_mask (int WAY);
        for (int i = 0; i < LINE_W; i++)
            xor_mask[i] = ((WAY % 2) == 0) ? 1'b1 : 1'b0;
    endfunction

    function logic [LINE_W-1:0] getHashedLineAddr (logic[31:0] addr, int WAY);
        getHashedLineAddr = addr[2 + SUB_LINE_W +: LINE_W] ^ (addr[2 + SUB_LINE_W + LINE_W +: LINE_W] & xor_mask(WAY));
    endfunction

    function logic[TAG_W-1:0] getTag(logic[31:0] addr);
        getTag = addr[2 + LINE_W + SUB_LINE_W +: TAG_W];
    endfunction

    function logic [LINE_W-1:0] getTagLineAddr (logic[31:0] addr);
        getTagLineAddr = addr[2 + SUB_LINE_W +: LINE_W];
    endfunction

    function logic [LINE_W+SUB_LINE_W-1:0] getDataLineAddr (logic[31:0] addr);
        getDataLineAddr = addr[2 +: LINE_W + SUB_LINE_W];
    endfunction

endinterface

interface addr_utils_interface #(parameter logic [31:0] BASE_ADDR = 32'h00000000, parameter logic [31:0] UPPER_BOUND = 32'hFFFFFFFF);
        //The range should be aligned for performance
        function address_range_check (input logic[31:0] addr);
            /* verilator lint_off UNSIGNED */
            /* verilator lint_off CMPCONST */
            return addr >= BASE_ADDR & addr <= UPPER_BOUND;
            /* verilator lint_on UNSIGNED */
            /* verilator lint_on CMPCONST */
        endfunction
endinterface