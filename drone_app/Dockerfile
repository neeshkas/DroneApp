FROM ghcr.io/cirruslabs/flutter:3.41.1 AS build

WORKDIR /app

ENV FLUTTER_SUPPRESS_ANALYTICS=true

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter config --enable-web && flutter build web --release

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
