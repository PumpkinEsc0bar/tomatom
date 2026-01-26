# Stage 1: build
FROM node:20-alpine AS build

WORKDIR /app

# backend FQDN via build-arg
ARG REACT_APP_API_URL
ENV REACT_APP_API_URL=$REACT_APP_API_URL

# Copy package.json / package-lock.json (if present)
COPY package*.json ./

RUN npm install

# Copy all in frontend
COPY . .

# Build frontend (SPA, React / Vite)
# if pure HTML, skip
# RUN npm run build

# Stage 2: production nginx
FROM nginx:alpine

WORKDIR /usr/share/nginx/html

COPY index.html .
COPY style ./style
COPY nginx.conf /etc/nginx/conf.d/default.conf

# build-arg в index.html via envsubst
# ENV API_BASE_URL=$REACT_APP_API_URL
RUN apk add --no-cache bash gettext \
    && envsubst '$REACT_APP_API_URL' < index.html > index.tmp.html \
    && mv index.tmp.html index.html \
    && apk del bash gettext

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
