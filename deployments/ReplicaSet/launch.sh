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

run_test() {
  mongo --port 47017 --tls --username super_mongo_user --password super_mongo_user_pwd <<EOF
show dbs;

quit();
EOF
}

clean_up() {
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_replica_set_primary.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_replica_set_secondary_a.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_replica_set_secondary_b.pid
}

launch() {
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_replica_set_primary.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_replica_set_secondary_a.pid
  kill_if_file_exists $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_replica_set_secondary_b.pid
  
  prepare_certs
  rm -rf logs
  mkdir logs
  rm -rf build/mongo_replica_set
  mkdir -p build/mongo_replica_set/mongodata_primary
  mkdir -p build/mongo_replica_set/mongodata_secondary_a
  mkdir -p build/mongo_replica_set/mongodata_secondary_b

  mongod --config "etc/primary.conf.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_replica_set_primary.pid
  mongod --config "etc/secondary_a.conf.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_replica_set_secondary_a.pid
  mongod --config "etc/secondary_b.conf.yaml" --pidfilepath $ROOT/deployments/$CURRENT_DEPLOYMENT/mongo_replica_set_secondary_b.pid

  mongo --port 47017 --tls <<EOF
db.adminCommand({replSetInitiate: { 
  _id: "mongo_replica_set", 
  members: [
    { _id: 0, host: "127.0.0.1:47017", priority: 2}, 
    { _id: 1, host: "127.0.0.1:47018", priority: 1}, 
    { _id: 2, host: "127.0.0.1:47019", priority: 1} ],
  settings: {
    electionTimeoutMillis: 3000
  }
}})
EOF
  
  # make sure the replica set is ready
  mongo --port 47017 --tls < $ROOT/scripts/check_replicaset_status.js || exit 1

  # super_mongo_user can do anything
  mongo --port 47017 --tls <<EOF
  use admin
  db.createUser(
    {
      user: "super_mongo_user",
      pwd: "super_mongo_user_pwd",
      roles: [
        { role: "userAdminAnyDatabase", db: "admin" },
        { role: "readWriteAnyDatabase", db: "admin" },
        { role: "clusterAdmin", "db" : "admin" }
      ]
    }
  )
EOF
}