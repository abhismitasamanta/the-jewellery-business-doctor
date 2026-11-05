-- 03_findings.sql
-- Run third. Rule-based findings: every bullet of the briefing, with the check that goes with it.
-- sev = importance (0 first), ord = order within the same importance.

create or replace view v_findings with (security_invoker = true) as
with up_low as (
  select c.category,
         c.wow_pct,
         count(*) as n,
         string_agg(s.item || ' (' || s.total_units || ' left, about ' || s.days_left || ' days of stock)', ', ' order by s.days_left) as items
  from v_category_summary c join v_stock_total s on s.category = c.category and s.status = 'LOW'
  where c.wow_pct >= 10 group by c.category, c.wow_pct),
other_low as (
  select count(*) as n,
         string_agg(item || ' (' || total_units || ' left, about ' || coalesce(days_left::text, '?') || ' days)', ', ' order by days_left) as items
  from v_stock_total where status = 'LOW' and category not in (select category from up_low)),
store_cat as (
  select t.category, t.store,
         sum(case when extract(isodow from g) >= 6 then t.weekend_target else t.weekday_target end) as target,
         (select coalesce(sum(c.revenue), 0) from clean_sales c
           where c.category = t.category and c.store = t.store and c.sale_date between d.sales_date - 2 and d.sales_date) as actual
  from targets t cross join v_dates d
       cross join generate_series(d.sales_date - 2, d.sales_date, interval '1 day') as g
  group by t.category, t.store, d.sales_date),
sc2 as (
  select category, store, target, actual, greatest(0, target - actual) as shortfall
  from store_cat),
below as (
  select c.category, c.pct_of_target,
         (select s.store from sc2 s where s.category = c.category order by s.shortfall desc limit 1) as top_store,
         (select round(s.actual / nullif(s.target, 0) * 100) from sc2 s where s.category = c.category order by s.shortfall desc limit 1) as top_pct,
         (select max(s.shortfall) from sc2 s where s.category = c.category) as top_short,
         (select max(s.shortfall) / nullif(sum(s.shortfall), 0) from sc2 s where s.category = c.category) as top_share,
         (select count(*) from sc2 s where s.category = c.category and s.shortfall >= (select min_store_shortfall from settings)) as stores_flagged,
         (select count(*) from sc2 s where s.category = c.category) as stores_all
  from v_category_summary c
  where c.flag = 'BELOW' and exists (select 1 from clean_sales x where x.sale_date = (select sales_date from v_dates))),
od as (select count(*) as n, string_agg(customer || ' (' || item_asked || ', ' || days_since || ' days)', ', ' order by days_since desc) as who from v_enquiry_status where flag = 'OVERDUE'),
ss as (
  select count(*) as n,
         string_agg(s.item || ' at ' || s.store || ' (' || s.units_in_stock || ' left, level ' || s.reorder_level || ')', ', ' order by s.item, s.store) as items
  from v_stock_store s join v_stock_total t on t.item = s.item and t.status = 'OK' where s.status = 'LOW'),
fall as (
  select c.category, c.wow_pct,
         (select string_agg(s.item, ' and ') from v_stock_total s where s.category = c.category and s.status = 'LOW') as low_items
  from v_category_summary c where c.wow_pct <= -15 and c.flag <> 'BELOW' and c.category <> 'Total')
select 0 as sev, 0 as ord,
       'No sales recorded for ' || to_char(d.sales_date, 'Dy DD Mon') || '.' as finding,
       'Confirm that no sales were missed in the Daily_Sales sheet.' as check_text
from v_dates d where not exists (select 1 from clean_sales c where c.sale_date = d.sales_date)
union all
select 1, 1,
       category || ' sales are +' || wow_pct || '% week on week, but ' || n || ' of its items ' || case when n = 1 then 'is' else 'are' end || ' at or below reorder level: ' || items || '.',
       'Check replenishment for ' || category || ' items before the weekend.'
from up_low
union all
select 1, 2, n || ' more item' || case when n > 1 then 's' else '' end || ' at or below reorder level: ' || items || '.',
       'Review stock for the low items.'
from other_low where n > 0
union all
select 1, 3,
       category || ' is at ' || pct_of_target || '% of its target. ' ||
       case when top_short >= (select min_store_shortfall from settings) and top_share >= 0.5
              then 'Over the last 3 days, most of the gap is at ' || top_store || ' (' || top_pct || '% of its target).'
            when stores_flagged = stores_all then 'Over the last 3 days, all stores are below target.'
            else 'No single store stands out over the last 3 days.' end,
       case when top_short >= (select min_store_shortfall from settings) and top_share >= 0.5
              then 'Check what changed in ' || category || ' at ' || top_store || '.'
            else 'Look at ' || category || ' sales by item.' end
from below
union all
select 2, 4, n || ' customer follow-up' || case when n > 1 then 's are' else ' is' end || ' overdue: ' || who || '.',
       'Follow up on the overdue enquiries today.'
from od where n > 0
union all
select 2, 5, n || ' store-level shortage' || case when n > 1 then 's' else '' end || ' on items that are fine in total: ' || items || '.',
       'Check whether stock can be moved between stores.'
from ss where n > 0
union all
select 2, 6, category || ' revenue is ' || wow_pct || '% week on week' ||
       case when low_items is not null then ', and ' || low_items || ' is also low on stock' else '' end || '.',
       'Look at ' || category || ' sales by store and by item.'
from fall;
