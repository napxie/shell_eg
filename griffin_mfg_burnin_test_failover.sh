#!/bin/bash

echo "$0: %%REPOID%%"

# Global variables
RED='\e[0;31m'
GREEN='\e[0;32m'
NC='\e[0m' # No Color
VENDOR_DEVICE_ID="80cf" # Device ID for Griffin cards before loading FW
FW_DEVICE_ID="00fa:00ce" # Device ID for Griffin cards after loading FW
TMP_VEND_FILE="/tmp/tmp_vend.txt"
TMP_FW_FILE="/tmp/tmp_fw.txt"
TMP_FILE="/tmp/tmp.txt"
TMP_PCI_DEVS="/tmp/tmp_devs.txt"
declare -A EXPANDER_MAP
EXPANDER_MAP=(['4']='3' ['21']='0' ['12']='1' ['13']='2' ['5']='4' ['20']='5' ['17']='6' ['16']='7' ['9']='8' ['8']='9')

echo -e "${GREEN}----- ADVICE ${0}:${NC} Make sure to the run the script from the fw-release directory"
if [ "$#" -eq 0 ]; then
    echo -e "${RED}----- ERROR:${NC}"; echo -e "----- Usage: $0 <Runtime(int) in hours"
#    exit 1
fi
RUNTIME=$1
RUNTIME=$((RUNTIME*60*60))
#RUNTIME=30
echo "----- Preparing to run burnin test for $RUNTIME seconds"
echo -e "Scan1:\n`./griffin scan`" | tee /tmp/burnin_summary.log

# Delete previously loaded drivers
rmmod nvmelite
rmmod griffin

# Get the:slot numbers for all the Griffin cards attached 
lspci -tv | egrep $VENDOR_DEVICE_ID\|$FW_DEVICE_ID | cut -d '+' -f2 | cut -c2-3 > $TMP_VEND_FILE
lspci -tv | egrep $VENDOR_DEVICE_ID\|$FW_DEVICE_ID | grep -v "+" | cut -d '-' -f2 | cut -c1-2 > $TMP_FW_FILE

cat $TMP_VEND_FILE $TMP_FW_FILE | egrep -e '[0-9]+' > $TMP_FILE
NUM_DEVS=$(cat $TMP_FILE | wc -l)

lspci | grep Non-Vol | cut -d ' ' -f1 > $TMP_PCI_DEVS
chmod +rwx /tmp/tmp*.txt
if [ $NUM_DEVS -le 0 ]; then
  echo -e "${RED}----- ERROR ${0}:${NC} No Griffin devices connected"
  exit 1
else
  # HACK: Remove and rescan the PCI tree before loading drivers
  pci_slot=0000:$(lspci | egrep $FW_DEVICE_ID\|$VENDOR_DEVICE_ID  | tail -1 | cut -d ' ' -f1)
  pci_tree=$(find /sys/devices -name $pci_slot | sed 's/\//#/5'  | cut -d '#' -f1)
  echo 1 > $pci_tree/remove && echo 1 > /sys/bus/pci/rescan
echo -e "Scan2:\n`./griffin scan`" | tee -a /tmp/burnin_summary.log
  
  # Install the griffin driver on all cards
  sleep 480
  insmod ./griffin.ko
  sleep 20
fi

echo -e "Scan3:\n`./griffin scan`" | tee -a /tmp/burnin_summary.log
echo "Burnin start-time: $(date)" | tee -a /tmp/burnin_summary.log
for (( i=1; i<=$NUM_DEVS; i++ )) do
  pci_slot=`cat $TMP_FILE | awk "NR==$i"`
  dev_dec=`printf "%d" 0x$pci_slot`
  pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
  char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
  if [ "$char_dev" == '' ]; then
    echo "Driver not attached on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}" | tee -a /tmp/burnin_summary.log
  fi
done

echo -e "Scan4:\n`./griffin scan`" | tee -a /tmp/burnin_summary.log
#First precondition and readback data on all Griffin cards
# Write first
for (( i = 1 ; i <= $NUM_DEVS ; i++ )) do
  dev=`cat $TMP_FILE | awk "NR==$i"`
  dev_dec=`printf "%d" 0x$dev`
  pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
  char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
  serial_num=`./griffin read-fru /dev/${char_dev} | grep -A1 "LTC" | grep "Serial Number" | sed 's/ \+//g' | cut -d ':' -f2`
  block_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3 | sed 's/ctl//g' | sed 's/$/n1/g'`
  if [ ! -d card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num} ]; then
    mkdir card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num};
  fi
  BLOCK_DEV_DR_CNT=$(ls /dev/${block_dev} | wc -l)
  if [ $BLOCK_DEV_DR_CNT -eq 1 ]; then
    echo "Starting prep write on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}" | tee -a ./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/burnin_fio.log   
    fio --rw=write --blocksize=512k --size=100% --loops=2 --ioengine=libaio --iodepth=256 --direct=1 --invalidate=1 --filename=/dev/${block_dev}  --name=prep_512k_write --output="./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/prep_write.log" &
    sleep 1
  else 
    echo "Block device driver $block_dev not loaded on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}" | tee -a /tmp/burnin_summary.log
  fi
done
wait
echo -e "Scan5:\n`./griffin scan`" | tee -a /tmp/burnin_summary.log
# Read back
for (( i = 1 ; i <= $NUM_DEVS ; i++ )) do
  dev=`cat $TMP_FILE | awk "NR==$i"`
  dev_dec=`printf "%d" 0x$dev`
  pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
  char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
  serial_num=`./griffin read-fru /dev/${char_dev} | grep -A1 "LTC" | grep "Serial Number" | sed 's/ \+//g' | cut -d ':' -f2`
  block_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3 | sed 's/ctl//g' | sed 's/$/n1/g'`
  BLOCK_DEV_DR_CNT=$(ls /dev/${block_dev} | wc -l)
  if [ $BLOCK_DEV_DR_CNT -eq 1 ]; then
    echo "Starting prep read on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}" | tee -a ./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/burnin_fio.log   
    fio --rw=read --blocksize=512k --size=100% --ioengine=libaio --iodepth=256 --direct=1 --invalidate=1 --filename=/dev/${block_dev}  --name=prep_512k_read --output="./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/prep_read.log" &
    sleep 1
  else 
    echo "Block device driver $block_dev disappeared on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}" | tee -a /tmp/burnin_summary.log
  fi
done
wait
echo -e "Scan6:\n`./griffin scan`" | tee -a /tmp/burnin_summary.log

START_TIME=$(date +%s)
for (( i = 1 ; i <= $NUM_DEVS ; i++ )) do
  dev=`cat $TMP_FILE | awk "NR==$i"`
  dev_dec=`printf "%d" 0x$dev`
  pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
  char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
  serial_num=`./griffin read-fru /dev/${char_dev} | grep -A1 "LTC" | grep "Serial Number" | sed 's/ \+//g' | cut -d ':' -f2`
  block_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3 | sed 's/ctl//g' | sed 's/$/n1/g'`
  BLOCK_DEV_DR_CNT=$(ls /dev/${block_dev} | wc -l)
  if [ $BLOCK_DEV_DR_CNT -eq 1 ]; then
    echo "Starting stress test on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}" | tee -a ./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/burnin_fio.log   
    fio --runtime=${RUNTIME} --direct=1 --ioengine=libaio --iodepth=32 --time_based --numjobs=1 --ramp_time=10 --filename=/dev/${block_dev} --name=4k --rwmixread=70 --rw=randrw --bs=4k --output="./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/stress_pattern.log" &
    sleep 1
  else 
    echo "Block device driver $block_dev disappeared on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}" | tee -a /tmp/burnin_summary.log
  fi
done
echo -e "Scan7:\n`./griffin scan`" | tee -a /tmp/burnin_summary.log
   
FIO_NUM_JOBS=$(ps -A | grep fio | wc -l)
FIO_NUM_JOBS=$((FIO_NUM_JOBS/2))
if [ $FIO_NUM_JOBS -lt $NUM_DEVS ]; then
  echo "Running only $FIO_NUM_JOBS fio jobs but $NUM_DEVS devices!?!... ERROR" | tee -a /tmp/burnin_summary.log
  if [ $NUM_DEVS -eq 1 ]; then
    exit 1
  fi
else
  echo "Running all $FIO_NUM_JOBS burnin fio jobs..."
fi
echo -e "Scan8:\n`./griffin scan`" | tee -a /tmp/burnin_summary.log

sleep $((RUNTIME+60))
for (( i = 1 ; i <= $NUM_DEVS ; i++ )) do
  dev=`cat $TMP_FILE | awk "NR==$i"`
  dev_dec=`printf "%d" 0x$dev`
  pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
  char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
  serial_num=`./griffin read-fru /dev/${char_dev} | grep -A1 "LTC" | grep "Serial Number" | sed 's/ \+//g' | cut -d ':' -f2`
  dmesg > ./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/dmesg.log
  ./loader --slot=$dev_dec --msgbuf > ./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/fw-loader.log  
  sleep 10
  
  cat ./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/stress_pattern.log | grep "err= 0" | cut -d ':' -f5-7 | cut -d ' ' -f2- > a.log
if [ -s a.log ]
then
echo 
else
    echo -e "${RED}----- FAILURE:${NC} Stress test FAILED on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}"
    echo "FAIL" | tee fio_${serial_num}.log
    continue
fi

  TIME_STR=$(cat ./card_test_burnin_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}/stress_pattern.log | grep "err= 0" | cut -d ':' -f5-7 | cut -d ' ' -f2-)
  END_TIME=$(date -D"$TIME_STR" +%s)
  if [ "$END_TIME" = "" ] || [ $((END_TIME-START_TIME)) -le $RUNTIME ]; then
    echo -e "${RED}----- FAILURE:${NC} Stress test FAILED on PhysicalSlot:${EXPANDER_MAP[$dev_dec]} SerialNum:${serial_num}" 
    echo "FAIL" | tee fio_${serial_num}.log
  else
    echo -e "${GREEN}----- SUCCESS:${NC} Stress test PASSED on PhysicalSlot:${EXPANDER_MAP[$dev_dec]} SerialNum:${serial_num}"
    echo "PASS" | tee fio_${serial_num}.log
  fi
done
echo -e "Scan9:\n`./griffin scan`" | tee -a /tmp/burnin_summary.log

echo "Burnin end-time: $(date)" | tee -a /tmp/burnin_summary.log
cat /tmp/burnin_summary.log

NUM_SERS=`cat /tmp/serial_nums.txt | wc -l`
for (( i = 1 ; i <= $NUM_SERS ; i++ )) do
  ser=`cat /tmp/serial_nums.txt | awk "NR==$i"`
  if [ ! -d /tmp/${ser} ]; then
    mkdir /tmp/${ser}
  fi
  cp -rf *_${ser}* /tmp/${ser}/.
  mv -f /tmp/*_${ser}* /tmp/${ser}/.
done
echo -e "Scan10:\n`./griffin scan`" | tee -a /tmp/burnin_summary.log
  
exit 0
