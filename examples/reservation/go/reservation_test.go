package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestValidation(t *testing.T) {
	for _, input := range []Input{{"", "keyboard", 1}, {"a/b", "keyboard", 1}, {"é", "keyboard", 1}, {"a", "keyboard", 0}, {"a", "keyboard", 101}} {
		if !errors.Is(validate(input), ErrInvalidInput) {
			t.Fatalf("accepted %#v", input)
		}
	}
	if err := validate(Input{"retry-1_ABC", "keyboard", 2}); err != nil {
		t.Fatal(err)
	}
}

func TestWorkerStopsAfterCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	ticks := make(chan struct{}, 10)
	go func() {
		defer close(done)
		runExpiry(ctx, time.Millisecond, func(context.Context) error {
			ticks <- struct{}{}
			return errors.New("recoverable")
		})
	}()
	defer cancel()
	for range 2 {
		select {
		case <-ticks:
		case <-time.After(time.Second):
			t.Fatal("worker did not retry")
		}
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("worker did not stop")
	}
}

func TestUnauthorizedRequestDoesNotReachDatabase(t *testing.T) {
	response := httptest.NewRecorder()
	Handler{token: "secret"}.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/api/reservations", nil))
	if response.Code != http.StatusUnauthorized {
		t.Fatal(response.Code)
	}
}
