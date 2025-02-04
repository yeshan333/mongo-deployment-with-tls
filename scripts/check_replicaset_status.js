
function checkReplicaSetStatus(timeout) {
    var startTime = new Date().getTime();
    while ((new Date().getTime() - startTime) < timeout * 1000) {
        var status = rs.status();
        for (var i = 0; i < status.members.length; i++) {
            if (status.members[i].stateStr === 'PRIMARY') {
                print("Replica set initialized successfully with a primary node." + status.members[i].name);
                return true;
            }
        }
        print("Waiting for the primary node to be elected...");
        sleep(1000); // check every second
    }
    print("Timeout reached without finding a primary node.");
    return false;
}

// timeout check
var timeoutSeconds = 10;

if (!checkReplicaSetStatus(timeoutSeconds)) {
    print("ReplicaSet initialization failed or timed out.");
    quit(1);
}

// quit MongoDB Shell
quit();