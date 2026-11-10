# ==========================================================
# HYDERABAD FOOD DELIVERY - DATA PREPROCESSING (R)
# ==========================================================

# ---------- SECTION A: Setup and loading ----------
library(dplyr)
library(ggplot2)
library(e1071)                 # for skewness()

# setwd("your/folder/path")    # set this to the folder containing the CSV

raw  <- read.csv("hyd_food_delivery.csv", na.strings = c("", "NA"))
data <- raw                    # we work on 'data'; 'raw' stays untouched

dim(data)
str(data)
summary(data)

# ---------- SECTION B: Functions used throughout ----------

# B1. Table of missing values per column
missing_summary <- function(df) {
  counts <- colSums(is.na(df))
  out <- data.frame(attribute = names(counts),
                    missing_values = as.integer(counts),
                    missing_percentages = round(100 * as.numeric(counts) / nrow(df), 2))
  out[out$missing_values > 0, ]
}

# B2. Most frequent value of a column (the mode)
get_mode <- function(x) {
  x <- x[!is.na(x)]
  names(sort(table(x), decreasing = TRUE))[1]
}

# B3. Fill missing values with the median
fill_median <- function(x) {
  x[is.na(x)] <- median(x, na.rm = TRUE)
  x
}

# B4. Fill missing values using a linear model
#     target     = column to fill, predictors = columns used to predict it
#     low / high = valid range, so predictions can't be impossible
impute_lm <- function(df, target, predictors, low, high) {
  fit <- lm(reformulate(predictors, response = target), data = df)
  cat(target, "- R-squared of the model:", round(summary(fit)$r.squared, 3), "\n")
  miss <- is.na(df[[target]])
  pred <- predict(fit, newdata = df[miss, ])
  pred <- round(pmin(pmax(pred, low), high), 1)
  df[[target]][miss] <- pred
  df
}

# B5. IQR fences for a column
iqr_bounds <- function(x) {
  q <- quantile(x, c(0.25, 0.75), na.rm = TRUE)
  i <- q[[2]] - q[[1]]
  c(lower = q[[1]] - 1.5 * i, upper = q[[2]] + 1.5 * i)
}

# B6. Cap values at the IQR fences
cap_iqr <- function(x) {
  b <- iqr_bounds(x)
  pmin(pmax(x, b[["lower"]]), b[["upper"]])
}

# B7. Scaling functions
min_max_scale <- function(x) (x - min(x)) / (max(x) - min(x))
z_score_scale <- function(x) (x - mean(x)) / sd(x)

# B8. Plot functions (one column at a time; we call them in loops)
plot_hist <- function(df, col, bins = 15) {
  ggplot(df, aes(x = .data[[col]])) +
    geom_histogram(aes(y = after_stat(density)), bins = bins,
                   fill = "skyblue", color = "black") +
    stat_function(fun = dnorm,
                  args = list(mean = mean(df[[col]], na.rm = TRUE),
                              sd = sd(df[[col]], na.rm = TRUE)),
                  color = "red", linewidth = 1) +
    labs(title = paste("Histogram of", col), x = col, y = "Density") +
    theme_classic()
}

plot_box <- function(df, col, title_prefix = "Boxplot", fill_color = "skyblue") {
  ggplot(df, aes(y = .data[[col]])) +
    geom_boxplot(fill = fill_color) +
    labs(title = paste(title_prefix, col), y = col) +
    theme_classic()
}

# ---------- SECTION C: Cleaning (types, text, duplicates) ----------

# C1. Fix the date type
data$order_date <- as.Date(data$order_date)

# C2. Standardise text: trim spaces and make UPPERCASE (order_id left alone)
text_cols <- setdiff(names(data)[sapply(data, is.character)], "order_id")
for (col in text_cols) {
  data[[col]] <- toupper(trimws(data[[col]]))
}
lapply(data[text_cols], unique)     # check: each column should show clean labels

# C3. Remove duplicates (order_id is the primary key)
sum(duplicated(data$order_id))      # expect 45
data <- data[!duplicated(data$order_id), ]
rownames(data) <- NULL
nrow(data)                          # expect 1500

# ---------- SECTION D: Missing values - detect ----------
missing_report <- missing_summary(data)
print(missing_report)

ggplot(missing_report, aes(x = reorder(attribute, missing_percentages),
                           y = missing_percentages)) +
  geom_col(fill = "skyblue", color = "black") +
  coord_flip() +
  labs(title = "Missing Percentage by Attribute", x = "Attribute", y = "Missing %") +
  theme_classic()

# Look at the numeric columns that have gaps
na_numeric <- c("distance_km", "tip_amount", "rating")
for (col in na_numeric) {
  print(summary(data[[col]]))
  print(plot_hist(data, col))
}

data_before_imputation <- data      # saved for the before/after comparison

# ---------- SECTION E: Missing values - treat ----------

# E1. Categorical columns
# A blank coupon means "no coupon used", so it is information, not a gap
data$coupon_used <- ifelse(is.na(data$coupon_code), 0, 1)
data$coupon_code[is.na(data$coupon_code)] <- "NO COUPON"

# Cuisine cannot be guessed -> its own category
data$cuisine[is.na(data$cuisine)] <- "UNKNOWN"

# Payment mode: fill with the most common value (UPI is about 58% of orders)
data$payment_mode[is.na(data$payment_mode)] <- get_mode(data$payment_mode)

# E2. Numeric columns
# Tips are right-skewed with many zeros -> median
data$tip_amount <- fill_median(data$tip_amount)

# Distance is strongly related to delivery time -> regression
data <- impute_lm(data, "distance_km", "delivery_time_min", low = 0.5, high = 100)

# Rating depends on distance and delivery time -> regression
# (record which ratings are predicted BEFORE filling them)
data$predicted_rating <- ifelse(is.na(data$rating), 1, 0)
data <- impute_lm(data, "rating", c("distance_km", "delivery_time_min"), low = 1, high = 5)

# E3. Verify: no NAs left, and compare before vs after
colSums(is.na(data))

compare_na <- data.frame()
for (col in na_numeric) {
  compare_na <- rbind(compare_na, data.frame(
    column = col,
    mean_before   = round(mean(data_before_imputation[[col]], na.rm = TRUE), 3),
    mean_after    = round(mean(data[[col]]), 3),
    median_before = median(data_before_imputation[[col]], na.rm = TRUE),
    median_after  = median(data[[col]]),
    sd_before     = round(sd(data_before_imputation[[col]], na.rm = TRUE), 3),
    sd_after      = round(sd(data[[col]]), 3)
  ))
}
print(compare_na)

for (col in na_numeric) print(plot_hist(data, col))   # shapes should look similar

write.csv(data, "clean_data.csv", row.names = FALSE)

# ---------- SECTION F: Outliers - detect and analyse ----------
numeric_cols <- c("order_value", "distance_km", "delivery_time_min",
                  "tip_amount", "rating", "items_count", "order_hour")

# F1. Visual check
for (col in numeric_cols) print(plot_box(data, col))
for (col in numeric_cols) print(plot_hist(data, col))
# order_hour is bimodal (lunch and dinner peaks) - the boxplot cannot show this

# F2. Outlier report (IQR rule and Z-score rule)
outlier_report <- data.frame()
for (col in numeric_cols) {
  x <- data[[col]]
  b <- iqr_bounds(x)
  z <- (x - mean(x)) / sd(x)
  outlier_report <- rbind(outlier_report, data.frame(
    column   = col,
    median   = median(x),
    lower    = round(b[["lower"]], 2),
    upper    = round(b[["upper"]], 2),
    n_below  = sum(x < b[["lower"]]),
    n_above  = sum(x > b[["upper"]]),
    n_iqr    = sum(x < b[["lower"]] | x > b[["upper"]]),
    n_z_gt_3 = sum(abs(z) > 3),
    skewness = round(skewness(x), 2)
  ))
}
print(outlier_report)

# F3. Domain sanity checks - are the extremes errors or real? (all should be 0)
sanity_checks <- c(
  order_value_le_0   = sum(data$order_value <= 0),
  items_lt_1         = sum(data$items_count < 1),
  rating_out_of_1_5  = sum(data$rating < 1 | data$rating > 5),
  distance_le_0      = sum(data$distance_km <= 0),
  delivery_time_le_0 = sum(data$delivery_time_min <= 0),
  hour_out_of_0_23   = sum(data$order_hour < 0 | data$order_hour > 23),
  tip_negative       = sum(data$tip_amount < 0),
  tip_gt_order_value = sum(data$tip_amount > data$order_value)
)
print(sanity_checks)

# Speed check in km/h (extreme values would be suspicious)
summary(data$distance_km / (data$delivery_time_min / 60))

# F4. Look at the most extreme rows
head(data[order(-data$order_value), c("order_id", "items_count", "order_value")], 10)
head(data[order(-data$delivery_time_min), c("order_id", "distance_km", "delivery_time_min")], 10)
# Conclusion: extremes are valid (big orders have many items, long deliveries
# have long distances), so we keep the rows and limit their influence by capping.

# ---------- SECTION G: Outliers - treat (capping) ----------
cap_cols <- c("order_value", "distance_km", "delivery_time_min", "tip_amount")
# rating (bounded 1-5), items_count (no IQR outliers) and order_hour are not capped

data_capped <- data
comparison_report <- data.frame()
for (col in cap_cols) {
  data_capped[[col]] <- cap_iqr(data[[col]])      # fences come from the uncapped data
  comparison_report <- rbind(comparison_report, data.frame(
    column       = col,
    max_before   = round(max(data[[col]]), 2),
    max_after    = round(max(data_capped[[col]]), 2),
    sd_before    = round(sd(data[[col]]), 2),
    sd_after     = round(sd(data_capped[[col]]), 2),
    rows_changed = sum(data[[col]] != data_capped[[col]])
  ))
}
print(comparison_report)

# Before / after boxplots
for (col in cap_cols) print(plot_box(data, col, "Before capping:", "lightblue"))
for (col in cap_cols) print(plot_box(data_capped, col, "After capping:", "lightgreen"))

nrow(data_capped) == nrow(data)                   # TRUE: no rows lost
write.csv(data_capped, "clean_data_post_outlier.csv", row.names = FALSE)

# ---------- SECTION H: Normalisation ----------
# Scale only continuous numeric columns (not flags, ids or dates)
scalable_cols <- c("order_value", "distance_km", "delivery_time_min",
                   "items_count", "tip_amount", "order_hour")
# order_hour is scaled so it sits on the same range as the others
# (note: it is cyclic, so 23 and 0 are far apart numerically - mention this in the report)

# H1. Min-max scaling (range 0 to 1)
data_minmax <- data_capped
for (col in scalable_cols) {
  data_minmax[[col]] <- min_max_scale(data_capped[[col]])
}

# H2. Z-score standardisation (mean 0, sd 1)
data_zscore <- data_capped
for (col in scalable_cols) {
  data_zscore[[col]] <- z_score_scale(data_capped[[col]])
}

# H3. Verify both
scaling_report <- data.frame()
for (col in scalable_cols) {
  scaling_report <- rbind(scaling_report, data.frame(
    column = col,
    minmax_min = round(min(data_minmax[[col]]), 3),
    minmax_max = round(max(data_minmax[[col]]), 3),
    z_mean     = round(mean(data_zscore[[col]]), 3),
    z_sd       = round(sd(data_zscore[[col]]), 3)
  ))
}
print(scaling_report)       # min 0, max 1, mean 0, sd 1 for every column

# Same shape, different scale (proof that scaling does not change the distribution)
print(plot_hist(data_capped, "order_value"))
print(plot_hist(data_minmax, "order_value"))
print(plot_hist(data_zscore, "order_value"))

# ---------- SECTION I: Save and final checks ----------
write.csv(data_minmax, "cleaned_data_post_normalization.csv", row.names = FALSE)
write.csv(data_zscore, "clean_data_post_z-score.csv", row.names = FALSE)

cat("Rows: raw =", nrow(raw), "| final =", nrow(data_minmax), "\n")
cat("Missing values left:", sum(is.na(data_minmax)), "\n")
cat("Duplicate order_ids left:", sum(duplicated(data_minmax$order_id)), "\n")
