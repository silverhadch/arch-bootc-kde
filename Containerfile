FROM docker.io/archlinux/archlinux:latest AS builder

ENV BOOTC_ROOTFS_MOUNTPOINT=/mnt

RUN mkdir -p "${BOOTC_ROOTFS_MOUNTPOINT}/var/lib/pacman" && \
    pacman -r "${BOOTC_ROOTFS_MOUNTPOINT}" --cachedir=/var/cache/pacman/pkg -Syyuu --noconfirm \
      base \
      dracut \
      linux \
      linux-firmware \
      ostree \
      systemd \
      btrfs-progs \
      e2fsprogs \
      xfsprogs \
      dosfstools \
      skopeo \
      dbus \
      dbus-glib \
      glib2 \
      pacman \
      shadow && \
  cp /etc/pacman.conf "${BOOTC_ROOTFS_MOUNTPOINT}/etc/pacman.conf" && \
  cp -r /etc/pacman.d "${BOOTC_ROOTFS_MOUNTPOINT}/etc/" && \
  pacman -S --clean && \
  rm -rf /var/cache/pacman/pkg/*

RUN pacman -Syu --noconfirm base-devel git rust ostree dracut whois && \
  pacman -S --clean && \
  rm -rf /var/cache/pacman/pkg/*

RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root \
    git clone https://github.com/bootc-dev/bootc.git /tmp/bootc && \
    cd /tmp/bootc && \
    CARGO_FEATURES="composefs-backend" make bin && \
    make install-all && \
    make install-initramfs-dracut && \
    git clone https://github.com/p5/coreos-bootupd.git -b sdboot-support /tmp/bootupd && \
    cd /tmp/bootupd && \
    cargo build --release --bins --features systemd-boot && \
    make install

RUN sh -c 'export KERNEL_VERSION="$(basename "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)")" && \
    dracut --force --no-hostonly --reproducible --zstd --verbose --kver "$KERNEL_VERSION"  "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"'

RUN cd "${BOOTC_ROOTFS_MOUNTPOINT}" && \
    mkdir -p boot sysroot var/home && \
    rm -rf var/log home root usr/local srv && \
    ln -s /var/home home && \
    ln -s /var/roothome root && \
    ln -s /var/usrlocal usr/local && \
    ln -s /var/srv srv

# Update useradd default to /var/home instead of /home for User Creation
RUN sed -i 's|^HOME=.*|HOME=/var/home|' "${BOOTC_ROOTFS_MOUNTPOINT}/etc/default/useradd"

# Setup a temporary root passwd (changeme) for dev purposes
# TODO: Replace this for a more robust option when in prod
RUN usermod --root "${BOOTC_ROOTFS_MOUNTPOINT}" -p "$(echo "changeme" | mkpasswd -s)" root

# Necessary for `bootc install`
RUN mkdir -p /usr/lib/ostree && \
    printf  "[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n" | \
    tee "/usr/lib/ostree/prepare-root.conf"

FROM scratch AS runtime

COPY --from=builder /mnt /

RUN bootc container lint
