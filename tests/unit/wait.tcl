source tests/support/cli.tcl

start_server {tags {"wait network external:skip"}} {
start_server {} {
    set slave [srv 0 client]
    set slave_host [srv 0 host]
    set slave_port [srv 0 port]
    set slave_pid [srv 0 pid]
    set master [srv -1 client]
    set master_host [srv -1 host]
    set master_port [srv -1 port]

    test {Setup slave} {
        $slave slaveof $master_host $master_port
        wait_for_condition 50 100 {
            [s 0 master_link_status] eq {up}
        } else {
            fail "Replication not started."
        }
    }
    
    test {WAIT out of range timeout (milliseconds)} {
        # Timeout is parsed as milliseconds by getLongLongFromObjectOrReply().
        # Verify we get out of range message if value is behind LLONG_MAX
        # (decimal value equals to 0x8000000000000000)
         assert_error "*or out of range*" {$master wait 2 9223372036854775808}
                  
         # expected to fail by later overflow condition after addition
         # of mstime(). (decimal value equals to 0x7FFFFFFFFFFFFFFF)
         assert_error "*timeout is out of range*" {$master wait 2 9223372036854775807}
         
         assert_error "*timeout is negative*" {$master wait 2 -1}         
    }
    
    test {WAIT should acknowledge 1 additional copy of the data} {
        $master set foo 0
        $master incr foo
        $master incr foo
        $master incr foo
        assert {[$master wait 1 5000] == 1}
        assert {[$slave get foo] == 3}
    }

    test {WAIT should not acknowledge 2 additional copies of the data} {
        $master incr foo
        assert {[$master wait 2 1000] <= 1}
    }

    test {WAIT should not acknowledge 1 additional copy if slave is blocked} {
        exec kill -SIGSTOP $slave_pid
        $master set foo 0
        $master incr foo
        $master incr foo
        $master incr foo
        assert {[$master wait 1 1000] == 0}
        exec kill -SIGCONT $slave_pid
        assert {[$master wait 1 1000] == 1}
    }

    test {WAIT implicitly blocks on client pause since ACKs aren't sent} {
        exec kill -SIGSTOP $slave_pid
        $master multi
        $master incr foo
        $master client pause 10000 write
        $master exec
        assert {[$master wait 1 1000] == 0}
        $master client unpause
        exec kill -SIGCONT $slave_pid
        assert {[$master wait 1 1000] == 1}
    }
}}
