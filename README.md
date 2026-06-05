# Antminer-checkd    

Авторизуется под заданными учетными данными на вебморде асика и парсит хэшрейт с заданным периодом, при падении хэшрейта ниже заданного отправляют команду перезагрузки.  

# Установка одной строкой:  

sudo curl -sSL https://raw.githubusercontent.com/Tkom3a/antminer-ckeckd/main/install.sh | bash  

# Конфигурацию:  

nano /opt/antminer-checkd/.env  

# Полное удаление:  

chmod 777 uninstall.sh
./uninstall.sh
