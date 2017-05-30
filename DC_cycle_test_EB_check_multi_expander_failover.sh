#!/bin/bash

echo "$0: %%REPOID%%"

# Global variables
VENDOR_DEVICE_ID="80cf" # Device ID for Griffin cards before loading FW
FW_DEVICE_ID="00fa:00ce" # Device ID for Griffin cards after loading FW
TMP_VEND_FILE="/tmp/tmp_vend.txt"
TMP_FW_FILE="/tmp/tmp_fw.txt"
TMP_FILE="/tmp/tmp.txt"
TMP_PCI_DEVS="/tmp/tmp_devs.txt"
declare -A EXPANDER_MAP
EXPANDER_MAP=(['4']='3' ['21']='0' ['12']='1' ['13']='2' ['5']='4' ['20']='5' ['17']='6' ['16']='7' ['9']='8' ['8']='9')
host_ip="192.168.0.213"
username="test"
password="test"
test_name=$1
BMC_IP=`./ipmitool lan print 1 | grep 'IP Address              : ' | cut -c 27-`

function feedback_to_console(){

    feedback_file="$test_name.txt"

    date > $feedback_file
    tail -n 3 $test_name/DC_cycle_test.log >> $feedback_file

    echo "** Start feedback...$host_ip $username/$password $feedback_file"

    ftp -n "$host_ip" << EOF 2>&1> /dev/null
     quote user $username
     quote pass $password
     put $feedback_file
EOF

    rm -f $feedback_file

    echo "** Feedback finish."

}

Locate_Griffins()
{
  # Get the slot numbers for all the Griffin cards attached
  lspci -tv | egrep $VENDOR_DEVICE_ID\|$FW_DEVICE_ID | cut -d '+' -f2 | cut -c2-3 > $TMP_VEND_FILE
  lspci -tv | egrep $VENDOR_DEVICE_ID\|$FW_DEVICE_ID | grep -v "+" | cut -d '-' -f2 | cut -c1-2 > $TMP_FW_FILE

  cat $TMP_VEND_FILE $TMP_FW_FILE | egrep -e '[0-9]+' > $TMP_FILE
  NUM_DEVS=$(cat $TMP_FILE | wc -l)

  lspci | grep Non-Vol | cut -d ' ' -f1 > $TMP_PCI_DEVS
  chmod +rwx /tmp/tmp*.txt
}

LoadDriver_Init()
{
  # Delete previously loaded drivers
  rmmod nvmelite
  rmmod griffin

  # HACK: Remove and rescan the PCI tree before loading drivers
  pci_slot=0000:$(lspci | egrep $FW_DEVICE_ID\|$VENDOR_DEVICE_ID  | tail -1 | cut -d ' ' -f1)
  pci_tree=$(find /sys/devices -name $pci_slot | sed 's/\//#/5'  | cut -d '#' -f1)
  echo 1 > $pci_tree/remove && echo 1 > /sys/bus/pci/rescan
  echo 1 > /sys/bus/pci/rescan

  echo -e "Scan1:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log
  # Load nvme driver on all cards
  sleep 480
  insmod ./griffin.ko
  sleep 20

  echo -e "Scan2:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log
  for (( i=1; i<=$NUM_DEVS; i++ )) do
    pci_slot=`cat $TMP_FILE | awk "NR==$i"`
    dev_dec=`printf "%d" 0x$pci_slot`
    pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
    char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
    if [ "$char_dev" == '' ]; then
      echo "Driver not attached on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}" | tee -a ${test_name}/cycle${num}_summary.log
 #     exit 1
    fi
  done
  echo -e "Scan3:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log

  if [ "$1" == 'init' ];then
rm -rf /tmp/serial_nums.txt
    # Now do a fresh init required. Then check for block device presence 
    for (( i=1; i<=$NUM_DEVS; i++ )) do
      dev=`cat $TMP_FILE | awk "NR==$i"`
      dev_dec=`printf "%d" 0x$dev`
      pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
      char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
      serial_num=`./griffin read-fru /dev/${char_dev} | grep -A1 "LTC" | grep "Serial Number" | sed 's/ \+//g' | cut -d ':' -f2`
      echo $serial_num >> /tmp/serial_nums.txt
      # FW log before init
      ./loader --slot=$dev_dec --msgbuf | tee ${test_name}/DC_cycle_pre-init_cycle${num}_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}.log
      echo "\e[32m Scrub on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]} \e[0m"
      # Init only for fresh start, i.e. cycle 0
      (((./griffin init  /dev/${char_dev} || echo "Scrub failed on pcisel:$pci_sel on PhysicalSlot:${EXPANDER_MAP[$dev_dec]}") 2>&1) | tee ${test_name}/DC_cycle_init_cycle${num}_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}.log) & 
    done
    wait
    sleep 20
  fi
  echo -e "Scan4:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log

  for (( i=1 ; i<=$NUM_DEVS ; i++ )) do
    dev=`cat $TMP_FILE | awk "NR==$i"`
    dev_dec=`printf "%d" 0x$dev`
    pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
    char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
    serial_num=`./griffin read-fru /dev/${char_dev} | grep -A1 "LTC" | grep "Serial Number" | sed 's/ \+//g' | cut -d ':' -f2`
    # Moved FW log verify to here from Log_Status() for debug
    ./loader --slot=$dev_dec --msgbuf | tee ${test_name}/DC_cycle_test_cycle${num}_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}.log 
    sleep 10
    #kill loader process
    processName=$(ps -a | grep loader | awk '{print$1}')
    kill -9 $processName
  done
  echo -e "Scan5:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log

}

Log_Status()
{
  echo -e "Scan6:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log
  for (( i = 1; i <= $NUM_DEVS; i++ )) do
    dev=`cat $TMP_FILE | awk "NR==$i"`
    dev_dec=`printf "%d" 0x$dev`
    pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
    char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
    serial_num=`./griffin read-fru /dev/${char_dev} | grep -A1 "LTC" | grep "Serial Number" | sed 's/ \+//g' | cut -d ':' -f2`
    #FIXME: block dev extraction should work with sysfs fix in FBK, use a hack in the meantime
    # block_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f4`
    block_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3 | sed 's/ctl//g' | sed 's/$/n1/g'`
    # Check block device presence
    ls /dev/${block_dev}
    block_dev_present=$?
    # Check Powerfail shutdown detected and save log
    powerfail_fail=$(cat ${test_name}/DC_cycle_test_cycle${num}_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}.log | grep "Unclean shutdown detected, metadata lost")
    powerfail_pass=$(cat ${test_name}/DC_cycle_test_cycle${num}_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}.log | grep "Powerfail shutdown detected")

    echo "DC Cycle TestLoop:${num} PhysicalSlot:${EXPANDER_MAP[$dev_dec]} SerialNum:${serial_num}" | tee -a ${test_name}/DC_cycle_test.log
    if [[ "$powerfail_pass" != "" && $block_dev_present -eq 0 ]];then
      echo "DC Cycle Test Result: PASS" | tee -a ${test_name}/DC_cycle_test.log
      echo "PASS" | tee -a ${test_name}/DC_cycle_test_${serial_num}.log
    elif [[ "$powerfail_pass" == "" && $block_dev_present -eq 0 ]];then
      echo "DC Cycle Test Result: PASS PARTIAL" | tee -a ${test_name}/DC_cycle_test.log
      echo "PASS" | tee -a ${test_name}/DC_cycle_test_${serial_num}.log
    else
      echo "DC Cycle Test Result: FAIL" | tee -a ${test_name}/DC_cycle_test.log
      echo "FAIL" | tee -a ${test_name}/DC_cycle_test_${serial_num}.log
    fi
  done
  echo -e "Scan7:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log
}

Sensor_Check()
{
  echo -e "Scan8:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log
  for (( i = 1; i <= $NUM_DEVS; i++ )) do
    dev=`cat $TMP_FILE | awk "NR==$i"`
    dev_dec=`printf "%d" 0x$dev`
    pci_sel=`cat $TMP_PCI_DEVS | awk "NR==$i"`
    char_dev=`./griffin scan  -s $pci_sel -q | sed 's/ \+/ /g' | cut -d ' ' -f3`
    serial_num=`./griffin read-fru /dev/${char_dev} | grep -A1 "LTC" | grep "Serial Number" | sed 's/ \+//g' | cut -d ':' -f2`
    ./griffin read-sensor /dev/${char_dev} | tee -a ${test_name}/DC_cycle_test_sensors_cycle${num}_slot${EXPANDER_MAP[$dev_dec]}_${serial_num}.log
  done
  echo -e "Scan9:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log
}

partition()
{
  for (( i = 1; i <= $NUM_DEVS; i++ )) do
    dev=`cat $TMP_FILE | awk "NR==$i"`
    dev_dec=`printf "%d" 0x$dev`
    fdisk /dev/griffin$((i-1))n1 < run_fdisk.txt
    mkfs.ext4 -T largefile /dev/griffin$((i-1))n1p1     
  done

}

#Run FIO    
Start_Fio()
{
  for (( i = 1; i <= $NUM_DEVS; i++ )) do
   ./testfio_multi.sh /dev/griffin$((i-1))n1p1 &
  done
  echo -e "Scan10:\\n `./griffin scan`" | tee -a ${test_name}/cycle${num}_summary.log
}

#judge whether the first time to run DC_cycle_test script
num=$(cat /tmp/num.log)
if [ "$num" == "" ];then
  num=0
  echo "The first time to run DC_cycle_test script"
  sleep 10
fi
if [ "$num" == "10" ];then
  echo "*** test finish ***"
  exit
fi
if [ $num -eq 0 ];then
  # the first time to run DC_cycle_test script
  Locate_Griffins
  LoadDriver_Init init
  Log_Status
  partition
  Start_Fio
  #wait 30 seconds
  sleep 30
  Sensor_Check
  ((num=num+1))
  echo num=$num
  echo $num > /tmp/num.log
  sync
  sync
  sync
  sleep 3
  #DC off/on
  ./reboot.sh $BMC_IP
  #feedback_to_console
else
  Locate_Griffins
  LoadDriver_Init
  Log_Status
  Start_Fio
  sleep 30
  Sensor_Check
  

  ((num=num+1))
  echo num=$num
  echo $num > /tmp/num.log
  sync
  sync
  sync
  sleep 3
  #DC off/on
  ./reboot.sh $BMC_IP
  #feedback_to_console
fi

