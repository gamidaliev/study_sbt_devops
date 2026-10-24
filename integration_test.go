package main

import (
	"context"
	"os"
	"testing"
	"time"
)

// Optional check against a real PostgreSQL instance; unit tests need no database.
func TestPostgresReconnect(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	store, err := openStore(dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	text := "hw3-integration-" + time.Now().UTC().Format(time.RFC3339Nano) + " ' quoted"
	item, err := store.Add(ctx, text)
	if err != nil {
		t.Fatal(err)
	}
	defer store.ExecContext(context.Background(), "DELETE FROM messages WHERE id = $1", item.ID)
	other, err := openStore(dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	items, err := other.List(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, got := range items {
		if got.ID == item.ID && got.Text == text {
			return
		}
	}
	t.Fatal("stored message was not found through a new connection pool")
}
