FROM node:20-alpine

RUN npm install -g @stacklance/envguard-cli @stacklance/envguard-audit zod 2>/dev/null || true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
