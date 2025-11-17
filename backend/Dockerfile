# 1. dev
FROM node:20-slim AS builder

WORKDIR /app

COPY package*.json ./
COPY tsconfig.json ./

RUN apt-get update && apt-get install -y libvips-dev
RUN npm install

COPY . .
RUN npm run build

# 2. prod

FROM node:20-slim

WORKDIR /app

RUN apt-get update && apt-get install -y libvips-tools

COPY package.json .
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

ENV PORT=8080
EXPOSE 8080


CMD [ "node", "dist/index.js" ]
