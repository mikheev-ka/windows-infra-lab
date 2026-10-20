# Повышение до контроллера домена (пример для домена lab.local)
$pass = "Qq123456" | ConvertTo-SecureString -AsPlainText -Force
Install-ADDSForest -DomainName "lab.local" -InstallDns -SafeModeAdministratorPassword $pass -Force