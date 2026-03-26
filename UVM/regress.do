# regress.do

set tests {
    riscv_smoke_test
    riscv_random_test
    riscv_int_alu_test
    riscv_load_store_test
    riscv_branch_test
    riscv_fpu_test
    riscv_reset_stress_test
    riscv_regression_test
}

vlib work
vlog -f src_files.list \
     +cover -covercells \
     +define+UVM_NO_DEPRECATED \
     -suppress 2583

foreach test $tests {
    vsim -voptargs=+acc \
         work.tb_top \
         -classdebug \
         -uvmcontrol=all \
         -cover \
         +UVM_TESTNAME=$test \
         +UVM_VERBOSITY=UVM_LOW \
         -do "run -all; coverage save ${test}.ucdb; quit -sim"
}


vcover merge riscv_merged.ucdb {*}[glob *.ucdb]


vcover report riscv_merged.ucdb \
    -details -annotate -all \
    -output coverage_merged_rpt.txt

echo "=== MERGED COVERAGE SUMMARY ==="
vcover report riscv_merged.ucdb -summary

