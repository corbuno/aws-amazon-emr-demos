CREATE DATABASE retail;

CREATE EXTERNAL TABLE IF NOT EXISTS retail.amazonreview( 
    marketplace       string, 
    customer_id       string, 
    review_id         string, 
    product_id        string, 
    product_parent    string, 
    product_title     string, 
    star_rating       integer, 
    helpful_votes     integer, 
    total_votes       integer, 
    vine              string, 
    verified_purchase string, 
    review_headline   string, 
    review_body       string, 
    review_date       date, 
    year              integer) 
STORED AS PARQUET LOCATION 's3://EXAMPLE-BUCKET/input/toy/';

SELECT count(*) 
FROM retail.amazonreview;

SELECT count(*) 
FROM retail.amazonreview 
WHERE star_rating = 3;
