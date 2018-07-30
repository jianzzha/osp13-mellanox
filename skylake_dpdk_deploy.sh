#!/bin/bash

error ()
{
  echo $* 1>&2
  exit 1
}

source /home/stack/stackrc || error "can't load stackrc"
if openstack stack list | grep overcloud; then
  openstack stack delete overcloud --wait --y
fi

clean_done=0
for i in $(seq 600); do
  sleep 3
  if ironic node-list | grep clean; then
    continue
  else
    clean_done=1
    break
  fi
done

if ((clean_done == 0)); then
  echo "node stuck in clean state"
  exit 1
fi

# add -e $PWD/disable-telemetry.yaml to disable ceilometry
# -e /home/stack/docker_registry.yaml
openstack overcloud deploy \
--templates \
-r $PWD/roles_data.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/host-config-and-reboot.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/neutron-ovs-dpdk.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/ovs-dpdk-permissions.yaml \
-e /home/stack/docker_registry.yaml \
-e $PWD/skylake-dpdk-environment.yaml \
-e $PWD/disable-telemetry.yaml \
--ntp-server clock.redhat.com

[ $? -eq 0 ] || exit 1
echo "modify /etc/hosts entry"
sudo sed -i -r '/compute/d' /etc/hosts
sudo sed -i -r '/controller/d' /etc/hosts
nova list | sed -r -n 's/.*(compute-[0-9]+).*ctlplane=([0-9.]+).*/\2 \1/p' | sudo tee --append /etc/hosts >/dev/null
nova list | sed -r -n 's/.*(controller-[0-9]+).*ctlplane=([0-9.]+).*/\2 \1/p' | sudo tee --append /etc/hosts >/dev/null

## copy public key over these nodes
for node in $(sed -r -n 's/.*(compute-[0-9]+|controller-[0-9]+).*/\1/p' /etc/hosts); do
    ANSIBLE_HOST_KEY_CHECKING=False UserKnownHostsFile=/dev/null ansible all -i $node, -m shell -a "> /root/.ssh/authorized_keys; echo $(sudo cat /home/stack/.ssh/id_rsa.pub) >> /root/.ssh/authorized_keys; echo $(sudo cat /root/.ssh/id_rsa.pub) >> /root/.ssh/authorized_keys" -u heat-admin -b
done

## clean known_hosts
> /home/stack/.ssh/known_hosts
