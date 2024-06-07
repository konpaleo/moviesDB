# moviesDB
SQL script for transforming a movies dataset into a normalized transient DuckDB database.\
The file "movies.csv" contains the raw data gathered from various movie-aggregator websites.

The script performs tasks including:
- Data cleaning
- Creating separate relations for the `STARS`, `DIRECTORS` and `GENRE`  columns
- Aggregating data for duplicates and calculating weighted ratings
