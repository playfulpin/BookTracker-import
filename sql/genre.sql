/*
SQLyog Ultimate v8.71 
MySQL - 5.1.50-community : Database - private
*********************************************************************
*/

/*!40101 SET NAMES utf8 */;

/*!40101 SET SQL_MODE=''*/;

/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
CREATE DATABASE /*!32312 IF NOT EXISTS*/`private` /*!40100 DEFAULT CHARACTER SET utf8 */;

USE `private`;

/*Table structure for table `mlgenrename` */

DROP TABLE IF EXISTS `mlgenrename`;

CREATE TABLE `mlgenrename` (
  `genreid` int(11) NOT NULL AUTO_INCREMENT,
  `parentgenreid` int(11) DEFAULT NULL,
  `genrecode` varchar(30) NOT NULL DEFAULT '',
  `genrenamerus` varchar(100) NOT NULL DEFAULT '',
  `TotalCount` int(11) NOT NULL DEFAULT '0',
  `NormalCount` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`genreid`),
  UNIQUE KEY `genrecode` (`genrecode`),
  KEY `parentgenreid` (`parentgenreid`),
  KEY `TotalCount` (`TotalCount`),
  KEY `NormalCount` (`NormalCount`)
) ENGINE=MyISAM AUTO_INCREMENT=127 DEFAULT CHARSET=utf8;

/*Data for the table `mlgenrename` */

LOCK TABLES `mlgenrename` WRITE;

insert  into `mlgenrename`(`genreid`,`parentgenreid`,`genrecode`,`genrenamerus`,`TotalCount`,`NormalCount`) values (18,1,'sf_history','Альтернативная история',0,0),(19,1,'sf_action','Боевая фантастика',0,0),(20,1,'sf_epic','Эпическая фантастика',0,0),(21,1,'sf_heroic','Героическая фантастика',0,0),(22,1,'sf_detective','Детективная фантастика',0,0),(23,1,'sf_cyberpunk','Киберпанк',0,0),(24,1,'sf_space','Космическая фантастика',0,0),(25,1,'sf_social','Социальная фантастика',0,0),(26,1,'sf_horror','Ужасы',0,0),(27,1,'sf_humor','Юмористическая фантастика',0,0),(28,1,'sf_fantasy','Фэнтези',0,0),(29,1,'sf','Научная фантастика',0,0),(30,2,'det_classic','Классический детектив',0,0),(31,2,'det_police','Полицейский детектив',0,0),(32,2,'det_action','Боевик',0,0),(33,2,'det_irony','Иронический детектив',0,0),(34,2,'det_espionage','Шпионский детектив',0,0),(35,2,'det_crime','Криминальный детектив',0,0),(36,2,'det_political','Политический детектив',0,0),(37,2,'det_maniac','Маньяки',0,0),(38,2,'det_hard','Крутой детектив',0,0),(39,2,'thriller','Триллер',0,0),(40,2,'detective','Детективы: прочее',0,0),(41,3,'prose_classic','Классическая проза',0,0),(42,3,'prose_history','Историческая проза',0,0),(43,3,'prose_contemporary','Современная проза',0,0),(44,3,'prose_counter','Контркультура',0,0),(45,3,'prose_rus_classic','Русская классическая проза',0,0),(46,3,'prose_su_classics','Советская классическая проза',0,0),(47,4,'love_contemporary','Современные любовные романы',0,0),(48,4,'love_history','Исторические любовные романы',0,0),(49,2,'love_detective','Любовные детективы',0,0),(50,4,'love_short','Короткие любовные романы',0,0),(51,4,'love_erotica','Эротика',0,0),(52,5,'adv_western','Вестерн',0,0),(53,5,'adv_history','Исторические приключения',0,0),(54,5,'adv_indian','Приключения про индейцев',0,0),(55,5,'adv_maritime','Морские приключения',0,0),(56,5,'adv_geo','Путешествия и география',0,0),(57,5,'adv_animal','Природа и животные',0,0),(58,5,'adventure','Приключения: прочее',0,0),(59,6,'child_tale','Сказка',0,0),(60,6,'child_verse','Детские стихи',0,0),(61,6,'child_prose','Детская проза',0,0),(62,1,'child_sf','Детская фантастика',0,0),(63,2,'child_det','Детские остросюжетные',0,0),(64,5,'child_adv','Детские приключения',0,0),(65,6,'child_education','Образовательная литература',0,0),(66,6,'children','Детская литература: прочее',0,0),(67,7,'poetry','Поэзия: прочее',0,0),(68,16,'dramaturgy','Драматургия: прочее',0,0),(69,8,'antique_ant','Античная литература',0,0),(70,8,'antique_european','Древнеевропейская литература',0,0),(71,8,'antique_russian','Древнерусская литература',0,0),(72,8,'antique_east','Древневосточная литература',0,0),(73,8,'antique_myths','Мифы. Легенды. Эпос',0,0),(74,8,'antique','Старинная литература: прочее',0,0),(75,9,'sci_history','История',0,0),(76,9,'sci_psychology','Психология',0,0),(77,9,'sci_culture','Культурология',0,0),(78,9,'sci_religion','Религиоведение',0,0),(79,9,'sci_philosophy','Философия',0,0),(80,9,'sci_politics','Политика',0,0),(81,9,'sci_business','Деловая литература',0,0),(82,9,'sci_juris','Юриспруденция',0,0),(83,9,'sci_linguistic','Языкознание',0,0),(84,9,'sci_medicine','Медицина',0,0),(85,9,'sci_phys','Физика',0,0),(86,9,'sci_math','Математика',0,0),(87,9,'sci_chem','Химия',0,0),(88,9,'sci_biology','Биология',0,0),(89,9,'sci_tech','Технические науки',0,0),(90,9,'science','Научная литература: прочее',0,0),(91,10,'comp_www','Интернет',0,0),(92,10,'comp_programming','Программирование',0,0),(93,10,'comp_hard','Аппаратное обеспечение',0,0),(94,10,'comp_soft','Программы',0,0),(95,10,'comp_db','Базы данных',0,0),(96,10,'comp_osnet','ОС и Сети',0,0),(97,10,'computers','Околокомпьютерная литература',0,0),(98,11,'ref_encyc','Энциклопедии',0,0),(99,11,'ref_dict','Словари',0,0),(100,11,'ref_ref','Справочники',0,0),(101,11,'ref_guide','Руководства',0,0),(102,11,'reference','Справочная литература',0,0),(103,15,'nonf_biography','Биографии и Мемуары',0,0),(104,15,'nonf_publicism','Публицистика',0,0),(105,15,'nonf_criticism','Критика',0,0),(106,11,'design','Искусство и Дизайн',0,0),(107,15,'nonfiction','Документальная литература',0,0),(108,12,'religion_rel','Религия',0,0),(109,12,'religion_esoterics','Эзотерика',0,0),(110,12,'religion_self','Самосовершенствование',0,0),(111,12,'religion','Религиозная литература: прочее',0,0),(112,13,'humor_anecdote','Анекдоты',0,0),(113,13,'humor_prose','Юмористическая проза',0,0),(114,7,'humor_verse','Юмористические стихи',0,0),(115,13,'humor','Юмор: прочее',0,0),(116,14,'home_cooking','Кулинария',0,0),(117,14,'home_pets','Домашние животные',0,0),(118,14,'home_crafts','Хобби и ремесла',0,0),(119,14,'home_entertain','Развлечения',0,0),(120,14,'home_health','Здоровье',0,0),(121,14,'home_garden','Сад и огород',0,0),(122,14,'home_diy','Сделай сам',0,0),(123,14,'home_sport','Спорт',0,0),(124,14,'home_sex','Эротика, Секс',0,0),(125,14,'home','Домоводство',0,0),(1,NULL,'sf_all','Фантастика',0,0),(2,NULL,'det_all','Детективы и Триллеры',0,0),(3,NULL,'prose_all','Проза',0,0),(4,NULL,'love_all','Любовные романы',0,0),(5,NULL,'adv_all','Приключения',0,0),(6,NULL,'child_all','Детское',0,0),(7,NULL,'poetry_all','Поэзия',0,0),(8,NULL,'antique_all','Старинное',0,0),(9,NULL,'sci_all','Наука, Образование',0,0),(10,NULL,'comp_all','Компьютеры и Интернет',0,0),(11,NULL,'ref_all','Справочная литература',0,0),(12,NULL,'religion_all','Религия и духовность',0,0),(13,NULL,'humor_all','Юмор',0,0),(14,NULL,'home_all','Домоводство (Дом и семья)',0,0),(15,NULL,'nonf_all','Документальная литература',0,0),(16,NULL,'dramaturgy_all','Драматургия',0,0),(17,NULL,'other','Прочее',0,0),(126,17,'unidentified','Неопознанное',0,0);

UNLOCK TABLES;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
