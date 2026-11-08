FROM denoland/deno:bin-2.5.4 AS deno
FROM python:3.12-slim
COPY --from=deno /deno /usr/local/bin/deno
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY klymusic ./klymusic
RUN useradd --create-home klymusic
USER klymusic
EXPOSE 8787
CMD ["uvicorn", "klymusic.app:app", "--host", "0.0.0.0", "--port", "8787", "--proxy-headers", "--forwarded-allow-ips", "*", "--no-access-log"]
