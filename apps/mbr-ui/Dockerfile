FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# VITE_API_BASE_URL is baked into the JS bundle at build time by Vite's static replacement.
# Set it to /api so all API calls hit the nginx reverse proxy path — the actual mbr-api URL
# is injected at runtime via $API_BASE_URL in nginx.conf.template, not here.
ARG VITE_API_BASE_URL=/api
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 80
