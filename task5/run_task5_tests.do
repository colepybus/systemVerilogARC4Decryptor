# Runs all six Task 5 testbenches in Questa.
# In the Questa transcript, type:
#   do C:/Users/colep/cpen311/cpen311-lab3/Lab_3/Lab_3/task5/run_task5_tests.do
# Each test prints ALL TESTS PASSED or a list of FAIL lines.
# Netlist tests are skipped until crack.vo / doublecrack.vo / task5.vo exist in this folder.
# Not a deliverable: don't submit this file or the work_* folders it creates.

onbreak {resume}
cd C:/Users/colep/cpen311/cpen311-lab3/Lab_3/Lab_3/task5
quit -sim

# RTL tests
vlib work_rtl
vmap work_rtl work_rtl
vlog -sv -work work_rtl init.sv ksa.sv prga.sv arc4.sv crack.sv doublecrack.sv task5.sv s_mem.v ct_mem.v pt_mem.v tb_rtl_crack.sv tb_rtl_doublecrack.sv tb_rtl_task5.sv

foreach tb {tb_rtl_crack tb_rtl_doublecrack tb_rtl_task5} {
    echo "===== $tb ====="
    vsim -voptargs=+acc -L altera_mf_ver work_rtl.$tb
    run -all
    quit -sim
}

# Netlist tests (each in its own library, because a module's .sv and .vo define the same module)
foreach m {crack doublecrack task5} {
    if {[file exists $m.vo]} {
        vlib work_syn_$m
        vmap work_syn_$m work_syn_$m
        vlog -sv -work work_syn_$m $m.vo tb_syn_$m.sv
        echo "===== tb_syn_$m ====="
        vsim -voptargs=+acc -L altera_mf_ver -L altera_ver -L altera_lnsim_ver -L cyclonev_ver work_syn_$m.tb_syn_$m
        run -all
        quit -sim
    } else {
        echo "===== tb_syn_$m SKIPPED: $m.vo not found ====="
    }
}

echo "===== done: check each section above for ALL TESTS PASSED ====="
