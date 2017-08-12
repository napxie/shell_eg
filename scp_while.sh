#!/usr/bin/expect
set timeout 3000

set server_host " "
set server_user " "
set password " "

set local_root " "
set server_root " "
while { [gets stdin line] >= 0 } {
    if {$line == "EOF"} {
        break
    }

    spawn scp -r $local_root$line $server_user@$server_host:$server_root$line
    expect "*password:"
    send "$password\r"

    expect eof
}

