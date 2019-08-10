SELECT
  tf.customer_id,
  tf.monetary_dnn,
  tf.monetary_btyd,
  tf.cnt_orders AS frequency_dnn,
  tf.cnt_orders - 1 AS frequency_btyd,
  tf.recency,
  tf.T,
  ROUND(tf.recency/cnt_orders, 2) AS time_between,
  ROUND(tf.avg_basket_value, 2) AS avg_basket_value,
  ROUND(tf.avg_basket_size, 2) AS avg_basket_size,
  tf.cnt_returns,
  (CASE
      WHEN tf.cnt_returns > 0 THEN 1
      ELSE 0 END) AS has_returned,

  (CASE
      WHEN tf.cnt_orders - 1 > 600 THEN 600
      ELSE tf.cnt_orders - 1 END) AS frequency_btyd_clipped,
  (CASE
      WHEN tf.monetary_btyd > 100000 THEN 100000
      ELSE ROUND(tf.monetary_btyd, 2) END) AS monetary_btyd_clipped,
  (CASE
      WHEN tt.target_monetary > 100000 THEN 100000
      ELSE ROUND(tt.target_monetary, 2) END) AS target_monetary_clipped,

  ROUND(tt.target_monetary, 2) as target_monetary
FROM
  (
    SELECT
      customer_id,
      SUM(order_value) AS monetary_dnn,
      (CASE
        WHEN COUNT(DISTINCT order_date) = 1 THEN 0
        ELSE SUM(order_value_btyd) / (COUNT(DISTINCT order_date) -1) END) AS monetary_btyd,
      DATE_DIFF(MAX(order_date), MIN(order_date), DAY) AS recency,
      DATE_DIFF(DATE('2011-08-08'), MIN(order_date), DAY) AS T,
      COUNT(DISTINCT order_date) AS cnt_orders,
      AVG(order_qty_articles) avg_basket_size,
      AVG(order_value) avg_basket_value,
      SUM(CASE
          WHEN order_value < 1 THEN 1
          ELSE 0 END) AS cnt_returns
    FROM
      (
        SELECT
          a.*,
          (CASE
              WHEN a.order_date = c.order_date_min THEN 0
              ELSE a.order_value END) AS order_value_btyd
        FROM
          `spw-demos.ltv_edu_auto.data_cleaned` a
        INNER JOIN (
          SELECT
            customer_id,
            MIN(order_date) AS order_date_min
          FROM
            `spw-demos.ltv_edu_auto.data_cleaned`
          GROUP BY
            customer_id) c
        ON
          c.customer_id = a.customer_id
      )
    WHERE
      order_date <= DATE('2011-08-08')
    GROUP BY
      customer_id) tf,

  (
    SELECT
      customer_id,
      SUM(order_value) target_monetary
    FROM
      `spw-demos.ltv_edu_auto.data_cleaned`
    GROUP BY
      customer_id) tt
WHERE
  tf.customer_id = tt.customer_id
  AND tf.monetary_dnn > 0
  AND tf.monetary_dnn <= 15000
  AND tf.monetary_btyd > 0
