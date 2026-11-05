package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
)

type Handler struct {
	service *Service
	token   string
	page    []byte
}

func (h Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet && r.URL.Path == "/" {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(h.page)
		return
	}
	if r.Header.Get("Authorization") != "Bearer "+h.token {
		writeJSON(w, 401, map[string]string{"error": "unauthorized"})
		return
	}
	h.route(w, r, "demo")
}

// snippet:handler
func (h Handler) route(w http.ResponseWriter, r *http.Request, owner string) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	var reservation Reservation
	var err error
	switch {
	case r.Method == http.MethodPost && r.URL.Path == "/api/reservations":
		if strings.Split(r.Header.Get("Content-Type"), ";")[0] != "application/json" {
			writeJSON(w, 415, map[string]string{"error": "unsupported_media_type"})
			return
		}
		var input Input
		decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
		if err = decoder.Decode(&input); err == nil {
			var extra any
			if decoder.Decode(&extra) != io.EOF {
				err = ErrInvalidInput
			}
		}
		if err != nil {
			writeJSON(w, 400, map[string]string{"error": "invalid_input"})
			return
		}
		reservation, err = h.service.Create(ctx, owner, input)
	case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/reservations/"):
		reservation, err = find(ctx, h.service.db, owner, strings.TrimPrefix(r.URL.Path, "/api/reservations/"))
	default:
		err = ErrNotFound
	}
	respond(w, reservation, err)
}

// end:handler

func respond(w http.ResponseWriter, reservation Reservation, err error) {
	status, code := 200, ""
	switch {
	case err == nil:
		writeJSON(w, status, reservation)
		return
	case errors.Is(err, ErrInvalidInput):
		status, code = 400, "invalid_input"
	case errors.Is(err, ErrNotFound):
		status, code = 404, "not_found"
	case errors.Is(err, ErrStock):
		status, code = 409, "insufficient_stock"
	case errors.Is(err, ErrKeyConflict):
		status, code = 409, "key_conflict"
	default:
		status, code = 503, "database_unavailable"
	}
	writeJSON(w, status, map[string]string{"error": code})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(value)
}
