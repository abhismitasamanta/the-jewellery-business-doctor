-- 04_briefing.sql
-- Run fourth. Builds the full email text in one column called message.

create or replace view v_briefing with (security_invoker = true) as
select
  '💎 Jewellery Business Doctor' || E'\n' || to_char(d.report_date, 'Dy DD Mon YYYY') || E'\n' ||
  coalesce((select E'\n' || string_agg('⚠️ ' || check_name || ': ' || status, E'\n') || E'\n' from v_data_status where status <> 'OK'), '') ||
  E'\nToday''s business pulse\n' ||
  'Sales vs target (' || to_char(d.sales_date, 'Dy DD Mon') || '): ' || coalesce((select pct_of_target::text || '%' from v_category_summary where category = 'Total' and exists (select 1 from clean_sales x where x.sale_date = d.sales_date)), 'No sales today') || E'\n' ||
  'Low-stock items: ' || (select count(*) from v_stock_total where status = 'LOW') || E'\n' ||
  'Overdue follow-ups: ' || (select count(*) from v_enquiry_status where flag = 'OVERDUE') || E'\n' ||
  E'\n📈 Week on week by category\n' ||
  coalesce((select string_agg(case when category = 'Total' then 'All categories' else category end || ': ' ||
                              coalesce(case when wow_pct >= 0 then '+' else '' end || wow_pct || '%', 'n/a'),
                              E'\n' order by (category = 'Total'), category)
            from v_category_summary), '') || E'\n' ||
  E'\n🔎 What the data shows\n' ||
  coalesce((select string_agg('• ' || finding, E'\n' order by sev, ord) from v_findings), '• Nothing is outside the rules today.') || E'\n' ||
  coalesce((select E'\n💡 Recommended checks\n' || string_agg(n || '. ' || check_text, E'\n' order by n)
            from (select check_text, row_number() over (order by min(sev * 10 + ord)) as n from v_findings group by check_text) q where n <= 5), '') || E'\n' ||
  coalesce((select E'\n⚠️ Data checks\n' || string_agg('• Sales record ' || id || ': ' || problem, E'\n') || E'\n' from v_data_issues), '') ||
  E'\nThese are checks to investigate, not proven causes.' as message
from v_dates d;
