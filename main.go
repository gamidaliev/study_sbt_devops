package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type message struct {
	ID   int64  `json:"id"`
	Text string `json:"text"`
}

type messageStore interface {
	PingContext(context.Context) error
	List(context.Context) ([]message, error)
	Add(context.Context, string) (message, error)
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func port() (string, error) {
	n, err := strconv.Atoi(env("APP_PORT", "8080"))
	if err != nil || n < 1 || n > 65535 {
		return "", fmt.Errorf("APP_PORT must be between 1 and 65535")
	}
	return strconv.Itoa(n), nil
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func handler(store messageStore) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"app": "hw3", "storage": "PostgreSQL"})
	})
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := store.PingContext(ctx); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "DOWN", "db": "DOWN"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "UP", "db": "UP"})
	})
	mux.HandleFunc("GET /messages", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		messages, err := store.List(ctx)
		if err != nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, http.StatusOK, messages)
	})
	mux.HandleFunc("POST /messages", func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 4096))
		if err != nil {
			http.Error(w, "message exceeds 4096 bytes", http.StatusRequestEntityTooLarge)
			return
		}
		text := strings.TrimSpace(string(body))
		if text == "" || strings.ContainsRune(text, '\x00') {
			http.Error(w, "message must contain non-empty text without NUL bytes", http.StatusBadRequest)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		result, err := store.Add(ctx, text)
		if err != nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, http.StatusCreated, result)
	})
	return mux
}

func probe(p string) error {
	client := &http.Client{
		Timeout:       3 * time.Second,
		Transport:     &http.Transport{Proxy: nil},
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	defer client.CloseIdleConnections()
	response, err := client.Get("http://127.0.0.1:" + p + "/health")
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("health returned HTTP %d", response.StatusCode)
	}
	return nil
}

func run() error {
	p, err := port()
	if err != nil {
		return err
	}
	if len(os.Args) == 2 && os.Args[1] == "healthcheck" {
		return probe(p)
	}
	if len(os.Args) != 1 {
		return fmt.Errorf("usage: app [healthcheck]")
	}
	if os.Getenv("PGPASSWORD") == "" {
		return fmt.Errorf("PGPASSWORD is required")
	}
	store, err := openStore("connect_timeout=5")
	if err != nil {
		return err
	}
	defer store.Close()
	server := &http.Server{
		Addr:              ":" + p,
		Handler:           handler(store),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1 << 16,
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	result := make(chan error, 1)
	go func() {
		log.Printf("listening on :%s", p)
		result <- server.ListenAndServe()
	}()
	select {
	case err := <-result:
		return err
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdown); err != nil {
			return err
		}
		if err := <-result; !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	}
}

func main() {
	if err := run(); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
