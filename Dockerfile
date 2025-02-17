FROM node:18.20.5 as build
WORKDIR /tmp/veraid-authority
COPY package.json ./
# -----------------------------------
# Original Steps
# COPY package-lock.json ./
# RUN npm ci 
# -----------------------------------
RUN npm install --loglevel verbose
COPY . ./
RUN npm run build && npm prune --omit=dev && rm -r src

FROM node:18.20.5-slim
LABEL org.opencontainers.image.source="https://github.com/relaycorp/veraid-authority"
WORKDIR /opt/veraid-authority
COPY --from=build /tmp/veraid-authority ./
USER node
ENTRYPOINT [ \
  "node", \
  "--experimental-vm-modules", \
  "--enable-source-maps", \
  "build/main/bin/server.js" \
  ]
EXPOSE 8080
