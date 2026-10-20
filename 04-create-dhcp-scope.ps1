# Исключаем адрес DC01 (192.168.200.10) и возможные статические адреса
Add-DhcpServerv4Scope -Name "LAN_Clients" `
    -StartRange 192.168.200.30 `
    -EndRange 192.168.200.254 `
    -SubnetMask 255.255.255.0 `
    -State Active

# Настраиваем параметры области: шлюз (DC01) и DNS (DC01)
Set-DhcpServerv4OptionValue -ScopeId 192.168.200.0 `
    -Router 192.168.200.10 `
    -DnsServer 192.168.200.10 `
    -DnsDomain "lab.local"