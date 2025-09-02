FROM docker.io/archlinux/archlinux:latest

# ---------------------------
# Package groups as Bash arrays
# ---------------------------
# System essentials
ARG SYSTEM_PACKAGES="dracut linux linux-firmware ostree composefs systemd btrfs-progs e2fsprogs xfsprogs udev cpio zstd binutils dosfstools conmon crun netavark skopeo dbus dbus-glib glib2 shadow nix sddm"

# KDE packages
ARG KDE_PACKAGES="kde-linux"

# Fonts
ARG FONT_PACKAGES="noto-fonts noto-fonts-cjk noto-fonts-emoji"

# Multimedia
ARG MULTIMEDIA_PACKAGES="qt6-multimedia-ffmpeg plymouth flatpakacpid aha clinfo ddcutil dmidecode mesa-utils ntfs-3g nvme-cli vulkan-tools wayland-utils xorg-xdpyinfo"

# CLI utilities
ARG CLI_PACKAGES="bash-completion bat busybox duf fastfetch fd gping grml-zsh-config htop jq less lsof mcfly nano nix nvtop openssh powertop procs ripgrep tldr trash-cli tree usbutils vim wget wl-clipboard ydotool zsh zsh-completions"

# Firmware / boot / drivers (added apparmor)
ARG FIRMWARE_PACKAGES="amd-ucode intel-ucode edk2-shell efibootmgr shim mesa libva-intel-driver libva-mesa-driver libva-nvidia-driver libva nvidia-open vpl-gpu-rt vulkan-icd-loader vulkan-intel vulkan-radeon apparmor"

# Network / VPN / SMB
ARG NETWORK_PACKAGES="dnsmasq freerdp2 iproute2 iwd libmtp networkmanager-l2tp networkmanager-openconnect networkmanager-openvpn networkmanager-pptp networkmanager-strongswan networkmanager-vpnc nfs-utils nss-mdns samba smbclient ufw"

# Accessibility / speech
ARG ACCESS_PACKAGES="espeak-ng orca"

# Pipewire / audio
ARG PIPEWIRE_PACKAGES="pipewire pipewire-pulse pipewire-zeroconf pipewire-ffado pipewire-libcamera sof-firmware wireplumber"

# Printing
ARG PRINT_PACKAGES="cups cups-browsed gutenprint ipp-usb hplip splix system-config-printer"

# Other user tools / vaults / encoding
ARG USER_PACKAGES="accountsservice aspell cryfs editorconfig-core-c encfs ffmpeg fwupd geoclue gocryptfs hspell icoutils jxrlib libappimage libavif libheif libjxl libraw opencv openexr switcheroo-control"

# Hardware / Xorg / Wayland
ARG HARDWARE_PACKAGES="xorg-xwayland acsccid bmusb ccid dosfstools fprintd iio-sensor-proxy steam-devices-git thermald tpm2-tss tuned-ppd"

# AUR packages
ARG AUR_PACKAGES="usb-dirty-pages-udev waydroid"

# ---------------------------
# Configure Arch snapshot and KDE Linux repo
# ---------------------------
RUN BUILD_DATE=$(curl --fail --silent https://cdn.kde.org/kde-linux/packaging/build_date.txt) && \
    if [ -z "$BUILD_DATE" ]; then \
        echo "ERROR: Could not fetch build_date.txt — refusing to build out-of-sync image." >&2; \
        exit 1; \
    fi && \
    echo "Server = https://archive.archlinux.org/repos/${BUILD_DATE}/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist && \
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
    mkdir -p /nix && chmod 755 /nix && \
    sed -i 's|^HOME=.*|HOME=/var/home|' /etc/default/useradd

# ---------------------------
# Copy local PKGBUILDs
# ---------------------------
COPY ./packages /packages

# ---------------------------
# Install base-devel and refresh twice
# ---------------------------
RUN pacman -Sy --noconfirm --refresh --refresh && \
    pacman -S --noconfirm sudo base-devel git && \
    rm -rf /var/cache/pacman/pkg/*

# ---------------------------
# Temporary build user
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
RUN cp -r /packages /home/build && chown -R build:build /home/build/packages && \
    cd /home/build/packages/bootc && makepkg -si --noconfirm && \
    cd /home/build/packages/bootupd && makepkg -si --noconfirm && \
    cd /home/build/packages/composefs-rs && makepkg -si --noconfirm

# ---------------------------
# Build paru and install AUR packages
# ---------------------------
RUN git clone https://aur.archlinux.org/paru.git /home/build/paru && \
    cd /home/build/paru && makepkg -si --noconfirm && \
    paru -S --noconfirm --needed $AUR_PACKAGES

USER root
WORKDIR /

# Cleanup build user
RUN userdel build && mv /etc/sudoers.bak /etc/sudoers

# ---------------------------
# Install all packages in grouped arrays
# ---------------------------
RUN pacman -Sy --noconfirm --refresh && \
    pacman -S --noconfirm \
        $SYSTEM_PACKAGES \
        $KDE_PACKAGES \
        $FONT_PACKAGES \
        $MULTIMEDIA_PACKAGES \
        $CLI_PACKAGES \
        $FIRMWARE_PACKAGES \
        $NETWORK_PACKAGES \
        $ACCESS_PACKAGES \
        $PIPEWIRE_PACKAGES \
        $PRINT_PACKAGES \
        $USER_PACKAGES \
        $HARDWARE_PACKAGES && \
    rm -rf /var/cache/pacman/pkg/*

# ---------------------------
# Enable/Disable systemd units safely
# ---------------------------
RUN systemctl disable dirmngr@etc-pacman.d-gnupg.socket || true && \
    systemctl disable gpg-agent-browser@etc-pacman.d-gnupg.socket || true && \
    systemctl disable gpg-agent-extra@etc-pacman.d-gnupg.socket || true && \
    systemctl disable gpg-agent-ssh@etc-pacman.d-gnupg.socket || true && \
    systemctl disable gpg-agent@etc-pacman.d-gnupg.socket || true && \
    systemctl disable keyboxd@etc-pacman.d-gnupg.socket || true && \
    systemctl disable archlinux-keyring-wkd-sync.timer || true && \
    systemctl disable systemd-networkd-wait-online.service || true && \
    systemctl disable systemd-networkd.service || true && \
    systemctl enable plasma-setup-live-system.service || true && \
    systemctl enable nvidia-suspend.service || true && \
    systemctl enable nvidia-hibernate.service || true && \
    systemctl enable nvidia-resume.service || true && \
    systemctl enable bluetooth.service || true && \
    systemctl enable cups.service || true && \
    systemctl enable tuned.service || true && \
    systemctl enable tuned-ppd.service || true && \
    systemctl enable thermald.service || true && \
    systemctl enable apparmor.service || true && \
    systemctl enable sddm.service || true && \
    systemctl enable avahi-daemon.socket || true && \
    systemctl enable avahi-daemon.service || true && \
    systemctl enable accounts-daemon.service || true && \
    systemctl enable NetworkManager.service || true

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
