PYTHON_SCRIPT_PATH=/build/CA_Summer_Project/types_helper
TYPE_DEF_FILES=lib/common-lib/ProcTypes.bsv,src/Proc.bsv


cd /build/CA_Summer_Project/pb_lab5 

cp src/Proc.bsv src/gdb/Proc.bsv.copy
python3.9 $PYTHON_SCRIPT_PATH/main.py \
    --filenames lib/common-lib/Types.bsv,lib/common-lib/ProcTypes.bsv,src/Proc.bsv \
    --debug_vars src/gdb/debug_vars.xml \
    --proc src/Proc.bsv \
    --reg_order src/gdb/regs_bits.txt \
    --base_xml src/gdb/base.xml \
    --output_xml src/gdb/custom.xml \

cd src

./risc-v -c -g
