FROM ghcr.io/cirruslabs/flutter:3.41.1 AS build

WORKDIR /app

ENV FLUTTER_SUPPRESS_ANALYTICS=true
ARG CLIENT_KEY=demo-client-key

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter config --enable-web && flutter build web --release --dart-define=CLIENT_KEY=${CLIENT_KEY}

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
