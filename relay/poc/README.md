# SROF Relay Docker POC

Purpose: prove that GitHub can become a thin ingress only, while execution is owned by a persistent PROFESYS container.

POC flow:

```text
ChatGPT -> GitHub issue -> tiny ingress workflow -> localhost:8790
        -> SROF Relay Docker -> governed SSH -> THINKPAD-E470
        -> durable receipt
```

GitHub Actions does not execute the machine operation. It submits a request and reads the receipt.

## POC operations

- host_health
- git_status

Target:
- THINKPAD-E470

## Runtime

Container:
- srof-relay-poc

Host bind:
- 127.0.0.1:8790 -> container:8790

Persistent data:
- /home/profesys/.local/share/srof-relay -> /data

Secrets are not baked into the image. SSH identity and known_hosts are read-only mounts.
