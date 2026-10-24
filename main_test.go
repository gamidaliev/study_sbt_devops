package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type fakeStore struct {
	messages []message
	err      error
}

func (s *fakeStore) PingContext(context.Context) error       { return s.err }
func (s *fakeStore) List(context.Context) ([]message, error) { return s.messages, s.err }
func (s *fakeStore) Add(_ context.Context, text string) (message, error) {
	if s.err != nil {
		return message{}, s.err
	}
	item := message{ID: int64(len(s.messages) + 1), Text: text}
	s.messages = append(s.messages, item)
	return item, nil
}

func TestMessageAPI(t *testing.T) {
	store := &fakeStore{messages: []message{}}
	h := handler(store)
	post := httptest.NewRecorder()
	h.ServeHTTP(post, httptest.NewRequest(http.MethodPost, "/messages", strings.NewReader("  saved-from-hw3  ")))
	if post.Code != http.StatusCreated {
		t.Fatalf("POST returned %d: %s", post.Code, post.Body)
	}
	get := httptest.NewRecorder()
	h.ServeHTTP(get, httptest.NewRequest(http.MethodGet, "/messages", nil))
	var messages []message
	if err := json.Unmarshal(get.Body.Bytes(), &messages); err != nil {
		t.Fatal(err)
	}
	if get.Code != 200 || len(messages) != 1 || messages[0].Text != "saved-from-hw3" || messages[0].ID != 1 {
		t.Fatalf("unexpected GET result: %d %s", get.Code, get.Body)
	}
	for _, tc := range []struct {
		body   string
		status int
	}{
		{" ", http.StatusBadRequest},
		{"bad\x00text", http.StatusBadRequest},
		{strings.Repeat("x", 4097), http.StatusRequestEntityTooLarge},
	} {
		response := httptest.NewRecorder()
		h.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/messages", strings.NewReader(tc.body)))
		if response.Code != tc.status {
			t.Fatalf("status = %d, want %d", response.Code, tc.status)
		}
	}
	if len(store.messages) != 1 {
		t.Fatal("invalid messages were stored")
	}
}

func TestDatabaseFailure(t *testing.T) {
	store := &fakeStore{err: errors.New("unavailable")}
	h := handler(store)
	for _, tc := range []struct{ method, path string }{
		{http.MethodGet, "/health"},
		{http.MethodGet, "/messages"},
		{http.MethodPost, "/messages"},
	} {
		r := httptest.NewRecorder()
		h.ServeHTTP(r, httptest.NewRequest(tc.method, tc.path, strings.NewReader("test")))
		if r.Code != http.StatusServiceUnavailable {
			t.Fatalf("%s: status %d", tc.path, r.Code)
		}
	}
}

func TestHealthProbe(t *testing.T) {
	store := &fakeStore{}
	server := httptest.NewServer(handler(store))
	defer server.Close()
	p := strings.TrimPrefix(server.URL, "http://127.0.0.1:")
	if err := probe(p); err != nil {
		t.Fatal(err)
	}
	failed := httptest.NewServer(handler(&fakeStore{err: errors.New("database down")}))
	defer failed.Close()
	failedPort := strings.TrimPrefix(failed.URL, "http://127.0.0.1:")
	if err := probe(failedPort); err == nil {
		t.Fatal("probe must reject a failed database")
	}
	server.Close()
	if err := probe(p); err == nil {
		t.Fatal("probe must reject a stopped server")
	}
}
