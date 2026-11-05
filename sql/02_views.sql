-- 02_views.sql
-- Run second. Creates the views that calculate KPIs and data checks.

-- dates: the report day and the sales day (same day)
create view v_dates with (security_invoker = true) as
select coalesce(demo_date, (now() at time zone 'Asia/Kolkata')::date) as report_date,
       coalesce(demo_date, (now() at time zone 'Asia/Kolkata')::date) as sales_date
from settings;

-- only valid sales rows
create view clean_sales with (security_invoker = true) as
select * from sales
where sale_date is not null and coalesce(store, '') <> '' and coalesce(category, '') <> ''
  and coalesce(item, '') <> '' and units >= 0 and revenue >= 0;

-- sales vs target and week on week, by category
create view v_category_summary with (security_invoker = true) as
with d as (select * from v_dates),
t as (
  select category,
         sum(case when extract(isodow from d.sales_date) >= 6 then weekend_target else weekday_target end) as target
  from targets cross join d group by category),
a as (select c.category, sum(c.revenue) as actual from clean_sales c, d where c.sale_date = d.sales_date group by c.category),
w as (
  select c.category,
         sum(c.revenue) filter (where c.sale_date > d.sales_date - 7 and c.sale_date <= d.sales_date) as last7,
         sum(c.revenue) filter (where c.sale_date > d.sales_date - 14 and c.sale_date <= d.sales_date - 7) as prev7
  from clean_sales c cross join d group by c.category),
x as (
  select t.category, coalesce(a.actual, 0) as actual, t.target, w.last7, w.prev7
  from t left join a using (category) left join w using (category))
select category, actual, target,
       round(actual / nullif(target, 0) * 100, 1) as pct_of_target,
       case when actual / nullif(target, 0) < (select below_target from settings) then 'BELOW' else '' end as flag,
       round((last7 / nullif(prev7, 0) - 1) * 100, 1) as wow_pct
from x
union all
select 'Total', sum(actual), sum(target), round(sum(actual) / nullif(sum(target), 0) * 100, 1), '',
       round((sum(last7) / nullif(sum(prev7), 0) - 1) * 100, 1)
from x;

-- stock: total per item, with days left and a LOW flag
create view v_stock_total with (security_invoker = true) as
select s.item_code, s.item, s.category,
       sum(s.units_in_stock) as total_units, sum(s.reorder_level) as total_reorder,
       coalesce(x.sold28, 0) as sold_28d,
       round(sum(s.units_in_stock) / nullif(x.sold28 / 28.0, 0), 1) as days_left,
       case when sum(s.units_in_stock) <= sum(s.reorder_level) then 'LOW' else 'OK' end as status,
       count(*) filter (where s.units_in_stock <= s.reorder_level) as stores_low
from stock_by_store s
left join (select c.item, sum(c.units) as sold28 from clean_sales c, v_dates d
           where c.sale_date > d.sales_date - 28 and c.sale_date <= d.sales_date group by c.item) x on x.item = s.item
group by s.item_code, s.item, s.category, x.sold28;

-- stock: each store
create view v_stock_store with (security_invoker = true) as
select s.item, s.category, s.store, s.units_in_stock, s.reorder_level,
       case when s.units_in_stock <= s.reorder_level then 'LOW' else 'OK' end as status
from stock_by_store s;

-- enquiries with follow-up flag
create view v_enquiry_status with (security_invoker = true) as
select e.enquiry_id, e.customer, e.item_asked, e.store, e.status, e.last_followup,
       case when e.status = 'Open' then d.report_date - e.last_followup end as days_since,
       case when e.status = 'Open' and d.report_date - e.last_followup > (select overdue_days from settings) then 'OVERDUE'
            when e.status = 'Open' then 'On track' else '' end as flag
from enquiries e cross join v_dates d;

-- is the data fresh? Sales are not checked here, because a day can have no sales.
create view v_data_status with (security_invoker = true) as
select 'Stock data' as check_name,
       case when stock_updated_on >= (select sales_date from v_dates) then 'OK'
            else 'STALE: stock last updated ' || coalesce(to_char(stock_updated_on, 'DD Mon YYYY'), 'never') end as status
from settings
union all
select 'Enquiry data',
       case when enquiries_updated_on >= (select sales_date from v_dates) then 'OK'
            else 'STALE: enquiries last updated ' || coalesce(to_char(enquiries_updated_on, 'DD Mon YYYY'), 'never') end
from settings;

-- bad rows in the sales table
create view v_data_issues with (security_invoker = true) as
select id, sale_date, store, category, item, units, revenue,
       concat_ws(', ', case when sale_date is null then 'no date' end,
                       case when coalesce(store, '') = '' then 'blank store' end,
                       case when coalesce(category, '') = '' then 'blank category' end,
                       case when coalesce(item, '') = '' then 'blank item' end,
                       case when units < 0 or revenue < 0 then 'negative units or revenue' end) as problem
from sales
where sale_date is null or coalesce(store, '') = '' or coalesce(category, '') = '' or coalesce(item, '') = ''
   or units < 0 or revenue < 0;
