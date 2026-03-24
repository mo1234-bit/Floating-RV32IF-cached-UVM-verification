`include "uvm_macros.svh"
import riscv_pkg::*;
import uvm_pkg::*;

class riscv_env_config extends uvm_object;
    `uvm_object_utils(riscv_env_config)
    virtual riscv_if vif;

    uvm_active_passive_enum agent_mode = UVM_ACTIVE;

    typedef enum { RANDOM_PROGRAM, HEX_FILE } stim_mode_e;
    stim_mode_e stim_mode = RANDOM_PROGRAM;

    string hex_file = "memfile.hex";

    int unsigned num_instrs     = 80;       // instructions per program
    int unsigned data_base_addr = 32'h10000000; // byte address for LD/ST base

    // Instruction mix weights (sum must be <= 95; remainder becomes NOPs)
    int unsigned w_r_type    = 20;
    int unsigned w_i_alu     = 18;
    int unsigned w_load      = 12;
    int unsigned w_store     = 10;
    int unsigned w_branch    = 10;
    int unsigned w_u_type    =  5;
    int unsigned w_fp_arith  = 12;
    int unsigned w_fp_mem    =  5;
    // implied NOP weight = 100 - sum(above)

  
    int unsigned run_cycles   = 5000;   // cycles per program run
    int unsigned reset_cycles = 5;      // reset assertion duration
    int unsigned iterations   = 1;      // how many programs to run per sequence

   
    bit          enable_reg_checks  = 1'b1;  // check register file at end
    bit          enable_mem_checks  = 1'b1;  // check memory writes
    bit          enable_ipc_check   = 1'b1;  // check IPC threshold
    real         min_ipc            = 0.0;   // minimum acceptable IPC (0 = skip)

    // Sentinel: if nonzero, test passes only when this reg == this value
    int unsigned sentinel_reg       = 0;
    logic [31:0] sentinel_value     = 32'hX;


    bit          track_mispredicts      = 1'b1;
    bit          detailed_cache_stats   = 1'b0;
    bit          log_every_reg_write    = 1'b0;  // very verbose — off by default
    bit          log_every_mem_write    = 1'b0;
    bit          enable_coverage        = 1'b1;
    bit          cg_opcodes_en          = 1'b1;
    bit          cg_alu_ctrl_en         = 1'b1;
    bit          cg_hazards_en          = 1'b1;
    bit          cg_branch_en           = 1'b1;
    bit          cg_cache_en            = 1'b1;
    bit          cg_rd_dest_en          = 1'b1;
    bit          cg_fpu_en              = 1'b1;

    uvm_verbosity verbosity = UVM_MEDIUM;

    function new(string name = "riscv_env_config");
        super.new(name);
    endfunction
    function void validate();
        int unsigned total_w;
        total_w = w_r_type + w_i_alu + w_load + w_store +
                  w_branch + w_u_type + w_fp_arith + w_fp_mem;

        if (total_w > 95)
            `uvm_fatal("CFG",
                $sformatf("Instruction weights sum to %0d (max 95)", total_w))

        if (stim_mode == HEX_FILE && hex_file == "")
            `uvm_fatal("CFG", "stim_mode is HEX_FILE but hex_file is empty")

        if (run_cycles < 100)
            `uvm_warning("CFG",
                $sformatf("run_cycles=%0d is very low", run_cycles))

        if (vif == null)
            `uvm_fatal("CFG", "vif handle is null — assign before validate()")

        `uvm_info("CFG", $sformatf("Config validated: %s", convert2string()), UVM_HIGH)
    endfunction

    function string convert2string();
        return $sformatf(
            "\n  stim_mode    = %s\n  hex_file     = %s\n  num_instrs   = %0d\n  run_cycles   = %0d\n  reset_cycles = %0d\n  iterations   = %0d\n  min_ipc      = %.2f\n  mix [R=%0d I=%0d LD=%0d ST=%0d BR=%0d U=%0d FP=%0d FPM=%0d]\n  coverage     = %0b\n  verbosity    = %s",
            stim_mode.name(), hex_file,
            num_instrs, run_cycles, reset_cycles, iterations,
            min_ipc,
            w_r_type, w_i_alu, w_load, w_store,
            w_branch, w_u_type, w_fp_arith, w_fp_mem,
            enable_coverage,
            verbosity.name()
        );
    endfunction

endclass : riscv_env_config
