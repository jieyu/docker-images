#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# This is copied from official dind script:
# https://raw.githubusercontent.com/docker/docker/master/hack/dind
if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
	mount -t securityfs none /sys/kernel/security || {
		echo >&2 'Could not mount /sys/kernel/security.'
		echo >&2 'AppArmor detection and --privileged mode might break.'
	}
fi

# Mount /tmp (conditionally)
if ! mountpoint -q /tmp; then
	mount -t tmpfs none /tmp
fi

# Check cgroupfs.
# TODO(jieyu): Verify the filesystem.
if [ ! -d /sys/fs/cgroup/ ]; then
  echo >&2 'Cgroupfs is not mounted'
  exit 1
fi

# Determine cgroup parent for docker daemon.
# We need to make sure cgroups created by the docker daemon do not
# interfere with other cgroups on the host, and do not leak after this
# container is terminated.
if [ -f /sys/fs/cgroup/systemd/release_agent ]; then
  # This means the user has bind mounted host /sys/fs/cgroup to the
  # same location in the container (e.g., using the following docker
  # run flags: `-v /sys/fs/cgroup:/sys/fs/cgroup`). In this case, we
  # need to make sure the docker daemon in the container does not
  # pollute the host cgroups hierarchy.
  # Note that `release_agent` file is only created at the root of a
  # cgroup hierarchy.
  CGROUP_PARENT="$(grep systemd /proc/self/cgroup | cut -d: -f3)/docker"
else
  CGROUP_PARENT="/docker"

  # For each cgroup subsystem, Docker does a bind mount from the
  # current cgroup to the root of the cgroup subsystem. For instance:
  #   /sys/fs/cgroup/memory/docker/<cid> -> /sys/fs/cgroup/memory
  #
  # This will confuse Kubelet and cadvisor and will dump the following
  # error messages in kubelet log:
  #   `summary_sys_containers.go:47] Failed to get system container stats for ".../kubelet.service"`
  #
  # This is because `/proc/<pid>/cgroup` is not affected by the bind
  # mount. The following is a workaround to recreate the original
  # cgroup environment by doing another bind mount for each subsystem.
  MOUNT_TABLE=$(cat /proc/self/mountinfo)
  DOCKER_CGROUP_MOUNTS=$(echo "${MOUNT_TABLE}" | grep /sys/fs/cgroup | grep docker)
  DOCKER_CGROUP=$(echo "${DOCKER_CGROUP_MOUNTS}" | head -n 1 | cut -d' ' -f 4)
  CGROUP_SUBSYSTEMS=$(echo "${DOCKER_CGROUP_MOUNTS}" | cut -d' ' -f 5)

  echo "${CGROUP_SUBSYSTEMS}" |
  while IFS= read -r SUBSYSTEM; do
    mkdir -p "${SUBSYSTEM}${DOCKER_CGROUP}"
    mount --bind "${SUBSYSTEM}" "${SUBSYSTEM}${DOCKER_CGROUP}"
  done
fi

cleanup() {
    set +e
    docker ps -aq | xargs -r docker stop
    pkill dockerd
}

dockerd \
  --cgroup-parent="${CGROUP_PARENT}" \
  --bip="${DOCKERD_BIP:-172.17.1.1/24}" \
  --mtu="${DOCKERD_MTU:-1400}" &

trap cleanup EXIT

# Wait until dockerd is ready.
until docker ps >/dev/null 2>&1
do
  echo "Waiting for dockerd..."
  sleep 1
done

"$@"
