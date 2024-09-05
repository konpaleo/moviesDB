# moviesDB
SQL script for transforming a movies dataset into a normalized DuckDB database.\
The file "movies.csv" contains raw data gathered from various movie-aggregator websites.\
Before running the script, a connection to a DuckDB database (transient or persistent) should be established.

The script performs tasks including:
- Data cleaning
- Creating separate relations for the `STARS`, `DIRECTORS` and `GENRE`  columns
- Aggregating data for duplicates and calculating weighted ratings
