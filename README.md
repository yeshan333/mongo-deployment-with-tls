# MongoDB Deployment in localhost with TLS

Reqiure:
- MongoDB Server
- mkcert

## Quick Start

```shell
bash run.sh
```

## ReplicaSet (PSS)

```shell
# Self-Managed Replica Set
bash run.sh ReplicaSet
```

Topology: [https://www.mongodb.com/docs/manual/images/replica-set-read-write-operations-primary.bakedsvg.svg](https://www.mongodb.com/docs/manual/images/replica-set-read-write-operations-primary.bakedsvg.svg)

![https://www.mongodb.com/docs/manual/images/replica-set-read-write-operations-primary.bakedsvg.svg](https://www.mongodb.com/docs/manual/images/replica-set-read-write-operations-primary.bakedsvg.svg)

## MongoDB Sharding Cluster 【TODO】

```shell
bash run.sh ShardingCluster
```
