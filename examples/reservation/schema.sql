CREATE TABLE product (
  sku text PRIMARY KEY,
  available integer NOT NULL CHECK (available >= 0)
);

CREATE TABLE reservation (
  owner_id text NOT NULL,
  request_key text NOT NULL,
  sku text NOT NULL REFERENCES product(sku),
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 100),
  status text NOT NULL CHECK (status IN ('held', 'expired')),
  expires_at bigint NOT NULL,
  PRIMARY KEY (owner_id, request_key)
);

CREATE INDEX reservation_expiry ON reservation(expires_at) WHERE status = 'held';
INSERT INTO product(sku, available) VALUES ('keyboard', 10);
