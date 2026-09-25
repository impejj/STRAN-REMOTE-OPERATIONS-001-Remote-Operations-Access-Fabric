FROM python:3.14-slim

ARG SROF_UID=1000
ARG SROF_GID=1000

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid "${SROF_GID}" srof \
    && useradd --create-home --uid "${SROF_UID}" --gid "${SROF_GID}" srof \
    && mkdir -p /data/receipts \
    && chown -R srof:srof /data

WORKDIR /app
COPY relay.py /app/relay.py

USER srof
ENV PYTHONUNBUFFERED=1
EXPOSE 8790
CMD ["python3", "/app/relay.py"]
