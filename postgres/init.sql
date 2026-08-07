-- =============================================================================
-- Seed OLTP schema: a small e-commerce domain (customers, products, orders,
-- order_items). Chosen because it gives realistic, relatable CDC events —
-- inserts as orders come in, updates as order status changes, and a natural
-- place to later demonstrate a breaking schema change (e.g. renaming or
-- dropping a column on `orders`) for the data-contract failure demo.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS shop;

CREATE TABLE shop.customers (
    customer_id     SERIAL PRIMARY KEY,
    email           VARCHAR(255) NOT NULL UNIQUE,
    full_name       VARCHAR(255) NOT NULL,
    signup_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    country         VARCHAR(2)  NOT NULL
);

CREATE TABLE shop.products (
    product_id      SERIAL PRIMARY KEY,
    sku             VARCHAR(64) NOT NULL UNIQUE,
    name            VARCHAR(255) NOT NULL,
    price_cents     INTEGER NOT NULL CHECK (price_cents >= 0),
    category        VARCHAR(100) NOT NULL
);

CREATE TABLE shop.orders (
    order_id        SERIAL PRIMARY KEY,
    customer_id     INTEGER NOT NULL REFERENCES shop.customers(customer_id),
    status          VARCHAR(32) NOT NULL DEFAULT 'placed',
    placed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE shop.order_items (
    order_item_id   SERIAL PRIMARY KEY,
    order_id        INTEGER NOT NULL REFERENCES shop.orders(order_id),
    product_id      INTEGER NOT NULL REFERENCES shop.products(product_id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    unit_price_cents INTEGER NOT NULL
);

-- Debezium reads these via logical replication. REPLICA IDENTITY FULL means
-- UPDATE/DELETE events carry the full previous row image, not just the PK —
-- needed for correct downstream contract/quality checks on changed columns.
ALTER TABLE shop.customers   REPLICA IDENTITY FULL;
ALTER TABLE shop.products    REPLICA IDENTITY FULL;
ALTER TABLE shop.orders      REPLICA IDENTITY FULL;
ALTER TABLE shop.order_items REPLICA IDENTITY FULL;

-- Publication Debezium's pgoutput plugin will stream from.
CREATE PUBLICATION lakehouse_pub FOR TABLES IN SCHEMA shop;

-- ---------------------------------------------------------------------------
-- Seed data
-- ---------------------------------------------------------------------------
INSERT INTO shop.customers (email, full_name, country) VALUES
    ('ada@example.com',    'Ada Lovelace',    'GB'),
    ('grace@example.com',  'Grace Hopper',    'US'),
    ('linus@example.com',  'Linus Torvalds',  'FI'),
    ('margaret@example.com','Margaret Hamilton','US');

INSERT INTO shop.products (sku, name, price_cents, category) VALUES
    ('SKU-001', 'Mechanical Keyboard', 8999, 'Electronics'),
    ('SKU-002', 'USB-C Hub',           3499, 'Electronics'),
    ('SKU-003', 'Standing Desk',      45999, 'Furniture'),
    ('SKU-004', 'Notebook (3-pack)',    999, 'Office');

INSERT INTO shop.orders (customer_id, status) VALUES
    (1, 'placed'),
    (2, 'shipped'),
    (3, 'placed');

INSERT INTO shop.order_items (order_id, product_id, quantity, unit_price_cents) VALUES
    (1, 1, 1, 8999),
    (1, 2, 2, 3499),
    (2, 3, 1, 45999),
    (3, 4, 5, 999);
