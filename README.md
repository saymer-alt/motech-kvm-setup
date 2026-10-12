# MoSTech KVM Setup

**Windows 10 Pro внутри МосТех Linux через QEMU/KVM.** Практический проект для доменных рабочих станций МосТех. Минимум на пяти компьютерах используется с лета 2026 года.

> **Статус: initial / documentation-first (v0.1.0-dev).** Скрипты сохранены как рабочая историческая база, но не проходили повторного тестирования и независимого аудита для новых машин. На существующих рабочих станциях ничего автоматически не изменяется.

## Что это решает

Основной ОС остаётся **МосТех Linux**. Пользователь входит в домен в Linux, открывает `virt-manager`, вручную запускает виртуальную **Windows 10 Pro**, переводит её в **полноэкранный режим** и отдельно входит в домен Windows под своей учётной записью.

Подключение VM — **мост `br0` (не NAT)**: Linux и Windows имеют разные IP-адреса и выступают отдельными узлами корпоративной сети. Удалённое администрирование гостевой Windows проводится через **LiteManager**, не RDP.

```text
Корпоративная LAN / DHCP / Active Directory
           │
   Физический Ethernet
           │
      МосТех Linux
    NetworkManager br0 ─── IP хоста
           │
     QEMU/KVM / libvirt
           │
      Windows 10 Pro ──── IP гостя
        (domain + LiteManager)
```

## Начните отсюда

**[QUICKSTART.md](QUICKSTART.md)** — восстановленная инструкция по шагам.

```bash
# Только после прочтения QUICKSTART и подготовки тестовой машины
sudo bash scripts/setup-kvm-motech.sh
# Сетевой мастер требует локальную консоль и DHCP
sudo bash scripts/setup-bridge.sh
# После перелогина
virt-manager
```

## Содержимое
- [scripts/setup-kvm-motech.sh](scripts/setup-kvm-motech.sh) — исходная установка KVM/libvirt и доступ пользователей.
- [scripts/setup-bridge.sh](scripts/setup-bridge.sh) — мастер `br0` через NetworkManager.
- [legacy/setup-kvm-motech-v1.sh](legacy/setup-kvm-motech-v1.sh) — ранняя версия установщика.
- [docs/networking.md](docs/networking.md) — мост, отдельный IP и риски.
- [docs/polkit.md](docs/polkit.md) — доменные пользователи, группа `libvirt`, права.
- [docs/windows-guest.md](docs/windows-guest.md) — Windows, VirtIO, SPICE, WinFsp, LiteManager и официальные источники.
- [windows/autounattend.example.xml](windows/autounattend.example.xml) — обезличенный XML-пример (не полноценная unattended установка).
- [windows/virtio-fs-y-drive.reg](windows/virtio-fs-y-drive.reg) — параметр диска `Y:` для Virtio-FS.
- [docs/security.md](docs/security.md) — аудит рисков, требования к публикации и тестам.

## Критически важно
1. Старый `autounattend.xml` содержал действующий на момент создания открытый пароль. Исходный XML **не загружен** в GitHub; заменить пароль на системах, где он использовался.
2. `setup-bridge.sh` переводит Ethernet в DHCP-мост и может отключить сеть. Не запускать удалённо или на ПК со статическим адресом без плана восстановления.
3. Исходное правило Polkit выдаёт группе `libvirt` широкие полномочия. Использовать только для доверенных пользователей.
4. Параметры RAM/CPU/диска VM, тонкости доменного присоединения и установки LiteManager требуют уточнения по рабочей конфигурации — значения не выдуманы.
5. В репозитории нет Windows-образов, ISO VirtIO и сторонних бинарных программ.

## Правовой статус

Лицензия пока **не выбрана**, поскольку права на материалы, созданные в рабочей среде, необходимо выяснить. Публичность репозитория сама по себе не означает разрешения на копирование или коммерческое использование.

[История и постановка задачи (issue #19)](https://github.com/saymer-alt/keenetic-knowledge-base/issues/19).
