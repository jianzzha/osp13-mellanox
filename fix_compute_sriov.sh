#/bin/bash


echo fix tuned profile
ssh root@compute-0  "grep -q '^isolated_cores' /etc/tuned/cpu-partitioning-variables.conf && sed -i 's/^isolated_cores.*/isolated_cores=2,4,6,8,10,12,14,16,18,26,28,30,32,34,36,38,40,42/' /etc/tuned/cpu-partitioning-variables.conf ||  echo 'isolated_cores=2,4,6,8,10,12,14,16,18,26,28,30,32,34,36,38,40,42' >> /etc/tuned/cpu-partitioning-variables.conf"

ssh root@compute-0 "tuned-adm profile cpu-partitioning"

echo reboot compute node
ssh root@compute-0 reboot 

echo wait for compute node come back
sleep 60
for n in $(seq  90); do
  reachable=1
  timeout 1 bash -c "cat < /dev/null > /dev/tcp/compute-0/22" || reachable=0
  if [ $reachable -eq 1 ]; then
    break
  fi
  sleep 1
done

[ $reachable -eq 1 ] || exit 1

# mellanox VF need to be in trust mode
for i in $(seq 0 7); do
   ssh root@compute-0 "ip link set p3p1 vf $i trust on"
done

echo "on compute-0, set mac table entries"
ssh root@compute-0 "ovs-vsctl set bridge br-int other_config:mac-table-size=16384"
ssh root@compute-0 "ovs-vsctl set bridge br-link0 other_config:mac-table-size=16384"
