# Hyderabad Food Delivery: Data Preprocessing in R

A step-by-step data cleaning and preparation pipeline in R for a synthetic Hyderabad food delivery dataset (1,545 raw orders, 14 columns). The aim is to take a messy dataset to an analysis-ready one and to record why each decision was made.

> The dataset is synthetic and was created for practice. It contains no real customer data.

## What is in this repository

| Item | Purpose |
| --- | --- |
| `hyd_food_delivery_preprocessing.R` | The full pipeline, in sections A to I |
| `hyd_food_delivery.csv` | The raw synthetic dataset |
| `clean_data.csv` | After type fixes, duplicate removal and missing-value treatment |
| `clean_data_post_outlier.csv` | After outlier capping |
| `cleaned_data_post_normalization.csv` | After min-max scaling |
| `clean_data_post_z-score.csv` | After z-score standardisation |
| `outputs/` | Graphs and console output from a run |

## The data

| Column | Meaning |
| --- | --- |
| `order_id` | Unique order identifier (primary key) |
| `order_date`, `order_hour` | When the order was placed |
| `area`, `cuisine` | Delivery area and cuisine type |
| `items_count`, `order_value` | Number of items and order amount |
| `distance_km`, `delivery_time_min` | Delivery distance and time taken |
| `weather` | Rainy or clear |
| `payment_mode`, `coupon_code` | How the customer paid and any coupon used |
| `tip_amount`, `rating` | Tip given and customer rating (1 to 5) |

## Pipeline and results

### 1. Clean types, text and duplicates

- Converted `order_date` to a date type.
- Trimmed spaces and upper-cased all text columns. This collapsed inconsistent spellings: `area` labels went from 45 to 8, `cuisine` from 26 to 6, and `payment_mode` from 15 to 3.
- Removed duplicates using `order_id` as the key: 45 duplicate rows removed, 1,545 rows down to 1,500.

### 2. Missing values

Counts are after duplicate removal.

| Column | Missing | Share | Treatment | Reason |
| --- | --- | --- | --- | --- |
| `coupon_code` | 1,085 | 72.33% | Set to `NO COUPON`, plus a `coupon_used` flag | A blank means no coupon was used, which is information, not a gap |
| `rating` | 135 | 9.00% | Linear regression on distance and delivery time (R-squared 0.483), clipped to 1 to 5 | Rating relates to both; imputed rows are flagged in `predicted_rating` |
| `tip_amount` | 75 | 5.00% | Median | Right-skewed with many zeros, so the mean would mislead |
| `payment_mode` | 22 | 1.47% | Most common value (UPI) | Categorical, no better predictor available |
| `distance_km` | 18 | 1.20% | Linear regression on delivery time (R-squared 0.666), clipped to 0.5 to 100 | Strongly related to delivery time |
| `cuisine` | 15 | 1.00% | New category `UNKNOWN` | Cannot be guessed reliably |

Check that imputation did not distort the data:

| Column | Mean before | Mean after | SD before | SD after |
| --- | --- | --- | --- | --- |
| `distance_km` | 4.077 | 4.069 | 2.739 | 2.729 |
| `tip_amount` | 13.604 | 13.423 | 17.237 | 16.818 |
| `rating` | 3.787 | 3.789 | 0.631 | 0.615 |


### 3. Outliers

- **Detection:** the IQR rule (1.5 times the IQR beyond the quartiles) and the Z-score rule, with skewness for context.

| Column | Outside IQR fences | Z-score beyond 3 |
| --- | --- | --- |
| `order_value` | 55 (all high) | 26 |
| `distance_km` | 42 (all high) | 22 |
| `delivery_time_min` | 41 (all high) | 17 |
| `tip_amount` | 47 (all high) | 22 |
| `rating` | 13 (all low) | 7 |
| `items_count`, `order_hour` | 0 | 0 |

- **Are they errors?** Domain checks found no negative or impossible values (no order value at or below 0, no rating outside 1 to 5, no tip above the order value, no hour outside 0 to 23). Implied delivery speed ranged from 1.0 to 19.6 km/h, median 7.3. The ten largest orders all had 4 to 6 items, and the longest deliveries were all long distances (14 to 18 km). The extremes are genuine, so no rows were dropped.
- **Treatment:** capped `order_value`, `distance_km`, `delivery_time_min` and `tip_amount` at the IQR fences. `rating`, `items_count` and `order_hour` were not capped.

| Column | Max before | Max after | SD before | SD after | Rows changed |
| --- | --- | --- | --- | --- | --- |
| `order_value` | 2,329 | 1,199.88 | 296.39 | 264.48 | 55 |
| `distance_km` | 18 | 10.39 | 2.73 | 2.47 | 42 |
| `delivery_time_min` | 79 | 55 | 10.34 | 9.73 | 41 |
| `tip_amount` | 140 | 50 | 16.82 | 14.95 | 47 |

![Order value before capping](outputs/boxplot_order_value_before_capping.png)
![Order value after capping](outputs/boxplot_order_value_after_capping.png)
![Distance before capping](outputs/boxplot_distance_before_capping.png)
![Distance after capping](outputs/boxplot_distance_after_capping.png)

### 4. Scaling

Applied to `order_value`, `distance_km`, `delivery_time_min`, `items_count`, `tip_amount` and `order_hour`.

- Min-max scaling to the range 0 to 1.
- Z-score standardisation to mean 0 and standard deviation 1.
- Both were verified for every column. The histograms below show the shape is unchanged; only the scale differs.

![Order value, capped](outputs/order_value_hist_capped.png)
![Order value, min-max scaled](outputs/order_value_hist_minmax.png)
![Order value, z-score scaled](outputs/order_value_hist_zscore.png)

### 5. Final checks

Rows: raw 1,545, final 1,500. Missing values left: 0. Duplicate order IDs left: 0.

## Decisions and limitations

- **Why the median for tips:** tips are right-skewed with many zeros, so the mean would be pulled upward.
- **Why regression for distance and rating:** both relate to other columns, so a model fills gaps better than a single constant. Limitation: regression imputation slightly shrinks the spread (rating SD 0.631 to 0.615), and the rating model is modest (R-squared 0.483), so imputed ratings are estimates. They are flagged in `predicted_rating` so they can be excluded or checked.
- **Why cap instead of delete:** the extremes are real orders, so removing them would discard valid information. Limitation: capping piles values at the fence, which shows as a spike in the last bar of the capped histogram, and a tip cap of 50 may flatten genuinely high tips.
- **Cyclic hour:** `order_hour` is scaled like the other columns, but 23 and 0 are numerically far apart even though they are neighbours on a clock. This matters if the column is used in a model.

## How to run

1. Install the packages: `install.packages(c("dplyr", "ggplot2", "e1071"))`.
2. Place `hyd_food_delivery.csv` in your working directory, or set it with `setwd()` at the top of the script.
3. Run the script from top to bottom. It writes the four cleaned CSV files listed above.

## Possible next steps

- Explore delivery time against distance, weather and area, and order value by cuisine and coupon use.
- Build a dashboard on the cleaned data.
- Compare simpler imputation methods against the regression approach.
