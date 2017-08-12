#!/usr/bin/expect
set timeout 3000

set server_host " "
set server_user " "
set password " "

set local_root " "
set server_root " "

spawn scp -r $local_root $server_user@$server_host:$server_root

expect {
    "*password:" {
        send "$password\r"
        exp_continue
    }
    "*?" {
        send "y\r"
    }
}

expect eof
