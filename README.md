# Cart leakage and retention analysis (Databricks SQL)

**Question:** How much revenue leaks between add-to-cart and purchase, which categories and brands cause it, and what is a cart-reminder nudge worth per month?

- **What I did:** Loaded 20.7M shopping events (2.4 GB) into Databricks and followed every cart to see whether it was bought within 7 days.
- **What I found:** **76.5% of carts are abandoned: $3.93M of products left unbought every month.** Half of it sits in just 23 of 465 categories.
- **Why it matters:** A reminder that wins back only 10% adds about $91K a month. Start with those 23 categories.

**Interactive case file:** [parthdhawan921-ops.github.io/Parth_Personal/#cart](https://parthdhawan921-ops.github.io/Parth_Personal/#cart)

![Databricks pipeline: 5 CSVs (2.4 GB) to a Unity Catalog volume, then Delta tables events_raw (20.69M rows), events (19.50M) and cart_outcomes (4.52M carts)](images/databricks_pipeline.png)

## Key findings

| Finding | Number |
|---|---|
| Events analysed (after cleaning) | 19.50M of 20.69M raw (5.8% removed) |
| Carts studied | 4.52M (one per user, product and day) |
| Carts abandoned (not bought within 7 days) | 3.46M, or 76.5% |
| Cart value left unbought | $18.76M over five months, about $3.93M a month |
| Category concentration | 23 of 465 categories hold 50% of the leak; 83 hold 80% |
| Repeat buyers | 9.2% of Nov and Dec first-time buyers buy again the next month |
| Value of a cart reminder at 10% recovery | About $91K a month net (5% = $42K, 15% = $140K) |

## Funnel at a glance

![Funnel tree: 20.7M events to a $91K-a-month reminder idea](A1_Funnel_Tree.png)

## Databricks pipeline

Five monthly CSVs (2.4 GB) land in a Unity Catalog volume. One `read_files` query loads them into a Delta table, and each step after that is its own Delta table: `events_raw` (20.69M rows) → `events` (19.50M, cleaned) → `cart_outcomes` (4.52M carts, one per user, product and day). Every query is in [A1_queries_as_run.sql](A1_queries_as_run.sql).

## Recommendation

Send a cart-reminder nudge, starting with the 23 categories that hold half of the leak. Run it as a holdout test before rolling it out, so the real recovery rate replaces the assumed one. Full detail is in the [memo](A1_memo.md).

## Method

1. Load five monthly CSVs into Delta tables.
2. Profile and clean: remove duplicate rows and invalid prices.
3. Build the funnel (view, cart, purchase) by users and by sessions.
4. Define an abandoned cart: the same user did not buy the same product within 7 days of adding it. The last 7 days of data are excluded, so every cart has a full 7-day window.
5. Value the leak in dollars by month, brand and category, with a Pareto analysis.
6. Build first-purchase cohorts and measure repeat rates.
7. Price a reminder nudge using clearly stated assumptions.

## Assumptions and limits

- **Assumed, not measured:** 10% recovery rate, 25% margin, $0.01 cost per reminder.
- Prices have no currency label in the source data; results are stated in $.
- The October cohort repeat rate (18.5%) is not reliable because the data starts in October, so earlier buyers look like new ones.
- 40.1% of abandoned value has no brand recorded, so brand results cover the rest.
- "Abandoned" means no purchase of the same product within 7 days. A buyer who returns later, or buys a similar product, still counts as abandoned.

## Tools

Databricks Free Edition, Unity Catalog, Delta tables, Databricks SQL (CTEs, window functions, EXISTS, date functions).

## Files

- [A1_memo.md](A1_memo.md): one-page memo with the recommendation
- [A1_queries_as_run.sql](A1_queries_as_run.sql): all queries, exactly as run
- [A1_Funnel_Tree.png](A1_Funnel_Tree.png): funnel and findings at a glance
- [images/databricks_pipeline.png](images/databricks_pipeline.png): the Databricks pipeline with row counts

## Data

[eCommerce Events History in Cosmetics Shop](https://www.kaggle.com/datasets/mkechinov/ecommerce-events-history-in-cosmetics-shop) (REES46 / Open CDP, Kaggle), Oct 2019 to Feb 2020. Credit: REES46 Marketing Platform. Raw files are not included in this repo (about 2.4 GB).

## Reproduce

Upload the five monthly CSVs to a Databricks volume (`/Volumes/workspace/cart_leakage/raw/`) and run the queries in order.
