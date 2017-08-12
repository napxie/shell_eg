#!/usr/bin/expect
set timeout 20
set ip "192.168.72.1"
set user "root"
set password "smt911te"

spawn ssh "$user\@$ip"

expect "$user@$ip's password:"
send "$password\r"

interact
