-- MySQL dump 10.13  Distrib 8.4.7, for macos26.1 (arm64)
--
-- Host: us-analytics-rds.cometchat.io    Database: analytics_logs
-- ------------------------------------------------------
-- Server version	8.0.40

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: `analytics_logs`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `analytics_logs` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;

USE `analytics_logs`;

--
-- Table structure for table `call_sessions`
--

DROP TABLE IF EXISTS `call_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `call_sessions` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `session_id` varchar(255) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `audio_minutes` int DEFAULT '0',
  `video_minutes` int DEFAULT '0',
  `recorded_minutes` int DEFAULT '0',
  `streaming_minutes` int DEFAULT '0',
  `duration` varchar(100) DEFAULT '0',
  `participants_count` int DEFAULT NULL,
  KEY `app_id_session_id_start_time_end_time` (`app_id`,`session_id`,`start_time`,`end_time`),
  KEY `app_id` (`app_id`),
  KEY `app_id_duration` (`app_id`,`duration`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `concurrent_user_count`
--

DROP TABLE IF EXISTS `concurrent_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `concurrent_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `minute` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `app_id_2` (`app_id`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id_year_month_day_hour_minute` (`app_id`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_year_month_hour` (`app_id`,`year`,`month`,`hour`),
  KEY `app_id_uts_year_month_hour_minute` (`app_id`,`uts`,`year`,`month`,`hour`,`minute`),
  KEY `app_id_uts_year_month_day_hour_minute` (`app_id`,`uts`,`year`,`month`,`day`,`hour`,`minute`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `daily_unique_user_count`
--

DROP TABLE IF EXISTS `daily_unique_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `daily_unique_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `daily_user_count`
--

DROP TABLE IF EXISTS `daily_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `daily_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dau_count_logs`
--

DROP TABLE IF EXISTS `dau_count_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `dau_count_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_uts_year_month_day` (`app_id`,`uts`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dau_entries_logs`
--

DROP TABLE IF EXISTS `dau_entries_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `dau_entries_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_uts_year_month_day` (`app_id`,`uts`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hau_count_logs`
--

DROP TABLE IF EXISTS `hau_count_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hau_count_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`,`day`,`hour`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id_uts_year_month_day_hour` (`app_id`,`uts`,`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hau_entries_logs`
--

DROP TABLE IF EXISTS `hau_entries_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hau_entries_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`,`day`,`hour`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id_uts_year_month_day_hour` (`app_id`,`uts`,`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hourly_unique_user_count`
--

DROP TABLE IF EXISTS `hourly_unique_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hourly_unique_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hourly_user_count`
--

DROP TABLE IF EXISTS `hourly_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hourly_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `mau_count_logs`
--

DROP TABLE IF EXISTS `mau_count_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mau_count_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_uts_year_month` (`app_id`,`uts`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `mau_entries_logs`
--

DROP TABLE IF EXISTS `mau_entries_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mau_entries_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_uts_year_month` (`app_id`,`uts`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `monthly_unique_user_count`
--

DROP TABLE IF EXISTS `monthly_unique_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `monthly_unique_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_uts_year_month` (`app_id`,`uts`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `monthly_user_count`
--

DROP TABLE IF EXISTS `monthly_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `monthly_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_uts_year_month` (`app_id`,`uts`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `participants`
--

DROP TABLE IF EXISTS `participants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `participants` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `session_id` varchar(255) NOT NULL,
  `uid` varchar(255) NOT NULL,
  `device_id` varchar(255) NOT NULL,
  `audio_minutes` int DEFAULT '0',
  `video_minutes` int DEFAULT '0',
  `video_timestamps` json DEFAULT NULL,
  `audio_timestamps` json DEFAULT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `meta` json DEFAULT NULL,
  KEY `app_id_session_id_uid_device_id` (`app_id`(50),`session_id`(50),`uid`(50),`device_id`(50)),
  KEY `app_id` (`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ping_logs`
--

DROP TABLE IF EXISTS `ping_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ping_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `uid` varchar(50) NOT NULL,
  `auth_token` varchar(255) DEFAULT NULL,
  `resource` varchar(255) DEFAULT NULL,
  `v` smallint DEFAULT '1',
  `app_info` json DEFAULT NULL,
  `sid` varchar(255) DEFAULT NULL,
  `origin` varchar(255) DEFAULT NULL,
  `version` varchar(15) DEFAULT NULL,
  `platform` varchar(50) DEFAULT NULL,
  `os_version` varchar(50) DEFAULT NULL,
  `user_agent` varchar(50) DEFAULT NULL,
  `api_version` varchar(50) DEFAULT NULL,
  `build_number` varchar(50) DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `minute` smallint DEFAULT NULL,
  `language` varchar(50) DEFAULT NULL,
  `ws_id` varchar(255) DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`uid`,`app_id`,`ws_id`(50),`auth_token`(50),`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id` (`app_id`),
  KEY `uid` (`uid`),
  KEY `auth_token` (`auth_token`),
  KEY `resource` (`resource`),
  KEY `origin` (`origin`),
  KEY `platform` (`platform`),
  KEY `user_agent` (`user_agent`),
  KEY `api_version` (`api_version`),
  KEY `uts` (`uts`),
  KEY `version` (`version`),
  KEY `app_id_uid` (`app_id`,`uid`),
  KEY `app_id_api_version` (`app_id`,`api_version`),
  KEY `app_id_resource` (`app_id`,`resource`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `year_month_day_hour_minute` (`year`,`month`,`day`,`hour`,`minute`),
  KEY `uts_year_month_day_hour_minute` (`uts`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_uts_year_month_day_hour_minute` (`app_id`,`uts`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_uts_uid_year_month_day_hour_minute` (`app_id`,`uts`,`uid`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_uts_uid_auth_token_ws_id_year_month` (`app_id`(10),`uts`,`uid`(15),`auth_token`(10),`ws_id`(10),`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_year_month_day_hour_minute` (`app_id`,`year`,`month`,`day`,`hour`,`minute`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `recordings`
--

DROP TABLE IF EXISTS `recordings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `recordings` (
  `app_id` varchar(50) NOT NULL,
  `session_id` varchar(255) NOT NULL,
  `recording_id` varchar(255) NOT NULL,
  `call_start_time` bigint DEFAULT '0',
  `timestamp` bigint DEFAULT '0',
  `recording_created_at` varchar(255) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `meta` json DEFAULT NULL,
  PRIMARY KEY (`app_id`,`session_id`,`recording_id`),
  KEY `session_id` (`session_id`),
  KEY `recording_id` (`recording_id`),
  KEY `app_id` (`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `recordings_dump`
--

DROP TABLE IF EXISTS `recordings_dump`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `recordings_dump` (
  `dump` text,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `recordings_meta`
--

DROP TABLE IF EXISTS `recordings_meta`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `recordings_meta` (
  `app_id` varchar(50) NOT NULL,
  `recording_id` varchar(255) NOT NULL,
  `session_id` varchar(255) DEFAULT NULL,
  `participants` text,
  `duration` double DEFAULT '0',
  `filename` varchar(255) NOT NULL,
  `meeting_url` varchar(255) NOT NULL,
  `destination` varchar(255) NOT NULL,
  `region` varchar(50) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `timestamp` bigint DEFAULT '0',
  `recording_created_at` varchar(255) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `meta` json DEFAULT NULL,
  PRIMARY KEY (`app_id`,`recording_id`),
  KEY `recording_id` (`recording_id`),
  KEY `app_id` (`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_events_logs`
--

DROP TABLE IF EXISTS `user_events_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_events_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `sent` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `uid` varchar(50) NOT NULL,
  `auth_token` varchar(255) DEFAULT NULL,
  `resource` varchar(255) DEFAULT NULL,
  `event` varchar(100) DEFAULT NULL,
  `v` smallint DEFAULT '1',
  `app_info` text,
  `sid` varchar(255) DEFAULT NULL,
  `origin` varchar(255) DEFAULT NULL,
  `version` varchar(15) DEFAULT NULL,
  `api_version` varchar(50) DEFAULT NULL,
  `build_number` varchar(50) DEFAULT NULL,
  KEY `app_id` (`app_id`),
  KEY `uts` (`uts`),
  KEY `v` (`v`),
  KEY `sent` (`sent`),
  KEY `uid` (`uid`),
  KEY `auth_token` (`auth_token`),
  KEY `event` (`event`),
  KEY `global` (`app_id`,`uts`,`uid`,`event`),
  KEY `uts_event` (`uts`,`event`),
  KEY `uts_event_app_id` (`uts`,`event`,`app_id`),
  KEY `uts_event_app_id_guid` (`uts`,`event`,`app_id`),
  KEY `global1` (`app_id`,`uts`,`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_logs`
--

DROP TABLE IF EXISTS `user_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `uid` varchar(50) NOT NULL,
  `auth_token` varchar(255) DEFAULT NULL,
  `resource` varchar(255) DEFAULT NULL,
  `v` smallint DEFAULT '1',
  `app_info` json DEFAULT NULL,
  `sid` varchar(255) DEFAULT NULL,
  `origin` varchar(255) DEFAULT NULL,
  `version` varchar(15) DEFAULT NULL,
  `platform` varchar(50) DEFAULT NULL,
  `os_version` varchar(50) DEFAULT NULL,
  `user_agent` varchar(50) DEFAULT NULL,
  `api_version` varchar(50) DEFAULT NULL,
  `build_number` varchar(50) DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `language` varchar(50) DEFAULT NULL,
  `ws_id` varchar(255) DEFAULT NULL,
  UNIQUE KEY `app_id_2` (`uid`,`app_id`,`ws_id`(50),`auth_token`(50),`year`,`month`,`day`,`hour`),
  KEY `id` (`id`),
  KEY `app_id` (`app_id`),
  KEY `uid` (`uid`),
  KEY `auth_token` (`auth_token`),
  KEY `resource` (`resource`),
  KEY `origin` (`origin`),
  KEY `platform` (`platform`),
  KEY `user_agent` (`user_agent`),
  KEY `api_version` (`api_version`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `date` (`date`),
  KEY `app_id_uid` (`app_id`,`uid`),
  KEY `app_id_auth_token` (`app_id`,`auth_token`),
  KEY `app_id_api_version` (`app_id`,`api_version`),
  KEY `app_id_resource` (`app_id`,`resource`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uid_auth_token` (`app_id`,`uid`,`auth_token`),
  KEY `app_id_uid_resource` (`app_id`,`uid`,`resource`),
  KEY `app_id_resource_auth_token` (`app_id`,`resource`,`auth_token`),
  KEY `year_month_day_hour` (`year`,`month`,`day`,`hour`),
  KEY `uts_year_month_day_hour` (`uts`,`year`,`month`,`day`,`hour`),
  KEY `app_id_uts_year_month_day_hour` (`app_id`,`uts`,`year`,`month`,`day`,`hour`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `hau_index` (`app_id`,`auth_token`,`sent`,`year`,`month`,`day`),
  KEY `version` (`version`),
  KEY `app_id_uts_uid` (`app_id`,`uts`,`uid`),
  KEY `app_id_uts_uid_year_month` (`app_id`,`uts`,`uid`,`year`,`month`),
  KEY `app_id_uts_uid_auth_token_ws_id_year_month` (`app_id`(10),`uts`,`uid`(15),`auth_token`(10),`ws_id`(10),`year`,`month`),
  KEY `user_logs_idx_app_id_year_month_day` (`app_id`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Current Database: `analytics_logs`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `analytics_logs` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;

USE `analytics_logs`;

--
-- Table structure for table `call_sessions`
--

DROP TABLE IF EXISTS `call_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `call_sessions` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `session_id` varchar(255) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `audio_minutes` int DEFAULT '0',
  `video_minutes` int DEFAULT '0',
  `recorded_minutes` int DEFAULT '0',
  `streaming_minutes` int DEFAULT '0',
  `duration` varchar(100) DEFAULT '0',
  `participants_count` int DEFAULT NULL,
  KEY `app_id_session_id_start_time_end_time` (`app_id`,`session_id`,`start_time`,`end_time`),
  KEY `app_id` (`app_id`),
  KEY `app_id_duration` (`app_id`,`duration`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `concurrent_user_count`
--

DROP TABLE IF EXISTS `concurrent_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `concurrent_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `minute` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `app_id_2` (`app_id`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id_year_month_day_hour_minute` (`app_id`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_year_month_hour` (`app_id`,`year`,`month`,`hour`),
  KEY `app_id_uts_year_month_hour_minute` (`app_id`,`uts`,`year`,`month`,`hour`,`minute`),
  KEY `app_id_uts_year_month_day_hour_minute` (`app_id`,`uts`,`year`,`month`,`day`,`hour`,`minute`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `daily_unique_user_count`
--

DROP TABLE IF EXISTS `daily_unique_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `daily_unique_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `daily_user_count`
--

DROP TABLE IF EXISTS `daily_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `daily_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dau_count_logs`
--

DROP TABLE IF EXISTS `dau_count_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `dau_count_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_uts_year_month_day` (`app_id`,`uts`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dau_entries_logs`
--

DROP TABLE IF EXISTS `dau_entries_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `dau_entries_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_uts_year_month_day` (`app_id`,`uts`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hau_count_logs`
--

DROP TABLE IF EXISTS `hau_count_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hau_count_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`,`day`,`hour`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id_uts_year_month_day_hour` (`app_id`,`uts`,`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hau_entries_logs`
--

DROP TABLE IF EXISTS `hau_entries_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hau_entries_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`,`day`,`hour`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id_uts_year_month_day_hour` (`app_id`,`uts`,`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hourly_unique_user_count`
--

DROP TABLE IF EXISTS `hourly_unique_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hourly_unique_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hourly_user_count`
--

DROP TABLE IF EXISTS `hourly_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hourly_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `year_month_hour` (`year`,`month`,`hour`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `mau_count_logs`
--

DROP TABLE IF EXISTS `mau_count_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mau_count_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_uts_year_month` (`app_id`,`uts`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `mau_entries_logs`
--

DROP TABLE IF EXISTS `mau_entries_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mau_entries_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uid` varchar(140) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`uid`,`year`,`month`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_uts_year_month` (`app_id`,`uts`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `monthly_unique_user_count`
--

DROP TABLE IF EXISTS `monthly_unique_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `monthly_unique_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_uts_year_month` (`app_id`,`uts`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `monthly_user_count`
--

DROP TABLE IF EXISTS `monthly_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `monthly_user_count` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `users_count` bigint DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`app_id`,`year`,`month`),
  KEY `app_id` (`app_id`),
  KEY `date` (`date`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `year` (`year`),
  KEY `users_count` (`users_count`),
  KEY `year_month` (`year`,`month`),
  KEY `app_id_year` (`app_id`,`year`),
  KEY `app_id_month` (`app_id`,`month`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`),
  KEY `app_id_uts_year_month` (`app_id`,`uts`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `participants`
--

DROP TABLE IF EXISTS `participants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `participants` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `session_id` varchar(255) NOT NULL,
  `uid` varchar(255) NOT NULL,
  `device_id` varchar(255) NOT NULL,
  `audio_minutes` int DEFAULT '0',
  `video_minutes` int DEFAULT '0',
  `video_timestamps` json DEFAULT NULL,
  `audio_timestamps` json DEFAULT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `meta` json DEFAULT NULL,
  KEY `app_id_session_id_uid_device_id` (`app_id`(50),`session_id`(50),`uid`(50),`device_id`(50)),
  KEY `app_id` (`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ping_logs`
--

DROP TABLE IF EXISTS `ping_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ping_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `uid` varchar(50) NOT NULL,
  `auth_token` varchar(255) DEFAULT NULL,
  `resource` varchar(255) DEFAULT NULL,
  `v` smallint DEFAULT '1',
  `app_info` json DEFAULT NULL,
  `sid` varchar(255) DEFAULT NULL,
  `origin` varchar(255) DEFAULT NULL,
  `version` varchar(15) DEFAULT NULL,
  `platform` varchar(50) DEFAULT NULL,
  `os_version` varchar(50) DEFAULT NULL,
  `user_agent` varchar(50) DEFAULT NULL,
  `api_version` varchar(50) DEFAULT NULL,
  `build_number` varchar(50) DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `minute` smallint DEFAULT NULL,
  `language` varchar(50) DEFAULT NULL,
  `ws_id` varchar(255) DEFAULT NULL,
  UNIQUE KEY `sudo_prime` (`uid`,`app_id`,`ws_id`(50),`auth_token`(50),`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id` (`app_id`),
  KEY `uid` (`uid`),
  KEY `auth_token` (`auth_token`),
  KEY `resource` (`resource`),
  KEY `origin` (`origin`),
  KEY `platform` (`platform`),
  KEY `user_agent` (`user_agent`),
  KEY `api_version` (`api_version`),
  KEY `uts` (`uts`),
  KEY `version` (`version`),
  KEY `app_id_uid` (`app_id`,`uid`),
  KEY `app_id_api_version` (`app_id`,`api_version`),
  KEY `app_id_resource` (`app_id`,`resource`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `year_month_day_hour_minute` (`year`,`month`,`day`,`hour`,`minute`),
  KEY `uts_year_month_day_hour_minute` (`uts`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_uts_year_month_day_hour_minute` (`app_id`,`uts`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `app_id_uts_uid_year_month_day_hour_minute` (`app_id`,`uts`,`uid`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_uts_uid_auth_token_ws_id_year_month` (`app_id`(10),`uts`,`uid`(15),`auth_token`(10),`ws_id`(10),`year`,`month`,`day`,`hour`,`minute`),
  KEY `app_id_year_month_day_hour_minute` (`app_id`,`year`,`month`,`day`,`hour`,`minute`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `recordings`
--

DROP TABLE IF EXISTS `recordings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `recordings` (
  `app_id` varchar(50) NOT NULL,
  `session_id` varchar(255) NOT NULL,
  `recording_id` varchar(255) NOT NULL,
  `call_start_time` bigint DEFAULT '0',
  `timestamp` bigint DEFAULT '0',
  `recording_created_at` varchar(255) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `meta` json DEFAULT NULL,
  PRIMARY KEY (`app_id`,`session_id`,`recording_id`),
  KEY `session_id` (`session_id`),
  KEY `recording_id` (`recording_id`),
  KEY `app_id` (`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `recordings_dump`
--

DROP TABLE IF EXISTS `recordings_dump`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `recordings_dump` (
  `dump` text,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `recordings_meta`
--

DROP TABLE IF EXISTS `recordings_meta`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `recordings_meta` (
  `app_id` varchar(50) NOT NULL,
  `recording_id` varchar(255) NOT NULL,
  `session_id` varchar(255) DEFAULT NULL,
  `participants` text,
  `duration` double DEFAULT '0',
  `filename` varchar(255) NOT NULL,
  `meeting_url` varchar(255) NOT NULL,
  `destination` varchar(255) NOT NULL,
  `region` varchar(50) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `timestamp` bigint DEFAULT '0',
  `recording_created_at` varchar(255) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `meta` json DEFAULT NULL,
  PRIMARY KEY (`app_id`,`recording_id`),
  KEY `recording_id` (`recording_id`),
  KEY `app_id` (`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_events_logs`
--

DROP TABLE IF EXISTS `user_events_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_events_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `sent` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `uid` varchar(50) NOT NULL,
  `auth_token` varchar(255) DEFAULT NULL,
  `resource` varchar(255) DEFAULT NULL,
  `event` varchar(100) DEFAULT NULL,
  `v` smallint DEFAULT '1',
  `app_info` text,
  `sid` varchar(255) DEFAULT NULL,
  `origin` varchar(255) DEFAULT NULL,
  `version` varchar(15) DEFAULT NULL,
  `api_version` varchar(50) DEFAULT NULL,
  `build_number` varchar(50) DEFAULT NULL,
  KEY `app_id` (`app_id`),
  KEY `uts` (`uts`),
  KEY `v` (`v`),
  KEY `sent` (`sent`),
  KEY `uid` (`uid`),
  KEY `auth_token` (`auth_token`),
  KEY `event` (`event`),
  KEY `global` (`app_id`,`uts`,`uid`,`event`),
  KEY `uts_event` (`uts`,`event`),
  KEY `uts_event_app_id` (`uts`,`event`,`app_id`),
  KEY `uts_event_app_id_guid` (`uts`,`event`,`app_id`),
  KEY `global1` (`app_id`,`uts`,`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_logs`
--

DROP TABLE IF EXISTS `user_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_logs` (
  `id` varchar(255) NOT NULL,
  `app_id` varchar(255) NOT NULL,
  `uts` bigint DEFAULT NULL,
  `sent` bigint DEFAULT NULL,
  `uid` varchar(50) NOT NULL,
  `auth_token` varchar(255) DEFAULT NULL,
  `resource` varchar(255) DEFAULT NULL,
  `v` smallint DEFAULT '1',
  `app_info` json DEFAULT NULL,
  `sid` varchar(255) DEFAULT NULL,
  `origin` varchar(255) DEFAULT NULL,
  `version` varchar(15) DEFAULT NULL,
  `platform` varchar(50) DEFAULT NULL,
  `os_version` varchar(50) DEFAULT NULL,
  `user_agent` varchar(50) DEFAULT NULL,
  `api_version` varchar(50) DEFAULT NULL,
  `build_number` varchar(50) DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `year` smallint DEFAULT NULL,
  `month` smallint DEFAULT NULL,
  `day` smallint DEFAULT NULL,
  `hour` smallint DEFAULT NULL,
  `language` varchar(50) DEFAULT NULL,
  `ws_id` varchar(255) DEFAULT NULL,
  UNIQUE KEY `app_id_2` (`uid`,`app_id`,`ws_id`(50),`auth_token`(50),`year`,`month`,`day`,`hour`),
  KEY `id` (`id`),
  KEY `app_id` (`app_id`),
  KEY `uid` (`uid`),
  KEY `auth_token` (`auth_token`),
  KEY `resource` (`resource`),
  KEY `origin` (`origin`),
  KEY `platform` (`platform`),
  KEY `user_agent` (`user_agent`),
  KEY `api_version` (`api_version`),
  KEY `sent` (`sent`),
  KEY `uts` (`uts`),
  KEY `date` (`date`),
  KEY `app_id_uid` (`app_id`,`uid`),
  KEY `app_id_auth_token` (`app_id`,`auth_token`),
  KEY `app_id_api_version` (`app_id`,`api_version`),
  KEY `app_id_resource` (`app_id`,`resource`),
  KEY `app_id_date` (`app_id`,`date`),
  KEY `app_id_sent` (`app_id`,`sent`),
  KEY `app_id_uid_auth_token` (`app_id`,`uid`,`auth_token`),
  KEY `app_id_uid_resource` (`app_id`,`uid`,`resource`),
  KEY `app_id_resource_auth_token` (`app_id`,`resource`,`auth_token`),
  KEY `year_month_day_hour` (`year`,`month`,`day`,`hour`),
  KEY `uts_year_month_day_hour` (`uts`,`year`,`month`,`day`,`hour`),
  KEY `app_id_uts_year_month_day_hour` (`app_id`,`uts`,`year`,`month`,`day`,`hour`),
  KEY `app_id_uts` (`app_id`,`uts`),
  KEY `hau_index` (`app_id`,`auth_token`,`sent`,`year`,`month`,`day`),
  KEY `version` (`version`),
  KEY `app_id_uts_uid` (`app_id`,`uts`,`uid`),
  KEY `app_id_uts_uid_year_month` (`app_id`,`uts`,`uid`,`year`,`month`),
  KEY `app_id_uts_uid_auth_token_ws_id_year_month` (`app_id`(10),`uts`,`uid`(15),`auth_token`(10),`ws_id`(10),`year`,`month`),
  KEY `user_logs_idx_app_id_year_month_day` (`app_id`,`year`,`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-06-21 18:24:27
