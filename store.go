package main

import (
	"context"
	"database/sql"
	"time"

	_ "github.com/lib/pq"
)

type postgresStore struct{ *sql.DB }

func openStore(dsn string) (*postgresStore, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(5 * time.Minute)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, err
	}
	_, err = db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS messages (
		id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
		text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 4096)
	)`)
	if err != nil {
		db.Close()
		return nil, err
	}
	return &postgresStore{db}, nil
}

func (s *postgresStore) List(ctx context.Context) ([]message, error) {
	rows, err := s.QueryContext(ctx, "SELECT id, text FROM messages ORDER BY id DESC LIMIT 100")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]message, 0)
	for rows.Next() {
		var item message
		if err := rows.Scan(&item.ID, &item.Text); err != nil {
			return nil, err
		}
		result = append(result, item)
	}
	return result, rows.Err()
}

func (s *postgresStore) Add(ctx context.Context, text string) (message, error) {
	var item message
	err := s.QueryRowContext(ctx, "INSERT INTO messages (text) VALUES ($1) RETURNING id, text", text).Scan(&item.ID, &item.Text)
	return item, err
}
