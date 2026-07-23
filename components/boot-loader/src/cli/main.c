#include "includes.h"

#define GUEST_MEM_SIZE 0x2000000 /* 32MB */
#define KERNEL_LOAD_ADDR 0x100000

static void die(const char *msg) {
    perror(msg);
    exit(1);
}

int main(int argc, char **argv)
{
    const char *plane0_path = NULL;
    const char *plane1_path = NULL;
    int plane = 0;

    const char *home = getenv("HOME");
    char default_plane0[PATH_MAX];
    if (home)
        snprintf(default_plane0, sizeof(default_plane0), "%s/workspaces/lvbs/test/mkosi-kvm/fedora-kvm.vmlinuz", home);
    else
        strncpy(default_plane0, "/home/user/workspaces/lvbs/test/mkosi-kvm/fedora-kvm.vmlinuz", sizeof(default_plane0));

    /* default host kernel for plane1 */
    const char *default_plane1 = "/boot/vmlinux-6.18.12-200.fc43.x86_64";

    if (argc == 1) {
        plane0_path = default_plane0;
        plane1_path = default_plane1;
    } else if (argc == 2) {
        plane0_path = argv[1];
        plane1_path = default_plane1;
    } else {
        plane0_path = argv[1];
        plane1_path = argv[2];
        if (argc >= 4)
            plane = atoi(argv[3]);
    }

    int kvm_fd = open("/dev/kvm", O_RDWR | O_CLOEXEC);
    if (kvm_fd < 0)
        die("open /dev/kvm");

    int api = ioctl(kvm_fd, KVM_GET_API_VERSION, 0);
    if (api < 0)
        die("KVM_GET_API_VERSION");

    int vm_fd = ioctl(kvm_fd, KVM_CREATE_VM, (unsigned long)0);
    if (vm_fd < 0)
        die("KVM_CREATE_VM");

    /* allocate guest memory */
    void *guest_mem = mmap(NULL, GUEST_MEM_SIZE, PROT_READ | PROT_WRITE,
                           MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
    if (guest_mem == MAP_FAILED)
        die("mmap guest_mem");

    struct kvm_userspace_memory_region region = {
        .slot = 0,
        .flags = 0,
        .guest_phys_addr = 0x0,
        .memory_size = GUEST_MEM_SIZE,
        .userspace_addr = (uint64_t)guest_mem,
    };

    if (ioctl(vm_fd, KVM_SET_USER_MEMORY_REGION, &region) < 0)
        die("KVM_SET_USER_MEMORY_REGION");

    /* load plane0 kernel into guest memory at KERNEL_LOAD_ADDR */
    const uint64_t PLANE0_ADDR = KERNEL_LOAD_ADDR;
    const uint64_t PLANE1_ADDR = 0x200000; /* 2MB */

    int kfd0 = open(plane0_path, O_RDONLY);
    if (kfd0 < 0)
        die("open plane0 kernel");
    ssize_t r0 = pread(kfd0, guest_mem + PLANE0_ADDR, GUEST_MEM_SIZE - PLANE0_ADDR, 0);
    if (r0 < 0)
        die("read plane0 kernel");
    close(kfd0);

    int kfd1 = open(plane1_path, O_RDONLY);
    if (kfd1 < 0)
        die("open plane1 kernel");
    ssize_t r1 = pread(kfd1, guest_mem + PLANE1_ADDR, GUEST_MEM_SIZE - PLANE1_ADDR, 0);
    if (r1 < 0)
        die("read plane1 kernel");
    close(kfd1);

    /* create vCPU */
    int vcpu_fd = ioctl(vm_fd, KVM_CREATE_VCPU, (unsigned long)0);
    if (vcpu_fd < 0)
        die("KVM_CREATE_VCPU");

    int vcpu_mmap_size = ioctl(kvm_fd, KVM_GET_VCPU_MMAP_SIZE, 0);
    if (vcpu_mmap_size <= 0)
        die("KVM_GET_VCPU_MMAP_SIZE");

    void *run = mmap(NULL, vcpu_mmap_size, PROT_READ | PROT_WRITE, MAP_SHARED, vcpu_fd, 0);
    if (run == MAP_FAILED)
        die("mmap kvm_run");

    /* setup basic registers (very minimal) */
    struct kvm_regs regs;
    memset(&regs, 0, sizeof(regs));
    regs.rsp = GUEST_MEM_SIZE - 0x1000;
    regs.rflags = 2;

    /* set initial regs for plane 0 */
    regs.rip = PLANE0_ADDR;
    if (ioctl(vcpu_fd, KVM_SET_REGS, &regs) < 0)
        die("KVM_SET_REGS");

    /* try to set sregs to a sane value (get/set) */
    struct kvm_sregs sregs;
    if (ioctl(vcpu_fd, KVM_GET_SREGS, &sregs) < 0)
        die("KVM_GET_SREGS");

    /* keep existing segments - more advanced setup may be needed */
    if (ioctl(vcpu_fd, KVM_SET_SREGS, &sregs) < 0)
        die("KVM_SET_SREGS");

    printf("Entering run loop (plane0=%s, plane1=%s, start_plane=%d)\n", plane0_path, plane1_path, plane);
    for (;;) {
        /* If the KVM run struct in your kernel includes a `plane` field,
           compile with -DKVM_RUN_HAS_PLANE and the following code will
           set it before each KVM_RUN. */
    /* before each run, set regs depending on target plane */
    if (plane == 0) {
        regs.rip = PLANE0_ADDR;
    } else {
        regs.rip = PLANE1_ADDR;
    }
    if (ioctl(vcpu_fd, KVM_SET_REGS, &regs) < 0)
        die("KVM_SET_REGS (per-plane)");

#ifdef KVM_RUN_HAS_PLANE
    struct kvm_run *kr = (struct kvm_run *)run;
    kr->plane = plane;
#endif

    int ret = ioctl(vcpu_fd, KVM_RUN, 0);
        if (ret < 0) {
            if (errno == EINTR)
                continue;
            die("KVM_RUN");
        }

        struct kvm_run *kr = (struct kvm_run *)run;
        switch (kr->exit_reason) {
        case KVM_EXIT_HLT:
            printf("KVM_EXIT_HLT\n");
            goto out;
        case KVM_EXIT_IO:
            printf("KVM_EXIT_IO\n");
            break;
        case KVM_EXIT_FAIL_ENTRY:
            fprintf(stderr, "KVM_EXIT_FAIL_ENTRY: hardware_entry_failure_reason=0x%llx\n",
                    (unsigned long long)kr->fail_entry.hardware_entry_failure_reason);
            goto out;
        case KVM_EXIT_INTERNAL_ERROR:
            fprintf(stderr, "KVM_EXIT_INTERNAL_ERROR: suberror=0x%x\n", kr->internal.suberror);
            goto out;
        default:
            printf("Unhandled KVM exit reason: %u\n", kr->exit_reason);
            goto out;
        }
    }

out:
    munmap(run, vcpu_mmap_size);
    close(vcpu_fd);
    munmap(guest_mem, GUEST_MEM_SIZE);
    close(vm_fd);
    close(kvm_fd);
    return 0;
}

