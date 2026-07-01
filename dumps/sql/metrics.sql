-- MySQL dump 10.13  Distrib 8.4.7, for macos26.1 (arm64)
--
-- Host: us-pro-metrics-db.cometchat.io    Database: metrics
-- ------------------------------------------------------
-- Server version	8.0.42

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
-- Current Database: `metrics`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `metrics` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;

USE `metrics`;

--
-- Table structure for table `app_billing`
--

DROP TABLE IF EXISTS `app_billing`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `app_billing` (
  `appid` varchar(50) NOT NULL DEFAULT 'NOT NULL',
  `is_mcu_billing` enum('0','1') NOT NULL DEFAULT '0',
  `is_dcu_billing` enum('0','1') NOT NULL DEFAULT '0',
  UNIQUE KEY `appid_UNIQUE` (`appid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billing_data`
--

DROP TABLE IF EXISTS `billing_data`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `billing_data` (
  `app_id` varchar(45) NOT NULL,
  `request_hash` varchar(255) NOT NULL,
  `start_ts` bigint NOT NULL,
  `end_ts` bigint NOT NULL,
  `mau` int DEFAULT NULL,
  `pcc` int DEFAULT NULL,
  `dcu` int DEFAULT NULL,
  `mcu` int DEFAULT NULL,
  `voice` int DEFAULT NULL,
  `voice_without_single_participant` int DEFAULT NULL,
  `video` int DEFAULT NULL,
  `video_without_single_participant` int DEFAULT NULL,
  `recording` int DEFAULT NULL,
  `recording_without_single_participant` int DEFAULT NULL,
  `updated_at` bigint DEFAULT NULL,
  `process_completed` tinyint NOT NULL DEFAULT '0',
  `total_time` int DEFAULT '0',
  `number_of_child_apps` int NOT NULL DEFAULT '0',
  UNIQUE KEY `unique_billing_record` (`app_id`,`start_ts`,`end_ts`),
  KEY `app_id_idx` (`app_id`,`start_ts`,`end_ts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `call_sessions`
--

DROP TABLE IF EXISTS `call_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `call_sessions` (
  `app_id` varchar(50) NOT NULL,
  `session_id` varchar(100) NOT NULL,
  `meeting_id` varchar(75) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `audio_minutes` int NOT NULL DEFAULT '0',
  `video_minutes` int NOT NULL DEFAULT '0',
  `recorded_minutes` int NOT NULL DEFAULT '0',
  `duration` varchar(50) DEFAULT '0',
  `participants_count` int NOT NULL,
  `audio_seconds` int NOT NULL DEFAULT '0',
  `video_seconds` int NOT NULL DEFAULT '0',
  `recorded_seconds` int NOT NULL DEFAULT '0',
  `total_duration_seconds` int NOT NULL DEFAULT '0',
  UNIQUE KEY `unique_calls` (`app_id`,`session_id`,`meeting_id`,`start_time`,`end_time`),
  KEY `app_id_session_id_start_time_end_time_meeting_id` (`app_id`,`session_id`,`start_time`,`end_time`,`meeting_id`),
  KEY `meeting_id` (`meeting_id`),
  KEY `start_time` (`start_time`,`app_id`,`session_id`,`meeting_id`),
  KEY `meeting_id_app_id` (`meeting_id`,`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ccu`
--

DROP TABLE IF EXISTS `ccu`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ccu` (
  `app_id` varchar(100) DEFAULT NULL,
  `uts` bigint DEFAULT NULL,
  `year` smallint unsigned DEFAULT NULL,
  `month` smallint unsigned DEFAULT NULL,
  `day` smallint unsigned DEFAULT NULL,
  `hour` smallint unsigned DEFAULT NULL,
  `minute` smallint unsigned DEFAULT NULL,
  `users` json NOT NULL,
  UNIQUE KEY `app_id_key` (`app_id`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `appid_uts` (`app_id`,`uts`),
  KEY `uts` (`uts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ccu_uids`
--

DROP TABLE IF EXISTS `ccu_uids`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ccu_uids` (
  `app_id` varchar(100) DEFAULT NULL,
  `uts` bigint DEFAULT NULL,
  `year` smallint unsigned DEFAULT NULL,
  `month` smallint unsigned DEFAULT NULL,
  `day` smallint unsigned DEFAULT NULL,
  `hour` smallint unsigned DEFAULT NULL,
  `minute` smallint unsigned DEFAULT NULL,
  `uids` json NOT NULL,
  UNIQUE KEY `app_id_key` (`app_id`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `appid_uts` (`app_id`,`uts`),
  KEY `uts` (`uts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `concurrent_user_count`
--

DROP TABLE IF EXISTS `concurrent_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `concurrent_user_count` (
  `id` varchar(255) DEFAULT NULL,
  `app_id` varchar(255) DEFAULT NULL,
  `uts` bigint NOT NULL DEFAULT '0',
  `year` smallint unsigned DEFAULT NULL,
  `month` smallint unsigned DEFAULT NULL,
  `day` smallint unsigned DEFAULT NULL,
  `hour` smallint unsigned DEFAULT NULL,
  `peak_concurrent_users` int unsigned DEFAULT NULL,
  `peak_minute_marker` int DEFAULT NULL,
  `hourly_data` json NOT NULL,
  UNIQUE KEY `app_id_key` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `idx_app_id_uts` (`app_id`,`uts`),
  KEY `idx_uts` (`uts`),
  KEY `year_month_day_hour` (`year`,`month`,`day`,`hour`,`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `daily_user_count`
--

DROP TABLE IF EXISTS `daily_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `daily_user_count` (
  `app_id` varchar(255) NOT NULL,
  `uts` bigint NOT NULL,
  `year` smallint NOT NULL,
  `month` smallint NOT NULL,
  `day` smallint NOT NULL,
  `uid` varchar(100) DEFAULT NULL,
  UNIQUE KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`,`uid`),
  KEY `app_id` (`app_id`),
  KEY `uts` (`uts`),
  KEY `year_month_day` (`year`,`month`,`day`),
  KEY `appid_uts` (`app_id`,`uts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `group_users`
--

DROP TABLE IF EXISTS `group_users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `group_users` (
  `appid` varchar(50) NOT NULL,
  `guid` varchar(100) NOT NULL,
  `uid` varchar(100) NOT NULL,
  UNIQUE KEY `appid_guid_uid` (`appid`,`guid`,`uid`),
  KEY `appid_guid` (`appid`,`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hourly_user_count`
--

DROP TABLE IF EXISTS `hourly_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hourly_user_count` (
  `app_id` varchar(255) NOT NULL,
  `uts` bigint NOT NULL,
  `year` smallint NOT NULL,
  `month` smallint NOT NULL,
  `day` smallint NOT NULL,
  `hour` smallint NOT NULL,
  `users_count` bigint DEFAULT '0',
  KEY `app_id` (`app_id`),
  KEY `uts` (`uts`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `year_month_day_hour` (`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `messages`
--

DROP TABLE IF EXISTS `messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `messages` (
  `app_id` varchar(45) NOT NULL,
  `message_id` bigint unsigned NOT NULL,
  `uid` varchar(100) NOT NULL,
  `sent_at` int unsigned NOT NULL,
  `year` int unsigned NOT NULL,
  `month` int unsigned NOT NULL,
  `day` int unsigned NOT NULL,
  `category` varchar(45) DEFAULT NULL,
  UNIQUE KEY `app_id_uid_year_month_day` (`app_id`,`uid`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `app_id_sent_at` (`app_id`,`sent_at`,`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `monthly_user_count`
--

DROP TABLE IF EXISTS `monthly_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `monthly_user_count` (
  `app_id` varchar(255) NOT NULL,
  `uts` bigint NOT NULL,
  `year` smallint NOT NULL,
  `month` smallint NOT NULL,
  `users_count` bigint DEFAULT '0',
  UNIQUE KEY `appid_uts` (`app_id`,`uts`),
  KEY `app_id` (`app_id`),
  KEY `uts` (`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `non_jwt_sessions`
--

DROP TABLE IF EXISTS `non_jwt_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `non_jwt_sessions` (
  `app_id` varchar(50) DEFAULT NULL,
  `meeting_id` varchar(100) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `participants_count` int NOT NULL,
  `audio_minutes` int NOT NULL DEFAULT '0',
  `video_minutes` int NOT NULL DEFAULT '0',
  `is_non_jwt_call` smallint NOT NULL DEFAULT '0',
  KEY `start_time_end_time_meeting_id` (`start_time`,`end_time`,`meeting_id`),
  KEY `meeting_id` (`meeting_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `old_data`
--

DROP TABLE IF EXISTS `old_data`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `old_data` (
  `app_id` varchar(45) NOT NULL,
  `event_ts` int unsigned NOT NULL,
  `actual_ts` int unsigned NOT NULL,
  `object` json DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `participants`
--

DROP TABLE IF EXISTS `participants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `participants` (
  `app_id` varchar(50) NOT NULL,
  `session_id` varchar(100) NOT NULL,
  `meeting_id` varchar(75) NOT NULL,
  `uid` varchar(50) NOT NULL,
  `audio_minutes` int NOT NULL DEFAULT '0',
  `video_minutes` int NOT NULL DEFAULT '0',
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `audio_seconds` int NOT NULL DEFAULT '0',
  `video_seconds` int NOT NULL DEFAULT '0',
  `total_duration_seconds` int NOT NULL DEFAULT '0',
  UNIQUE KEY `unique_participants` (`app_id`,`session_id`,`meeting_id`,`start_time`,`end_time`,`uid`),
  KEY `app_id_session_id_uid_meeting_id` (`app_id`,`session_id`,`uid`,`meeting_id`),
  KEY `meeting_id` (`meeting_id`),
  KEY `start_time` (`start_time`,`app_id`,`session_id`,`meeting_id`),
  KEY `meeting_id_app_id` (`meeting_id`,`app_id`)
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
  `session_id` varchar(100) NOT NULL,
  `meeting_id` varchar(100) NOT NULL,
  `recording_id` varchar(100) NOT NULL,
  `duration_in_seconds` float NOT NULL,
  `call_start_time` bigint DEFAULT '0',
  `recording_created_at` varchar(100) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_recording` (`app_id`,`session_id`,`meeting_id`,`recording_id`),
  KEY `meeting_id` (`meeting_id`),
  KEY `app_meeting_recording` (`app_id`,`meeting_id`,`recording_id`)
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
  `recording_id` varchar(100) NOT NULL,
  `session_id` varchar(100) NOT NULL,
  `meeting_id` varchar(100) NOT NULL,
  `participants` text,
  `duration_in_seconds` double DEFAULT '0',
  `filename` varchar(500) NOT NULL,
  `meeting_url` varchar(500) NOT NULL,
  `destination` varchar(500) NOT NULL,
  `region` varchar(50) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `recording_created_at` varchar(100) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_recording` (`app_id`,`session_id`,`meeting_id`,`recording_id`),
  KEY `meeting_id` (`meeting_id`),
  KEY `app_meeting_recording` (`app_id`,`meeting_id`,`recording_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `search_metrics`
--

DROP TABLE IF EXISTS `search_metrics`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `search_metrics` (
  `app_id` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `message_id` bigint NOT NULL,
  `uts` bigint unsigned NOT NULL,
  `event` varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `event_action` varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `time_taken_millis` bigint DEFAULT '0',
  `rows_scanned` bigint DEFAULT '0',
  UNIQUE KEY `unique_idx` (`app_id`,`message_id`,`uts`,`event`,`event_action`),
  KEY `app_uts` (`app_id`,`uts`),
  KEY `uts_app` (`uts`,`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `status_table`
--

DROP TABLE IF EXISTS `status_table`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `status_table` (
  `process_name` varchar(50) NOT NULL,
  `last_run_time_end` bigint NOT NULL DEFAULT '0',
  UNIQUE KEY `process_name` (`process_name`)
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
  `app_id` varchar(50) NOT NULL,
  `uts` bigint unsigned DEFAULT NULL,
  `uid` varchar(100) NOT NULL COMMENT '\n\n',
  `resource` varchar(255) DEFAULT NULL,
  `v` smallint unsigned DEFAULT '1',
  `app_info` json DEFAULT NULL,
  `sid` varchar(255) DEFAULT NULL,
  `origin` varchar(255) DEFAULT NULL,
  `version` varchar(50) DEFAULT NULL,
  `platform` varchar(50) DEFAULT NULL,
  `os_version` varchar(50) DEFAULT NULL,
  `user_agent` varchar(50) DEFAULT NULL,
  `ws_id` varchar(255) DEFAULT NULL,
  `api_version` varchar(50) DEFAULT NULL,
  `build_number` varchar(50) DEFAULT NULL,
  `language` varchar(50) DEFAULT NULL,
  `year` smallint unsigned DEFAULT NULL,
  `month` smallint unsigned DEFAULT NULL,
  `day` smallint unsigned DEFAULT NULL,
  `hour` smallint unsigned DEFAULT NULL,
  UNIQUE KEY `app_id` (`app_id`,`uid`,`ws_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id_2` (`app_id`,`uid`,`year`,`month`,`day`,`hour`),
  KEY `app_id_3` (`app_id`,`uts`),
  KEY `year_month_day_hour` (`year`,`month`,`day`,`hour`),
  KEY `appid_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `uts` (`uts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Current Database: `metrics`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `metrics` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;

USE `metrics`;

--
-- Table structure for table `app_billing`
--

DROP TABLE IF EXISTS `app_billing`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `app_billing` (
  `appid` varchar(50) NOT NULL DEFAULT 'NOT NULL',
  `is_mcu_billing` enum('0','1') NOT NULL DEFAULT '0',
  `is_dcu_billing` enum('0','1') NOT NULL DEFAULT '0',
  UNIQUE KEY `appid_UNIQUE` (`appid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billing_data`
--

DROP TABLE IF EXISTS `billing_data`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `billing_data` (
  `app_id` varchar(45) NOT NULL,
  `request_hash` varchar(255) NOT NULL,
  `start_ts` bigint NOT NULL,
  `end_ts` bigint NOT NULL,
  `mau` int DEFAULT NULL,
  `pcc` int DEFAULT NULL,
  `dcu` int DEFAULT NULL,
  `mcu` int DEFAULT NULL,
  `voice` int DEFAULT NULL,
  `voice_without_single_participant` int DEFAULT NULL,
  `video` int DEFAULT NULL,
  `video_without_single_participant` int DEFAULT NULL,
  `recording` int DEFAULT NULL,
  `recording_without_single_participant` int DEFAULT NULL,
  `updated_at` bigint DEFAULT NULL,
  `process_completed` tinyint NOT NULL DEFAULT '0',
  `total_time` int DEFAULT '0',
  `number_of_child_apps` int NOT NULL DEFAULT '0',
  UNIQUE KEY `unique_billing_record` (`app_id`,`start_ts`,`end_ts`),
  KEY `app_id_idx` (`app_id`,`start_ts`,`end_ts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `call_sessions`
--

DROP TABLE IF EXISTS `call_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `call_sessions` (
  `app_id` varchar(50) NOT NULL,
  `session_id` varchar(100) NOT NULL,
  `meeting_id` varchar(75) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `audio_minutes` int NOT NULL DEFAULT '0',
  `video_minutes` int NOT NULL DEFAULT '0',
  `recorded_minutes` int NOT NULL DEFAULT '0',
  `duration` varchar(50) DEFAULT '0',
  `participants_count` int NOT NULL,
  `audio_seconds` int NOT NULL DEFAULT '0',
  `video_seconds` int NOT NULL DEFAULT '0',
  `recorded_seconds` int NOT NULL DEFAULT '0',
  `total_duration_seconds` int NOT NULL DEFAULT '0',
  UNIQUE KEY `unique_calls` (`app_id`,`session_id`,`meeting_id`,`start_time`,`end_time`),
  KEY `app_id_session_id_start_time_end_time_meeting_id` (`app_id`,`session_id`,`start_time`,`end_time`,`meeting_id`),
  KEY `meeting_id` (`meeting_id`),
  KEY `start_time` (`start_time`,`app_id`,`session_id`,`meeting_id`),
  KEY `meeting_id_app_id` (`meeting_id`,`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ccu`
--

DROP TABLE IF EXISTS `ccu`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ccu` (
  `app_id` varchar(100) DEFAULT NULL,
  `uts` bigint DEFAULT NULL,
  `year` smallint unsigned DEFAULT NULL,
  `month` smallint unsigned DEFAULT NULL,
  `day` smallint unsigned DEFAULT NULL,
  `hour` smallint unsigned DEFAULT NULL,
  `minute` smallint unsigned DEFAULT NULL,
  `users` json NOT NULL,
  UNIQUE KEY `app_id_key` (`app_id`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `appid_uts` (`app_id`,`uts`),
  KEY `uts` (`uts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ccu_uids`
--

DROP TABLE IF EXISTS `ccu_uids`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ccu_uids` (
  `app_id` varchar(100) DEFAULT NULL,
  `uts` bigint DEFAULT NULL,
  `year` smallint unsigned DEFAULT NULL,
  `month` smallint unsigned DEFAULT NULL,
  `day` smallint unsigned DEFAULT NULL,
  `hour` smallint unsigned DEFAULT NULL,
  `minute` smallint unsigned DEFAULT NULL,
  `uids` json NOT NULL,
  UNIQUE KEY `app_id_key` (`app_id`,`year`,`month`,`day`,`hour`,`minute`),
  KEY `appid_uts` (`app_id`,`uts`),
  KEY `uts` (`uts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `concurrent_user_count`
--

DROP TABLE IF EXISTS `concurrent_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `concurrent_user_count` (
  `id` varchar(255) DEFAULT NULL,
  `app_id` varchar(255) DEFAULT NULL,
  `uts` bigint NOT NULL DEFAULT '0',
  `year` smallint unsigned DEFAULT NULL,
  `month` smallint unsigned DEFAULT NULL,
  `day` smallint unsigned DEFAULT NULL,
  `hour` smallint unsigned DEFAULT NULL,
  `peak_concurrent_users` int unsigned DEFAULT NULL,
  `peak_minute_marker` int DEFAULT NULL,
  `hourly_data` json NOT NULL,
  UNIQUE KEY `app_id_key` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `idx_app_id_uts` (`app_id`,`uts`),
  KEY `idx_uts` (`uts`),
  KEY `year_month_day_hour` (`year`,`month`,`day`,`hour`,`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `daily_user_count`
--

DROP TABLE IF EXISTS `daily_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `daily_user_count` (
  `app_id` varchar(255) NOT NULL,
  `uts` bigint NOT NULL,
  `year` smallint NOT NULL,
  `month` smallint NOT NULL,
  `day` smallint NOT NULL,
  `uid` varchar(100) DEFAULT NULL,
  UNIQUE KEY `app_id_year_month_day` (`app_id`,`year`,`month`,`day`,`uid`),
  KEY `app_id` (`app_id`),
  KEY `uts` (`uts`),
  KEY `year_month_day` (`year`,`month`,`day`),
  KEY `appid_uts` (`app_id`,`uts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `group_users`
--

DROP TABLE IF EXISTS `group_users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `group_users` (
  `appid` varchar(50) NOT NULL,
  `guid` varchar(100) NOT NULL,
  `uid` varchar(100) NOT NULL,
  UNIQUE KEY `appid_guid_uid` (`appid`,`guid`,`uid`),
  KEY `appid_guid` (`appid`,`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hourly_user_count`
--

DROP TABLE IF EXISTS `hourly_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hourly_user_count` (
  `app_id` varchar(255) NOT NULL,
  `uts` bigint NOT NULL,
  `year` smallint NOT NULL,
  `month` smallint NOT NULL,
  `day` smallint NOT NULL,
  `hour` smallint NOT NULL,
  `users_count` bigint DEFAULT '0',
  KEY `app_id` (`app_id`),
  KEY `uts` (`uts`),
  KEY `app_id_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `year_month_day_hour` (`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `messages`
--

DROP TABLE IF EXISTS `messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `messages` (
  `app_id` varchar(45) NOT NULL,
  `message_id` bigint unsigned NOT NULL,
  `uid` varchar(100) NOT NULL,
  `sent_at` int unsigned NOT NULL,
  `year` int unsigned NOT NULL,
  `month` int unsigned NOT NULL,
  `day` int unsigned NOT NULL,
  `category` varchar(45) DEFAULT NULL,
  UNIQUE KEY `app_id_uid_year_month_day` (`app_id`,`uid`,`year`,`month`,`day`),
  KEY `app_id` (`app_id`),
  KEY `app_id_sent_at` (`app_id`,`sent_at`,`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `monthly_user_count`
--

DROP TABLE IF EXISTS `monthly_user_count`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `monthly_user_count` (
  `app_id` varchar(255) NOT NULL,
  `uts` bigint NOT NULL,
  `year` smallint NOT NULL,
  `month` smallint NOT NULL,
  `users_count` bigint DEFAULT '0',
  UNIQUE KEY `appid_uts` (`app_id`,`uts`),
  KEY `app_id` (`app_id`),
  KEY `uts` (`uts`),
  KEY `app_id_year_month` (`app_id`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `non_jwt_sessions`
--

DROP TABLE IF EXISTS `non_jwt_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `non_jwt_sessions` (
  `app_id` varchar(50) DEFAULT NULL,
  `meeting_id` varchar(100) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `participants_count` int NOT NULL,
  `audio_minutes` int NOT NULL DEFAULT '0',
  `video_minutes` int NOT NULL DEFAULT '0',
  `is_non_jwt_call` smallint NOT NULL DEFAULT '0',
  KEY `start_time_end_time_meeting_id` (`start_time`,`end_time`,`meeting_id`),
  KEY `meeting_id` (`meeting_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `old_data`
--

DROP TABLE IF EXISTS `old_data`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `old_data` (
  `app_id` varchar(45) NOT NULL,
  `event_ts` int unsigned NOT NULL,
  `actual_ts` int unsigned NOT NULL,
  `object` json DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `participants`
--

DROP TABLE IF EXISTS `participants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `participants` (
  `app_id` varchar(50) NOT NULL,
  `session_id` varchar(100) NOT NULL,
  `meeting_id` varchar(75) NOT NULL,
  `uid` varchar(50) NOT NULL,
  `audio_minutes` int NOT NULL DEFAULT '0',
  `video_minutes` int NOT NULL DEFAULT '0',
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `audio_seconds` int NOT NULL DEFAULT '0',
  `video_seconds` int NOT NULL DEFAULT '0',
  `total_duration_seconds` int NOT NULL DEFAULT '0',
  UNIQUE KEY `unique_participants` (`app_id`,`session_id`,`meeting_id`,`start_time`,`end_time`,`uid`),
  KEY `app_id_session_id_uid_meeting_id` (`app_id`,`session_id`,`uid`,`meeting_id`),
  KEY `meeting_id` (`meeting_id`),
  KEY `start_time` (`start_time`,`app_id`,`session_id`,`meeting_id`),
  KEY `meeting_id_app_id` (`meeting_id`,`app_id`)
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
  `session_id` varchar(100) NOT NULL,
  `meeting_id` varchar(100) NOT NULL,
  `recording_id` varchar(100) NOT NULL,
  `duration_in_seconds` float NOT NULL,
  `call_start_time` bigint DEFAULT '0',
  `recording_created_at` varchar(100) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_recording` (`app_id`,`session_id`,`meeting_id`,`recording_id`),
  KEY `meeting_id` (`meeting_id`),
  KEY `app_meeting_recording` (`app_id`,`meeting_id`,`recording_id`)
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
  `recording_id` varchar(100) NOT NULL,
  `session_id` varchar(100) NOT NULL,
  `meeting_id` varchar(100) NOT NULL,
  `participants` text,
  `duration_in_seconds` double DEFAULT '0',
  `filename` varchar(500) NOT NULL,
  `meeting_url` varchar(500) NOT NULL,
  `destination` varchar(500) NOT NULL,
  `region` varchar(50) NOT NULL,
  `start_time` bigint DEFAULT '0',
  `end_time` bigint DEFAULT '0',
  `recording_created_at` varchar(100) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_recording` (`app_id`,`session_id`,`meeting_id`,`recording_id`),
  KEY `meeting_id` (`meeting_id`),
  KEY `app_meeting_recording` (`app_id`,`meeting_id`,`recording_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `search_metrics`
--

DROP TABLE IF EXISTS `search_metrics`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `search_metrics` (
  `app_id` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `message_id` bigint NOT NULL,
  `uts` bigint unsigned NOT NULL,
  `event` varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `event_action` varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `time_taken_millis` bigint DEFAULT '0',
  `rows_scanned` bigint DEFAULT '0',
  UNIQUE KEY `unique_idx` (`app_id`,`message_id`,`uts`,`event`,`event_action`),
  KEY `app_uts` (`app_id`,`uts`),
  KEY `uts_app` (`uts`,`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `status_table`
--

DROP TABLE IF EXISTS `status_table`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `status_table` (
  `process_name` varchar(50) NOT NULL,
  `last_run_time_end` bigint NOT NULL DEFAULT '0',
  UNIQUE KEY `process_name` (`process_name`)
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
  `app_id` varchar(50) NOT NULL,
  `uts` bigint unsigned DEFAULT NULL,
  `uid` varchar(100) NOT NULL COMMENT '\n\n',
  `resource` varchar(255) DEFAULT NULL,
  `v` smallint unsigned DEFAULT '1',
  `app_info` json DEFAULT NULL,
  `sid` varchar(255) DEFAULT NULL,
  `origin` varchar(255) DEFAULT NULL,
  `version` varchar(50) DEFAULT NULL,
  `platform` varchar(50) DEFAULT NULL,
  `os_version` varchar(50) DEFAULT NULL,
  `user_agent` varchar(50) DEFAULT NULL,
  `ws_id` varchar(255) DEFAULT NULL,
  `api_version` varchar(50) DEFAULT NULL,
  `build_number` varchar(50) DEFAULT NULL,
  `language` varchar(50) DEFAULT NULL,
  `year` smallint unsigned DEFAULT NULL,
  `month` smallint unsigned DEFAULT NULL,
  `day` smallint unsigned DEFAULT NULL,
  `hour` smallint unsigned DEFAULT NULL,
  UNIQUE KEY `app_id` (`app_id`,`uid`,`ws_id`,`year`,`month`,`day`,`hour`),
  KEY `app_id_2` (`app_id`,`uid`,`year`,`month`,`day`,`hour`),
  KEY `app_id_3` (`app_id`,`uts`),
  KEY `year_month_day_hour` (`year`,`month`,`day`,`hour`),
  KEY `appid_year_month_day_hour` (`app_id`,`year`,`month`,`day`,`hour`),
  KEY `uts` (`uts`)
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

-- Dump completed on 2026-06-21 18:31:10
