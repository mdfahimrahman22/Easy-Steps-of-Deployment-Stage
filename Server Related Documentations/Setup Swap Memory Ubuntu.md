# Setup Swap Memory on Ubuntu Server

This guide explains how to allocate, activate, and permanently configure **Swap Memory** on an Ubuntu Linux server to prevent Out-Of-Memory (OOM) crashes during Docker builds, package installations, and traffic spikes.

---

## 1. Quick Setup (4GB Swap)

Run the following commands on your Ubuntu server:

```bash
# 1. Allocate 4GB space for the swap file
sudo fallocate -l 4G /swapfile

# 2. Restrict permissions (only root can read/write)
sudo chmod 600 /swapfile

# 3. Mark the file as Linux swap area
sudo mkswap /swapfile

# 4. Activate the swap file
sudo swapon /swapfile

# 5. Make swap permanent across server reboots
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## 2. Verify Swap Status

Check memory and swap allocation:

```bash
free -h
```

Output should show:
```text
               total        used        free      shared  buff/cache   available
Mem:           1.9Gi       651Mi       128Mi       3.2Mi       1.3Gi       1.2Gi
Swap:          4.0Gi          0B       4.0Gi
```

Or view active swap devices:

```bash
sudo swapon --show
```

---

## 3. Recommended Optimization: Swappiness Tuning

By default, Ubuntu swappiness is set to `60` (frequently swapping memory to disk). For SSD servers, it is recommended to set swappiness to `10` or `20` so Linux prioritizes physical RAM and only uses swap when RAM is nearly full:

```bash
# Check current swappiness
cat /proc/sys/vm/swappiness

# Temporarily set to 10
sudo sysctl vm.swappiness=10

# Permanently set to 10 across reboots
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
```

---

## 4. How to Remove or Resize Swap (If Needed)

If you ever need to remove or change the swap size:

```bash
# 1. Deactivate swap
sudo swapoff /swapfile

# 2. Remove the file
sudo rm /swapfile

# 3. Remove the entry from /etc/fstab
sudo sed -i '/\/swapfile none swap sw 0 0/d' /etc/fstab
```
