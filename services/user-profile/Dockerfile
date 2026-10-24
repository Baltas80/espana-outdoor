FROM golang:1.27.1-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/user-profile ./cmd/user-profile

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/user-profile /app/user-profile
COPY migrations /app/migrations
ENV PORT=8080
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/user-profile"]
