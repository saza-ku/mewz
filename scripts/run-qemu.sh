#!/bin/bash
set -ex

REPO_ROOT=$(git rev-parse --show-toplevel)
cd $REPO_ROOT

# Create a test directory for virtio-fs
mkdir -p /tmp/mewz-virtiofs

QEMU_ARGS=(
    "-kernel"
    "zig-out/bin/mewz.qemu.elf"
    "-cpu"
    "Icelake-Server"
    "-m"
    "512"
    "-device"
    "virtio-net,netdev=net0,disable-legacy=on,disable-modern=off"
    "-netdev"
    "user,id=net0,hostfwd=tcp:0.0.0.0:1234-:1234"
    "-chardev"
    "socket,id=char0,path=/tmp/vhostqemu"
    "-device"
    "vhost-user-fs-pci,chardev=char0,tag=myfs,mount_tag=myfs"
    "-object"
    "memory-backend-file,id=mem,size=512M,mem-path=/dev/shm,share=on"
    "-numa"
    "node,memdev=mem"
    "-no-reboot"
    "-serial"
    "mon:stdio"
    "-monitor"
    "telnet::3333,server,nowait"
    "-nographic"
    "-gdb"
    "tcp::12345"
    "-object"
    "filter-dump,id=fiter0,netdev=net0,file=virtio-net.pcap"
    "-device"
    "isa-debug-exit,iobase=0x501,iosize=2"
    "-append"
    "ip=10.0.2.15/24 gateway=10.0.2.2 virtiofs=myfs"
)

DEBUG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d | --debug)
            DEBUG=true
            ;;
        -*)
            echo "invalid option"
            exit 1
            ;;
        *)
            ;;
    esac
    shift
done

if $DEBUG; then
    QEMU_ARGS+=("-S")
fi

# Start virtiofsd in the background
virtiofsd --socket-path=/tmp/vhostqemu --shared-dir=/tmp/mewz-virtiofs --cache=auto &
VIRTIOFSD_PID=$!

# Let x be the return code of Mewz. Then, the return code of QEMU is 2x+1.
qemu-system-x86_64 "${QEMU_ARGS[@]}" || QEMU_RETURN_CODE=$(( $? ))
RETURN_CODE=$(( (QEMU_RETURN_CODE-1)/2 ))

# Cleanup
kill $VIRTIOFSD_PID
rm -f /tmp/vhostqemu

exit $RETURN_CODE

