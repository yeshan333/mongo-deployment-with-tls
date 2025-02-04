prepare_certs() {
  # ref: https://www.doppler.com/blog/how-to-configure-mongodb-5-for-tlsssl-connections-on-debianubuntu
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/mkcert
  export CAROOT=$ROOT/deployments/$CURRENT_DEPLOYMENT/mkcert
  mkcert -install
  cat mkcert/rootCA.pem mkcert/rootCA-key.pem > mkcert/CA.pem
  # Generate Server Certificate
  mkcert -cert-file mongo-tls.crt -key-file mongo-tls.key localhost 127.0.0.1 ::1
  # Generage Client Certificate
  mkcert -client -cert-file mongo-tls-client.crt -key-file mongo-tls-client.key localhost 127.0.0.1 ::1
  
  # MongoDB Server Certificate
  cat mongo-tls.crt mongo-tls.key > mongo-tls.pem
  # MongoDB Client Certificate、ReplicaSet member Certificate
  cat mongo-tls-client.crt mongo-tls-client.key > mongo-tls-client.pem
}

clean_up() {
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongos_a.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongos_b.pid

  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_config_shard_primary.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_config_shard_secondary_a.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_config_shard_secondary_b.pid
  
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_shard_a_primary.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_shard_a_secondary_a.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_shard_a_secondary_b.pid

  echo "Cleaning up MongoDB Sharding Cluster..."
}

run_test() {
  echo "Running MongoDB Sharding Cluster test..."
  mongo --port 27011 --tls --username mongo_super_user --password mongo_super_user_pwd <<EOF
show dbs;

quit();
EOF
}

check_mongo_ports() {
  host="127.0.0.1"
  port=$1
  if nc -z "$host" "$port"; then
    echo "Mongo Port $port on $host is open."
    return 0
  else
    # mongod、mongos need standby
    echo "Mongo Port $port on $host is not open."
    return 1
  fi
}

ensure_mongo_ports_are_ready() {
  # timeout check in seconds
  timeout=60
  interval=1 # check interval seconds

  for ((i=0; i<timeout; i++)); do
    check_mongo_ports $1
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

prepare_mongo_shard() {
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
  mongo --port 27011 --tls --username mongo_super_user --password mongo_super_user_pwd < $ROOT/scripts/check_sharded_cluster.js || exit 1
}

startup_config_shard() {
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_config_shard_primary.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_config_shard_secondary_a.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_config_shard_secondary_b.pid
  rm -rf $ROOT/deployments/$CURRENT_DEPLOYMENT/build/config_shard_repl
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build/config_shard_repl/mongodata_primary
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build/config_shard_repl/mongodata_secondary_a
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build/config_shard_repl/mongodata_secondary_b

  mongod --config "$ROOT/deployments/$CURRENT_DEPLOYMENT/etc/mongo_config_shard/mongo_cfg_primary.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_config_shard_primary.pid &
  mongod --config "$ROOT/deployments/$CURRENT_DEPLOYMENT/etc/mongo_config_shard/mongo_cfg_secondary_a.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_config_shard_secondary_a.pid &
  mongod --config "$ROOT/deployments/$CURRENT_DEPLOYMENT/etc/mongo_config_shard/mongo_cfg_secondary_b.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_config_shard_secondary_b.pid &

  ensure_mongo_ports_are_ready 27017
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

  mongo --port 27017 --tls < $ROOT/scripts/check_replicaset_status.js || exit 1
}

startup_shard_a() {
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_shard_a_primary.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_shard_a_secondary_a.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_shard_a_secondary_b.pid

  rm -rf $ROOT/deployments/$CURRENT_DEPLOYMENT/build/shard_a_repl
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build/shard_a_repl/mongodata_primary
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build/shard_a_repl/mongodata_secondary_a
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build/shard_a_repl/mongodata_secondary_b

  mongod --config "$ROOT/deployments/$CURRENT_DEPLOYMENT/etc/mongo_shard_a/mongo_cfg_primary.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_shard_a_primary.pid &
  mongod --config "$ROOT/deployments/$CURRENT_DEPLOYMENT/etc/mongo_shard_a/mongo_cfg_secondary_a.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_shard_a_secondary_a.pid &
  mongod --config "$ROOT/deployments/$CURRENT_DEPLOYMENT/etc/mongo_shard_a/mongo_cfg_secondary_b.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_shard_a_secondary_b.pid &

  ensure_mongo_ports_are_ready 37017
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

  mongo --port 37017 --tls < $ROOT/scripts/check_replicaset_status.js || exit 1
}

startup_mongos() {
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongos_a.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongos_b.pid

  mongos --config "$ROOT/deployments/$CURRENT_DEPLOYMENT/etc/mongos/mongos_a_cfg.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongos_a.pid &
  mongos --config "$ROOT/deployments/$CURRENT_DEPLOYMENT/etc/mongos/mongos_b_cfg.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongos_b.pid &

  ensure_mongo_ports_are_ready 27011
  ensure_mongo_ports_are_ready 27012
}

launch() {
  rm -rf $ROOT/deployments/$CURRENT_DEPLOYMENT/build
  rm -rf $ROOT/deployments/$CURRENT_DEPLOYMENT/logs
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/logs
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build

  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build/shard_a_repl/mongodata_primary
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build/shard_a_repl/mongodata_secondary_a
  mkdir -p $ROOT/deployments/$CURRENT_DEPLOYMENT/build/shard_a_repl/mongodata_secondary_b

  prepare_certs

  startup_config_shard
  startup_shard_a
  startup_mongos
  prepare_mongo_shard
}