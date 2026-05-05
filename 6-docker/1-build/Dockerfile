# Step 6.1 - Docker build demo image
FROM alpine:3.20

RUN apk add --no-cache bash curl iproute2 iputils

WORKDIR /app
COPY app.sh /app/app.sh
RUN chmod +x /app/app.sh

ENV DEMO_NAME="docker-build-demo"

ENTRYPOINT ["/app/app.sh"]
