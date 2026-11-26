# Running-kernel observations

The local 0.4.19 candidate adds `system.kernel_observation`. This is installation
metadata, not an applicability verdict. It uses only standard Python modules;
without Python the existing inventory still runs and the observation is empty.

The observer binds observations to the release and architecture and discards a
capture if the release changes during collection. Config reads are bounded to
2 MiB and image reads to 128 MiB. Hashing rejects a file changed or replaced
during measurement. Package commands have three-second timeouts.

The payload distinguishes a running `/proc/config.gz` from an installed boot
config. Only an explicitly detected host scope can read boot config/image and
their dpkg ownership as host evidence. Containers and unknown isolation scopes
report the missing host evidence. They never borrow a container's package
database or boot directory to identify its shared kernel.

The receiver validates this observation against the kernel's full release and
architecture and stores it in the existing component evidence property 2000.
It requires the updated shared helper and receiver include. No Windows-agent
change is needed for these Linux kernel groups.

Publishing an agent version is separate from collecting new evidence on a
machine. Offline machines and stopped collectors still need to run and upload
a fresh capture. Package, config and image metadata must then be compared with
trusted vendor build/source evidence before a Pending changes state.
