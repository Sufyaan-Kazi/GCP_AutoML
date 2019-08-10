SELECT
  customer_id,
  order_date,
  order_value,
  order_qty_articles
FROM
(
  SELECT
    CustomerID AS customer_id,
    PARSE_DATE("%m/%d/%y", SUBSTR(InvoiceDate, 0, 8)) AS order_date,
    ROUND(SUM(UnitPrice * Quantity), 2) AS order_value,
    SUM(Quantity) AS order_qty_articles,
    (
      SELECT
        MAX(PARSE_DATE("%m/%d/%y", SUBSTR(InvoiceDate, 0, 8)))
      FROM
        `spw-demos.ltv_edu_auto.data_source` tl
      WHERE
        tl.CustomerID = t.CustomerID
    ) latest_order
  FROM
    `spw-demos.ltv_edu_auto.data_source` t
  GROUP BY
      CustomerID,
      order_date
) a

INNER JOIN (
  SELECT
    CustomerID
  FROM (
    SELECT
      CustomerID,
      SUM(positive_value) cnt_positive_value
    FROM (
      SELECT
        CustomerID,
        (
          CASE
            WHEN SUM(UnitPrice * Quantity) > 0 THEN 1
            ELSE 0
          END ) positive_value
      FROM
        `spw-demos.ltv_edu_auto.data_source`
      WHERE
        PARSE_DATE("%m/%d/%y", SUBSTR(InvoiceDate, 0, 8)) < DATE('2011-08-08')
      GROUP BY
        CustomerID,
        SUBSTR(InvoiceDate, 0, 8) )
    GROUP BY
      CustomerID )
  WHERE
    cnt_positive_value > 1
  ) b
ON
  a.customer_id = b. CustomerID
WHERE
  DATE_DIFF(DATE('2011-12-12'), latest_order, DAY) <= 90
  AND (
    (order_qty_articles > 0 and order_Value > 0) OR
    (order_qty_articles < 0 and order_Value < 0)
  )
