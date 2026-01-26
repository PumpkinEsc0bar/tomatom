# Stage 1: build
FROM node:20-alpine AS build

WORKDIR /app

# Подставляем backend FQDN через build-arg
ARG REACT_APP_API_URL
ENV REACT_APP_API_URL=$REACT_APP_API_URL

# Копируем package.json / package-lock.json (если есть)
COPY package*.json ./

# Устанавливаем зависимости
RUN npm install

# Копируем весь фронтенд
COPY . .

# Строим frontend (для SPA, React / Vite и т.д.)
# Если чистый HTML, можно пропустить
# RUN npm run build

# Stage 2: production nginx
FROM nginx:alpine

WORKDIR /usr/share/nginx/html

# Копируем index.html и nginx конфиг
COPY index.html .
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Можно передать build-arg в index.html через envsubst
# ENV API_BASE_URL=$REACT_APP_API_URL
RUN apk add --no-cache bash gettext \
    && envsubst '$REACT_APP_API_URL' < index.html > index.tmp.html \
    && mv index.tmp.html index.html \
    && apk del bash gettext

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
