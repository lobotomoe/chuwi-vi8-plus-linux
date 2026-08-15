# Provenance of `bootia32.efi`

`bootia32.efi` is a byte-for-byte copy of `gcdia32.efi` from Debian's
`grub-efi-ia32-unsigned` package. Nothing was patched, rebuilt or repacked.

## Chain

| Step | Value |
|---|---|
| Suite | Debian 13 "trixie", `main`, `binary-amd64` |
| Package | `grub-efi-ia32-unsigned` |
| Version | `2.12-9+deb13u2` |
| Package URL | `https://deb.debian.org/debian/pool/main/g/grub2/grub-efi-ia32-unsigned_2.12-9+deb13u2_amd64.deb` |
| Package size | 1323616 bytes |
| Package SHA-256 | `e4e12e529871a2b2bc0ce34c8cf272b6f5422aabb867307fae64f20626e11c99` |
| Path inside package | `usr/lib/grub/i386-efi/monolithic/gcdia32.efi` |
| Extracted size | 1867776 bytes |
| **`bootia32.efi` SHA-256** | `d21e473e4f81716aae013720024755cd5ff89c9674ee5326fd3c4c6f7a84f0e7` |

The package SHA-256 above is the one published in Debian's `Packages` index for
`dists/trixie/main/binary-amd64`, which is covered by the archive's signed
`InRelease` file. The same `.deb`, byte-identical, also ships in the pool of the
`debian-13.6.0-amd64-netinst.iso` image.

## Why this binary and not another

GRUB images carry a compiled-in *prefix* that tells them where to look for
`grub.cfg` and modules. Debian builds several 32-bit EFI images with different
prefixes:

| Image | Compiled-in prefix | Use |
|---|---|---|
| `grubia32.efi` | `/EFI/debian` | Installed Debian systems |
| **`gcdia32.efi`** | **`/boot/grub`** | **Removable/optical media** |
| `grubnetia32.efi` | (network) | PXE |

`gcdia32.efi` is the removable-media build. Renamed to `bootia32.efi` and placed in
`\EFI\BOOT\` on a FAT32 stick, it reads `/boot/grub/grub.cfg` from that same stick —
which is precisely where Ubuntu, Lubuntu, Xubuntu and Debian ISOs keep their boot
menu. That makes one file work for all of them with no extra configuration.

It is also *monolithic*: every GRUB module is compiled in, so the `insmod` lines in a
distribution's `grub.cfg` succeed even though the stick carries no `i386-efi` module
directory.

## Verifying it yourself

```sh
shasum -a 256 -c artifacts/SHA256SUMS      # macOS
sha256sum -c artifacts/SHA256SUMS          # Linux
```

To re-derive the file from Debian's archive instead of trusting this copy:

```sh
./scripts/fetch-bootia32.sh --output /tmp/bootia32.efi
shasum -a 256 /tmp/bootia32.efi
```

The script resolves the current package version from Debian's `Packages` index,
verifies the downloaded `.deb` against the SHA-256 in that index, and extracts the
same path. If Debian has since published a newer `grub2` upload the hash will differ
from the one above — that is expected, and the script prints the version it used.

## License

GRUB is GNU GPL v3 or later, and `bootia32.efi` is therefore **not** covered by this
repository's MIT licence — see the note at the end of [`../LICENSE`](../LICENSE).

Redistributing the binary carries the obligation to make the corresponding source
available. It is the unmodified Debian build of `grub2` `2.12-9+deb13u2`, whose exact
corresponding source is:

- <https://deb.debian.org/debian/pool/main/g/grub2/grub2_2.12-9+deb13u2.dsc>
- <https://deb.debian.org/debian/pool/main/g/grub2/grub2_2.12.orig.tar.xz>
- <https://deb.debian.org/debian/pool/main/g/grub2/grub2_2.12-9+deb13u2.debian.tar.xz>

Browsable at <https://sources.debian.org/src/grub2/2.12-9+deb13u2/>. If those URLs have
since been rotated out of the active pool, the same version is kept permanently at
<https://snapshot.debian.org/package/grub2/>.
