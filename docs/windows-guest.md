# Windows 10 Pro как гостевая ОС МосТех

## Проверенная схема
Хост и гостевая Windows — разные компьютеры в одном корпоративном домене; у Windows отдельные IP/MAC. Пользователь запускает Windows через `virt-manager` вручную и переключается на полный экран. Для удалённого администрирования гостевой ОС применяется **LiteManager**, не RDP.

## Зависимости и официальные ресурсы
- **QEMU:** https://www.qemu.org/
- **virt-manager:** https://virt-manager.org/
- **libvirt:** https://libvirt.org/
- **VirtIO Windows drivers:** https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/ и https://github.com/virtio-win/virtio-win-pkg-scripts
- **SPICE и Windows Guest Tools:** https://www.spice-space.org/download.html
- **WinFsp (для сценариев файловой интеграции):** https://winfsp.dev/ и https://github.com/winfsp/winfsp/releases
- **LiteManager:** https://www.litemanager.ru/ (проверять документацию и лицензирование у поставщика)
- **Windows ISO:** получать из утверждённого организацией источника Microsoft/корпоративного лицензирования.

Не хранить в GitHub ISO, EXE/MSI, проприетарные установщики, инструменты обхода активации и корпоративные образы.

## Установка
1. Подготовить хост KVM/libvirt и `br0`, как указано в QUICKSTART.
2. В `virt-manager` создать Windows VM из авторизованного ISO; задать ресурсы по возможностям ПК.
3. Настроить сетевой интерфейс VM на **Bridge br0** (рекомендован `virtio` после наличия драйверов).
4. Установить Windows; установить необходимые гостевые драйверы из проверенного источника.
5. Ввести Windows в домен согласно корпоративным правилам, настроить GPO и LiteManager.
6. Проверить IP, сеть, вход под доменным пользователем и полноэкранную консоль.

## Unattended
`windows/autounattend.xml` — обезличенная копия исходного XML с `CHANGE_ME_USERNAME` и `CHANGE_ME_PASSWORD`; перед применением необходимо заменить заглушки локально и **не коммитить реальные реквизиты**. `windows/autounattend.example.xml` — минимальный безопасный пример. Исходный XML не публикуется. Исходный приватный `autounattend.xml` содержит plaintext-пароль и НЕ МОЖЕТ быть опубликован. В исходном файле Windows Pro выбиралась индексом `3`; индекс зависит от конкретного ISO и должен определяться отдельно.

## Virtio-FS
`windows/virtio-fs-y-drive.reg` задаёт `MountPoint = Y:` для службы Virtio-FS. Этот REG сам по себе **не настраивает** общую папку на Linux-хосте и не устанавливает необходимые драйверы или WinFsp. Сделать резервную копию реестра, проверять версию драйверов, не применять без подтверждённой схемы подключения.

## Неизвестные параметры
В исходных материалах не зафиксированы точные значения CPU, RAM, размера диска, модели видеокарты, способа автозагрузки Virtio-FS и настроек LiteManager. Не подставлять вымышленные значения.
