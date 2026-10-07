# A1 memo: Cart leakage in a cosmetics shop

**Recommendation:** Launch a cart-reminder nudge, targeting high-ticket categories first. At a 10% recovery rate it is worth about **$91K a month net** (about $42K at 5%, $140K at 15%).

**The question:** How much revenue leaks between add-to-cart and purchase, which categories and brands cause it, and what is a reminder worth per month?

**Data:** eCommerce Events History in Cosmetics Shop (REES46 / Open CDP, Kaggle), Oct 2019 to Feb 2020. 20,692,840 events; 19,497,292 after removing 5.8% (duplicates and invalid prices). Prices have no currency label, so results are in $. Analysis in SQL on Databricks.

## Findings
1. **The funnel leaks at the cart.** Of 1,596,371 users who viewed, 24.9% carted; only 27.8% of carters (110,518 users) bought. By session, 84% of cart sessions end without a purchase.
2. **$3.93M of cart value goes unbought each month** (average of Oct to Jan). 76.5% of carts are abandoned (3,459,026 of 4,523,377), and the rate stays between 75% and 78% in every month, so the leak is steady.
3. **It is concentrated in a minority of categories.** 83 of 465 categories (18%) hold 80% of the leaked value; 23 hold 50%. No single category exceeds 7.3%.
4. **Value, not volume, ranks the problem.** Among named brands, runail (5.0%), grattol (4.2%) and irisk (3.6%) lead by cart volume. `strong` has only 4,036 carts but leaks 3.3% of the total, at about $189 per abandoned cart. 40.1% of the leak sits in carts with no recorded brand.
5. **New customers rarely return.** About 9.2% of Nov and Dec first-time buyers buy again the next month. (The Oct cohort shows 18.5% but is inflated by returning customers, as the data starts in October.)

## What a nudge is worth (monthly)
| Recovery rate | Recovered revenue | Net value |
|---|---|---|
| 5% | $196K | $42K |
| 10% | $393K | $91K |
| 15% | $589K | $140K |

Net value = recovered revenue x 25% gross margin, minus $0.01 per reminder sent to every abandoned cart.

## Assumptions and limits
- **Margin (25%) and reminder cost ($0.01) are my assumptions**, not data. Net value moves roughly one-for-one with margin.
- **Abandoned** = same user did not buy the same product within 7 days of carting; carts in the last 7 days of data are excluded. Buying a different product still counts as abandoned. Repeat carts of one product by one user on one day count once.
- **Recovery rate is untested.** 5 to 10% is a reasonable range; 15% is optimistic. Test with a holdout group before relying on any figure.
- Funnel stages are not strictly sequenced: some buyers have no logged view.
- 42% of rows have no brand and 98% have no category name, so brand findings cover the named brands only.

## Next steps
Run the nudge on a randomised holdout, starting with the 23 categories that hold half the leak, and measure real recovery before scaling.
