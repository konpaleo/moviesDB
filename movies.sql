CREATE TABLE rawdata AS
SELECT * FROM read_csv_auto('movies.csv');

--DATA CLEANING------------------------------------------

UPDATE rawdata SET YEAR = replace(YEAR, '(', '');
UPDATE rawdata SET YEAR = replace(YEAR, ')', '');
UPDATE rawdata SET YEAR = replace(YEAR, 'I', '');
UPDATE rawdata SET YEAR = left(YEAR, 4) WHERE YEAR NOT LIKE '____';
UPDATE rawdata SET YEAR = trim(YEAR);
UPDATE rawdata SET YEAR = NULL WHERE YEAR NOT LIKE '2___' 
				AND YEAR NOT LIKE '1___';


UPDATE rawdata SET GENRE = replace(GENRE, chr(10), '');

UPDATE rawdata SET "ONE-LINE" = replace("ONE-LINE", chr(10), '');
UPDATE rawdata SET "ONE-LINE" = trim("ONE-LINE");
UPDATE rawdata SET "ONE-LINE" = NULL WHERE "ONE-LINE" = 'Add a Plot';

--UPDATE rawdata SET GROSS = replace(GROSS, '$', '');
--UPDATE rawdata SET GROSS = replace(GROSS, 'M', '');
UPDATE rawdata SET GROSS = trim(GROSS);
--UPDATE rawdata SET GROSS = CAST(GROSS AS DOUBLE);

UPDATE rawdata SET MOVIES = trim(MOVIES);
UPDATE rawdata SET MOVIES = replace(MOVIES, '#', '');
UPDATE rawdata SET MOVIES = replace(MOVIES, '_', '');
-- treating some special cases 
UPDATE rawdata SET MOVIES = replace(MOVIES, '100% Coco', 'Coco');
UPDATE rawdata SET MOVIES = replace(MOVIES, '3%', 'Three');

UPDATE rawdata SET STARS = replace(STARS, chr(10), '');
UPDATE rawdata SET STARS = trim(STARS);


-- splitting directors and stars into different columns
ALTER TABLE rawdata ADD COLUMN DIRECTORS VARCHAR;
UPDATE rawdata SET DIRECTORS =
       CASE
               WHEN STARS LIKE 'Director%:%|%'
                       THEN regexp_extract(STARS,'(?:Directors?:)(.*?)(?:\|)')
               WHEN STARS LIKE 'Director%:%'
                       THEN regexp_extract(STARS,'(?:Directors?:)(.*?)$')
               ELSE NULL
       END;

UPDATE rawdata SET STARS = 
	CASE
		WHEN STARS LIKE 'Director%:%|%'
			THEN regexp_replace(STARS, '(?:.*?\|)', '')
		WHEN STARS LIKE 'Director%:%'
			THEN NULL
		ELSE STARS
	END;
 
UPDATE rawdata SET STARS = trim(STARS);
UPDATE rawdata SET STARS = replace(STARS, 'Stars:', '');
UPDATE rawdata SET STARS = replace(STARS, 'Star:', '');
UPDATE rawdata SET DIRECTORS = trim(DIRECTORS);
UPDATE rawdata SET DIRECTORS = replace(DIRECTORS, 'Directors:', '');
UPDATE rawdata SET DIRECTORS = replace(DIRECTORS, 'Director:', '');
UPDATE rawdata SET DIRECTORS = replace(DIRECTORS, '|', '');


-- concatenating directors and stars for each group of movie duplicates
WITH aggregated_directors AS (
	SELECT MOVIES, concat_ws(', ', STRING_AGG(DISTINCT DIRECTORS)) AS CONCATENATED_DIRECTORS
     	FROM rawdata
     	WHERE DIRECTORS IS NOT NULL AND TRIM(DIRECTORS) <> ''
     	GROUP BY MOVIES)
UPDATE rawdata SET DIRECTORS =
     	(SELECT CONCATENATED_DIRECTORS
     	FROM aggregated_directors ad
     	WHERE ad.MOVIES = rawdata.MOVIES)
WHERE EXISTS 
	(SELECT 1 FROM aggregated_directors ad
	WHERE ad.MOVIES = rawdata.MOVIES);

WITH aggregated_stars AS (
	SELECT MOVIES, concat_ws(', ', STRING_AGG(DISTINCT STARS)) AS CONCATENATED_STARS
     	FROM rawdata
     	WHERE STARS IS NOT NULL AND TRIM(STARS) <> ''
     	GROUP BY MOVIES)
UPDATE rawdata SET STARS =
     	(SELECT CONCATENATED_STARS
     	FROM aggregated_stars ags
     	WHERE ags.MOVIES = rawdata.MOVIES)
WHERE EXISTS 
	(SELECT 1 FROM aggregated_stars ags
	WHERE ags.MOVIES = rawdata.MOVIES);


-- replacing rating with weighted mean of ratings and votes with sum of votes for
-- each group of duplicates
WITH weighted_ratings AS (
	SELECT MOVIES,
        SUM(RATING * CAST(REPLACE(VOTES, ',', '') AS DOUBLE)) AS WEIGHTED_RATING,
	SUM(CAST(REPLACE(VOTES, ',', '') AS DOUBLE)) AS TOTAL_VOTES
	FROM rawdata 
	WHERE VOTES IS NOT NULL AND TRIM(VOTES) <> ''
	GROUP BY MOVIES)
UPDATE rawdata SET 
	RATING = wr.WEIGHTED_RATING / wr.TOTAL_VOTES,
     	VOTES = wr.TOTAL_VOTES
	FROM weighted_ratings wr WHERE rawdata.MOVIES = wr.MOVIES;

UPDATE rawdata SET RATING = ROUND(RATING, 1);
UPDATE rawdata SET VOTES = CAST(VOTES AS INTEGER);

-- setting runtime to NULL for TVseries episodes (episode number is unknown)
WITH title_counts AS (
       SELECT MOVIES, COUNT(*) AS count
       FROM rawdata
       GROUP BY MOVIES)
UPDATE rawdata SET RUNTIME = NULL
WHERE MOVIES IN (
       SELECT MOVIES FROM title_counts
       WHERE count > 1);

-- concatenating descriptions for duplicates
WITH aggregated_lines AS (
	SELECT MOVIES, concat_ws(', ', STRING_AGG(DISTINCT "ONE-LINE"))
	AS CONCATENATED_LINES FROM rawdata
     	WHERE "ONE-LINE" IS NOT NULL AND TRIM("ONE-LINE") <> ''
     	GROUP BY MOVIES)
UPDATE rawdata SET "ONE-LINE" =
     	(SELECT CONCATENATED_LINES
     	FROM aggregated_lines agl
     	WHERE agl.MOVIES = rawdata.MOVIES)
WHERE EXISTS 
	(SELECT 1 FROM aggregated_lines agl
	WHERE agl.MOVIES = rawdata.MOVIES);



--SCHEMA IMPROVEMENT----------------------------------------

CREATE TABLE newdata AS
SELECT DISTINCT 
MOVIES, YEAR, GENRE, RATING, VOTES, "ONE-LINE", RUNTIME, GROSS, STARS, DIRECTORS
FROM rawdata ORDER BY MOVIES;

-- duckDB does not support adding a constrained column (primary key)
CREATE TABLE Movies_new AS
SELECT ROW_NUMBER() OVER () AS ID, * FROM
(SELECT * FROM newdata ORDER BY MOVIES);

DROP TABLE newdata;
ALTER TABLE Movies_new RENAME TO newdata;
UPDATE newdata SET ID = CAST(ID AS INTEGER);

-- creating the Movies entity table
CREATE TABLE Movies (
			movieID INTEGER PRIMARY KEY,
			title VARCHAR,
			release_year INTEGER,
			genre VARCHAR,
			rating DOUBLE,
			votes INTEGER,
			runtime INTEGER,
			description VARCHAR,
			gross VARCHAR);

INSERT INTO Movies (
	movieID, title, release_year, genre, rating, votes, runtime, description, gross)
SELECT 
	ID, MOVIES, YEAR, GENRE, RATING, VOTES, RUNTIME, "ONE-LINE", GROSS
FROM newdata;

-- creating the Stars entity table--------
CREATE TABLE star_temp AS 
SELECT UNNEST(string_split(STARS, ',')) AS sname FROM newdata;

DELETE FROM star_temp WHERE sname = '';
UPDATE star_temp SET sname = trim(sname);

CREATE TABLE dist_star AS
SELECT DISTINCT sname AS sname FROM star_temp;

DROP TABLE star_temp;

CREATE TABLE star_temp AS
SELECT ROW_NUMBER() OVER () AS starID, * FROM 
(SELECT * FROM dist_star ORDER BY sname);

DROP TABLE dist_star;
UPDATE star_temp SET starID = CAST(starID AS INTEGER);

CREATE TABLE Stars (
		starID INTEGER PRIMARY KEY,
		sname VARCHAR);

INSERT INTO Stars (starID, sname)
SELECT starID, sname FROM star_temp;

DROP TABLE star_temp;

-- creating the Directors entity table--------
CREATE TABLE dir_temp AS 
SELECT UNNEST(string_split(DIRECTORS, ',')) AS dname FROM newdata;

DELETE FROM dir_temp WHERE dname = '';
UPDATE dir_temp SET dname = trim(dname);

CREATE TABLE dist_dir AS
SELECT DISTINCT dname AS dname FROM dir_temp;

DROP TABLE dir_temp;

CREATE TABLE dir_temp AS
SELECT ROW_NUMBER() OVER () AS dirID, * FROM
(SELECT * FROM dist_dir ORDER BY dname);

DROP TABLE dist_dir;
UPDATE dir_temp SET dirID = CAST(dirID AS INTEGER);

CREATE TABLE Directors (
		dirID INTEGER PRIMARY KEY,
		dname VARCHAR);

INSERT INTO Directors (dirID, dname)
SELECT dirID, dname FROM dir_temp;

DROP TABLE dir_temp;

-- creating the Genres entity table--------
CREATE TABLE gen_temp AS 
SELECT UNNEST(string_split(GENRE, ',')) AS genre FROM newdata;

DELETE FROM gen_temp WHERE genre = '';
UPDATE gen_temp SET genre = trim(genre);

CREATE TABLE dist_genres AS
SELECT DISTINCT genre AS genre FROM gen_temp;

DROP TABLE gen_temp;

CREATE TABLE gen_temp AS
SELECT ROW_NUMBER() OVER () AS genreID, * FROM
(SELECT * FROM dist_genres ORDER BY genre);

DROP TABLE dist_genres;
UPDATE gen_temp SET genreID = CAST(genreID AS INTEGER);

CREATE TABLE Genres (
		genreID INTEGER PRIMARY KEY,
		genre VARCHAR);

INSERT INTO Genres (genreID, genre)
SELECT genreID, genre FROM gen_temp;

DROP TABLE gen_temp;


-- creating the Movies_Stars relationship junction table---------

CREATE TABLE Movies_Stars (
		movieID INTEGER REFERENCES Movies(movieID),
		starID INTEGER REFERENCES Stars(starID));

INSERT INTO Movies_Stars (movieID, starID)
SELECT m.movieID, s.starID
FROM Stars s
JOIN (
    SELECT UNNEST(string_split(nd.STARS, ', ')) AS unstar, nd.MOVIES
    FROM newdata nd
    WHERE nd.STARS IS NOT NULL
) AS unnested ON trim(s.sname) = trim(unnested.unstar)
JOIN Movies m ON trim(m.title) = trim(unnested.MOVIES)
GROUP BY m.movieID, s.starID
ORDER BY m.movieID;


-- creating the Movies_Directors relationship junction table---------

CREATE TABLE Movies_Directors (
		movieID INTEGER REFERENCES Movies(movieID),
		dirID INTEGER REFERENCES Directors(dirID));

INSERT INTO Movies_Directors (movieID, dirID)
SELECT m.movieID, d.dirID
FROM Directors d
JOIN (
    SELECT UNNEST(string_split(nd.DIRECTORS, ', ')) AS undir, nd.MOVIES
    FROM newdata nd
    WHERE nd.DIRECTORS IS NOT NULL
) AS unnested ON trim(d.dname) = trim(unnested.undir)
JOIN Movies m ON trim(m.title) = trim(unnested.MOVIES)
GROUP BY m.movieID, d.dirID
ORDER BY m.movieID;


-- creating the Movies_Genres relationship junction table---------

CREATE TABLE Movies_Genres (
		movieID INTEGER REFERENCES Movies(movieID),
		genreID INTEGER REFERENCES Genres(genreID));

INSERT INTO Movies_Genres (movieID, genreID)
SELECT m.movieID, g.genreID
FROM Genres g
JOIN (
    SELECT UNNEST(string_split(nd.GENRE, ', ')) AS ungen, nd.MOVIES
    FROM newdata nd
    WHERE nd.GENRE IS NOT NULL
) AS unnested ON trim(g.genre) = trim(unnested.ungen)
JOIN Movies m ON trim(m.title) = trim(unnested.MOVIES)
GROUP BY m.movieID, g.genreID
ORDER BY m.movieID;


ALTER TABLE Movies DROP COLUMN genre;
DROP TABLE rawdata;
DROP TABLE newdata;
