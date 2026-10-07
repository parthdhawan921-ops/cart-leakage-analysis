# A1: Cart leakage and repeat cohorts (Databricks SQL)

**Question:** How much revenue leaks between add-to-cart and purchase, which categories and brands cause it, and what is a cart-reminder nudge worth per month?

**Answer:** About $3.93M of cart value goes unbought each month (76.5% of carts abandoned); 83 of 465 categories hold 80% of it. A nudge recovering 10% is worth about $91K a month net, at an assumed 25% margin.

- Memo: `final/A1_memo.md`
- All queries, as run: `final/A1_queries_as_run.sql`

**Data:** eCommerce Events History in Cosmetics Shop, REES46 / Open CDP (Kaggle), Oct 2019 to Feb 2020. Credit REES46. Raw files are not included. Prices carry no currency label; results are stated in $.

**Reproduce:** upload the five monthly CSVs to a Databricks volume (`/Volumes/workspace/cart_leakage/raw/`) and run the queries in order.
