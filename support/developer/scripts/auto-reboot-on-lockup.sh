#!/bin/bash

sudo sysctl -w kernel.hardlockup_panic=1
sudo sysctl -w kernel.softlockup_panic=1     # optional, catches soft hangs too
sudo sysctl -w kernel.panic=10               # reboot 10s after panic -> SSH returns
sudo sysctl -w kernel.panic_on_oops=1
# persist:
echo -e "kernel.hardlockup_panic=1\nkernel.softlockup_panic=1\nkernel.panic=10\nkernel.panic_on_oops=1" | sudo tee /etc/sysctl.d/99-lockup-panic.conf
