FROM python:3.14-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY relay.py /app/relay.py

RUN useradd --create-home --uid 10001 srof \
    && mkdir -p /data/receipts \
    && chown -R srof:srof /data

USER srof
ENV PYTHONUNBUFFERED=1
EXPOSE 8790
CMD ["python3", "/app/relay.py"]
