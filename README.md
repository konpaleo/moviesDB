# moviesDB
SQL code for transforming movie data into a normalized transient DuckDB database.\
The file "movies.csv" contains raw data gathered from various movie-aggregator websites.\

The script performs various data cleaning tasks, including:
- Removing unwanted characters from the `YEAR` column
- Cleaning up the `GENRE`, `ONE-LINE`, `GROSS`, `MOVIES`, and `STARS` columns
- Extracting and normalizing directors and stars into separate columns
- Aggregating data for duplicates and calculating weighted ratings
