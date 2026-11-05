-- 04_briefing.sql
-- Run fourth. Builds the full email text in one column called message, in three sections: Sales, Stock, Enquiries.

create or replace view v_briefing with (security_invoker = true) as
select
  '💎 Jewellery Business Doctor' || E'\n' || to_char(d.report_date, 'Dy DD Mon YYYY') || E'\n' ||
  coalesce((select E'\n' || string_agg('⚠️ ' || check_name || ': ' || status, E'\n') || E'\n' from v_data_status where status <> 'OK'), '') ||

  -- ===== AT A GLANCE =====
  E'\n📌 AT A GLANCE\n' ||
  'Sales vs target: ' || p.txt || E'\n' ||
  'Low-stock items: ' || (select count(*) from v_stock_total where status = 'LOW') || E'\n' ||
  'Overdue follow-ups: ' || (select count(*) from v_enquiry_status where flag = 'OVERDUE') || E'\n' ||

  -- ===== SALES =====
  E'\n━━━━━━━━━━━━━━━━━━\n💰 SALES\n━━━━━━━━━━━━━━━━━━\n' ||
  'Sales vs target (' || to_char(d.sales_date, 'Dy DD Mon') || '): ' || p.txt || E'\n' ||
  E'\nWeek on week by category\n' ||
  coalesce((select string_agg('• ' || case when category = 'Total' then 'All categories' else category end || ': ' ||
                              coalesce(case when wow_pct >= 0 then '+' else '' end || wow_pct || '%', 'n/a'),
                              E'\n' order by (category = 'Total'), category)
            from v_category_summary), '') || E'\n' ||

  coalesce((select E'\n' || string_agg('• ' || finding, E'\n' order by sev, ord)
            from v_findings where ord in (0, 3)), '') || E'\n' ||

  -- ===== STOCK =====
  E'\n━━━━━━━━━━━━━━━━━━\n📦 STOCK\n━━━━━━━━━━━━━━━━━━\n' ||
  coalesce((select 'Low-stock items: ' || count(*) || E'\n' ||
                   string_agg('• ' || item || ' – ' || total_units || ' left' || coalesce(' (about ' || days_left || ' days)', ''),
                              E'\n' order by days_left nulls last)
            from v_stock_total where status = 'LOW'),
           '✅ No items at or below reorder level.') || E'\n' ||
  coalesce((select E'\nLow (below reorder level) in one store, fine (at reorder level) in total: ' || count(*) || E'\n' ||
                   string_agg('• ' || s.item || ' at ' || s.store || ' – ' || s.units_in_stock || ' left (reorder level ' || s.reorder_level || ')',
                              E'\n' order by s.item, s.store)
            from v_stock_store s join v_stock_total t on t.item = s.item and t.status = 'OK'
            where s.status = 'LOW') || E'\n', '') ||
  coalesce((select E'\n🔥 Selling fast, running low\n' || string_agg('• ' || finding, E'\n' order by ord)
            from v_findings where ord = 1) || E'\n', '') ||

  -- ===== ENQUIRIES =====
  E'\n━━━━━━━━━━━━━━━━━━\n👥 ENQUIRIES\n━━━━━━━━━━━━━━━━━━\n' ||
  'Open enquiries: ' || (select count(*) from enquiries where status = 'Open') ||
  '   |   Overdue: ' || (select count(*) from v_enquiry_status where flag = 'OVERDUE') || E'\n' ||
  coalesce((select E'\nOverdue follow-ups (no contact for more than ' || (select overdue_days from settings) || E' days)\n' ||
                   string_agg('• ' || customer || ' – ' || item_asked || ' (' || store || '), ' || days_since || ' days',
                              E'\n' order by days_since desc)
            from v_enquiry_status where flag = 'OVERDUE'),
           E'\n✅ No overdue follow-ups.') ||
  coalesce((select E'\n→ Follow up on these enquiries today.' where exists (select 1 from v_enquiry_status where flag = 'OVERDUE')), '') || E'\n' ||

  coalesce((select E'\n⚠️ Data checks\n' || string_agg('• Sales record ' || id || ': ' || problem, E'\n') || E'\n' from v_data_issues), '') ||
  E'\nThese are checks to investigate, not proven causes.' as message
from v_dates d
cross join lateral (
  select coalesce((select pct_of_target::text || '%' from v_category_summary
                   where category = 'Total' and exists (select 1 from clean_sales x where x.sale_date = d.sales_date)),
                  'No sales today') as txt) p;
