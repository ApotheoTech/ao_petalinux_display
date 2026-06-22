# Ubuntu 24.04 Bring-Up on Custom Kria K26 Carrier (SD Boot)

How to boot Ubuntu 24.04 LTS to a login prompt on a custom K26 carrier, using a
custom `BOOT.BIN` and a patched device tree supplied as `user-override.dtb`.

> Scope: this gets you to a **working terminal / login** on serial console.
> DisplayPort output is **not** covered here (still WIP).

---

## ⚠️ Prerequisite: build the PetaLinux project first

**This guide does not stand alone.** It is the Ubuntu-distro branch and it
*consumes* two artifacts that are produced by the PetaLinux project:

| Artifact | Produced by | Used here for |
| :--- | :--- | :--- |
| `BOOT.BIN` | PetaLinux project (`main`) | FSBL/`psu_init`, PMUFW, ATF, U-Boot for the custom carrier |
| `system.dtb` | PetaLinux project (`main`) | the hardware device tree → patched into `user-override.dtb` |

**Order of operations:**

1. **Build / run the `main` PetaLinux project first** → see the PetaLinux repo:
   **[PetaLinux project — `main`](<LINK-TO-PETALINUX-REPO>)**. That build emits the
   `BOOT.BIN` and `system.dtb` referenced throughout this guide
   (`images/linux/BOOT.BIN`, `images/linux/system.dtb`).
2. **Then follow this guide** (the Ubuntu 24.04 branch) to lay those artifacts onto
   an Ubuntu rootfs and SD-boot.

If `main` hasn't been built, you have no `BOOT.BIN` / `system.dtb` and nothing below
will work. The custom-carrier hardware enablement (clocks, MIO, GT, psu_init) lives
entirely in the PetaLinux project; Ubuntu here supplies only the userspace.

> Branch layout: `main` = PetaLinux BSP/project (hardware) · this branch = Ubuntu
> 24.04 distro bring-up (userspace), dependent on `main`.

---

## What you need

- Custom carrier + K26 SOM, boot-mode straps set to **SD**
- **`BOOT.BIN`** — from the **PetaLinux project (`main`)**, at
  `images/linux/BOOT.BIN` (FSBL/`psu_init` + PMUFW + ATF + U-Boot). This is what
  makes the custom carrier come up.
- **`system.dtb`** — from the same PetaLinux build, at `images/linux/system.dtb`
  (your hardware device tree)
- **Ubuntu 24.04 Kria SD image** — https://ubuntu.com/download/amd (kernel 6.8.x)
- microSD card (use a genuine, decent-quality card)
- USB-serial adapter for console: **115200 8N1**, port `ttyPS0`
- A Linux host with `dtc` (`apt install device-tree-compiler`) and an SD writer

---

## Step 1 — Flash the Ubuntu 24.04 image

Write the downloaded image to the SD card with Etcher (or `dd`). This produces:

- **p1** — FAT32 boot partition (`/boot/firmware`), holds `BOOT.BIN`, `boot.scr.uimg`, `image.fit`
- **p2** — ext4 `writable` partition = the Ubuntu rootfs (`root=LABEL=writable`)

Leave Ubuntu's stock `boot.scr.uimg` and `image.fit` in place — the stock boot
script already has a hook that loads `user-override.dtb` and uses it in place of
the reference Kria DTB.

## Step 2 — Build `user-override.dtb` from your `system.dtb`

Two edits are required. Do both on a host:

```bash
dtc -I dtb -O dts system.dtb -o uo.dts
```

**a) Disable SD write-protect.** Under *this* boot method (Ubuntu 6.8 kernel via
`image.fit` + `user-override.dtb`), the SD card comes up read-only at the block
level — root mounts `ro`, `systemd-remount-fs` fails, and you drop to emergency
mode. `disable-wp;` is the workaround that makes this method mount rw.

> NOTE — this is **not** a carrier hardware fault. The same SD in the same slot
> mounts rw under PetaLinux with no `disable-wp`. The read-only is specific to this
> Ubuntu-over-`image.fit` path (how Ubuntu's 6.8 SDHCI driver handles the WP line
> here), so `disable-wp` is compensating for that method, not for the board.

Add `disable-wp;` to the SD controller node (and the eMMC node, harmless):

```dts
mmc@ff170000 {            /* SD  = mmcblk1 — REQUIRED */
    ...
    disable-wp;
};
mmc@ff160000 {            /* eMMC = mmcblk0 — optional */
    ...
    disable-wp;
};
```

> ⚠️ It is `disable-wp` with a **HYPHEN**. `disable_wp` (underscore) is silently
> ignored by the kernel and does nothing — this was the single biggest time sink.

**b) Set a recognizable model string.** Ubuntu's `flash-kernel` reads
`/proc/device-tree/model`; an empty/unknown string gives `Unsupported platform ''`
and wedges `apt`. On this tree the root `model` is empty/missing (hence the empty
quotes in the error), so you **add** it to the **root `/ {` node** — the outermost
block, alongside `compatible`, not inside `aliases`/`axi`/`cpus`:

```dts
/ {
    compatible = "xlnx,zynqmp";
    model = "ZynqMP K26";        /* ADD THIS — directly in the root node */
    ...
};
```

> The `*` in flash-kernel's db entries (e.g. `ZynqMP K26*`) is a **glob wildcard,
> not a literal character**. `ZynqMP K26` satisfies `ZynqMP K26*`, so use
> `ZynqMP K26` — **do not** put the `*` in your `model` string.

Recompile:

```bash
dtc -I dts -O dtb uo.dts -o user-override.dtb
```

## Step 3 — Copy files to the FAT32 boot partition (p1)

Place these at the **root** of p1, alongside the existing `boot.scr.uimg` / `image.fit`:

- `BOOT.BIN`  (exact name, uppercase)
- `user-override.dtb`  (exact name — watch for stale copies / `.dtb.dtb`)

## Step 4 — Boot

1. Set carrier boot-mode straps to **SD**, insert the card.
2. Connect serial console (**115200 8N1**).
3. Power on.

Boot flow: your `BOOT.BIN` U-Boot → runs `boot.scr.uimg` → loads `image.fit`
(Ubuntu 6.8 kernel + ramdisk) and **your** `user-override.dtb` at `0x70000000` →
`root=LABEL=writable` on p2 → Ubuntu 24.04 reaches the login prompt.

Default login: `ubuntu` / `ubuntu` (forces a password change on first login).

## Step 5 — Verify

```bash
uname -r                 # 6.8.0-xxxx-xilinx (Ubuntu kernel)
cat /etc/os-release      # Ubuntu 24.04
findmnt /                # /dev/mmcblk1p2, options include rw   <-- rw is the win
cat /sys/block/mmcblk1/ro   # 0  (write-protect cleared)
cat /proc/cmdline
```

`findmnt /` showing **rw** = the `disable-wp` fix took and you're past the
emergency-mode trap.

---

## Debug — if the model isn't found (`Unsupported platform ''`)

Read what's live on the running board (authoritative — it's the tree the kernel
actually booted):

```bash
cat /proc/device-tree/model; echo        # e.g. "ZynqMP K26"  (echo adds a newline)
```

Confirm it inside the compiled DTB from a host:

```bash
dtc -I dtb -O dts user-override.dtb | grep -m1 'model ='
```

List the patterns flash-kernel will accept:

```bash
grep -i 'Machine:' /usr/share/flash-kernel/db/all.db | sort -u
```

Check your live model matches a db pattern (same `*` glob semantics as the shell):

```bash
m=$(cat /proc/device-tree/model)
case "$m" in
  "ZynqMP K26"*) echo "matches ZynqMP K26* -> OK" ;;
  *) echo "no match: '$m'" ;;
esac
```

If `/proc/device-tree/model` reads something other than `ZynqMP K26`, the wrong
DTB is live (stale copy) — recheck the `user-override.dtb` on the FAT partition.

---

## Gotchas (all hit during bring-up)

- **`disable-wp` not `disable_wp`** — hyphen, or it's silently ignored. Needed only
  for this Ubuntu method; not a carrier WP fault (PetaLinux mounts rw without it).
- **`user-override.dtb`** must be at the FAT root, exact name; confirm date/size
  to avoid booting a stale copy.
- **`model`** must be non-empty and match a flash-kernel db pattern, or `apt` breaks
  with `Unsupported platform ''`. Add it to the **root `/ {` node**. The `*` in db
  entries is a wildcard — use `ZynqMP K26`, **not** `ZynqMP K26*`.
- **Use a genuine SD card** — flaky cards compound the WP/emergency-mode symptoms.
- Boot path (`image.fit`) is decoupled from `apt`'s kernel management; an `apt`
  kernel upgrade can leave the running kernel and `/lib/modules` mismatched.
  Consider `apt-mark hold` on the kernel once stable.

## Not covered (open)

- **DisplayPort output** — `zynqmp_dpsub` probes but no `/dev/dri` yet on Ubuntu's
  6.8 kernel; under investigation (DRM/psgtr module-load vs vendor-kernel behavior).
