#!/usr/bin/env bash
#
# Make the cameras survive a reboot and a kernel upgrade.
#
# Without this the modules are built for one exact kernel: the next update
# changes vermagic and the camera disappears without a word. DKMS rebuilds both
# modules whenever a kernel is installed, which turns a silent breakage into a
# visible build failure.
#
# Run after build-modules.sh. Needs the sources it left in ~/src.

set -o errexit
set -o nounset
set -o pipefail

build_root="${BUILD_ROOT:-$HOME/src}"
atomisp_src="$build_root/atomisp-build/src/drivers/staging/media/atomisp"
ov2680_src="$build_root/ov2680-build/ov2680.c"
version=1.0

log() { printf -- '--- %s\n' "$*"; }

for path in "$atomisp_src/Makefile" "$ov2680_src"; do
  [[ -e $path ]] || { printf 'error: missing %s, run build-modules.sh first\n' "$path" >&2; exit 1; }
done

command -v dkms > /dev/null || { printf 'error: dkms is not installed\n' >&2; exit 1; }

# Without the meta package a future kernel arrives with no headers and every
# DKMS build after it fails.
if ! dpkg-query -W -f='${Status}' linux-headers-generic 2>/dev/null | grep -q '^install ok installed'; then
  log "installing linux-headers-generic so future kernels bring their headers"
  sudo apt-get install -y -q linux-headers-generic
fi

log "atomisp sources into /usr/src/atomisp-vi8-$version"
sudo rm -rf "/usr/src/atomisp-vi8-$version"
sudo mkdir -p "/usr/src/atomisp-vi8-$version"
sudo cp -a "$atomisp_src/." "/usr/src/atomisp-vi8-$version/"
sudo find "/usr/src/atomisp-vi8-$version" \
     \( -name '*.o' -o -name '*.ko' -o -name '*.cmd' -o -name '*.mod' \
        -o -name '*.mod.c' -o -name 'modules.order' -o -name 'Module.symvers' \) -delete

# atomisp's Makefile writes its includes as $(srctree)/drivers/staging/media/
# atomisp/..., and linux-headers ships no driver sources, so the build tree has
# to be reachable at exactly that path inside the headers tree before make runs.
sudo tee "/usr/src/atomisp-vi8-$version/dkms-pre-build.sh" > /dev/null <<'PRE'
#!/bin/sh
set -eu
headers=${kernel_source_dir:-/lib/modules/$kernelver/build}
mkdir -p "$headers/drivers/staging/media"
ln -sfn "$(pwd)" "$headers/drivers/staging/media/atomisp"
PRE

# Leaving the symlink behind would dangle once DKMS clears the build tree.
sudo tee "/usr/src/atomisp-vi8-$version/dkms-post-build.sh" > /dev/null <<'POST'
#!/bin/sh
set -eu
headers=${kernel_source_dir:-/lib/modules/$kernelver/build}
rm -f "$headers/drivers/staging/media/atomisp"
POST

sudo chmod +x "/usr/src/atomisp-vi8-$version/dkms-pre-build.sh" \
              "/usr/src/atomisp-vi8-$version/dkms-post-build.sh"

sudo tee "/usr/src/atomisp-vi8-$version/dkms.conf" > /dev/null <<CONF
PACKAGE_NAME="atomisp-vi8"
PACKAGE_VERSION="$version"
AUTOINSTALL="yes"
PRE_BUILD="dkms-pre-build.sh"
POST_BUILD="dkms-post-build.sh"
MAKE[0]="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build CONFIG_INTEL_ATOMISP=y CONFIG_VIDEO_ATOMISP=m modules"
CLEAN="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
BUILT_MODULE_NAME[0]="atomisp"
DEST_MODULE_LOCATION[0]="/updates"
BUILT_MODULE_NAME[1]="atomisp_gmin_platform"
BUILT_MODULE_LOCATION[1]="pci"
DEST_MODULE_LOCATION[1]="/updates"
CONF

log "ov2680 sources into /usr/src/ov2680-vi8-$version"
sudo rm -rf "/usr/src/ov2680-vi8-$version"
sudo mkdir -p "/usr/src/ov2680-vi8-$version"
sudo cp "$ov2680_src" "/usr/src/ov2680-vi8-$version/ov2680.c"
printf 'obj-m += ov2680.o\n' | sudo tee "/usr/src/ov2680-vi8-$version/Makefile" > /dev/null
sudo tee "/usr/src/ov2680-vi8-$version/dkms.conf" > /dev/null <<CONF
PACKAGE_NAME="ov2680-vi8"
PACKAGE_VERSION="$version"
AUTOINSTALL="yes"
MAKE[0]="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build modules"
CLEAN="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
BUILT_MODULE_NAME[0]="ov2680"
DEST_MODULE_LOCATION[0]="/updates"
CONF

for pkg in atomisp-vi8 ov2680-vi8; do
  log "dkms $pkg/$version"
  sudo dkms remove "$pkg/$version" --all > /dev/null 2>&1 || true
  sudo dkms add "$pkg/$version"
  sudo dkms build "$pkg/$version"
  sudo dkms install "$pkg/$version"
done

log "status"
dkms status
