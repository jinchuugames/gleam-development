package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// snippet:worker
func runExpiry(ctx context.Context, interval time.Duration, sweep func(context.Context) error) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			operation, cancel := context.WithTimeout(ctx, 2*time.Second)
			if err := sweep(operation); err != nil {
				log.Printf("expiry: %v", err)
			}
			cancel()
		}
	}
}

// end:worker

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

// snippet:lifetime
func run() error {
	root, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		return errors.New("DATABASE_URL must not be empty")
	}
	config, err := pgxpool.ParseConfig(url)
	if err != nil {
		return err
	}
	config.MaxConns = 5
	config.ConnConfig.RuntimeParams["statement_timeout"] = "1500"
	db, err := pgxpool.NewWithConfig(root, config)
	if err != nil {
		return err
	}
	defer db.Close()
	token := os.Getenv("API_TOKEN")
	if token == "" {
		return errors.New("API_TOKEN must not be empty")
	}
	pagePath := os.Getenv("PAGE_PATH")
	if pagePath == "" {
		pagePath = "../web/index.html"
	}
	page, err := os.ReadFile(pagePath)
	if err != nil {
		return err
	}
	port, interval := envInt("PORT", 8080), envInt("SWEEP_MS", 1000)
	if port <= 0 || port > 65535 || interval <= 0 {
		return errors.New("invalid port or sweep interval")
	}
	service := NewService(db, time.Now)
	server := &http.Server{
		Addr: fmt.Sprintf("127.0.0.1:%d", port), Handler: Handler{service, token, page},
		ReadHeaderTimeout: 2 * time.Second, ReadTimeout: 5 * time.Second,
		WriteTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second,
	}
	workerDone := make(chan struct{})
	go func() {
		defer close(workerDone)
		runExpiry(root, time.Duration(interval)*time.Millisecond, service.Expire)
	}()
	serverDone := make(chan error, 1)
	go func() { serverDone <- server.ListenAndServe() }()
	// snippet:shutdown
	select {
	case <-root.Done():
	case err = <-serverDone:
	}
	stop()
	drain, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	shutdownErr := server.Shutdown(drain)
	if shutdownErr != nil {
		server.Close()
	}
	<-workerDone
	// end:shutdown
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return shutdownErr
}

// end:lifetime

func envInt(name string, fallback int) int {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	number, err := strconv.Atoi(value)
	if err != nil {
		log.Fatalf("%s must be an integer", name)
	}
	return number
}
