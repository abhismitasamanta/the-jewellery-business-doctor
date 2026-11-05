# The Jewellery Business Doctor 💎

An n8n workflow that reads a jewellery business's daily sales, stock and enquiry data from Google Sheets, loads it into Supabase (Postgres), calculates KPIs and rule-based findings in SQL, and emails a plain-language "business diagnosis" through Gmail.

All data in this project is fictional.

## How it works
1. Update three Google Sheet tabs: `Daily_Sales`, `Stock_Current`, `Enquiries_Sheet`.
2. Change the value in cell A2 of the `Submit` tab (header `ready_date` in A1). This is the trigger.
3. n8n loads the three tabs into Supabase and checks that stock and enquiries are fresh.
4. It emails the briefing. If the freshness check fails, the email still goes out, with a warning line at the top.

```
Submit -> Read Sales -> Add Sales -> Read Stock -> Update Stock -> Mark Stock Updated
       -> Read Enquiries -> Update Enquiries -> Mark Enquiries Updated -> Check ready
       -> All 3 Data Ready? -> Get Briefing -> Gmail -> Log Report Sent
```

## What the report covers
- Sales vs target (weekday and weekend targets)
- Week-on-week change for every category, and in total
- Low stock vs reorder level, with days of stock left
- Store-level shortages on items that are fine in total
- Overdue customer follow-ups
- Which store is behind target over the last 3 days
- Data-quality warnings (blank store, negative units or revenue)

## Days with nothing to load
The workflow still runs and sends the report when:
- **there are no sales:** the report says "No sales today"
- **there are no new enquiries:** the enquiries already in the database are used, and overdue follow-ups are still listed
- **both are empty**

This needs *Always Output Data* on the Read Sales, Add Sales, Read Enquiries and Update Enquiries nodes, and the guarded queries in `sql/05_n8n_queries.sql`. Keep the header row in each tab, even when it has no data.

## Setup
1. Create a Supabase project. In the SQL Editor run, in order: `sql/01_tables.sql`, `sql/02_views.sql`, `sql/03_findings.sql`, `sql/04_briefing.sql`.
2. Load your daily targets into `targets` (columns: store, category, weekday_target, weekend_target) with Table Editor > Import CSV. Optionally load sales history into `sales`, and stock, enquiries.
3. Create the Google Sheet with the tabs `Submit`, `Daily_Sales`, `Stock_Current`, `Enquiries_Sheet`. Column names:
   - Daily_Sales: `sale_date, store, category, item, units, revenue` (format `sale_date` as plain text, yyyy-mm-dd)
   - Stock_Current: `item_code, item, category, store, units_in_stock, reorder_level, stock_date`
   - Enquiries_Sheet: `enquiry_id, enquiry_date, customer, item_asked, store, status, last_followup`
4. In n8n, import `n8n/Jewellery_Business_Doctor.json`. Then:
   - connect your Google Sheets, Postgres (use the Supabase *Session pooler* connection) and Gmail credentials
   - set your spreadsheet in each Google Sheets node (the file has `YOUR_SPREADSHEET_ID` as a placeholder)
   - set your email in the Gmail nodes (the file has `YOUR_EMAIL@example.com`)
5. The Submit trigger is "Row Added or Updated", every minute. Activate the workflow.

## Rules you can change (table `settings`)
| Column | Meaning | Default |
|---|---|---|
| `overdue_days` | an open enquiry is overdue after this many days | 3 |
| `below_target` | below this share of target is flagged | 0.95 |
| `min_store_shortfall` | smallest 3-day gap (Rs) worth naming a store | 10000 |
| `demo_date` | fix the report date for demos; leave empty for today | empty |

## Known limits
- Week-on-week and the 3-day store view depend on complete daily sales. A missing day makes them look worse than they are.
- The findings are checks to investigate, not proven causes.
