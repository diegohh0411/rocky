FROM node:lts-slim
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
RUN npm install -g opencode-ai && mkdir -p /root/.config/opencode
