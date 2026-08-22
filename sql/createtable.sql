/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00'*/;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO'*/;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


-- Закачки ------------------------------------------------------------------------------------------

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mllbr_main`.`mldownload` (
  `dl_id` int(11) unsigned NOT NULL auto_increment,
  `bookid` int(11) NOT NULL,
  `library` varchar(256) collate utf8_general_ci NOT NULL default'',
  `title` varchar(255) NOT NULL DEFAULT '',
  `FullName` varchar(200) NOT NULL default '',
  `seqname` varchar(254) NOT NULL DEFAULT '',
  `genrenamerus` varchar(100) NOT NULL default '',    
  `filesize` int(11) NOT NULL default 0,
  `lang` varchar(10) NOT NULL DEFAULT '', 
  `ext` varchar(5) NOT NULL DEFAULT '', 
  `dl_position` int(10) NOT NULL,
  `dl_done` char(1) collate utf8_general_ci NOT NULL default'',
  `dl_date` DATETIME, 
  `dl_msg` varchar(256) collate utf8_general_ci NOT NULL default'',
  PRIMARY KEY  (`dl_id`),
  KEY `bookid` (`bookid`),
  KEY `dl_position` (`dl_position`),
  KEY `dl_done` (`dl_done`),
  KEY `library` (`library`),
  KEY `dl_msg` (`dl_msg`),
  UNIQUE KEY `URec` (`bookid`,`library`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

-- Группы ------------------------------------------------------------------------------------------

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mllbr_main`.`mlgroup` (
  `uc_id` int(10) unsigned NOT NULL auto_increment,
  `bookid` int(11) NOT NULL,
  `groupid` int(10) unsigned NOT NULL ,
  `library` varchar(256) collate utf8_general_ci NOT NULL default'',
  `date_gr` DATETIME,   --   Дата добавления/переноса в группу
  PRIMARY KEY  (`uc_id`),
  KEY `bookid` (`bookid`),
  KEY `groupid` (`groupid`),
  KEY `library` (`library`),
  UNIQUE KEY `URec` (`bookid`,`groupid`,`library`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 ;
/*!40101 SET character_set_client = @saved_cs_client */;

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mllbr_main`.`mlgroupname` (
  `groupid` int(10) unsigned NOT NULL auto_increment,
  `groupidparrent` int(10) unsigned NOT NULL DEFAULT 0,
  `groupname` varchar(50) collate utf8_general_ci NOT NULL default'',
  PRIMARY KEY `groupid` (`groupid`),
  KEY `groupidparrent` (`groupidparrent`),
  UNIQUE KEY `groupnameall` (`groupid`,`groupidparrent`,`groupname`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 ;

LOCK TABLES `mllbr_main`.`mlgroupname` WRITE;
/*!40000 ALTER TABLE `mllbr_main`.`mlgroupname` DISABLE KEYS */;
INSERT IGNORE INTO `mllbr_main`.`mlgroupname` VALUES (1,0,'Избранное'),(2,0,'К прочтению'),(3,0,'Прочитано');
/*!40000 ALTER TABLE `mllbr_main`.`mlgroupname` ENABLE KEYS */;
UNLOCK TABLES;
/*!40101 SET character_set_client = @saved_cs_client */;

-- Базовый список жанров -------------------------------------------------------------------------------

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mllbr_main`.`mlgenrelist` (
  `genrecode` varchar(30) NOT NULL DEFAULT'',
  `genregroup` varchar(100) NOT NULL DEFAULT'',
  `genrenamerus` varchar(100) NOT NULL DEFAULT'',
  UNIQUE KEY `genrecode` (`genrecode`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

LOCK TABLES `mllbr_main`.`mlgenrelist` WRITE;
/*!40000 ALTER TABLE `mllbr_main`.`mlgenrelist` DISABLE KEYS */;
INSERT IGNORE INTO `mllbr_main`.`mlgenrelist`(`genrecode`,`genregroup`,`genrenamerus`) values ('sf_history','Фантастика (Научная фантастика и Фэнтези)','Альтернативная история'),('sf_action','Фантастика (Научная фантастика и Фэнтези)','Боевая фантастика'),('sf_epic','Фантастика (Научная фантастика и Фэнтези)','Эпическая фантастика'),('sf_heroic','Фантастика (Научная фантастика и Фэнтези)','Героическая фантастика'),('sf_detective','Фантастика (Научная фантастика и Фэнтези)','Детективная фантастика'),('sf_cyberpunk','Фантастика (Научная фантастика и Фэнтези)','Киберпанк'),('sf_space','Фантастика (Научная фантастика и Фэнтези)','Космическая фантастика'),('sf_social','Фантастика (Научная фантастика и Фэнтези)','Социально-психологическая фантастика'),('sf_horror','Фантастика (Научная фантастика и Фэнтези)','Ужасы и Мистика'),('sf_humor','Фантастика (Научная фантастика и Фэнтези)','Юмористическая фантастика'),('sf_fantasy','Фантастика (Научная фантастика и Фэнтези)','Фэнтези'),('sf','Фантастика (Научная фантастика и Фэнтези)','Научная Фантастика'),('det_classic','Детективы и Триллеры','Классический детектив'),('det_police','Детективы и Триллеры','Полицейский детектив'),('det_action','Детективы и Триллеры','Боевик'),('det_irony','Детективы и Триллеры','Иронический детектив'),('det_history','Детективы и Триллеры','Исторический детектив'),('det_espionage','Детективы и Триллеры','Шпионский детектив'),('det_crime','Детективы и Триллеры','Криминальный детектив'),('det_political','Детективы и Триллеры','Политический детектив'),('det_maniac','Детективы и Триллеры','Маньяки'),('det_hard','Детективы и Триллеры','Крутой детектив'),('thriller','Детективы и Триллеры','Триллер'),('detective','Детективы и Триллеры','Детектив (не относящийся в прочие категории).'),('prose_classic','Проза','Классическая проза'),('prose_history','Проза','Историческая проза'),('prose_contemporary','Проза','Современная проза'),('prose_counter','Проза','Контркультура'),('prose_rus_classic','Проза','Русская классическая проза'),('prose_su_classics','Проза','Советская классическая проза'),('love_contemporary','Любовные романы','Современные любовные романы'),('love_history','Любовные романы','Исторические любовные романы'),('love_detective','Любовные романы','Остросюжетные любовные романы'),('love_short','Любовные романы','Короткие любовные романы'),('love_erotica','Любовные романы','Эротика'),('adv_western','Приключения','Вестерн'),('adv_history','Приключения','Исторические приключения'),('adv_indian','Приключения','Приключения про индейцев'),('adv_maritime','Приключения','Морские приключения'),('adv_geo','Приключения','Путешествия и география'),('adv_animal','Приключения','Природа и животные'),('adventure','Приключения','Прочие приключения (то, что не вошло в другие категории)'),('child_tale','Детское','Сказка'),('child_verse','Детское','Детские стихи'),('child_prose','Детское','Детскиая проза'),('child_sf','Детское','Детская фантастика'),('child_det','Детское','Детские остросюжетные'),('child_adv','Детское','Детские приключения'),('child_education','Детское','Детская образовательная литература'),('children','Детское','Прочая детская литература (то, что не вошло в другие категории)'),('poetry','Поэзия, Драматургия','Поэзия'),('dramaturgy','Поэзия, Драматургия','Драматургия'),('antique_ant','Старинное','Античная литература'),('antique_european','Старинное','Европейская старинная литература'),('antique_russian','Старинное','Древнерусская литература'),('antique_east','Старинное','Древневосточная литература'),('antique_myths','Старинное','Мифы. Легенды. Эпос'),('antique','Старинное','Прочая старинная литература (то, что не вошло в другие категории)'),('sci_history','Наука, Образование','История'),('sci_psychology','Наука, Образование','Психология'),('sci_culture','Наука, Образование','Культурология'),('sci_religion','Наука, Образование','Религиоведение'),('sci_philosophy','Наука, Образование','Философия'),('sci_politics','Наука, Образование','Политика'),('sci_business','Наука, Образование','Деловая литература'),('sci_juris','Наука, Образование','Юриспруденция'),('sci_linguistic','Наука, Образование','Языкознание'),('sci_medicine','Наука, Образование','Медицина'),('sci_phys','Наука, Образование','Физика'),('sci_math','Наука, Образование','Математика'),('sci_chem','Наука, Образование','Химия'),('sci_biology','Наука, Образование','Биология'),('sci_tech','Наука, Образование','Технические науки'),('science','Наука, Образование','Прочая научная литература (то, что не вошло в другие категории)'),('comp_www','Компьютеры и Интернет','Интернет'),('comp_programming','Компьютеры и Интернет','Программирование'),('comp_hard','Компьютеры и Интернет','Компьютерное \'железо\' (аппаратное обеспечение)'),('comp_soft','Компьютеры и Интернет','Программы'),('comp_db','Компьютеры и Интернет','Базы данных'),('comp_osnet','Компьютеры и Интернет','ОС и Сети'),('computers','Компьютеры и Интернет','Прочая околокомпьтерная литература (то, что не вошло в другие категории)'),('ref_encyc','Справочная литература','Энциклопедии'),('ref_dict','Справочная литература','Словари'),('ref_ref','Справочная литература','Справочники'),('ref_guide','Справочная литература','Руководства'),('reference','Справочная литература','Прочая справочная литература (то, что не вошло в другие категории)'),('nonf_biography','Документальная литература','Биографии и Мемуары'),('nonf_publicism','Документальная литература','Публицистика'),('nonf_criticism','Документальная литература','Критика'),('design','Документальная литература','Искусство и Дизайн'),('nonfiction','Документальная литература','Прочая документальная литература (то, что не вошло в другие категории)'),('religion_rel','Религия и духовность','Религия'),('religion_esoterics','Религия и духовность','Эзотерика'),('religion_self','Религия и духовность','Самосовершенствование'),('religion','Религия и духовность','Прочая религионая литература (то, что не вошло в другие категории)'),('humor_anecdote','Юмор','Анекдоты'),('humor_prose','Юмор','Юмористическая проза'),('humor_verse','Юмор','Юмористические стихи'),('humor','Юмор','Прочий юмор (то, что не вошло в другие категории)'),('home_cooking','Домоводство (Дом и семья)','Кулинария'),('home_pets','Домоводство (Дом и семья)','Домашние животные'),('home_crafts','Домоводство (Дом и семья)','Хобби и ремесла'),('home_entertain','Домоводство (Дом и семья)','Развлечения'),('home_health','Домоводство (Дом и семья)','Здоровье'),('home_garden','Домоводство (Дом и семья)','Сад и огород'),('home_diy','Домоводство (Дом и семья)','Сделай сам'),('home_sport','Домоводство (Дом и семья)','Спорт'),('home_sex','Домоводство (Дом и семья)','Эротика, Секс'),('home','Домоводство (Дом и семья)','Прочиее домоводство (то, что не вошло в другие категории)');
/*!40000 ALTER TABLE `mllbr_main`.`mlgenrelist` ENABLE KEYS */;
UNLOCK TABLES;
/*!40101 SET character_set_client = @saved_cs_client */;


-- Аннотация ------------------------------------------------------------------------------------------
  
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mldescription` (
  `ds_id` int(11) NOT NULL auto_increment,
  `bookid` int(11),
  `descr` varchar(20000) NOT NULL,
   PRIMARY KEY  (`ds_id`),
   KEY `bookid` (`bookid`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

-- Обложка ------------------------------------------------------------------------------------------

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mlcoverpage` (
  `cp_id` int(11) NOT NULL auto_increment,
  `bookid` int(11),
  `cover` MEDIUMBLOB ,
   PRIMARY KEY  (`cp_id`),
   KEY `bookid` (`bookid`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

-- Рейтинг ------------------------------------------------------------------------------------------

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;

CREATE TABLE IF NOT EXISTS `mlrating` (
  `rt_id` int(11) unsigned NOT NULL auto_increment,
  `bookid` int(11) NOT NULL,
  `rating` char(1) collate utf8_general_ci NOT NULL default'',
  PRIMARY KEY  (`rt_id`),
  KEY `bookid` (`bookid`),
  KEY `rating` (`Rating`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 ;
/*!40101 SET character_set_client = @saved_cs_client */;

-- Скачано ------------------------------------------------------------------------------------------

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mldownloaddata` (
  `dd_id` int(11) unsigned NOT NULL auto_increment,
  `bookid` int(11) NOT NULL,
  `date_dl` DATETIME,
  PRIMARY KEY  (`dd_id`),
  UNIQUE KEY `bookid` (`bookid`),
  KEY `date_dl` (`date_dl`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 ;
/*!40101 SET character_set_client = @saved_cs_client */;

-- Новинки ------------------------------------------------------------------------------------------

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mlnewsname` (
  `critid` int(10) unsigned NOT NULL auto_increment,
  `critname` varchar(256) collate utf8_general_ci NOT NULL default'',
  `critfilter` blob,
  `critsql` text,
  PRIMARY KEY  (`critid`),
  KEY `critname` (`critname`(50))
  
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 ;
/*!40101 SET character_set_client = @saved_cs_client */;

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mlnews` (
  `cb_id` int(10) unsigned NOT NULL auto_increment,
  `critid` int(10) unsigned NOT NULL,
  `bookid` int(11) NOT NULL,
  PRIMARY KEY  (`cb_id`),
  KEY `critid` (`critid`),
  KEY `bookid` (`bookid`),
  UNIQUE KEY `URec` (`bookid`,`critid`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 ;
/*!40101 SET character_set_client = @saved_cs_client */;


-- Ключевые слова ------------------------------------------------------------------------------------------

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mluserkeyword` (
  `kw_id` int(10) unsigned NOT NULL auto_increment,
  `bookid` int(11) NOT NULL,
  `userkeywords` varchar(254) collate utf8_general_ci NOT NULL default'',
  PRIMARY KEY  (`kw_id`),
  KEY `bookid` (`bookid`),
  KEY `userkeywords` (`userkeywords`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 ;
/*!40101 SET character_set_client = @saved_cs_client */;

-- Примечания ------------------------------------------------------------------------------------------

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `mluserprim` (
  `up_id` int(10) unsigned NOT NULL auto_increment,
  `bookid` int(11) NOT NULL,
  `prim` varchar(254) collate utf8_general_ci NOT NULL default'',
  PRIMARY KEY  (`up_id`),
  KEY `bookid` (`bookid`),
  KEY `Prim` (`Prim`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8 ;
/*!40101 SET character_set_client = @saved_cs_client */;

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;

CREATE TABLE IF NOT EXISTS `mlbook` (
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

CREATE TABLE IF NOT EXISTS `mlcustinfo` (
  `ci_id` int(11) NOT NULL auto_increment,
  `bookid` int(11),
  `di_history` varchar(2048) NOT NULL DEFAULT '',    -- [0,1] история создания и изменения документа
  `custominfo` varchar(2048) NOT NULL DEFAULT '',
   PRIMARY KEY  (`ci_id`),
   KEY `bookid` (`bookid`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `mlauthorname` (
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
  KEY `LastName` (`LastName`(20)),
  KEY `FullName` (`FullName`(60))
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `mlauthor` (
  `la_id` int(11) NOT NULL auto_increment,
  `bookid` int(10) unsigned NOT NULL DEFAULT '0',
  `authorid` int(10) unsigned NOT NULL DEFAULT '0',
  `role` binary(1) NOT NULL DEFAULT 'a' COMMENT 'a-автор,t-переводчик,i-иллюстратор',
  PRIMARY KEY (`la_id`),
  KEY `bookid` (`bookid`),
  KEY `authorid` (`authorid`),
  UNIQUE KEY `bookseq` (`bookid`,`authorid`,`role`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `mlseqname` (
  `seqid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `seqname` varchar(254) NOT NULL DEFAULT '',
  `TotalCount` int(11)  NOT NULL default '0',
  `NormalCount` int(11)  NOT NULL default '0',  
  PRIMARY KEY (`seqid`),
  KEY `TotalCount` (`TotalCount`),
  KEY `NormalCount` (`NormalCount`),  
  UNIQUE KEY `seqname` (`seqname`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `mlseq` (
  `sq_id` int(11) NOT NULL auto_increment,
  `bookid` int(11) NOT NULL,
  `seqid` int(11) NOT NULL,
  `seqnum` int(11) NOT NULL,
  PRIMARY KEY (`sq_id`),
  KEY (`bookid`),
  KEY `seqId` (`seqid`),
  UNIQUE KEY `bookseq` (`bookid`,`seqid`,`seqnum`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `mlgenrename` (
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
  KEY `genrenamerus` (`genrenamerus`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `mlgenre` (
  `gn_id` int(11) NOT NULL auto_increment,
  `bookid` int(10) unsigned NOT NULL DEFAULT '0',
  `genreid` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`gn_id`),
  KEY `bookid` (`bookid`),
  KEY `genreid` (`genreid`)
) ENGINE=MyISAM AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

 CREATE TABLE IF NOT EXISTS `mlactual` (
 `BookId` int(10) unsigned NOT NULL,
 `FileType` char(4) character set ascii collate ascii_bin NOT NULL,
 `Author` varchar(200) character set utf8 NOT NULL default '',
 `Title` varchar(254) collate utf8_unicode_ci NOT NULL default '',
 `FileName` varchar(245) collate utf8_unicode_ci NOT NULL default '',
 `ArcName` varchar(245) collate utf8_unicode_ci NOT NULL default '',
 `Status` smallint(6) NOT NULL default 0,
  KEY `bookid` (`bookid`)
 ) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;


/*!40101 SET character_set_client = @saved_cs_client */;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
