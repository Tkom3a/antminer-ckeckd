FROM python:3.11-slim

WORKDIR /app

# Устанавливаем зависимости
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Копируем скрипт
COPY ckeck.py .
RUN chmod +x check.py

# Создаем директорию для логов
RUN mkdir -p /var/log && touch /var/log/antminer-checkd.log

# Запускаем монитор
ENTRYPOINT ["python3", "-u", "check.py"]
