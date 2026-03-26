`include "uvm_macros.svh"
import riscv_pkg::*;
import uvm_pkg::*;
class riscv_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(riscv_scoreboard)

    uvm_analysis_imp_reg   #(reg_write_txn,      riscv_scoreboard) aimp_reg;
    uvm_analysis_imp_mem   #(mem_txn,            riscv_scoreboard) aimp_mem;
    uvm_analysis_imp_branch#(branch_txn,         riscv_scoreboard) aimp_branch;
    uvm_analysis_imp_stats #(pipeline_stats_txn, riscv_scoreboard) aimp_stats;

    riscv_env_config  cfg;
    riscv_seq_item    expected;   // set by test after build_phase

    // Shadow models
    logic [31:0] shadow_int[32];
    logic [31:0] shadow_fp [32];
    logic [31:0] shadow_mem[bit [31:0]];   // bit index — 2-state, legal

    int unsigned pass_count;
    int unsigned fail_count;
    int unsigned check_count;

    // Prologue in-flight checking
    int unsigned reg_write_count;       // counts write_reg calls
    bit          prologue_checked;      // fires prologue check exactly once

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // -----------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db #(riscv_env_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "riscv_scoreboard: riscv_env_config not found")

        aimp_reg    = new("aimp_reg",    this);
        aimp_mem    = new("aimp_mem",    this);
        aimp_branch = new("aimp_branch", this);
        aimp_stats  = new("aimp_stats",  this);

        reset_shadows();
    endfunction

    function void reset_shadows();
        foreach (shadow_int[i]) shadow_int[i] = 0;
        foreach (shadow_fp[i])  shadow_fp[i]  = 0;
        shadow_mem.delete();
        pass_count = 0; fail_count = 0; check_count = 0;
        reg_write_count = 0; prologue_checked = 0;
    endfunction

   
    function void write_reg(reg_write_txn t);
    if (!t.is_fp) begin
        if (t.rd != 0) shadow_int[t.rd] = t.data;
    end else begin
        shadow_fp[t.rd] = t.data;
    end
    reg_write_count++;
    // Only check prologue for random programs — directed hex has no fixed prologue
    if (!prologue_checked && reg_write_count >= 14 &&
        cfg.stim_mode == riscv_env_config::RANDOM_PROGRAM) begin
        prologue_checked = 1;
        check_prologue_regs();
    end
endfunction

    function void write_mem(mem_txn t);
        if (t.is_write) shadow_mem[bit'(t.addr)] = t.data;
    endfunction

    function void write_branch(branch_txn t);
        // Accumulated in monitor; no per-branch action needed here
    endfunction

 
    function void write_stats(pipeline_stats_txn s);
        `uvm_info("SB", $sformatf("\n%s", s.convert2string()), UVM_LOW)

        if (expected == null) begin
            `uvm_info("SB","No exp_int_regs set — skipping end-of-program register check.",UVM_MEDIUM)
        end else begin
            if (cfg.enable_reg_checks) check_registers();
            if (cfg.enable_mem_checks) check_memory();
        end
        // IPC check runs for all tests that have a min_ipc threshold
        if (cfg.enable_ipc_check) check_ipc(s);

        // Structural checks always run (don't need an expected item)
        check_x0_zero();

        print_summary();
    endfunction

    // -----------------------------------------------------------------------
    function void check_registers();
        for (int i = 1; i < 32; i++) begin
            if (expected.exp_int_regs[i] === 32'hX) continue;
            check_count++;
            if (shadow_int[i] !== expected.exp_int_regs[i]) begin
                `uvm_error("SB",
                    $sformatf("INT REG MISMATCH x%0d: got=0x%08h exp=0x%08h",
                              i, shadow_int[i], expected.exp_int_regs[i]))
                fail_count++;
            end else pass_count++;
        end
        for (int i = 0; i < 32; i++) begin
            if (expected.exp_fp_regs[i] === 32'hX) continue;
            check_count++;
            if (shadow_fp[i] !== expected.exp_fp_regs[i]) begin
                `uvm_error("SB",
                    $sformatf("FP REG MISMATCH f%0d: got=0x%08h exp=0x%08h",
                              i, shadow_fp[i], expected.exp_fp_regs[i]))
                fail_count++;
            end else pass_count++;
        end
    endfunction

    function void check_memory();
        foreach (expected.exp_mem[addr]) begin
            check_count++;
            if (!shadow_mem.exists(addr)) begin
                `uvm_error("SB",
                    $sformatf("MEM CHECK: addr 0x%08h never written (exp=0x%08h)",
                              addr, expected.exp_mem[addr]))
                fail_count++;
            end else if (shadow_mem[addr] !== expected.exp_mem[addr]) begin
                `uvm_error("SB",
                    $sformatf("MEM MISMATCH addr=0x%08h got=0x%08h exp=0x%08h",
                              addr, shadow_mem[addr], expected.exp_mem[addr]))
                fail_count++;
            end else pass_count++;
        end
    endfunction

    function void check_ipc(pipeline_stats_txn s);
        real effective_min = (expected != null && expected.min_ipc > 0.0)
                             ? expected.min_ipc : cfg.min_ipc;
        if (effective_min <= 0.0) return;
        check_count++;
        if (s.ipc < effective_min) begin
            `uvm_error("SB",
                $sformatf("IPC FAIL: got=%.3f min=%.3f", s.ipc, effective_min))
            fail_count++;
        end else begin
            `uvm_info("SB",
                $sformatf("IPC PASS: %.3f >= %.3f", s.ipc, effective_min), UVM_LOW)
            pass_count++;
        end
    endfunction

   
    function void check_prologue_regs();
        // x1-x7: known seed values
        for (int r = 1; r <= 7; r++) begin
            check_count++;
            if (shadow_int[r] !== 32'(r)) begin
                `uvm_error("SB", $sformatf(
                    "PROLOGUE FAIL x%0d: got=0x%08h exp=0x%08h (after prologue)",
                    r, shadow_int[r], 32'(r)))
                fail_count++;
            end else pass_count++;
        end
        // x8: base address (prologue uses LUI only for upper 20 bits; lower 12=0)
        check_count++;
        if (shadow_int[8] !== 32'h10000000) begin
            `uvm_error("SB", $sformatf(
                "PROLOGUE FAIL x8: got=0x%08h exp=0x10000000 (data base ptr)",
                shadow_int[8]))
            fail_count++;
        end else pass_count++;
        // x9 = 1.0f, x10 = 2.0f
        check_count++;
        if (shadow_int[9] !== 32'h3F800000) begin
            `uvm_error("SB", $sformatf(
                "PROLOGUE FAIL x9: got=0x%08h exp=0x3F800000 (1.0f seed)",
                shadow_int[9]))
            fail_count++;
        end else pass_count++;
        check_count++;
        if (shadow_int[10] !== 32'h40000000) begin
            `uvm_error("SB", $sformatf(
                "PROLOGUE FAIL x10: got=0x%08h exp=0x40000000 (2.0f seed)",
                shadow_int[10]))
            fail_count++;
        end else pass_count++;
        `uvm_info("SB", $sformatf(
            "Prologue check done: %0d passed, %0d failed",
            pass_count, fail_count), UVM_MEDIUM)
    endfunction

    function void check_x0_zero();
        check_count++;
        if (shadow_int[0] !== 32'h0) begin
            `uvm_error("SB", $sformatf("x0 != 0! (got 0x%08h)", shadow_int[0]))
            fail_count++;
        end else pass_count++;
    endfunction

    function void print_summary();
        `uvm_info("SB", $sformatf("\n============================================================\n  SCOREBOARD SUMMARY\n  Total Checks : %0d\n  PASSED       : %0d\n  FAILED       : %0d\n============================================================", check_count, pass_count, fail_count), UVM_LOW)
    endfunction

    function void report_phase(uvm_phase phase);
        if (fail_count > 0)
            `uvm_error("SB", $sformatf("TEST FAILED: %0d check(s) failed", fail_count))
        else if (check_count > 0)
            `uvm_info("SB", "ALL CHECKS PASSED", UVM_NONE)
    endfunction

endclass : riscv_scoreboard
