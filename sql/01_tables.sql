-- 01_tables.sql
-- Run first, in the Supabase SQL Editor. Creates the 6 tables, unique keys and privacy settings.

-- Daily sales (rows are appended every day from the Daily_Sales sheet)
create table sales (
  id bigint generated always as identity primary key,
  sale_date date,
  store text,
  category text,
  item text,
  units integer,
  revenue numeric
);

-- Daily revenue targets per store and category
create table targets (
  store text,
  category text,
  weekday_target numeric,
  weekend_target numeric
);

-- Current stock only (overwritten from the Stock_Current sheet)
create table stock_by_store (
  item_code text,
  item text,
  category text,
  store text,
  units_in_stock integer,
  reorder_level integer,
  stock_date date
);

-- Customer enquiries (from the Enquiries_Sheet tab)
create table enquiries (
  enquiry_id text,
  enquiry_date date,
  customer text,
  item_asked text,
  store text,
  status text,
  last_followup date
);

-- One-row table with the rules and freshness markers
create table settings (
  id integer primary key default 1 check (id = 1),
  demo_date date,                                     -- leave empty to use today's date (Asia/Kolkata)
  overdue_days integer not null default 3,            -- an open enquiry is overdue after this many days
  below_target numeric not null default 0.95,         -- below 95% of target = BELOW
  min_store_shortfall numeric not null default 10000, -- smallest 3-day gap (Rs) worth naming a store
  stock_updated_on date,                              -- set by n8n after stock is loaded
  enquiries_updated_on date                           -- set by n8n after enquiries are loaded
);
insert into settings default values;

-- Log of reports already sent
create table report_log (
  report_date date primary key,
  sent_at timestamptz not null default now()
);

-- Unique keys so n8n can update instead of duplicating
create unique index sales_day_store_item_uniq on sales (sale_date, store, item);
create unique index stock_item_store_idx on stock_by_store (item, store);
create unique index enquiries_id_idx on enquiries (enquiry_id);

-- Keep the tables private (n8n connects with the database password, which is not affected)
alter table sales enable row level security;
alter table targets enable row level security;
alter table stock_by_store enable row level security;
alter table enquiries enable row level security;
alter table settings enable row level security;
alter table report_log enable row level security;
