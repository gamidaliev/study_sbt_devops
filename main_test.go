package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthContract(t *testing.T) {
	server := httptest.NewServer(handler("test-app"))
	defer server.Close()
	response, err := http.Get(server.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	var body map[string]string
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != 200 || body["status"] != "UP" || body["app"] != "test-app" {
		t.Fatalf("unexpected response: status=%d body=%v", response.StatusCode, body)
	}
	if err := probe(server.URL + "/health"); err != nil {
		t.Fatal(err)
	}
	if err := probe(server.URL + "/missing"); err == nil {
		t.Fatal("probe must reject non-200 responses")
	}
	server.Close()
	if err := probe(server.URL + "/health"); err == nil {
		t.Fatal("probe must reject an unreachable service")
	}
}

func TestPort(t *testing.T) {
	for _, value := range []string{"", "8080", "9090", "1", "65535", "0", "-1", "65536", "abc"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv("APP_PORT", value)
			got, err := port()
			valid := value == "" || value == "8080" || value == "9090" || value == "1" || value == "65535"
			if (err == nil) != valid {
				t.Fatalf("port() = %q, %v", got, err)
			}
			if value == "" && got != "8080" {
				t.Fatalf("default port = %q", got)
			}
		})
	}
}
