# Manage MongoDB Shard Cluster
# config_shard_repl_primary: mongod --config "$ROOT/examples/mongo_auth/etc/mongo_config_shard/mongo_cfg_primary.yml"
# config_shard_repl_secondary_a: mongod --config "$ROOT/examples/mongo_auth/etc/mongo_config_shard/mongo_cfg_secondary_a.yml"
# config_shard_repl_secondary_b: mongod --config "$ROOT/examples/mongo_auth/etc/mongo_config_shard/mongo_cfg_secondary_b.yml"

# mongo_shard_a_repl_primary: mongod --config "$ROOT/examples/mongo_auth/etc/mongo_shard_a/mongo_cfg_primary.yml"
# mongo_shard_a_repl_secondary_a: mongod --config "$ROOT/examples/mongo_auth/etc/mongo_shard_a/mongo_cfg_secondary_a.yml"
# mongo_shard_a_repl_secondary_b: mongod --config "$ROOT/examples/mongo_auth/etc/mongo_shard_a/mongo_cfg_secondary_b.yml"

# mongos_a: mongos --config "$ROOT/examples/mongo_auth/etc/mongos/mongos_a_cfg.yml"
# mongos_b: mongos --config "$ROOT/examples/mongo_auth/etc/mongos/mongos_b_cfg.yml"


clean_up() {
    echo "Cleaning up MongoDB Sharding Cluster..."
}

run_test() {
    echo "Running MongoDB Sharding Cluster test..."
}

check_mongo_ports() {
  host="127.0.0.1"
  ports=("27011" "27012" "27017" "37017")
  for port in "${ports[@]}"; do
    if nc -z "$host" "$port"; then
        echo "Mongo Port $port on $host is open."
    else
      # mongod、mongos need standby
      return 0
    fi
  done
  return 1
}

ensure_mongo_ports_are_ready() {
  # timeout check in seconds
  timeout=60
  interval=1 # check interval seconds

  for ((i=0; i<timeout; i++)); do
    check_mongo_ports
    result=$?
    if [ $result -ne 1 ]; then
      break
    fi
    sleep $interval
  done

  if [ $i -eq $timeout ]; then
      echo "mongod、mongos starup failed!!!"
      exit 1
  fi
}

check_mongos_shard_status() {

# Cluster Member enable X503 authenticate, need auth access for db
mongo --port 27011 --tls <<EOF
use admin
db.createUser(
  {
    user: "mongo_super_user",
    pwd: "mongo_super_user_pwd",
    roles: [
      { role: "userAdminAnyDatabase", db: "admin" },
      { role: "readWriteAnyDatabase", db: "admin" },
      { role: "clusterAdmin", "db" : "admin" }
    ]
  }
)
EOF

# add sharding
mongo --port 27011 --tls --username mongo_super_user --password mongo_super_user_pwd <<EOF
sh.addShard( "shard_a_repl/127.0.0.1:37017,127.0.0.1:37018,127.0.0.1:37019")
EOF
mongo --port 27012 --tls --username mongo_super_user --password mongo_super_user_pwd <<EOF
sh.addShard( "shard_a_repl/127.0.0.1:37017,127.0.0.1:37018,127.0.0.1:37019")
EOF

# make sure sharded cluster status
mongo --port 27011 --tls --username mongo_super_user --password mongo_super_user_pwd < etc/check_mongo_sharding_cluster.js || exit 1
}

launch() {
    echo "Launching MongoDB Sharding Cluster..."

 # # https://www.mongodb.com/docs/manual/tutorial/deploy-replica-set-with-keyfile-access-control/#deploy-new-replica-set-with-keyfile-access-control
  # openssl rand -base64 756 > replica_set_keyfile
  # chmod 400 replica_set_keyfile

  rm -rf $ROOT/examples/$CURRENT_EXAMPLE/*.log
  rm -rf $ROOT/examples/$CURRENT_EXAMPLE/build/config_shard_repl
  rm -rf $ROOT/examples/$CURRENT_EXAMPLE/build/shard_a_repl

  mkdir -p $ROOT/examples/$CURRENT_EXAMPLE/build/config_shard_repl/mongodata_primary
  mkdir -p $ROOT/examples/$CURRENT_EXAMPLE/build/config_shard_repl/mongodata_secondary_a
  mkdir -p $ROOT/examples/$CURRENT_EXAMPLE/build/config_shard_repl/mongodata_secondary_b

  mkdir -p $ROOT/examples/$CURRENT_EXAMPLE/build/shard_a_repl/mongodata_primary
  mkdir -p $ROOT/examples/$CURRENT_EXAMPLE/build/shard_a_repl/mongodata_secondary_a
  mkdir -p $ROOT/examples/$CURRENT_EXAMPLE/build/shard_a_repl/mongodata_secondary_b

  sleep 3s
  export ROOT=$ROOT
  goreman -f $ROOT/examples/$CURRENT_EXAMPLE/Procfile check
  goreman -b 11855 -f $ROOT/examples/$CURRENT_EXAMPLE/Procfile start &
  echo $! > goreman_process.pid
  disown $(cat goreman_process.pid)

  sleep 5s
  goreman -f $ROOT/examples/$CURRENT_EXAMPLE/Procfile run status

  ensure_mongo_ports_are_ready
  status=$?
  if [ $status -ne 0 ]; then
    # if failed start again
    goreman -b 11855 -f $ROOT/examples/$CURRENT_EXAMPLE/Procfile run restart-all
    ensure_mongo_ports_are_ready
  fi

  mongo --port 27017 --tls <<EOF
db.adminCommand({replSetInitiate: { 
  _id: "config_shard_repl", 
  members: [
    { _id: 0, host: "127.0.0.1:27017", priority: 2}, 
    { _id: 1, host: "127.0.0.1:27018", priority: 1}, 
    { _id: 2, host: "127.0.0.1:27019", priority: 1} ],
  settings: {
    electionTimeoutMillis: 3000
  }
}})
EOF

  mongo --port 27017 --tls < etc/check_replica_set.js || exit 1

  mongo --port 37017 --tls <<EOF
db.adminCommand({replSetInitiate: { 
  _id: "shard_a_repl", 
  members: [
    { _id: 0, host: "127.0.0.1:37017", priority: 2}, 
    { _id: 1, host: "127.0.0.1:37018", priority: 1}, 
    { _id: 2, host: "127.0.0.1:37019", priority: 1} ],
  settings: {
    electionTimeoutMillis: 3000
  }
}})
EOF

  mongo --port 37017 --tls < etc/check_replica_set.js || exit 1

  check_mongos_shard_status
}