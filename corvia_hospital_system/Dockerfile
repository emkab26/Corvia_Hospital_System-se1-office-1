FROM ghcr.io/cirruslabs/flutter:3.44.1 AS build

WORKDIR /app

# The path override in pubspec.yaml must exist before pub get runs.
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
RUN flutter pub get

COPY . .

ARG CORVIA_ENV=local
ARG CORVIA_EXPECTED_BACKEND_ORIGIN
ARG SUPABASE_URL=http://127.0.0.1:54321
ARG SUPABASE_ANON_KEY
ARG OAUTH_REDIRECT_URL
ARG CORVIA_EMERGENCY_DISPATCH_ENABLED=false
ARG CORVIA_WS4_TEAM_EMS_HANDOFF_ENABLED=false

# Only public client configuration belongs in a Flutter web artifact.
RUN flutter build web --release --base-href / \
    --dart-define=CORVIA_ENV="$CORVIA_ENV" \
    --dart-define=CORVIA_EXPECTED_BACKEND_ORIGIN="$CORVIA_EXPECTED_BACKEND_ORIGIN" \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
    --dart-define=OAUTH_REDIRECT_URL="$OAUTH_REDIRECT_URL" \
    --dart-define=CORVIA_EMERGENCY_DISPATCH_ENABLED="$CORVIA_EMERGENCY_DISPATCH_ENABLED" \
    --dart-define=CORVIA_WS4_TEAM_EMS_HANDOFF_ENABLED="$CORVIA_WS4_TEAM_EMS_HANDOFF_ENABLED"

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
