# LinuxReinstall

One-script Linux reinstall from a rescue or live environment: wipe the target
disk, bootstrap the chosen distro family into it, carry the network over,
install the bootloader and hand back a machine you can ssh into.

The machine is never truly empty: it always boots into something, a provider
rescue image or a live ISO. This script runs there and replaces the system on
the target disk, which is exactly what hosting panels call reinstall.

## Supported distros

| Slug | Family | Mechanism |
|---|---|---|
| `debian-12`, `debian-13` | debootstrap | debootstrap with openssh, grub and ifupdown |
| `ubuntu-22.04`, `ubuntu-24.04` | debootstrap | same, ubuntu mirror |
| `devuan-5`, `mint-22`, `kali-roll` | debootstrap | same, respective mirrors |
| `proxmox-8` | proxmox | debootstrap bookworm plus the PVE repository |
| `fedora-42`, `rocky-9`, `alma-9`, `centos-stream-10` | dnf | `dnf --installroot` with core group and grub2 |
| `opensuse-leap-15.6`, `opensuse-tumbleweed` | zypper | `zypper --root` with a repo added first |
| `arch-linux` | pacstrap | `pacstrap -K -G -M` with base, kernel and grub |
| `alpine-3.21` | apk | `apk --root` with alpine-base and openssh |

Add a distro by adding a catalog row; add a family by adding
`lib/bootstrap/<family>.sh`.

## Usage

Boot the machine into its rescue system, then:

```bash
git clone https://github.com/KirillGrachev/LinuxReinstall.git
cd LinuxReinstall

# Inspect what would happen; nothing is touched.
./reinstall.sh --distro debian-12 --disk /dev/sda --dry-run \
    --ssh-key "$(cat ~/.ssh/id_ed25519.pub)"
less /tmp/reinstall-journal.tsv

# For real. The disk is wiped after an interactive confirmation.
sudo ./reinstall.sh --distro debian-12 --disk /dev/sda \
    --hostname edge-01 --ssh-key-file ~/.ssh/id_ed25519.pub \
    --network static --address 203.0.113.10/24 --gateway 203.0.113.1 \
    --boot efi --swap 2048 --timezone Europe/Helsinki
reboot
```

A real run refuses to start without an SSH key: a fresh machine without key
access is a lockout. `--yes` skips the confirmation for automation.

## Safety model

- Guards run before any side effect: mounted target refused, missing device
  refused, non-root real run refused, wipe requires typing yes.
- The rescue check warns instead of failing: live ISOs are legitimate.
- `--dry-run` journals every command line and file write instead of running
  it; `/tmp/reinstall-journal.tsv` is the plan you can read and diff.
- Every external command and file write goes through `run_exec` /
  `run_write_file`, so there is no silent side channel around dry-run.
- Layout is plain GPT: ESP or bios_grub first, optional swap, ext4 root;
  network config is carried from the rescue interface with the default route.

Exit codes: `0` success or help, `1` runtime failure, `2` usage or guard
error, `3` operator declined at the confirmation.

## Tests

```bash
sudo apt-get install -y shellcheck bats
./tests/run-tests.sh
```

The suites cover CLI contract, catalog resolution, guards, sfdisk rendering,
network renderers, bootstrap journals and a full dry-run pipeline order.
CI runs shellcheck plus the suites on ubuntu-24.04.

## Limits (v1)

- amd64 only; arm64 mirrors and grub targets are a follow-up.
- One interface with the default route is carried over; bonding and vlans
  are configured after boot.
- Cross-family installs are limited by the rescue host: debootstrap works
  from any host, while dnf, zypper, pacstrap and apk need their own tool
  plus repo config, so the reliable path for those families is a rescue
  of the same family. The preflight guard refuses early otherwise.
- Image-write installs (Talos, RouterOS) are phase 2: they dd a prepared
  image instead of bootstrapping packages. Windows is out of scope by design.

## License

MIT, see [LICENSE](LICENSE).
