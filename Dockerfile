FROM python:3.11-slim

# Install system dependencies for PIL
RUN apt-get update && apt-get install -y \
    libfreetype6-dev \
    libjpeg-dev \
    libpng-dev \
    cron \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN pip3 install --no-cache-dir Pillow python-dotenv google-generativeai \
  requests

# Copy files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY cronjobs /etc/cron.d/cronjobs
COPY app/ /app/

# Set up cron
RUN chmod 0644 /etc/cron.d/cronjobs && \
    crontab /etc/cron.d/cronjobs && \
    touch /var/log/cron.log

# Start supervisord
CMD ["/usr/bin/supervisord"]