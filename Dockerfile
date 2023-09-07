# Stage 1: Build the Go application
FROM golang:1.20.7 AS builder

WORKDIR /app

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app ./cmd/

# Stage 2: Create a minimal image
FROM alpine:3.18

RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy the cmd and templates directories from the builder stage
COPY --from=builder /app/cmd ./cmd
COPY --from=builder /app/templates ./templates
COPY --from=builder /app/app .

CMD ["./app"]
