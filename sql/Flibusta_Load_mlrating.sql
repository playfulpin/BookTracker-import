--
-- Flibusta
--
/*
 +------------------------------------------------------------------------------
  This SQL designed to run against MultiLib database
  from 'HeidiSQL' environment to provide rating info
  for the books.
  
  Prerequeste:
    file 'lib.librate.sql.gz' must be downloaded from
    FLIBUSTA dumps and extracted to the folder "G:\My Drive\FromDropBox\SQLdumps"
    in the followng format "librate_YYYY-MM-DD.sql" (like librate_2024-11-30.sql).
    That file should be run in 'HeidiSQL' to create table 'librate'
    in the 'flibusta' database.
 +------------------------------------------------------------------------------
*/
--
-- Set character set the client will use to send SQL statements to the server
--
SET NAMES 'utf8mb3';

--
-- Set default database
--
USE flibusta;

--
--        Step 01.
--  Create and populate intermidient table `librating`
--

DROP TABLE IF EXISTS `librating`;

CREATE TABLE `librating`
  (
    `rt_id`  INT(11) UNSIGNED NOT NULL AUTO_INCREMENT,
    `bookid` INT(11)          NOT NULL,
    `rating` CHAR(1)          NOT NULL DEFAULT '' COLLATE 'utf8_general_ci',
    PRIMARY KEY (`rt_id`) USING BTREE
  )
COLLATE = 'utf8_general_ci' ENGINE = MYISAM;

INSERT IGNORE INTO librating
      (
        rt_id,
        bookid,
        rating
      )
    SELECT
            0      AS 'rt_id',
            BookId AS 'bookid',
            ROUND(
              AVG(CONVERT(Rate, UNSIGNED))
              )    AS 'rating'
    FROM
            librate
    GROUP BY
            bookid;
--
--        Step 02.
--  populate table `mlrating`
--
DROP TABLE IF EXISTS `mlrating`;
--
-- Create table `mlrating`
--

CREATE TABLE mlrating
  (
    rt_id  INT(11) UNSIGNED NOT NULL AUTO_INCREMENT,
    bookid INT(11)          NOT NULL,
    rating CHAR(1)          NOT NULL DEFAULT '',
    PRIMARY KEY (rt_id)
  )
ENGINE = MYISAM,
AUTO_INCREMENT = 340117,
AVG_ROW_LENGTH = 12,
CHARACTER SET utf8mb3,
CHECKSUM = 0,
COLLATE utf8mb3_general_ci,
ROW_FORMAT = FIXED;

--
-- Create index `bookid` on table `mlrating`
--
ALTER TABLE mlrating
ADD INDEX bookid (bookid);

--
-- Create index `rating` on table `mlrating`
--
ALTER TABLE mlrating
ADD INDEX rating (rating);

INSERT INTO mlrating
      (
        rt_id,
        bookid,
        rating
      )
    SELECT
            *
    FROM
            librating;
--
--        Done.
--