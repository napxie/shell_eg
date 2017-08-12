#!/bin/bash 

#use nvme tool to create a log file


echo "Start to check NVME SSD SMART criteria"

while read line
do
    STRING_BEGIN=`echo $line | awk -F: '{print $1}' | sed 's/ //g'`
    if [ "$STRING_BEGIN" == "critical_warning" ];then
        echo check $STRING_BEGIN
		STRING_END=`echo $line | awk '{print $NF}'`
		[ "$STRING_END" != "0" ] && echo -e "Failed, The critical_warning of $STRING_END is not equal 0" && exit 1
		echo -e "Pass, The critical_warning of $STRING_END is equal 0\n"
    elif [ "$STRING_BEGIN" == "available_spare" ];then
        echo check $STRING_BEGIN
		STRING_END=`echo $line | awk '{print $NF}'| sed 's/%//g'`
		[ $STRING_END -le 99 ] && echo -e "Failed, The available_spare of $STRING_END is less equal than 99" && exit 1
		echo -e "Pass, the available_spare of $STRING_END is greater than 99\n"
    elif [ "$STRING_BEGIN" == "percentage_used" ];then
        echo check $STRING_BEGIN
		STRING_END=`echo $line | awk '{print $NF}'| sed 's/%//g'`
		[ $STRING_END -gt 1 ] && echo -e "Failed, The percentage_used of $STRING_END is greater than 1" && exit 1
		echo -e "Pass, the percentage_used of $STRING_END is less equal than 1\n"
	elif [ "$STRING_BEGIN" == "media_errors" ];then
        echo check $STRING_BEGIN
		STRING_END=`echo $line | awk '{print $NF}'`
		[ $STRING_END -ge 1 ] && echo -e "Failed, The media_errors of $STRING_END is greater equal than 1" && exit 1
		echo -e "Pass, the media_errors of $STRING_END is less than 1\n"
	elif [ "$STRING_BEGIN" == "WarningTemperatureTime" ];then
        echo check $STRING_BEGIN
		STRING_END=`echo $line | awk '{print $NF}'`
		[ $STRING_END -ge 10 ] && echo -e "Failed, The warning Temperature Time of $STRING_END is greater equal than 10" && exit 1
		echo -e "Pass, the Warning Temperature Time of $STRING_END is less than 10\n"
	elif [ "$STRING_BEGIN" == "CriticalCompositeTemperatureTime" ];then
        echo check $STRING_BEGIN
		STRING_END=`echo $line | awk '{print $NF}'`
		[ $STRING_END -ge 5 ] && echo -e "Failed, The Critical Composite Temperature Time of $STRING_END is greater equal than 5" && exit 1
		echo -e "Pass, the Critical Composite Temperature Time of $STRING_END is less than 5\n"
    fi
done < log

echo Check NVME SSD SMART criteria Pass!