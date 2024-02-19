PYTHON_SCRIPT_PATH=/build/CA_Summer_Project/types_helper
TYPE_DEF_FILES=lib/common-lib/ProcTypes.bsv,src/Proc.bsv


cd /build/CA_Summer_Project/pb_lab5 

python3.9 $PYTHON_SCRIPT_PATH/custom_reg_creator.py \
    --filenames $TYPE_DEF_FILES \
    --debug_vars src/gdb/debug_vars.xml > src/gdb/custom_regs.xml

python3.9 $PYTHON_SCRIPT_PATH/bluespec_custom_reg_creator.py \
    --filenames $TYPE_DEF_FILES \
    --debug_vars src/gdb/debug_vars.xml > src/gdb/bluespec_custom_regs.txt


python3.9 $PYTHON_SCRIPT_PATH/bluespec_custom_reg_replacer.py \
    --proc src/Proc.bsv \
    --custom_reg_code src/gdb/bluespec_custom_regs.txt > src/Proc_Rep.bsv
mv src/Proc_Rep.bsv src/Proc.bsv 

python3.9 $PYTHON_SCRIPT_PATH/main_xml.py \
    --filenames $TYPE_DEF_FILES \
    --xml src/gdb/base.xml > src/gdb/given_def.xml

sed -e '/<!-- Sed replace custom_regs.xml here. -->/{r src/gdb/custom_regs.xml' -e 'd}' \
    -e '/<!-- Sed replace given_def.xml here. -->/{r src/gdb/given_def.xml' -e 'd}' \
    src/gdb/base.xml > src/gdb/custom.xml

python3.9 $PYTHON_SCRIPT_PATH/main_regs_order.py \
    --filenames $TYPE_DEF_FILES \
    --xml src/gdb/custom.xml > src/gdb/regs_bits.txt


cd src

./risc-v -c -g
