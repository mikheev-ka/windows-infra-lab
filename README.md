# Развертывание Windows Server (DC01) и базовой инфраструктуры

Данный раздел описывает создание лабораторной среды на базе Windows Server. Сервер **DC01** выполняет роль шлюза между внешней сетью (WAN) и изолированной внутренней сетью (LAN), а также предоставляет основные инфраструктурные сервисы: Active Directory, DNS, DHCP и маршрутизацию (NAT).

## Архитектура стенда

| Хостнейм | IP-адрес (LAN) | Роль |
| :--- | :--- | :--- |
| **DC01** | 192.168.200.10 | Шлюз (NAT), AD, DNS, DHCP |
| LINUX-ZABBIX-01 | 192.168.200.30 | Статический IP (настраивается позже) |
| LINUX-VCS | 192.168.200.31 | Статический IP (настраивается позже) |
| LINUX-GRAFANA | 192.168.200.32 | Статический IP (настраивается позже) |
| LINUX-PROMETHEUS | 192.168.200.33 | Статический IP (настраивается позже) |
| LINUX-NODE-1 | 192.168.200.34 | Статический IP (настраивается позже) |
| LINUX-NODE-2 | 192.168.200.35 | Статический IP (настраивается позже) |

> **Порядок развертывания:** Сначала настраивается Windows Server (DC01) с ролью DHCP, которая выдает адреса начиная с `192.168.200.30`. Затем разворачиваются Linux-серверы, которые получают эти адреса по DHCP, после чего мы закрепляем их как статические через `netplan`.

---

## 1. Требования и подготовка

*   **ОС:** Windows Server 2019 / 2022 / 2025 (Desktop Experience).
*   **Сетевые адаптеры:** Минимум два (WAN и LAN).
*   **Имя сервера:** `DC01`.
*   **Особенности настройки сети:**
    *   **LAN-адаптер** (Host-Only) настраивается сразу: `192.168.200.10`, маска `255.255.255.0`, шлюз **пустой** (сервер сам является шлюзом для этой сети), DNS: `127.0.0.1` (или `192.168.200.10`).
    *   **WAN-адаптер** (NAT) изначально **отключен** в настройках виртуальной машины. Он будет включен позже, на этапе настройки RRAS, чтобы избежать конфликтов DNS при повышении сервера до контроллера домена. Адрес получается по DHCP от VirtualBox (стабильно `10.0.2.15`, шлюз `10.0.2.2`).

---

## 2. Установка и настройка Active Directory (AD DS)

> **Автоматизация:** Вы можете использовать скрипт `01_promote_dc.ps1`, запустив его от имени администратора. Он выполнит установку роли и повышение до контроллера домена. После этого сервер перезагрузится.

**Ручной вариант (PowerShell):**
```powershell
# 1. Установка роли
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# 2. Повышение до контроллера домена (пароль DSRM: Qq123456)
$pass = "Qq123456" | ConvertTo-SecureString -AsPlainText -Force
Install-ADDSForest -DomainName "lab.local" -InstallDns -SafeModeAdministratorPassword $pass -Force
```
> **Важно:** После перезагрузки входите в систему под учётной записью `LAB\Administrator`.

---

## 3. Настройка DNS Server

> **Автоматизация:** Скрипт `02_configure_infra.ps1` настроит пересылку и обратную зону автоматически.

**Ручная настройка (PowerShell):**
```powershell
# Настройка пересылки (Forwarders) на публичные DNS
Add-DnsServerForwarder -IPAddress "8.8.8.8", "1.1.1.1"

# Создание обратной зоны (Reverse Lookup Zone) для сети 192.168.200.0/24
Add-DnsServerPrimaryZone -NetworkID "192.168.200.0/24" -ReplicationScope Forest
```

---

## 4. Установка и настройка DHCP Server

**Ручная настройка (PowerShell):**
```powershell
# 1. Установка роли
Install-WindowsFeature -Name DHCP -IncludeManagementTools

# 2. Авторизация в AD
Add-DhcpServerInDC -DnsName "dc01.lab.local" -IPAddress 192.168.200.10

# 3. Создание области (пул адресов .30 - .254)
Add-DhcpServerv4Scope -Name "LAN_Clients" `
    -StartRange 192.168.200.30 `
    -EndRange 192.168.200.254 `
    -SubnetMask 255.255.255.0 `
    -State Active

# 4. Настройка параметров (шлюз, DNS)
Set-DhcpServerv4OptionValue -ScopeId 192.168.200.0 `
    -Router 192.168.200.10 `
    -DnsServer 192.168.200.10 `
    -DnsDomain "lab.local"
```

---

## 5. Установка и настройка RRAS (Маршрутизация и NAT)

**Шаг 0: Добавление WAN-адаптера**
Зайдите в настройки виртуальной машины в VirtualBox, **включите второй сетевой адаптер** (тип подключения: **NAT**) и запустите ВМ. Адаптер получит IP `10.0.2.15` со шлюзом `10.0.2.2`.

**Ручная настройка (PowerShell):**
```powershell
# 1. Установка роли
Install-WindowsFeature -Name RemoteAccess, Routing -IncludeManagementTools

# 2. Включение маршрутизации
Install-RemoteAccess -VPNType RoutingOnly

# 3. Включение пересылки IP-пакетов (замените имена интерфейсов на свои, узнать можно через Get-NetAdapter)
Set-NetIPInterface -Forwarding Enabled -InterfaceAlias "Ethernet", "Ethernet 2"

# 4. Включение правил брандмауэра для маршрутизации
Get-NetFirewallRule -DisplayGroup *routing* | Enable-NetFirewallRule
```

*Графическая настройка NAT выполняется в консоли **RRAS** (правой кнопкой по NAT -> Новый интерфейс -> выбрать WAN как публичный, LAN как частный).*

---

## 6. Проверка работоспособности

1.  **Проверка DHCP:** Подключите тестовый клиент (или виртуальную машину) к сети `Host-Only` и убедитесь, что он получил IP из диапазона `192.168.200.30 – 254`, шлюз `192.168.200.10` и DNS `192.168.200.10`.
2.  **Проверка DNS:** С клиента выполните `nslookup google.com` – должен вернуться IP-адрес.
3.  **Проверка NAT (выход в интернет):** С клиента выполните `ping 8.8.8.8`.
4.  **Проверка маршрутизации между сетями:** С DC01 выполните `ping 10.0.2.2` (шлюз провайдера) и `ping 192.168.200.30` (сервер Zabbix).

---

## Примечания и рекомендации

*   **Статическая маршрутизация клиентов:** Когда вы настроите статические IP на Linux-серверах через `netplan`, рекомендуется добавить эти адреса в исключения DHCP (`Add-DhcpServerv4ExclusionRange`), чтобы сервер случайно не выдал их другим устройствам в будущем.
*   **Особенность NAT в VirtualBox:** Адрес `10.0.2.15` закрепляется за виртуальной машиной намертво, что делает схему стабильной.
*   **Резервное копирование:** После настройки всех ролей создайте снимок (snapshot) виртуальной машины DC01.


### Файл `windows-infra-lab/02_configure_infra.ps1`
*(Обновлен диапазон DHCP обратно на `.30-.254`)*

```powershell
# Скрипт настройки DNS, DHCP и RRAS
# Запускать от имени Администратора ПОСЛЕ перезагрузки и входа в домен LAB\Administrator!
# ВАЖНО: Перед запуском включите WAN-адаптер (NAT) в VirtualBox!

$ErrorActionPreference = "Stop"

Write-Host "=== 1. Настройка DNS (Forwarders, Reverse Zone) ===" -ForegroundColor Cyan
Add-DnsServerForwarder -IPAddress "8.8.8.8", "1.1.1.1"
Add-DnsServerPrimaryZone -NetworkID "192.168.200.0/24" -ReplicationScope Forest

Write-Host "=== 2. Установка и настройка DHCP ===" -ForegroundColor Cyan
Install-WindowsFeature -Name DHCP -IncludeManagementTools
# Авторизация в AD
Add-DhcpServerInDC -DnsName "dc01.lab.local" -IPAddress 192.168.200.10

# Создание области (пул 30-254 для первоначальной выдачи адресов Linux-серверам)
Add-DhcpServerv4Scope -Name "LAN_Clients" `
    -StartRange 192.168.200.30 `
    -EndRange 192.168.200.254 `
    -SubnetMask 255.255.255.0 `
    -State Active

# Настройка параметров области
Set-DhcpServerv4OptionValue -ScopeId 192.168.200.0 `
    -Router 192.168.200.10 `
    -DnsServer 192.168.200.10 `
    -DnsDomain "lab.local"

Write-Host "=== 3. Установка и настройка RRAS ===" -ForegroundColor Cyan
Install-WindowsFeature -Name RemoteAccess, Routing -IncludeManagementTools
Install-RemoteAccess -VPNType RoutingOnly

# Включение пересылки IP-пакетов (проверьте имена адаптеров через Get-NetAdapter)
Write-Host "Включение IP Forwarding..." -ForegroundColor Yellow
Set-NetIPInterface -Forwarding Enabled -InterfaceAlias "Ethernet", "Ethernet 2" -ErrorAction SilentlyContinue

# Включение правил брандмауэра для маршрутизации
Get-NetFirewallRule -DisplayGroup *routing* | Enable-NetFirewallRule

Write-Host "=== Настройка завершена! ===" -ForegroundColor Green
Write-Host "Не забудьте вручную настроить NAT в консоли RRAS:" -ForegroundColor Yellow
Write-Host " 1. Откройте Routing and Remote Access."
Write-Host " 2. Разверните IPv4 -> NAT."
Write-Host " 3. Добавьте WAN-интерфейс как Public (с включенным NAT)."
Write-Host " 4. Добавьте LAN-интерфейс как Private."
```

---

### Файл `windows-infra-lab/01_promote_dc.ps1`
*(Остался без изменений, просто для полноты картины)*

```powershell
# Скрипт установки AD DS и повышения до контроллера домена
# Запускать от имени Администратора!
# ВНИМАНИЕ: WAN-адаптер (NAT) должен быть отключен в VirtualBox!

$ErrorActionPreference = "Stop"

Write-Host "=== 1. Установка роли AD DS ===" -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Write-Host "=== 2. Повышение до контроллера домена ===" -ForegroundColor Cyan
$DomainName = "lab.local"
$SafeModePassword = "Qq123456" | ConvertTo-SecureString -AsPlainText -Force

Write-Host "Создается новый лес: $DomainName" -ForegroundColor Yellow
Write-Host "Пароль DSRM: Qq123456" -ForegroundColor Yellow

# Запуск установки (сервер перезагрузится автоматически)
Install-ADDSForest -DomainName $DomainName `
                   -InstallDns `
                   -SafeModeAdministratorPassword $SafeModePassword `
                   -Force
