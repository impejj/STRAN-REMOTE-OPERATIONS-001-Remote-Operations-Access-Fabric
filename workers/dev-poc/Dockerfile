FROM python:3.14-slim

RUN pip install --no-cache-dir pytest==8.4.2 \
    && useradd --create-home --uid 10001 srof

WORKDIR /worker
COPY runner.py /worker/runner.py

RUN mkdir -p /out \
    && chown -R srof:srof /worker /out

USER srof

ENV PYTHONUNBUFFERED=1
ENV SROF_SOURCE_ROOT=/src
ENV SROF_OUT_ROOT=/out

ENTRYPOINT ["python3", "/worker/runner.py"]
