FROM docker.io/archlinux/archlinux:latest

# ---------------------------
# Configure Arch snapshot and KDE Linux repo
# ---------------------------
RUN BUILD_DATE=$(curl --fail --silent https://cdn.kde.org/kde-linux/packaging/build_date.txt) && \
    if [ -z "$BUILD_DATE" ]; then \
        echo "ERROR: Could not fetch build_date.txt — refusing to build out-of-sync image." >&2; \
        exit 1; \
    fi && \
    # Point pacman to Arch snapshot
    echo "Server = https://archive.archlinux.org/repos/${BUILD_DATE}/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist && \
    # Add KDE Linux repos using printf
    printf '%s\n' \
        '[kde-linux]' \
        'SigLevel = Never' \
        'Server = https://cdn.kde.org/kde-linux/packaging/packages/' \
        '' \
        '[kde-linux-debug]' \
        'SigLevel = Never' \
        'Server = https://cdn.kde.org/kde-linux/packaging/packages-debug/' \
        >> /etc/pacman.conf

# ---------------------------
# Make /etc world-readable and create /nix directory, update useradd defaults
# ---------------------------
RUN chmod o+rx /etc && \
    mkdir -p /nix && \
    chmod 755 /nix

RUN sed -i 's|^HOME=.*|HOME=/var/home|' /etc/default/useradd

# ---------------------------
# Copy local PKGBUILDs
# ---------------------------
COPY ./packages /packages

# ---------------------------
# Install base-devel and refresh twice
# ---------------------------
RUN pacman -Sy --noconfirm --refresh --refresh && \
    pacman -S --noconfirm sudo base-devel && \
    rm -rf /var/cache/pacman/pkg/*

# ---------------------------
# Create temporary build user
# ---------------------------
RUN useradd -m --shell=/bin/bash build && usermod -L build && \
    cp /etc/sudoers /etc/sudoers.bak && \
    echo "build ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo "root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    chown -R build:build /packages

USER build
WORKDIR /home/build

# ---------------------------
# Build local PKGBUILDs
# ---------------------------
RUN cp -r /packages /home/build && \
    chown -R build:build /home/build/packages && \
    cd /home/build/packages/bootc && makepkg -si --noconfirm && \
    cd /home/build/packages/bootupd && makepkg -si --noconfirm && \
    cd /home/build/packages/composefs-rs && makepkg -si --noconfirm

USER root
WORKDIR /

# Cleanup build user
RUN userdel build && mv /etc/sudoers.bak /etc/sudoers

# ---------------------------
# Install essential system packages and KDE Banana packages
# ---------------------------
RUN pacman -Sy --noconfirm --refresh && \
    pacman -S --noconfirm \
        dracut linux linux-firmware ostree composefs systemd \
        btrfs-progs e2fsprogs xfsprogs udev cpio zstd binutils dosfstools \
        conmon crun netavark skopeo dbus dbus-glib glib2 shadow nix \
        kde-linux sddm && \
    pacman -S --noconfirm --clean && \
    rm -rf /var/cache/pacman/pkg/*

RUN systemctl enable sddm.service

# ---------------------------
# Generate reproducible dracut initramfs
# ---------------------------
RUN KVER=$(basename "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E '*.img' | tail -n 1)") && \
    echo "$KVER" > kernel_version.txt && \
    dracut --force --no-hostonly --reproducible --zstd --verbose --kver "$KVER" \
           --add ostree "/usr/lib/modules/$KVER/initramfs.img" && \
    rm kernel_version.txt

# ---------------------------
# Prepare filesystem for OSTree
# ---------------------------
RUN mkdir -p /boot /sysroot /var/home && \
    rm -rf /var/log /home /root /usr/local /srv && \
    ln -s /var/home /home && \
    ln -s /var/roothome /root && \
    ln -s /var/usrlocal /usr/local && \
    ln -s /var/srv /srv

# ---------------------------
# Cleanup packages directory
# ---------------------------
RUN rm -rf /packages

# ---------------------------
# Copy OSTree configuration
# ---------------------------
COPY files/ostree/prepare-root.conf /usr/lib/ostree/prepare-root.conf

# ---------------------------
# Labels
# ---------------------------
LABEL containers.bootc=1
