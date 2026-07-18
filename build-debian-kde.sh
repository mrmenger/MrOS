#!/usr/bin/env bash
#
# build-debian-kde.sh
# Сборка собственного Debian-based дистрибутива с KDE Plasma и установщиком Calamares.
# Запускать на Linux (Debian/Ubuntu/Kali и т.п.), под Windows не работает.
#
# Установка зависимостей (Debian/Ubuntu):
#   sudo apt update
#   sudo apt install -y live-build debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools calibre? 
#   sudo apt install -y live-build
#
# Использование:
#   sudo ./build-debian-kde.sh
#
set -e
set -u

# === Конфигурация дистрибутива ===
DISTRO_NAME="MyOS"
DISTRO_VERSION="1.0"
ARCH="amd64"
SUITE="bookworm"          # Debian 12
MIRROR="http://deb.debian.org/debian"
LIVE_USER="user"
LIVE_PASS="live"

BUILD_ROOT="$(pwd)/build"
ISO_NAME="${DISTRO_NAME}-${DISTRO_VERSION}-${ARCH}.iso"

echo "==> Очистка предыдущей сборки"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"

# === 1. Инициализация live-build ===
lb config \
    --architecture "$ARCH" \
    --distribution "$SUITE" \
    --mirror-bootstrap "$MIRROR" \
    --mirror-binary "$MIRROR" \
    --binary-images iso-hybrid \
    --bootloader grub-pc \
    --debian-installer none \
    --mode debian \
    --archive-areas "main contrib non-free non-free-firmware" \
    --linux-packages "linux-image" \
    --apt-indices false \
    --apt-recommends true \
    --iso-application "$DISTRO_NAME" \
    --iso-publisher "MyOS Team" \
    --iso-volume "$DISTRO_NAME $DISTRO_VERSION" \
    --bootappend-live "boot=live components quiet splash mitigations=off nowatchdog"

# === 2. Пакеты: база + KDE Plasma + установщик ===
mkdir -p config/package-lists
cat > config/package-lists/desktop.list.chroot <<'PKG'
# Базовая система
linux-image-amd64
live-boot
live-config
systemd
sudo
network-manager
firmware-linux-free
firmware-linux-nonfree
firmware-realtek
firmware-iwlwifi

# Графика и Xorg (минимальный набор драйверов — меньше вес)
xserver-xorg
xserver-xorg-video-all
xinit

# KDE Plasma (базовый, без тяжёлых опциональных модулей)
kde-plasma-desktop
plasma-nm
plasma-pa
dolphin
konsole
kate
ark
spectacle
breeze-gtk-theme
# Лёгкий DM вместо тяжёлого
sddm

# Утилиты — лёгкие замены для слабых ПК
firefox-esr
# Вместо полного LibreOffice — только ядро + писатель/таблицы/презентации
libreoffice-writer
libreoffice-calc
libreoffice-impress
# Печать (минимум)
cups
printer-driver-all
gparted
fonts-dejavu
fonts-noto
# Для генерации логотипов брендинга при сборке
imagemagick
# Экран загрузки (splash)
plymouth
plymouth-themes

# === Оптимизация для слабых ПК ===
# Лёгкий файловый менеджер-альтернатива и терминал при необходимости
# (pcmanfm-qt не ставим, чтобы не тянуть LXQt; Dolphin достаточно лёгкий)
# Аудио-сервер без Pulse (легче): используем pipewire только если есть,
# иначе оставляем базовый ALSA
alsa-utils

# Установщик на целевой диск
calamares
calamares-settings-debian
PKG

# === 3. Скрипты настройки образа ===
mkdir -p config/includes.chroot/etc/skel/Desktop
mkdir -p config/includes.chroot/etc/sddm.conf.d
mkdir -p config/includes.chroot/usr/share/calamares/branding
mkdir -p config/includes.chroot/etc/skel/.config

# Автологин в SDDM (лёгкий DM для слабых ПК)
cat > config/includes.chroot/etc/sddm.conf.d/autologin.conf <<'SDM'
[Autologin]
User=user
Session=plasmax11.desktop

[General]
# X11 надёжнее Wayland на старом железе
DisplayServer=x11

[Theme]
# Пустая/дефолтная лёгкая тема
Current=breeze
SDM

# --- Оптимизация KDE Plasma: отключаем эффекты композитора ---
mkdir -p config/includes.chroot/etc/skel/.config
cat > config/includes.chroot/etc/skel/.config/kwinrc <<'KWIN'
[Compositing]
Enabled=false
OpenGLIsUnsafe=false
Backend=XRender

[Desktops]
Number=1

[Plugins]
blurEnabled=false
contrastEnabled=false
slideEnabled=false
kwin4_effect_fadeEnabled=false
KWIN

# Отключаем поиск/индексацию файлов (Baloo) — жрёт CPU и диск
cat > config/includes.chroot/etc/skel/.config/baloofilerc <<'BALOO'
[Basic Settings]
Indexing-Enabled=false
BALOO

# Отключаем анимации и снижаем визуальную нагрузку Plasma
cat > config/includes.chroot/etc/skel/.config/kdeglobals <<'KGLOB'
[KDE]
AnimationDurationFactor=0
SingleClick=false

[General]
BrowserApplication=firefox-esr.desktop
KGLOB

# Создание живого пользователя и sudo
mkdir -p config/includes.chroot/etc/sudoers.d
cat > config/includes.chroot/etc/sudoers.d/live <<'SUD'
user ALL=(ALL) NOPASSWD: ALL
SUD
chmod 440 config/includes.chroot/etc/sudoers.d/live 2>/dev/null || true

# Ярлык запуска установщика на рабочем столе
cat > config/includes.chroot/etc/skel/Desktop/install.desktop <<'DSK'
[Desktop Entry]
Type=Application
Name=Установить MyOS
Exec=pkexec calamares
Icon=calamares
Terminal=false
Categories=System;
DSK
chmod +x config/includes.chroot/etc/skel/Desktop/install.desktop 2>/dev/null || true

# Хук: создаём пользователя при сборке chroot
mkdir -p config/hooks/live
cat > config/hooks/live/01-user.chroot <<'HOOK'
#!/bin/sh
set -e
if ! id user >/dev/null 2>&1; then
    useradd -m -s /bin/bash user
    echo "user:live" | chpasswd
    usermod -aG sudo,audio,video,plugdev,netdev user
fi
HOOK
chmod +x config/hooks/live/01-user.chroot

# Хук оптимизации для слабых ПК
cat > config/hooks/live/02-lowspec.chroot <<'HOOK'
#!/bin/sh
set -e

# 1. zram-swap — сжатая память вместо/в дополнение к swap на диске.
#    Помогает системам с малым объёмом ОЗУ (1-2 ГБ).
apt-get install -y zram-tools || true
if [ -f /etc/default/zramswap ]; then
    sed -i 's/^#\?PERCENT=.*/PERCENT=50/' /etc/default/zramswap
    sed -i 's/^#\?ALGO=.*/ALGO=zstd/' /etc/default/zramswap
fi

# 2. Уменьшаем агрессивность свопа и настраиваем кэш
cat > /etc/sysctl.d/99-lowspec.conf <<'SYS'
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
SYS

# 3. Отключаем тяжёлые/ненужные для слабых ПК сервисы
for svc in ModemManager.service cups-browsed.service \
           avahi-daemon.service bluetooth.service; do
    systemctl disable "$svc" 2>/dev/null || true
done

# 4. Меньше tty-консолей (экономия памяти)
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/lowspec.conf <<'LOG'
[Login]
NAutoVTs=2
ReserveVT=2
LOG

# 5. Планировщик I/O для HDD (mq-deadline) — плавнее на медленных дисках
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/60-ioscheduler.rules <<'UDEV'
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
UDEV

# 6. preload/prelink не ставим (спорная польза); чистим кэш apt для веса ISO
apt-get clean
HOOK
chmod +x config/hooks/live/02-lowspec.chroot

# === 3.1. Локали, timezone, hostname, консоль ===
mkdir -p config/includes.chroot/etc

# hostname
echo "myos" > config/includes.chroot/etc/hostname
cat > config/includes.chroot/etc/hosts <<'HOSTS'
127.0.0.1	localhost
127.0.1.1	myos
::1		localhost ip6-localhost ip6-allnodes ip6-allrouters
HOSTS

# Локали (en_US + ru_RU UTF-8)
mkdir -p config/includes.chroot/etc/default
cat > config/includes.chroot/etc/locale.gen <<'LGEN'
en_US.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
LGEN
cat > config/includes.chroot/etc/default/locale <<'LOC'
LANG=en_US.UTF-8
LOC

# Раскладка клавиатуры консоли (US + RU переключение Alt+Shift)
cat > config/includes.chroot/etc/default/keyboard <<'KBD'
XKBMODEL="pc105"
XKBLAYOUT="us,ru"
XKBVARIANT=","
XKBOPTIONS="grp:alt_shift_toggle"
BACKSPACE="guess"
KBD

# Хук: генерация локалей и часового пояса при сборке
cat > config/hooks/live/03-locale.chroot <<'HOOK'
#!/bin/sh
set -e
if command -v locale-gen >/dev/null 2>&1; then
    locale-gen || true
fi
ln -sf /usr/share/zoneinfo/UTC /etc/localtime || true
echo "UTC" > /etc/timezone || true
HOOK
chmod +x config/hooks/live/03-locale.chroot

# === 3.2. Дефолтные настройки Plasma (панель, тема, обои) ===
# Тёмная тема Breeze лёгкая и опрятная; курсор и иконки Breeze.
cat >> config/includes.chroot/etc/skel/.config/kdeglobals <<'KGLOB2'

[KDE]
LookAndFeelPackage=org.kde.breeze.desktop
widgetStyle=Breeze

[Icons]
Theme=breeze
KGLOB2

# Скрываем неиспользуемые уведомления Baloo и т.п.
cat > config/includes.chroot/etc/skel/.config/plasma-localerc <<'PLC'
[Formats]
LANG=en_US.UTF-8
PLC

# === 3.3. Брендинг Calamares ===
BRAND_DIR="config/includes.chroot/etc/calamares/branding/myos"
mkdir -p "$BRAND_DIR"

cat > "$BRAND_DIR/branding.desc" <<'BRAND'
---
componentName: myos

welcomeStyleCalamares: false
welcomeExpandingLogo: true

windowExpanding: normal
windowSize: 800px,520px
windowPlacement: center

strings:
    productName:         MyOS
    shortProductName:    MyOS
    version:             1.0
    shortVersion:        1.0
    versionedName:       MyOS 1.0
    shortVersionedName:  MyOS 1.0
    bootloaderEntryName: MyOS
    productUrl:          https://example.org/myos
    supportUrl:          https://example.org/myos/support
    releaseNotesUrl:     https://example.org/myos/notes

images:
    productLogo:         "logo.png"
    productIcon:         "logo.png"
    productWelcome:      "welcome.png"

slideshow: "show.qml"

style:
    sidebarBackground:    "#2c3e50"
    sidebarText:          "#ffffff"
    sidebarTextSelect:    "#3498db"
    sidebarTextHighlight: "#3498db"
BRAND

# Простейший слайдшоу-компонент установщика
cat > "$BRAND_DIR/show.qml" <<'QML'
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }
    Slide {
        Text {
            anchors.centerIn: parent
            text: "Добро пожаловать в MyOS — лёгкий Linux с KDE Plasma"
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 22
            color: "#2c3e50"
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            text: "Оптимизирован для слабых ПК: быстрый старт, минимум нагрузки"
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 22
            color: "#2c3e50"
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            text: "Установка почти завершена. Спасибо, что выбрали MyOS!"
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 22
            color: "#2c3e50"
        }
    }
}
QML

# Плейсхолдеры-картинки (генерируются при сборке через ImageMagick, если есть)
cat > config/hooks/live/04-branding-images.chroot <<'HOOK'
#!/bin/sh
set -e
BDIR=/etc/calamares/branding/myos
mkdir -p "$BDIR"
if command -v convert >/dev/null 2>&1; then
    convert -size 200x200 xc:'#2c3e50' -gravity center \
        -pointsize 40 -fill white -annotate 0 "MyOS" "$BDIR/logo.png" || true
    convert -size 480x260 xc:'#34495e' -gravity center \
        -pointsize 32 -fill white -annotate 0 "MyOS 1.0" "$BDIR/welcome.png" || true
fi
HOOK
chmod +x config/hooks/live/04-branding-images.chroot

# === 3.4. Конфигурация Calamares ===
CALA_DIR="config/includes.chroot/etc/calamares"
mkdir -p "$CALA_DIR/modules"

cat > "$CALA_DIR/settings.conf" <<'CALASET'
---
modules-search: [ local, /usr/lib/x86_64-linux-gnu/calamares/modules ]

instances:
- id:     rootfs
  module: unpackfs
  config: unpackfs.conf

sequence:
- show:
  - welcome
  - locale
  - keyboard
  - partition
  - users
  - summary
- exec:
  - partition
  - mount
  - unpackfs
  - machineid
  - fstab
  - locale
  - keyboard
  - localecfg
  - users
  - networkcfg
  - hwclock
  - contextualprocess
  - bootloader
  - packages
  - luksbootkeyfile
  - plymouthcfg
  - initramfscfg
  - initramfs
  - grubcfg
  - bootloader
  - umount
- show:
  - finished

branding: myos

prompt-install: true
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: false
CALASET

# Модуль unpackfs — распаковка squashfs на целевой диск
cat > "$CALA_DIR/modules/unpackfs.conf" <<'UNPACK'
---
unpack:
    - source: "/run/live/medium/live/filesystem.squashfs"
      sourcefs: "squashfs"
      destination: ""
UNPACK

# Модуль users — параметры пользователя/пароля
cat > "$CALA_DIR/modules/users.conf" <<'USERS'
---
defaultGroups:
    - cdrom
    - floppy
    - sudo
    - audio
    - dip
    - video
    - plugdev
    - netdev
    - bluetooth
autologinGroup:  autologin
doAutologin:     false
sudoersGroup:    sudo
setRootPassword: true
availableShells: /bin/bash
avatarFilePath:  ~/.face
passwordRequirements:
    minLength: 4
    maxLength: -1
USERS

# Модуль bootloader — GRUB
cat > "$CALA_DIR/modules/bootloader.conf" <<'BOOT'
---
efiBootLoader: "grub"
kernel: "/vmlinuz"
img: "/initrd.img"
timeout: "5"
bootloaderEntryName: "MyOS"
kernelParams: [ "quiet", "splash", "mitigations=off", "nowatchdog" ]
grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"
efiBootloaderId: "MyOS"
BOOT

# Модуль packages — удалить live-специфичные пакеты после установки
cat > "$CALA_DIR/modules/packages.conf" <<'PKGCFG'
---
backend: apt
operations:
  - remove:
    - calamares
    - calamares-settings-debian
    - live-boot
    - live-boot-initramfs-tools
    - live-config
    - live-config-systemd
PKGCFG

# Модуль removeuser — почистить live-пользователя после установки
cat > "$CALA_DIR/modules/removeuser.conf" <<'RMUSER'
---
username: user
RMUSER

# contextualprocess: удалить автологин SDDM в установленной системе
cat > "$CALA_DIR/modules/contextualprocess.conf" <<'CTX'
---
- packagechooser_packagechooser:
     enabled:
        - dummy

- always:
    command: "rm -f /etc/sddm.conf.d/autologin.conf; rm -f /etc/sudoers.d/live; rm -f /root/Desktop/install.desktop; rm -f /home/*/Desktop/install.desktop"
    timeout: 30
CTX

# === 4. Сборка ===
echo "==> lb build (это займёт значительное время, ~10-30 мин)"
lb build

# Переименовываем итоговый ISO
if [ -f "live-image-${ARCH}.hybrid.iso" ]; then
    mv "live-image-${ARCH}.hybrid.iso" "../${ISO_NAME}"
    echo "==> Готово: ../${ISO_NAME}"
else
    echo "!! ISO не найден, проверьте вывод lb build"
    exit 1
fi
