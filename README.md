# MyOS — собственный Linux-дистрибутив на базе Debian с KDE Plasma

Минимальный, но полноценный дистрибутив: собирается из пакетов Debian,
поставляется с рабочим окружением **KDE Plasma** и **установщиком Calamares**
(можно грузиться в Live-режиме и установить на диск).

## Что внутри
- Debian 12 (bookworm), amd64
- KDE Plasma + набор приложений (Dolphin, Konsole, Kate, Firefox, LibreOffice Writer/Calc/Impress)
- SDDM с автологином живого пользователя `user` / пароль `live`
- Calamares — графический установщик на жёсткий диск
- Поддержка BIOS и UEFI (hybrid ISO)

## Оптимизация для слабых ПК
Дистрибутив специально настроен под слабое железо (1-2 ГБ ОЗУ, HDD, старые CPU):
- **Композитор KWin отключён** (backend XRender, без blur/анимаций) — плавный интерфейс без GPU-нагрузки
- **Baloo (индексация файлов) отключён** — не грузит CPU/диск в фоне
- **Анимации Plasma выключены** (`AnimationDurationFactor=0`)
- **zram-swap** (сжатая память, zstd, 50% ОЗУ) — спасает при малом объёме памяти
- **Тонкий sysctl**: `swappiness=10`, оптимизация кэша и dirty-страниц
- **Отключены лишние сервисы**: ModemManager, avahi, bluetooth, cups-browsed
- **I/O-планировщик** mq-deadline для HDD, none для SSD/NVMe
- **Параметры ядра**: `mitigations=off nowatchdog` — прирост на старых CPU
- **SDDM** вместо тяжёлых DM, X11 вместо Wayland (стабильнее на старом железе)
- **Лёгкий набор пакетов**: LibreOffice по модулям, минимум опциональных KDE-модулей

## Самый лёгкий способ собрать ISO — GitHub Actions (без установки чего-либо)
Ничего ставить на свой ПК не нужно. Облако GitHub соберёт ISO бесплатно.

1. Создай бесплатный аккаунт на https://github.com
2. Создай новый репозиторий (например `myos`).
3. Загрузи туда всё содержимое папки `E:\os` (кнопка **Add file → Upload files**,
   перетащи файлы и папки `.github`, `build-debian-kde.sh`, `README.md`).
4. Открой вкладку **Actions** в репозитории → выбери workflow **Build MyOS ISO**
   → нажми **Run workflow**.
5. Подожди ~20-40 минут. Когда сборка станет зелёной, зайди в неё и внизу
   в разделе **Artifacts** скачай `MyOS-ISO` (это zip с готовым `.iso` внутри).

> Workflow лежит в `.github/workflows/build-iso.yml` и запускается автоматически
> при каждом push, либо вручную кнопкой **Run workflow**.

## Альтернатива — собрать локально на Linux
Если есть Linux-машина или WSL2:

```bash
sudo apt update
sudo apt install -y live-build debootstrap squashfs-tools xorriso \
     grub-pc-bin grub-efi-amd64-bin mtools dosfstools
chmod +x build-debian-kde.sh
sudo ./build-debian-kde.sh
```

Итоговый образ: `MyOS-1.0-amd64.iso`

## Запись на флешку
Linux:
```bash
sudo dd if=MyOS-1.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```
Windows: используй Rufus (режим DD).

## Что настроено «из коробки»
- **Локали**: en_US.UTF-8 + ru_RU.UTF-8, часовой пояс UTC
- **Клавиатура**: раскладки US/RU, переключение Alt+Shift
- **hostname**: `myos`
- **Тема Plasma**: Breeze (лёгкая), иконки Breeze
- **Splash**: Plymouth
- **Установщик Calamares** полностью настроен:
  - Брендинг MyOS (логотип, слайдшоу, цвета) — генерируется при сборке
  - Модули: welcome, locale, keyboard, partition, users, summary, bootloader (GRUB)
  - После установки автоматически удаляются live-пакеты (calamares, live-boot,
    live-config), автологин SDDM, sudo-файл live и ярлык установщика

## Учётные данные
- Live-пользователь: `user` / `live` (sudo без пароля в Live-режиме)
- При установке Calamares создаёт нового пользователя и пароль root

## Кастомизация
- Список пакетов: `config/package-lists/desktop.list.chroot`
- Настройки рабочего стола живого пользователя: `config/includes.chroot/etc/skel/`
- Брендинг Calamares: `config/includes.chroot/etc/calamares/branding/myos/`
- Конфиг установщика: `config/includes.chroot/etc/calamares/settings.conf` и `modules/`
- Локали/клавиатура/hostname: секция «3.1» в `build-debian-kde.sh`
- Имя/версия дистрибутива: переменные в начале `build-debian-kde.sh`

## Структура
```
build-debian-kde.sh   # главный скрипт сборки
README.md             # этот файл
build/                # создаётся при сборке (config/ + временные файлы)
```
