// 定义函数来检查副本集状态
function checkShardingClusterStatus(timeout) {
    var startTime = new Date().getTime();
    while ((new Date().getTime() - startTime) < timeout * 1000) {
        var statusResult = db.getSiblingDB('admin').runCommand( { listshards : 1 } );
        for (var i = 0; i < statusResult.shards.length; i++) {
            if (statusResult.shards[i]._id === 'shard_a_repl') {
                print("ShardingCluster initialization success.");
                return true;
            }
        }
        print("Waiting for the shard initialization...");
        sleep(1000); // check every second
    }
    print("Timeout reached without finding shard_a_repl.");
    return false;
}

// timeout check
var timeoutSeconds = 30;

if (!checkShardingClusterStatus(timeoutSeconds)) {
    print("ShardingCluster initialization failed or timed out. Can't run tests!");
    quit(1);
}

// quit MongoDB Shell
quit();