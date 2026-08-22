/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

SET @saved_cs_client     = @@character_set_client; 
SET character_set_client = utf8; 

DROP TABLE IF EXISTS `libavtoraliase`;
drop table if exists mlauthoraliase;

-- Основная таблица ------------------------------------------------------------------------------------------

DROP TABLE IF EXISTS `mlbook`;
CREATE TABLE `mlbook` (
  `bookid` int(11) NOT NULL auto_increment,          -- [*]   ИД книги в базе
  `library` varchar(64) NOT NULL DEFAULT '',         -- [*]   Библиотека
  `title` varchar(255) NOT NULL DEFAULT '',          -- [1]   Название книги
  `lang` varchar(10) NOT NULL DEFAULT '',            -- [1]   Язык книги
  `date_in` DATETIME,                                -- [*]   Дата поступления
  `filename` varchar(255) NOT NULL DEFAULT '',       -- [*]   Имя файла
  `filesize` int(11) NOT NULL default 0,             -- [*]   Если FB2 - размер без архивации
  `arcname` varchar(255) NOT NULL DEFAULT '',        -- [*]   Имя файла
  `ext` varchar(5) NOT NULL DEFAULT '',              -- [*]   Расширение
  `deleted` char(1) NOT NULL DEFAULT '',             -- [*]   Удалено (для Librus, Flibusta)
  `md5` char(32) NOT NULL DEFAULT '',                -- [*]   MD5
  `srclang` varchar(10) NOT NULL DEFAULT '',         -- [0,1] язык, на котором исходно написана книга, то есть язык до перевода
  `date_wr` char(32) default '',                     -- [0,1] Дата написания книги Из FB2
  `keywords` varchar(255) NOT NULL DEFAULT '',       -- [0,1] Из FB2
  `di_progused` varchar(255) NOT NULL DEFAULT '',    -- [0,1] В какой программе изготовлено
  `di_date` char(32) default '',                     -- [1]   Дата создания документа
  `di_srcurl` varchar(255) NOT NULL DEFAULT '',      -- [0,n] URL страницы, откуда взят текст для подготовки документа
  `di_srcosr` varchar(100) NOT NULL DEFAULT '',      -- [0,1] автор текста, который был использован при подготовке документа
  `di_author` varchar(100) NOT NULL DEFAULT '',      -- [1,n] автор документа
  `di_id` varchar(254) NOT NULL DEFAULT '',          -- [1]   уникальный идентификатор документа FB2
  `di_version` varchar(10) NOT NULL DEFAULT '',      -- [1]   Версия документа
  `pi_bookname` varchar(255) NOT NULL DEFAULT '',    -- [0,1] название оригинальной (бумажной) книги
  `pi_publisher` varchar(100) NOT NULL DEFAULT '',   -- [0,1] название издательства
  `pi_city` varchar(50) NOT NULL DEFAULT '',         -- [0,1] город, в котором издана книга
  `pi_year` varchar(10) NOT NULL DEFAULT '',         -- [0,1] год издания книги
  `pi_isbn` varchar(100) NOT NULL DEFAULT '',        -- [0,1] ISBN издания
-- pi_sequence  [0,n]
   PRIMARY KEY  (`bookid`),
   KEY `md5` (`md5`),
   KEY `ext` (`ext`),
   KEY `lang` (`lang`),
   KEY `deleted` (`deleted`),
   KEY `filename` (`filename`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

insert ignore into mlbook select `BookId`, Database(),`Title`,lower(`Lang`),`Time`,'',`Filesize`,'',lower(`FileType`),`Deleted`,lower(`md5`),`srclang`,'',`keywords`,'','','','',`FileAuthor`,'',`Ver`,'','','',`Year`,'' from libbook;

update ignore mlbook as a, libfilenameold as b set a.FileName=b.FileName where a.BookId=b.BookId;
update ignore mlbook as a, libfilename as b set a.FileName=b.FileName where a.BookId=b.BookId;
update ignore mlbook set FileName=BookId where FileName='' and ext='fb2';
update ignore mlbook set FileName=concat(BookId,'.',ext) where FileName='' and ext<>'fb2';

-- UPDATE IGNORE mlbook AS a, libsrclang AS b SET a.srclang=b.srclang WHERE a.bookid=b.bookid;
-- drop table IF EXISTS `libsrclang`;


-- Дополнтельная информация  ----------------------------------------------------------------------------
  
DROP TABLE IF EXISTS `mlcustinfo`;
CREATE TABLE `mlcustinfo` (
  `ci_id` int(11) NOT NULL auto_increment,
  `bookid` int(11),
  `di_history` varchar(2048) NOT NULL DEFAULT '',    -- [0,1] история создания и изменения документа
  `custominfo` varchar(2048) NOT NULL DEFAULT '',
   PRIMARY KEY  (`ci_id`),
   KEY `bookid` (`bookid`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

insert ignore into mlcustinfo select null,`BookId`,'', `title1` from libbook where title1<>'';

drop table IF EXISTS `libbook`;
drop table IF EXISTS `libfilename`;
drop table IF EXISTS `libfilenameold`;

update ignore mlbook set Deleted='0' where deleted & 1 = 0;
update ignore mlbook set Deleted='1' where deleted & 1 <> 0;

-- Авторы ------------------------------------------------------------------------------------------

DROP TABLE IF EXISTS `mlauthorname`;
CREATE TABLE `mlauthorname` (
  `authorid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `FirstName` varchar(99) NOT NULL DEFAULT '',
  `MiddleName` varchar(99) NOT NULL DEFAULT '',
  `LastName` varchar(99) NOT NULL DEFAULT '',
  `NickName` varchar(33) NOT NULL DEFAULT '',
  `FullName` varchar(200) NOT NULL default '',
  `Email` varchar(255) NOT NULL,
  `TotalCount` int(11)  NOT NULL default '0',
  `NormalCount` int(11)  NOT NULL default '0',  
  PRIMARY KEY (`authorid`),
  KEY `TotalCount` (`TotalCount`),
  KEY `NormalCount` (`NormalCount`),  
  KEY `FirstName` (`FirstName`(20)),
  KEY `MiddleName` (`LastName`(20)),
  KEY `NickName` (`LastName`(20)),
  KEY `LastName` (`LastName`(20)),
  KEY `FullName` (`FullName`(60))
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `mlauthor`;
CREATE TABLE `mlauthor` (
  `la_id` int(11) NOT NULL auto_increment,
  `bookid` int(10) unsigned NOT NULL DEFAULT '0',
  `authorid` int(10) unsigned NOT NULL DEFAULT '0',
  `role` binary(1) NOT NULL DEFAULT 'a' COMMENT 'a-автор,t-переводчик,i-иллюстратор',
  PRIMARY KEY (`la_id`),
  KEY `bookid` (`bookid`),
  KEY `authorid` (`authorid`),
  UNIQUE KEY `bookseq` (`bookid`,`authorid`,`role`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

insert ignore into mlauthorname select `AvtorId`,`FirstName`,`MiddleName`,`LastName`,`NickName`,trim(Concat_WS(" ",libavtorname.LastName,libavtorname.FirstName)) as fullname,`Email`, null,null  from libavtorname join libavtor using(AvtorId) group by AvtorId;
insert ignore into mlauthor select null,`BookId`,`AvtorId`, "a" from libavtorname join libavtor using(AvtorId);

drop table if exists aaa;
create temporary table aaa (select authorid from mlauthor join mlauthorname using (authorid) where firstname="" and lastname="" and middlename="" and nickname="" group by authorid);
CREATE INDEX authorid ON aaa  (authorid);
delete from mlauthor where authorid in (select authorid from aaa);

drop table if exists aaa;
create temporary table aaa (select authorid from mlauthor join mlauthorname using (authorid) where firstname like "%автор%" or lastname like "%автор %" or middlename like "%автор%" group by authorid);
CREATE INDEX authorid ON aaa  (authorid);
delete from mlauthor where authorid in (select authorid from aaa);

drop table if exists aaa;
set @a:=(select min(authorid) from mlauthorname where Lastname="Автор неизвестен");
insert ignore into mlauthor(authorid,bookid,role) select @a, bookid,'a' from mlbook where bookid not in (select bookid from mlauthor);


drop table if exists aaa;
create temporary table aaa (select authorid from mlauthor group by authorid);
CREATE INDEX authorid ON aaa  (authorid);
delete from mlauthorname where authorid not in (select authorid from aaa);

drop table IF EXISTS `libavtorname`;
drop table IF EXISTS `libavtor`;

drop table if exists aaa;
create temporary table aaa (
select authorid,count(bookid) as tcount from mlbook join mlauthor using (bookid)   join mlauthorname using(authorid) group by authorid);
update ignore mlauthorname as a, aaa as b set totalcount=tcount where a.authorid=b.authorid;

drop table if exists aaa;
create temporary table aaa (
select authorid,count(bookid) as tcount from mlbook join mlauthor using(bookid) join  mlauthorname using (authorid) where deleted='0' group by authorid);
update ignore mlauthorname as a, aaa as b set normalcount=tcount where a.authorid=b.authorid;

-- Серии ------------------------------------------------------------------------------------------

DROP TABLE IF EXISTS `mlseqname`;
CREATE TABLE `mlseqname` (
  `seqid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `seqname` varchar(254) NOT NULL DEFAULT '',
  `TotalCount` int(11)  NOT NULL default '0',
  `NormalCount` int(11)  NOT NULL default '0',  
  PRIMARY KEY (`seqid`),
  KEY `TotalCount` (`TotalCount`),
  KEY `NormalCount` (`NormalCount`),  
  UNIQUE KEY `seqname` (`seqname`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `mlseq`;
CREATE TABLE `mlseq` (
  `sq_id` int(11) NOT NULL auto_increment,
  `bookid` int(11) NOT NULL,
  `seqid` int(11) NOT NULL,
  `seqnum` int(11) NOT NULL,
  PRIMARY KEY (`sq_id`),
  KEY (`bookid`),
  KEY `seqId` (`seqid`),
  UNIQUE KEY `bookseq` (`bookid`,`seqid`,`seqnum`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;


insert ignore into mlseq select null,`BookId`,`SeqId`,`SeqNumb` from libseqname join libseq using(SeqId); 
insert ignore into mlseqname select `SeqId`,`seqname`,null,null from libseqname join mlseq using(seqid);

drop table if exists aaa;
create temporary table aaa (
select seqid,count(bookid) as tcount from mlbook join mlseq using(bookid) join mlseqname using (seqid) group by seqid);
update ignore mlseqname as a, aaa as b set totalcount=tcount where a.seqid=b.seqid;

drop table if exists aaa;
create temporary table aaa (
select seqid,count(bookid) as tcount from mlbook join mlseq using(bookid) join mlseqname using (seqid) where deleted='0' group by seqid);
update ignore mlseqname as a, aaa as b set normalcount=tcount where a.seqid=b.seqid;

drop table IF EXISTS `libseqname`;
drop table IF EXISTS `libseq`;

-- Жанры ------------------------------------------------------------------------------------------

DROP TABLE IF EXISTS `mlgenrename`;
CREATE TABLE `mlgenrename` (
  `genreid` int(11) NOT NULL auto_increment,
  `parentgenreid` int(11) default NULL,
  `genrecode` varchar(30) NOT NULL default '',
  `genrenamerus` varchar(100) NOT NULL default '',
  `TotalCount` int(11)  NOT NULL default '0',
  `NormalCount` int(11)  NOT NULL default '0',  
  PRIMARY KEY  (`genreid`),
  KEY `parentgenreid` (`parentgenreid`),
  KEY `TotalCount` (`TotalCount`),
  KEY `NormalCount` (`NormalCount`),  
  KEY `genrecode` (`genrecode`),
  KEY `genrenamerus` (`genrenamerus`(50))
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `mlgenre`;
CREATE TABLE `mlgenre` (
  `gn_id` int(11) NOT NULL auto_increment,
  `bookid` int(10) unsigned NOT NULL DEFAULT '0',
  `genreid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`gn_id`),
  KEY `bookid` (`bookid`),
  KEY `genreid` (`genreid`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `mlgenrenametemp`;
CREATE temporary TABLE `mlgenrenametemp` (
  `genreid` int(11) NOT NULL auto_increment,
  `parentgenreid` int(11) default NULL,
  `genrecode` varchar(30) NOT NULL default '',
  `genrenamerus` varchar(100) NOT NULL default '',
  `genremeta` varchar(100) NOT NULL default '',
  PRIMARY KEY  (`genreid`),
  KEY `parentgenreid` (`parentgenreid`),
  KEY `genrecode` (`genrecode`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

insert ignore into mlgenrenametemp select genreid,null,genrecode,GenreDesc,Genremeta from libgenrelist;

DROP TABLE IF EXISTS `aaa`;
CREATE temporary TABLE `aaa` (
  `genreid` int(11) NOT NULL auto_increment,
  `genremeta` varchar(100) NOT NULL default '',
  PRIMARY KEY  (`genreid`)
) ENGINE=MyISAM AUTO_INCREMENT=1000001 DEFAULT CHARSET=utf8;

insert ignore into aaa select null,Genremeta from libgenrelist group by Genremeta;

update ignore mlgenrenametemp as a, aaa as b set parentgenreid=b.genreid where a.genremeta=b.genremeta ;
insert ignore into mlgenrenametemp select genreid,null,"",GenreMeta,GenreMeta from aaa;
drop table if exists aaa;
insert ignore into mlgenrename select genreid,parentgenreid,genrecode,genrenamerus,null,null from mlgenrenametemp;
DROP TABLE IF EXISTS `mlgenrenametemp`;
insert ignore into mlgenre select null,bookid,genreid from libgenre;

drop table IF EXISTS `libgenrelist`;
drop table IF EXISTS `libgenre`;

drop table if exists aaa;
create temporary table aaa (
select genreid,count(bookid) as tcount from mlbook join mlgenre using (bookid) join mlgenrename using (genreid) group by genreid);
update ignore mlgenrename as a, aaa as b set totalcount=tcount where a.genreid=b.genreid;

drop table if exists aaa;
create temporary table aaa (
select genreid,count(bookid) as tcount from mlbook join mlgenre using (bookid) join mlgenrename using (genreid)  where deleted='0' group by genreid);
update ignore mlgenrename as a, aaa as b set normalcount=tcount where a.genreid=b.genreid;

drop table if exists aaa;

drop table if exists mldescription;
CREATE TABLE IF NOT EXISTS `mldescription` (
  `ds_id` int(11) NOT NULL auto_increment,
  `bookid` int(11),
  `descr` varchar(20000) NOT NULL,
   PRIMARY KEY  (`ds_id`),
   KEY `bookid` (`bookid`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

-- insert ignore into mldescription select null,`bookid`,`body` from libbannotations;
-- drop table if exists libbannotations;



SET character_set_client = @saved_cs_client; 
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
