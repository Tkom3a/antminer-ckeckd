#!/usr/bin/env python3
import requests
import time
import logging
import sys
from datetime import datetime
import argparse
import os
import signal
from requests.auth import HTTPDigestAuth

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/asic-monitor.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class ASICMonitor:
    def __init__(self, ip, port, username, password, telegram_token, telegram_chat_id,
                 min_hashrate=0, check_interval=300, reboot_threshold=3):
        self.ip = ip
        self.port = port
        self.username = username
        self.password = password
        self.base_url = f"http://{ip}:{port}"
        self.telegram_token = telegram_token
        self.telegram_chat_id = telegram_chat_id
        self.min_hashrate = min_hashrate
        self.check_interval = check_interval
        self.reboot_threshold = reboot_threshold
        self.last_restart_time = 0
        self.min_restart_interval = 600
        self.session = None
        self.consecutive_errors = 0
        self.running = True
        
    def setup_signal_handlers(self):
        """Настройка обработчиков сигналов для graceful shutdown"""
        signal.signal(signal.SIGTERM, self.shutdown)
        signal.signal(signal.SIGINT, self.shutdown)
    
    def shutdown(self, signum, frame):
        """Graceful shutdown"""
        logger.info("Получен сигнал остановки...")
        self.running = False
        sys.exit(0)
    
    def send_telegram(self, message):
        """Отправка сообщения в Telegram"""
        if not self.telegram_token or not self.telegram_chat_id:
            return False
            
        try:
            url = f"https://api.telegram.org/bot{self.telegram_token}/sendMessage"
            data = {
                "chat_id": self.telegram_chat_id,
                "text": message,
                "parse_mode": "HTML"
            }
            response = requests.post(url, data=data, timeout=10)
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Ошибка Telegram: {e}")
            return False
    
    def setup_session(self):
        """Настройка сессии с авторизацией"""
        try:
            self.session = requests.Session()
            self.session.auth = HTTPDigestAuth(self.username, self.password)
            self.session.headers.update({
                'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
            })
            
            # Проверяем авторизацию
            response = self.session.get(self.base_url, timeout=5)
            if response.status_code == 200:
                logger.info("✅ Digest авторизация работает")
                return True
            else:
                logger.error(f"❌ Ошибка авторизации: статус {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"❌ Ошибка настройки сессии: {e}")
            return False
    
    def check_connection(self):
        """Проверка доступности ASIC"""
        try:
            response = self.session.get(self.base_url, timeout=5)
            return response.status_code == 200
        except:
            return False
    
    def get_hashrate(self):
        """Получение хэшрейта"""
        try:
            # Пробуем получить статистику
            endpoints = [
                f"{self.base_url}/cgi-bin/stats.cgi",
                f"{self.base_url}/cgi-bin/miner_status.cgi"
            ]
            
            for endpoint in endpoints:
                try:
                    response = self.session.get(endpoint, timeout=5)
                    if response.status_code == 200:
                        data = response.json()
                        if 'STATS' in data:
                            for stat in data['STATS']:
                                if 'GHS 5s' in stat:
                                    hashrate = float(stat['GHS 5s']) / 1000
                                    logger.debug(f"Хэшрейт: {hashrate:.2f} TH/s")
                                    return hashrate
                except:
                    continue
            
            return None
        except Exception as e:
            logger.error(f"Ошибка получения хэшрейта: {e}")
            return None
    
    def restart_asic(self):
        """Перезагрузка ASIC"""
        try:
            current_time = time.time()
            if current_time - self.last_restart_time < self.min_restart_interval:
                logger.warning("⏳ Слишком частые перезагрузки, пропускаем")
                return False
            
            logger.info("🔄 Попытка перезагрузки ASIC...")
            
            # Пробуем разные методы перезагрузки
            reboot_methods = [
                (f"{self.base_url}/cgi-bin/reboot.cgi", "GET"),
                (f"{self.base_url}/cgi-bin/reboot", "GET"),
                (f"{self.base_url}/cgi-bin/reboot.cgi", "POST"),
            ]
            
            for url, method in reboot_methods:
                try:
                    if method == "GET":
                        response = self.session.get(url, timeout=10)
                    else:
                        response = self.session.post(url, timeout=10)
                    
                    if response.status_code in [200, 302]:
                        logger.info(f"✅ Команда перезагрузки отправлена через {url}")
                        self.last_restart_time = current_time
                        
                        message = f"🔴 <b>ASIC {self.ip}:{self.port} перезагружен</b>\n"
                        message += f"Причина: низкий хэшрейт\n"
                        message += f"Время: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
                        self.send_telegram(message)
                        return True
                except Exception as e:
                    logger.debug(f"Ошибка при {url}: {e}")
                    continue
            
            logger.error("❌ Не удалось перезагрузить ASIC")
            return False
            
        except Exception as e:
            logger.error(f"❌ Ошибка перезагрузки: {e}")
            return False
    
    def run(self):
        """Основной цикл мониторинга"""
        logger.info(f"🚀 Запуск мониторинга ASIC {self.ip}:{self.port}")
        
        # Настраиваем обработчики сигналов
        self.setup_signal_handlers()
        
        # Настраиваем сессию
        if not self.setup_session():
            self.send_telegram(f"⚠️ <b>ASIC {self.ip}:{self.port}</b>\nОшибка авторизации")
            return
        
        # Отправляем уведомление о запуске
        start_message = f"🟢 <b>Мониторинг ASIC {self.ip}:{self.port} запущен</b>\n"
        start_message += f"Минимальный хэшрейт: {self.min_hashrate} TH/s\n"
        start_message += f"Интервал проверки: {self.check_interval}с"
        self.send_telegram(start_message)
        
        last_hashrate_check = 0
        
        while self.running:
            try:
                # Проверяем подключение
                if not self.check_connection():
                    self.consecutive_errors += 1
                    logger.error(f"❌ Потеря связи ({self.consecutive_errors}/{self.reboot_threshold})")
                    
                    if self.consecutive_errors >= self.reboot_threshold:
                        logger.warning("⚠️ Максимальное количество ошибок, перезагрузка...")
                        if self.restart_asic():
                            self.consecutive_errors = 0
                            time.sleep(120)
                    else:
                        time.sleep(60)
                    continue
                
                # Проверяем хэшрейт
                current_time = time.time()
                if self.min_hashrate > 0 and (current_time - last_hashrate_check) >= 60:
                    hashrate = self.get_hashrate()
                    last_hashrate_check = current_time
                    
                    if hashrate is not None:
                        logger.info(f"📊 Текущий хэшрейт: {hashrate:.2f} TH/s")
                        
                        if hashrate < self.min_hashrate:
                            logger.warning(f"⚠️ Низкий хэшрейт: {hashrate:.2f} TH/s < {self.min_hashrate} TH/s")
                            
                            message = f"⚠️ <b>Низкий хэшрейт на {self.ip}:{self.port}</b>\n"
                            message += f"Текущий: {hashrate:.2f} TH/s\n"
                            message += f"Минимальный: {self.min_hashrate} TH/s\n"
                            message += f"Время: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
                            self.send_telegram(message)
                            
                            if self.restart_asic():
                                self.consecutive_errors = 0
                                time.sleep(120)
                                continue
                    else:
                        logger.warning("⚠️ Не удалось получить хэшрейт")
                        self.consecutive_errors += 1
                        if self.consecutive_errors >= self.reboot_threshold:
                            logger.warning("⚠️ Максимальное количество ошибок получения хэшрейта, перезагрузка...")
                            if self.restart_asic():
                                self.consecutive_errors = 0
                                time.sleep(120)
                        continue
                
                # Всё хорошо - выводим хэшрейт в лог
                if hashrate is not None:
                    logger.info(f"✅ ASIC работает нормально. Хэшрейт: {hashrate:.2f} TH/s")
                else:
                    logger.info(f"✅ ASIC работает нормально")
                
                self.consecutive_errors = 0
                time.sleep(self.check_interval)
                
            except Exception as e:
                logger.error(f"❌ Ошибка в основном цикле: {e}")
                time.sleep(60)

def main():
    parser = argparse.ArgumentParser(description='ASIC Monitor for Antminer S19')
    parser.add_argument('--ip', required=True, help='IP адрес ASIC')
    parser.add_argument('--port', type=int, default=80, help='Порт веб-интерфейса')
    parser.add_argument('--user', default='root', help='Имя пользователя')
    parser.add_argument('--password', required=True, help='Пароль')
    parser.add_argument('--telegram-token', required=True, help='Telegram Bot Token')
    parser.add_argument('--telegram-chat', required=True, help='Telegram Chat ID')
    parser.add_argument('--min-hashrate', type=float, default=0, help='Минимальный хэшрейт в TH/s')
    parser.add_argument('--interval', type=int, default=300, help='Интервал проверки в секундах')
    parser.add_argument('--reboot-threshold', type=int, default=3, help='Количество ошибок до перезагрузки')
    
    args = parser.parse_args()
    
    monitor = ASICMonitor(
        ip=args.ip,
        port=args.port,
        username=args.user,
        password=args.password,
        telegram_token=args.telegram_token,
        telegram_chat_id=args.telegram_chat,
        min_hashrate=args.min_hashrate,
        check_interval=args.interval,
        reboot_threshold=args.reboot_threshold
    )
    
    try:
        monitor.run()
    except KeyboardInterrupt:
        logger.info("Мониторинг остановлен")
    except Exception as e:
        logger.error(f"Фатальная ошибка: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
