FROM python:3.14-slim

RUN pip install --no-cache-dir \
      pytest==8.4.2 \
      pydantic==2.13.4 \
      jsonschema>=4.23,<5 \
      rfc8785==0.1.4 \
    && useradd --create-home --uid 10001 srof

WORKDIR /worker
COPY runner.py /worker/runner.py
COPY test_runner.py /worker/test_runner.py

RUN mkdir -p /out \
    && chown -R srof:srof /worker /out

USER srof

ENV PYTHONUNBUFFERED=1
ENV SROF_SOURCE_ROOT=/src
ENV SROF_OUT_ROOT=/out
ENV PYTHONPATH=/worker

ENTRYPOINT ["python3", "/worker/runner.py"]
