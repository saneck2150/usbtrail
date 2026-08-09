#include "vmlinux.h"

#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

/*
 * Minimal v0.1 build smoke probe.
 * Real ENTRY -> SUBMIT -> RETURN attribution comes next.
 */
SEC("fentry/usbdev_ioctl")
int BPF_PROG(usbtrail_usbdev_ioctl_enter, struct file* file, unsigned int cmd, unsigned long arg) {
    (void)file;
    (void)cmd;
    (void)arg;
    return 0;
}

char LICENSE[] SEC("license") = "GPL";
