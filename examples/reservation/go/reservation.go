package main

import (
	"context"
	"errors"
	"regexp"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrInvalidInput = errors.New("invalid_input")
	ErrNotFound     = errors.New("not_found")
	ErrStock        = errors.New("insufficient_stock")
	ErrKeyConflict  = errors.New("key_conflict")
	identifier      = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,64}$`)
)

type Input struct {
	Key      string `json:"key"`
	SKU      string `json:"sku"`
	Quantity int    `json:"quantity"`
}

type Reservation struct {
	Key       string `json:"key"`
	SKU       string `json:"sku"`
	Quantity  int    `json:"quantity"`
	Status    string `json:"status"`
	ExpiresAt int64  `json:"expires_at"`
}

// snippet:dependencies
type Service struct {
	db  *pgxpool.Pool
	now func() time.Time
}

func NewService(db *pgxpool.Pool, now func() time.Time) *Service {
	return &Service{db: db, now: now}
}

// end:dependencies

func validate(input Input) error {
	if !identifier.MatchString(input.Key) || !identifier.MatchString(input.SKU) || input.Quantity < 1 || input.Quantity > 100 {
		return ErrInvalidInput
	}
	return nil
}

// snippet:create
func (s *Service) Create(ctx context.Context, owner string, input Input) (Reservation, error) {
	if err := validate(input); err != nil {
		return Reservation{}, err
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Reservation{}, err
	}
	defer tx.Rollback(context.Background())
	reservation, err := reserve(ctx, tx, owner, input, s.now().Unix())
	if err != nil {
		return Reservation{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Reservation{}, err
	}
	return reservation, nil
}

// end:create

// snippet:reserve
func reserve(ctx context.Context, tx pgx.Tx, owner string, input Input, now int64) (Reservation, error) {
	var available int
	err := tx.QueryRow(ctx, "SELECT available FROM product WHERE sku = $1 FOR UPDATE", input.SKU).Scan(&available)
	if errors.Is(err, pgx.ErrNoRows) {
		return Reservation{}, ErrNotFound
	}
	if err != nil {
		return Reservation{}, err
	}
	previous, err := find(ctx, tx, owner, input.Key)
	if err == nil {
		if previous.SKU != input.SKU || previous.Quantity != input.Quantity {
			return Reservation{}, ErrKeyConflict
		}
		return previous, nil
	}
	if !errors.Is(err, ErrNotFound) {
		return Reservation{}, err
	}
	if available < input.Quantity {
		return Reservation{}, ErrStock
	}
	return insert(ctx, tx, owner, input, now)
}

// end:reserve

func insert(ctx context.Context, tx pgx.Tx, owner string, input Input, now int64) (Reservation, error) {
	_, err := tx.Exec(ctx, "UPDATE product SET available = available - $1 WHERE sku = $2", input.Quantity, input.SKU)
	if err != nil {
		return Reservation{}, err
	}
	reservation := Reservation{input.Key, input.SKU, input.Quantity, "held", now + 60}
	_, err = tx.Exec(ctx, "INSERT INTO reservation(owner_id, request_key, sku, quantity, status, expires_at) VALUES ($1, $2, $3, $4, 'held', $5)", owner, input.Key, input.SKU, input.Quantity, reservation.ExpiresAt)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.ConstraintName == "reservation_pkey" {
		return Reservation{}, ErrKeyConflict
	}
	return reservation, err
}

// This interface exists because both the pool and a transaction execute this read.
type rowQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func find(ctx context.Context, db rowQuerier, owner, key string) (Reservation, error) {
	var reservation Reservation
	err := db.QueryRow(ctx, "SELECT request_key, sku, quantity, status, expires_at FROM reservation WHERE owner_id = $1 AND request_key = $2", owner, key).
		Scan(&reservation.Key, &reservation.SKU, &reservation.Quantity, &reservation.Status, &reservation.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Reservation{}, ErrNotFound
	}
	return reservation, err
}

// snippet:expire
func (s *Service) Expire(ctx context.Context) error {
	_, err := s.db.Exec(ctx, `WITH expired AS (
		UPDATE reservation SET status = 'expired'
		WHERE status = 'held' AND expires_at <= $1
		RETURNING sku, quantity
	), totals AS (
		SELECT sku, sum(quantity)::integer AS quantity FROM expired GROUP BY sku
	)
	UPDATE product SET available = available + totals.quantity
	FROM totals WHERE product.sku = totals.sku`, s.now().Unix())
	return err
}

// end:expire
