```
服务器准备：
确保至少有两台服务器/节点可用，并且它们能够互相通信
确认你的 IP 地址是否正确 (脚本中硬编码的 31.58.137.32 和 52.73.157.190)
确保所有节点上的防火墙允许 GlusterFS 所需的端口（主要是 24007-24008 和 49152+ 的高端口）

curl -v telnet://52.73.157.190:24007
curl -v telnet://31.58.137.32:24007

提前准备存储目录：在每个存储节点上，提前创建并设置正确权限：

docker network create --driver overlay --attachable gluster-net

mkdir -p /data/gluster/brick  
chmod -R 755 /data/gluster

docker node ls

docker node update --label-add gluster-storage=true ip-172-31-17-119.ec2.internal
docker node update --label-add gluster-storage=true non-critical-dev-vm

mkdir -p ./scripts
cp setup-gluster.sh ./scripts/
chmod +x ./scripts/setup-gluster.sh

docker stack deploy -c docker-compose.yml glusterfs

docker stack ps glusterfs

docker exec $(docker ps -q -f name=glusterfs-server) gluster volume info

移出
docker stack rm glusterfs
```
