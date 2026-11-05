-- 05_n8n_queries.sql
-- These are NOT run in Supabase. Each query is pasted into the Postgres node (Execute Query) in n8n.
-- Parameters ($1, $2 ...) come from the "Query Parameters" field of that node.
-- The same queries are already inside n8n/Jewellery_Business_Doctor.json.

-- ---------------------------------------------------------------
-- Add Sales to Database          (Read Sales: Settings > Always Output Data = ON)
-- Query Parameters: {{ [$json.sale_date ?? "", $json.store ?? "", $json.category ?? "", $json.item ?? "", String($json.units ?? ""), String($json.revenue ?? "")] }}
-- The "where" line stops a blank row being inserted on a day with no sales.
-- ---------------------------------------------------------------
insert into sales (sale_date, store, category, item, units, revenue)
select nullif($1::text,'')::date, $2::text, $3::text, $4::text, nullif($5::text,'')::int, nullif($6::text,'')::numeric
where nullif($1::text,'') is not null
on conflict (sale_date, store, item) do update
set category = excluded.category, units = excluded.units, revenue = excluded.revenue;

-- ---------------------------------------------------------------
-- Update Stock in Database (update the row if it exists, otherwise insert it)
-- Query Parameters: {{ [$json.item_code ?? "", $json.store ?? "", $json.item ?? "", $json.category ?? "", String($json.units_in_stock ?? ""), String($json.reorder_level ?? ""), String($json.stock_date ?? "")] }}
-- ---------------------------------------------------------------
with upd as (
  update stock_by_store
  set item = $3, category = $4,
      units_in_stock = coalesce(nullif($5,'')::int, units_in_stock),
      reorder_level  = coalesce(nullif($6,'')::int, reorder_level),
      stock_date = (case when $7::text ~ '^[0-9]+$' then date '1899-12-30' + $7::text::int else nullif($7::text,'')::date end)
  where item_code = $1 and store = $2
  returning 1)
insert into stock_by_store (item_code, item, category, store, units_in_stock, reorder_level, stock_date)
select $1, $3, $4, $2, nullif($5,'')::int, nullif($6,'')::int,
       (case when $7::text ~ '^[0-9]+$' then date '1899-12-30' + $7::text::int else nullif($7::text,'')::date end)
where not exists (select 1 from upd);

-- ---------------------------------------------------------------
-- Mark Stock Updated  (uses the latest stock_date in the Stock sheet, so change that column every day)
-- Alternative: set it to today's date: update settings set stock_updated_on = (now() at time zone 'Asia/Kolkata')::date
-- ---------------------------------------------------------------
update settings set stock_updated_on = (select max(stock_date) from stock_by_store);

-- ---------------------------------------------------------------
-- Update Enquiries in Database   (Read Enquiries and this node: Always Output Data = ON)
-- Query Parameters: {{ [$json.enquiry_id ?? "", String($json.enquiry_date ?? ""), $json.customer ?? "", $json.item_asked ?? "", $json.store ?? "", $json.status ?? "", String($json.last_followup ?? "")] }}
-- Accepts real dates or Google Sheets date numbers. The last "and" stops a blank row on a day with no enquiries.
-- ---------------------------------------------------------------
with upd as (
  update enquiries
  set enquiry_date = (case when $2::text ~ '^[0-9]+$' then date '1899-12-30' + $2::text::int else nullif($2::text,'')::date end),
      customer = $3, item_asked = $4, store = $5, status = $6,
      last_followup = (case when $7::text ~ '^[0-9]+$' then date '1899-12-30' + $7::text::int else nullif($7::text,'')::date end)
  where enquiry_id = $1
  returning 1)
insert into enquiries (enquiry_id, enquiry_date, customer, item_asked, store, status, last_followup)
select $1,
       (case when $2::text ~ '^[0-9]+$' then date '1899-12-30' + $2::text::int else nullif($2::text,'')::date end),
       $3, $4, $5, $6,
       (case when $7::text ~ '^[0-9]+$' then date '1899-12-30' + $7::text::int else nullif($7::text,'')::date end)
where not exists (select 1 from upd) and nullif($1::text,'') is not null;

-- ---------------------------------------------------------------
-- Mark Enquiries Updated  (today's date, so a day with no new enquiries still counts as updated)
-- ---------------------------------------------------------------
update settings set enquiries_updated_on = (now() at time zone 'Asia/Kolkata')::date;

-- ---------------------------------------------------------------
-- Check Sales, Stock and Enquiries Ready  (feeds the "All 3 Data Ready?" IF node: {{ $json.ready }} is true)
-- ---------------------------------------------------------------
select (select count(*) from v_data_status where status <> 'OK') = 0 as ready;

-- ---------------------------------------------------------------
-- Get Briefing  (the email body is {{ $json.message }})
-- ---------------------------------------------------------------
select message from v_briefing;

-- ---------------------------------------------------------------
-- Log Report Sent  (optional)
-- ---------------------------------------------------------------
insert into report_log (report_date) select report_date from v_dates on conflict do nothing;
