-- MySQL dump 10.13  Distrib 8.0.46, for Linux (x86_64)
--
-- Host: 10.0.0.12    Database: pulsecustomerdb
-- ------------------------------------------------------
-- Server version	8.0.46-0ubuntu0.24.04.2

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
-- Table structure for table `app_microservice`
--

DROP TABLE IF EXISTS `app_microservice`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `app_microservice` (
  `appId` bigint unsigned NOT NULL,
  `microserviceId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT '0',
  `addedAt` int NOT NULL,
  `addedBy` bigint unsigned NOT NULL,
  `updatedAt` int NOT NULL,
  `updatedBy` bigint unsigned NOT NULL,
  PRIMARY KEY (`appId`,`microserviceId`),
  KEY `app_microservice_microserviceid_foreign` (`microserviceId`),
  KEY `app_microservice_addedby_foreign` (`addedBy`),
  KEY `app_microservice_updatedby_foreign` (`updatedBy`),
  CONSTRAINT `app_microservice_addedby_foreign` FOREIGN KEY (`addedBy`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `app_microservice_appid_foreign` FOREIGN KEY (`appId`) REFERENCES `apps` (`id`) ON DELETE CASCADE,
  CONSTRAINT `app_microservice_microserviceid_foreign` FOREIGN KEY (`microserviceId`) REFERENCES `microservices` (`id`) ON DELETE CASCADE,
  CONSTRAINT `app_microservice_updatedby_foreign` FOREIGN KEY (`updatedBy`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `app_microservice`
--

LOCK TABLES `app_microservice` WRITE;
/*!40000 ALTER TABLE `app_microservice` DISABLE KEYS */;
/*!40000 ALTER TABLE `app_microservice` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `app_parameter`
--

DROP TABLE IF EXISTS `app_parameter`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `app_parameter` (
  `appId` bigint unsigned NOT NULL,
  `parameterId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `value` json NOT NULL,
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`appId`,`parameterId`),
  KEY `app_parameter_parameterid_foreign` (`parameterId`),
  CONSTRAINT `app_parameter_appid_foreign` FOREIGN KEY (`appId`) REFERENCES `apps` (`id`) ON DELETE CASCADE,
  CONSTRAINT `app_parameter_parameterid_foreign` FOREIGN KEY (`parameterId`) REFERENCES `parameters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `app_parameter`
--

LOCK TABLES `app_parameter` WRITE;
/*!40000 ALTER TABLE `app_parameter` DISABLE KEYS */;
/*!40000 ALTER TABLE `app_parameter` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `app_user`
--

DROP TABLE IF EXISTS `app_user`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `app_user` (
  `app_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `role` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'moderator',
  `accessKey` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`app_id`,`user_id`),
  KEY `app_user_createdat_index` (`createdAt`),
  KEY `app_user_updatedat_index` (`updatedAt`),
  KEY `app_user_role_index` (`role`),
  KEY `app_user_user_id_foreign` (`user_id`),
  CONSTRAINT `app_user_app_id_foreign` FOREIGN KEY (`app_id`) REFERENCES `apps` (`id`) ON DELETE CASCADE,
  CONSTRAINT `app_user_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `app_user`
--

LOCK TABLES `app_user` WRITE;
/*!40000 ALTER TABLE `app_user` DISABLE KEYS */;
/*!40000 ALTER TABLE `app_user` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `apps`
--

DROP TABLE IF EXISTS `apps`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `apps` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `parentId` bigint unsigned DEFAULT NULL,
  `parentHash` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `hash` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `owner` bigint unsigned NOT NULL,
  `region` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `version` varchar(15) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `plan` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `oldPlan` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `trialEndsAt` int DEFAULT NULL,
  `planChangedAt` int DEFAULT NULL,
  `downgradesAt` int DEFAULT NULL,
  `cancelsAt` int DEFAULT NULL,
  `startOfEvent` int DEFAULT NULL,
  `endOfEvent` int DEFAULT NULL,
  `metadata` json DEFAULT NULL,
  `invoiceFrom` int DEFAULT NULL,
  `lastInvoiceAmount` int DEFAULT NULL,
  `lastInvoiceAt` int DEFAULT NULL,
  `state` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  `scheduledToDeleteAt` int DEFAULT NULL,
  `deletedAt` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `apps_createdat_index` (`createdAt`),
  KEY `apps_updatedat_index` (`updatedAt`),
  KEY `apps_deletedat_index` (`deletedAt`),
  KEY `apps_owner_foreign` (`owner`),
  KEY `apps_parentid_index` (`parentId`),
  CONSTRAINT `apps_owner_foreign` FOREIGN KEY (`owner`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `apps_parentid_foreign` FOREIGN KEY (`parentId`) REFERENCES `apps` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `apps`
--

LOCK TABLES `apps` WRITE;
/*!40000 ALTER TABLE `apps` DISABLE KEYS */;
/*!40000 ALTER TABLE `apps` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `cb_plans`
--

DROP TABLE IF EXISTS `cb_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cb_plans` (
  `id` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `parentPlan` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `amount` int DEFAULT NULL,
  `isCBPlan` tinyint(1) NOT NULL DEFAULT '1',
  `visible` tinyint(1) NOT NULL DEFAULT '0',
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `cb_plans_id_unique` (`id`),
  KEY `cb_plans_createdat_index` (`createdAt`),
  KEY `cb_plans_updatedat_index` (`updatedAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `cb_plans`
--

LOCK TABLES `cb_plans` WRITE;
/*!40000 ALTER TABLE `cb_plans` DISABLE KEYS */;
INSERT INTO `cb_plans` VALUES ('free-2023-01',NULL,'Build plan','On-prem deployment plan',0,1,0,1781704676,1781704676),('onprem',NULL,'On-prem (onprem)','On-prem deployment plan',0,0,0,1700000000,1781780288);
/*!40000 ALTER TABLE `cb_plans` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `codes`
--

DROP TABLE IF EXISTS `codes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `codes` (
  `code` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `type` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'verifyEmail',
  `user_id` bigint unsigned NOT NULL,
  `app_id` bigint unsigned NOT NULL,
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`user_id`,`type`,`app_id`),
  KEY `codes_createdat_index` (`createdAt`),
  KEY `codes_updatedat_index` (`updatedAt`),
  KEY `codes_type` (`type`),
  KEY `codes_user_id` (`user_id`),
  KEY `codes_app_id` (`app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `codes`
--

LOCK TABLES `codes` WRITE;
/*!40000 ALTER TABLE `codes` DISABLE KEYS */;
/*!40000 ALTER TABLE `codes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `customer_otp`
--

DROP TABLE IF EXISTS `customer_otp`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer_otp` (
  `customer_id` bigint unsigned NOT NULL,
  `otp` varchar(6) COLLATE utf8mb4_unicode_ci NOT NULL,
  `createdAt` int NOT NULL,
  PRIMARY KEY (`customer_id`,`otp`),
  CONSTRAINT `customer_otp_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `customer_otp`
--

LOCK TABLES `customer_otp` WRITE;
/*!40000 ALTER TABLE `customer_otp` DISABLE KEYS */;
/*!40000 ALTER TABLE `customer_otp` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `customerhook_webhook`
--

DROP TABLE IF EXISTS `customerhook_webhook`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `customerhook_webhook` (
  `hook` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `webhookId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT '0',
  `addedAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`hook`,`webhookId`),
  KEY `customerhook_webhook_addedat_index` (`addedAt`),
  KEY `customerhook_webhook_updatedat_index` (`updatedAt`),
  KEY `customerhook_webhook_webhookid_foreign` (`webhookId`),
  CONSTRAINT `customerhook_webhook_hook_foreign` FOREIGN KEY (`hook`) REFERENCES `customerhooks` (`hook`) ON DELETE CASCADE,
  CONSTRAINT `customerhook_webhook_webhookid_foreign` FOREIGN KEY (`webhookId`) REFERENCES `webhooks` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `customerhook_webhook`
--

LOCK TABLES `customerhook_webhook` WRITE;
/*!40000 ALTER TABLE `customerhook_webhook` DISABLE KEYS */;
/*!40000 ALTER TABLE `customerhook_webhook` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `customerhooks`
--

DROP TABLE IF EXISTS `customerhooks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `customerhooks` (
  `hook` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `isActive` tinyint(1) NOT NULL DEFAULT '0',
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`hook`),
  KEY `customerhooks_createdat_index` (`createdAt`),
  KEY `customerhooks_updatedat_index` (`updatedAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `customerhooks`
--

LOCK TABLES `customerhooks` WRITE;
/*!40000 ALTER TABLE `customerhooks` DISABLE KEYS */;
/*!40000 ALTER TABLE `customerhooks` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `email_verificationCode`
--

DROP TABLE IF EXISTS `email_verificationCode`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `email_verificationCode` (
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `verificationCode` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `createdAt` int NOT NULL,
  `ipinfo` json DEFAULT NULL,
  PRIMARY KEY (`email`),
  KEY `email_verificationcode_verificationcode_index` (`verificationCode`),
  KEY `email_verificationcode_createdat_index` (`createdAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `email_verificationCode`
--

LOCK TABLES `email_verificationCode` WRITE;
/*!40000 ALTER TABLE `email_verificationCode` DISABLE KEYS */;
/*!40000 ALTER TABLE `email_verificationCode` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `hook_microservice`
--

DROP TABLE IF EXISTS `hook_microservice`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hook_microservice` (
  `microserviceId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `hook` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT '0',
  `AddedAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`microserviceId`,`hook`),
  KEY `hook_microservice_hook_foreign` (`hook`),
  KEY `hook_microservice_addedat_index` (`AddedAt`),
  KEY `hook_microservice_updatedat_index` (`updatedAt`),
  CONSTRAINT `hook_microservice_hook_foreign` FOREIGN KEY (`hook`) REFERENCES `hooks` (`hook`) ON DELETE CASCADE,
  CONSTRAINT `hook_microservice_microserviceid_foreign` FOREIGN KEY (`microserviceId`) REFERENCES `microservices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `hook_microservice`
--

LOCK TABLES `hook_microservice` WRITE;
/*!40000 ALTER TABLE `hook_microservice` DISABLE KEYS */;
INSERT INTO `hook_microservice` VALUES ('link-preview','before_message',1,1568382527,1568382527),('thumbnail-generation','before_message',1,1568382516,1568382516);
/*!40000 ALTER TABLE `hook_microservice` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `hooks`
--

DROP TABLE IF EXISTS `hooks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hooks` (
  `hook` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `isActive` tinyint(1) NOT NULL DEFAULT '0',
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`hook`),
  KEY `hooks_createdat_index` (`createdAt`),
  KEY `hooks_updatedat_index` (`updatedAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `hooks`
--

LOCK TABLES `hooks` WRITE;
/*!40000 ALTER TABLE `hooks` DISABLE KEYS */;
INSERT INTO `hooks` VALUES ('after_auth_token_created','The hook triggers after the auth token is created.',1,1663248017,1663248017),('after_auth_token_deleted','The hook triggers after the auth token is deleted.',1,1663248017,1663248017),('after_auth_token_updated','The hook triggers after the auth token is updated.',1,1663248017,1663248017),('after_first_message','The hook triggers after sending the first message.',1,1663248017,1663248017),('after_first_user','The hook triggers after creating the first user.',1,1663248017,1663248017),('after_group_created','The hook triggers after group is created.',1,1663248017,1663248017),('after_group_deleted','The hook triggers after group is deleted.',1,1663248017,1663248017),('after_group_joined','The hook triggers after user joins a group.',1,1663248017,1663248017),('after_group_left','The hook triggers after user leaves a group.',1,1663248017,1663248017),('after_group_members_added','The hook triggers after members are added to group.',1,1663248017,1663248017),('after_group_members_banned','The hook triggers after members are banned from group.',1,1663248017,1663248017),('after_group_members_kicked','The hook triggers after member is kicked from group.',1,1663248017,1663248017),('after_group_members_unbanned','The hook triggers after members are unbanned from group.',1,1663248017,1663248017),('after_group_updated','The hook will be triggered after adding user into the database.',1,1663248017,1663248017),('after_logged_out','The hook triggers after user logs out.',1,1663248017,1663248017),('after_message','The hook triggers after sending a message.',1,1663248017,1663248017),('after_scope_changed','The hook will be triggered after changing the scope.',1,1663248017,1663248017),('after_user_added','The hook will be triggered after adding user into the database.',1,1663248017,1663248017),('after_user_deactivated','The hook will be triggered after adding user into the database.',1,1663248017,1663248017),('after_user_deleted','The hook triggers after user is deleted.',1,1663248017,1663248017),('after_user_reactivated','The hook will be triggered after adding user into the database.',1,1663248017,1663248017),('after_user_updated','The hook will be triggered after adding user into the database.',1,1663248017,1663248017),('after_webhook_created','The hook will be triggered after creating webhook.',1,1663248017,1663248017),('after_webhook_deleted','The hook will be triggered after deleting webhook.',1,1663248017,1663248017),('after_webhook_disabled','The hook will be triggered after disabling webhook',1,1663248017,1663248017),('after_webhook_enabled','The hook will be triggered after enabling webhook.',1,1663248017,1663248017),('after_webhook_updated','The hook will be triggered after updating webhook.',1,1663248017,1663248017),('before_message','The hook will be triggered before adding message to database.',1,1663248017,1663248017),('before_message_edited','The hook will be triggered before adding edited message to database.',1,1552383451,1552383451),('before_user_added','The hook will be triggered after adding user into the database.',0,1663248017,1663248017);
/*!40000 ALTER TABLE `hooks` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `interface_params`
--

DROP TABLE IF EXISTS `interface_params`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `interface_params` (
  `interfaceId` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `key` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `dataType` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `defaultValue` json DEFAULT NULL,
  `value` json DEFAULT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `required` tinyint(1) NOT NULL DEFAULT '0',
  `createdAt` int DEFAULT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`interfaceId`,`key`),
  KEY `interface_params_createdat_index` (`createdAt`),
  KEY `interface_params_updatedat_index` (`updatedAt`),
  KEY `interface_params_interfaceid_index` (`interfaceId`),
  KEY `interface_params_key_index` (`key`),
  KEY `interface_params_datatype_index` (`dataType`),
  KEY `interface_params_required_index` (`required`),
  CONSTRAINT `interface_params_interfaceid_foreign` FOREIGN KEY (`interfaceId`) REFERENCES `microservices` (`interfaceId`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `interface_params`
--

LOCK TABLES `interface_params` WRITE;
/*!40000 ALTER TABLE `interface_params` DISABLE KEYS */;
/*!40000 ALTER TABLE `interface_params` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `interface_trigger`
--

DROP TABLE IF EXISTS `interface_trigger`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `interface_trigger` (
  `triggerId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `interfaceId` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  PRIMARY KEY (`interfaceId`,`triggerId`),
  KEY `interface_trigger_interfaceid_index` (`interfaceId`),
  KEY `interface_trigger_triggerid_index` (`triggerId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `interface_trigger`
--

LOCK TABLES `interface_trigger` WRITE;
/*!40000 ALTER TABLE `interface_trigger` DISABLE KEYS */;
INSERT INTO `interface_trigger` VALUES ('before_message','extension_link-preview'),('before_message','extension_thumbnail-generation');
/*!40000 ALTER TABLE `interface_trigger` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `interface_trigger_filter`
--

DROP TABLE IF EXISTS `interface_trigger_filter`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `interface_trigger_filter` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `parent` int unsigned DEFAULT NULL,
  `interfaceId` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `triggerId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `triggerFilterId` int unsigned NOT NULL,
  `key` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `operator` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `value` json NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `interface_trigger_filter_parent_index` (`parent`),
  KEY `interface_trigger_filter_interfaceid_index` (`interfaceId`),
  KEY `interface_trigger_filter_triggerfilterid_index` (`triggerFilterId`),
  KEY `interface_trigger_filter_triggerid_index` (`triggerId`),
  KEY `interface_trigger_filter_key_index` (`key`),
  KEY `interface_trigger_filter_operator_index` (`operator`),
  KEY `interface_trigger_filter_enabled_index` (`enabled`),
  CONSTRAINT `interface_trigger_filter_interfaceid_foreign` FOREIGN KEY (`interfaceId`) REFERENCES `microservices` (`interfaceId`) ON DELETE CASCADE,
  CONSTRAINT `interface_trigger_filter_parent_foreign` FOREIGN KEY (`parent`) REFERENCES `interface_trigger_filter` (`id`) ON DELETE CASCADE,
  CONSTRAINT `interface_trigger_filter_triggerfilterid_foreign` FOREIGN KEY (`triggerFilterId`) REFERENCES `trigger_filters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `interface_trigger_filter`
--

LOCK TABLES `interface_trigger_filter` WRITE;
/*!40000 ALTER TABLE `interface_trigger_filter` DISABLE KEYS */;
INSERT INTO `interface_trigger_filter` VALUES (1,NULL,'extension_thumbnail-generation','before_message',9,'hasImageOrVideo','=','true',1),(3,NULL,'extension_link-preview','before_message',4,'hasText','=','true',1);
/*!40000 ALTER TABLE `interface_trigger_filter` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `microservice_plan`
--

DROP TABLE IF EXISTS `microservice_plan`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `microservice_plan` (
  `planId` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `microserviceId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `addedAt` int NOT NULL,
  PRIMARY KEY (`planId`,`microserviceId`),
  KEY `microservice_plan_microserviceid_foreign` (`microserviceId`),
  CONSTRAINT `microservice_plan_microserviceid_foreign` FOREIGN KEY (`microserviceId`) REFERENCES `microservices` (`id`) ON DELETE CASCADE,
  CONSTRAINT `microservice_plan_planid_foreign` FOREIGN KEY (`planId`) REFERENCES `cb_plans` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `microservice_plan`
--

LOCK TABLES `microservice_plan` WRITE;
/*!40000 ALTER TABLE `microservice_plan` DISABLE KEYS */;
/*!40000 ALTER TABLE `microservice_plan` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `microservice_region`
--

DROP TABLE IF EXISTS `microservice_region`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `microservice_region` (
  `microserviceId` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `regionId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT '0',
  `AddedAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`microserviceId`,`regionId`),
  KEY `microservice_region_microserviceid_index` (`microserviceId`),
  KEY `microservice_region_regionid_index` (`regionId`),
  KEY `microservice_region_addedat_index` (`AddedAt`),
  KEY `microservice_region_updatedat_index` (`updatedAt`),
  CONSTRAINT `microservice_region_microserviceid_foreign` FOREIGN KEY (`microserviceId`) REFERENCES `microservices` (`id`) ON DELETE CASCADE,
  CONSTRAINT `microservice_region_regionid_foreign` FOREIGN KEY (`regionId`) REFERENCES `regions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `microservice_region`
--

LOCK TABLES `microservice_region` WRITE;
/*!40000 ALTER TABLE `microservice_region` DISABLE KEYS */;
INSERT INTO `microservice_region` VALUES ('document','onprem',1,1781783060,1781783060),('document','us',1,1781783060,1781783060),('link-preview','onprem',1,1781783060,1781783060),('link-preview','us',1,1781783060,1781783060),('polls','onprem',1,1781783060,1781783060),('polls','us',1,1781783060,1781783060),('stickers','onprem',1,1781783060,1781783060),('stickers','us',1,1781783060,1781783060),('thumbnail-generation','onprem',1,1781783060,1781783060),('thumbnail-generation','us',1,1781783060,1781783060),('whiteboard','onprem',1,1781783060,1781783060),('whiteboard','us',1,1781783060,1781783060);
/*!40000 ALTER TABLE `microservice_region` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `microservices`
--

DROP TABLE IF EXISTS `microservices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `microservices` (
  `id` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `interfaceId` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `tagLine` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `iconURL` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `author` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `webhookURL` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `accessToAppData` tinyint(1) NOT NULL DEFAULT '0',
  `adminURL` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `websiteURL` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `docURL` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `useBasicAuth` tinyint(1) NOT NULL DEFAULT '0',
  `username` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `password` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `isActive` tinyint(1) NOT NULL DEFAULT '0',
  `isPrivate` tinyint(1) NOT NULL DEFAULT '0',
  `isInvisible` tinyint(1) NOT NULL DEFAULT '1',
  `isThirdParty` tinyint(1) NOT NULL DEFAULT '0',
  `hash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  `markedAsLegacyAt` int DEFAULT NULL,
  `endOfLifeAt` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `microservices_name_index` (`name`),
  KEY `microservices_author_index` (`author`),
  KEY `microservices_email_index` (`email`),
  KEY `microservices_hash_index` (`hash`),
  KEY `microservices_createdat_index` (`createdAt`),
  KEY `microservices_updatedat_index` (`updatedAt`),
  KEY `microservices_interfaceid_index` (`interfaceId`),
  KEY `microservices_usebasicauth_index` (`useBasicAuth`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `microservices`
--

LOCK TABLES `microservices` WRITE;
/*!40000 ALTER TABLE `microservices` DISABLE KEYS */;
INSERT INTO `microservices` VALUES ('document','extension_document','Collaborative document','Allows you create and share documents for collaboration','Allows you create and share documents for collaboration','','CometChat','help@cometchat.com','https://extensions-%s.cometchat-cluster-2.in/document/v1/create',0,'','https://www.cometchat.com','',1,'user_sdX5gSSZnM4130dI','HYEVrXC0Ms43a7p4',1,0,0,0,'cc6a546c506d891ff8f9d74cd0fb064646769a37',1592815197,1592815197,NULL,NULL),('link-preview','extension_link-preview','Link Preview','Generate meta description for URLs.','Generate meta description for URLs.',NULL,'CometChat','help@cometchat.com','https://extensions-%s.cometchat-cluster-2.in/link-preview/v1/generate-preview',0,NULL,'https://www.cometchat.com',NULL,1,'user_yT3sGmZ8nuCyESmL','bBeVG4zC4a4G9Gut',1,0,0,1,'a94523fda51c990d7c9df1a3c35b0aefe6ac415d',1568374120,1568374120,NULL,NULL),('polls','extension_polls','Polls','Polls to quickly ask for opinions in chats','Polls to quickly ask for opinions in chats',NULL,'CometChat','help@cometchat.com',NULL,0,NULL,'https://www.cometchat.com',NULL,1,'user_CMeUFgFvD67ZiaQw','WSxR0hUnYMjsO57H',1,0,0,0,'857ebac25404bbdb67527d520d4fd964f93ddf3a',1594721219,1594721219,NULL,NULL),('stickers','extension_stickers','Stickers','Send & manage stickers','Send & manage stickers',NULL,'CometChat','help@cometchat.com','https://extensions-%s.cometchat-cluster-2.in/stickers/v1/react',0,'https://extensions-%s.cometchat-cluster-2.in/stickers/v1/show-setting','https://www.cometchat.com',NULL,1,'user_i6tX8SQyM2Pl82Hm','KFZ2q4Emg0TOZ5rP',1,0,0,0,'457fbb203f473a7500f5fd264a49be5a93c58a7b',1592815197,1592815197,NULL,NULL),('thumbnail-generation','extension_thumbnail-generation','Thumbnail Generation','Generate thumbnails for images and videos.','Generate thumbnails for images and videos.',NULL,'CometChat','help@cometchat.com','https://extensions-%s.cometchat-cluster-2.in/thumbnail-generator/generate',0,NULL,'https://www.cometchat.com',NULL,1,'user_Z2m3FFAtnFFJGz2h','x4cDnjPj8zpssnUD',1,0,0,1,'e32cc5f7a609d1dbaa45c10f297329db96dedb89',1568374050,1568374050,NULL,NULL),('whiteboard','extension_whiteboard','Collaborative whiteboard','Allows you create and share whiteboards for collaboration','Allows you create and share whiteboards for collaboration',NULL,'CometChat','help@cometchat.com','https://extensions-%s.cometchat-cluster-2.in/whiteboard/v1/create',0,NULL,'https://www.cometchat.com',NULL,1,'user_sarCyjTVBH0CYAn9','xwwU6ONVVfIesPwL',1,0,0,0,'d728e330a7d1df0f5a5511acd14be7f12bfef09f',1595838286,1595838286,NULL,NULL);
/*!40000 ALTER TABLE `microservices` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `migrations`
--

DROP TABLE IF EXISTS `migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `migrations` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `migration` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `batch` int NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=99 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `migrations`
--

LOCK TABLES `migrations` WRITE;
/*!40000 ALTER TABLE `migrations` DISABLE KEYS */;
INSERT INTO `migrations` VALUES (1,'2018_11_20_101829_create_users_table',1),(2,'2018_11_29_175047_create_apps_table',1),(3,'2018_11_29_175853_create_app_user_table',1),(4,'2018_12_14_043248_alter_app_user_add_accesskey',1),(5,'2018_12_18_153943_create_usermeta_table',1),(6,'2018_12_19_123523_create_codes_table',1),(7,'2018_12_19_163339_alter_users_add_email_verified',1),(8,'2019_02_21_112752_create_microservices_table',1),(9,'2019_02_21_113863_create_hooks_table',1),(10,'2019_02_21_114974_create_hook_microservice_table',1),(11,'2019_02_23_154651_create_categories_table',1),(12,'2019_02_23_154679_create_category_microservice_table',1),(13,'2019_02_23_154689_create_app_microservice_table',1),(14,'2019_03_11_164845_add_icon_to_microservices_table',1),(15,'2019_03_15_113863_create_customerhooks_table',1),(16,'2019_03_15_113869_create_webhooks_table',1),(17,'2019_03_15_113879_create_customerhook_webhook_table',1),(18,'2019_04_10_132443_create_cb_plans_table',1),(19,'2019_04_10_143445_create_cb_addons_table',1),(20,'2019_04_10_189224_create_cb_addon_plan_table',1),(21,'2019_04_11_198233_add_enabled_to_cb_addons_plans_table',1),(22,'2019_04_12_156753_add_isinvisible_to_microservice_table',1),(23,'2019_04_12_156853_rename_active_to_isactive',1),(24,'2019_04_13_112564_create_paymentmeta_table',1),(25,'2019_04_14_101564_create_paymentmethodcalllog_table',1),(26,'2019_04_14_111664_create_paymentwebhooklog_table',1),(27,'2019_04_30_151746_add_type_to_cb_addons_table',1),(28,'2019_05_02_060823_add_docurl_to_microservices_table',1),(29,'2019_05_06_080934_add_accessToAppData_to_microservices_table',1),(30,'2019_07_08_231432_add_visible_to_cb_plans_and_cb_addons',1),(31,'2019_08_05_987561_add_region_to_app',1),(32,'2019_08_16_187785_alter_microservices_as_interfaces',1),(33,'2019_08_17_186541_create_interface_trigger',1),(34,'2019_08_17_265164_insert_interface_trigger',1),(35,'2019_08_17_648953_create_trigger_filters',1),(36,'2019_08_17_798654_create_interface_trigger_filter',1),(37,'2019_08_19_569443_create_interface_params',1),(38,'2019_08_19_898654_create_operators',1),(39,'2019_08_20_998654_insert_operators',1),(40,'2019_08_28_681497_insert_trigger_filters',1),(41,'2019_09_04_684682_create_regions',1),(42,'2019_09_04_684699_create_microservice_region',1),(43,'2019_09_06_000547_update_app_region',1),(44,'2019_09_09_98211_create_regionmeta_table',1),(45,'2019_09_24_163339_alter_users_add_istestaccount',1),(46,'2019_10_01_221987_create_features_table',1),(47,'2019_10_01_321247_insert_features_table',1),(48,'2019_10_01_431323_create_plan_features_table',1),(49,'2019_10_24_879012_alter_apps_add_trialendsat',1),(50,'2019_12_17_890264_create_subscriptionlog',1),(51,'2020_01_02_283742_alter_apps_add_metadata',1),(52,'2020_01_03_692033_alter_apps_add_lastInvoiceAmount',1),(53,'2020_01_13_120912_alter_apps_add_lastInvoiceAt',1),(54,'2020_01_14_908578_create_app_subscription',1),(55,'2020_03_11_853212_insert_hooks',1),(56,'2020_05_06_290323_create_microservice_plan',1),(57,'2020_05_07_919749_alter_apps_add_cancelsAt',1),(58,'2020_05_08_897113_insert_push_notification_triggers',1),(59,'2020_05_21_390111_alter_users_add_paidAtleastOnce',1),(60,'2020_05_27_381988_pooled_and_manual_billing',1),(61,'2020_06_06_646687_scheduled_cancellation_and_manual_invoice',1),(62,'2020_06_29_100923_alter_cb_plans_add_amount',1),(63,'2020_07_06_894921_alter_apps_add_downgradesAt',1),(64,'2020_09_03_923312_alter_apps_add_invoiceFrom',1),(65,'2020_09_04_368768_alter_app_user_modify_role',1),(66,'2020_09_04_368799_alter_codes_modify_type_add_app_id',1),(67,'2020_09_24_184231_alter_cb_addons_modify_type',1),(68,'2020_10_15_902312_alter_apps_add_scheduledToDeleteAt',1),(69,'2020_10_16_346545_alter_users_add_pooledBilling',1),(70,'2020_11_13_781230_create_parameters_table',1),(71,'2020_11_13_909821_create_parameter_plan_table',1),(72,'2020_11_13_990011_create_app_parameter_table',1),(73,'2020_12_28_789211_alter_users_add_authChangedAt',1),(74,'2021_02_08_110315_alter_parameter_plan_add_isInvisible',1),(75,'2021_02_18_892111_alter_parameters_add_title',1),(76,'2021_02_18_901667_insert_parameters',1),(77,'2021_03_15_252300_alter_cb_plans_add_parentPlan',1),(78,'2021_03_17_131498_alter_apps_add_version',1),(79,'2021_04_06_989136_alter_apps_modify_state',1),(80,'2021_04_22_109210_alter_apps_add_oldPlan',1),(81,'2021_04_23_487219_alter_app_subscription_add_term_dates',1),(82,'2021_06_11_988333_create_user_secrets_table',1),(83,'2021_06_30_118092_drop_unique_contactNumber',1),(84,'2021_09_24_420210_alter_apps_add_event_timestamps',1),(85,'2021_09_24_420210_create_app_event_table',1),(86,'2022_01_24_798102_create_app_event_log_table',1),(87,'2023_01_23_901312_insert_new_hooks',1),(88,'2023_05_25_820210_alter_app_subscription_add_discount',1),(89,'2023_09_21_000001_create_table_email_verification_code',1),(90,'2023_10_03_506935_add_email_verification_webhook',1),(91,'2023_11_24_245124_alter_usermeta_modify_value',1),(92,'2024_02_22_245124_alter_evc_add_ipinfo',1),(93,'2024_03_12_163648_alter_app_subscription_add_soft_deletes',1),(94,'2025_01_20_239391_create_table_customer_otp',1),(95,'2025_05_12_054912_add_legacy_based_columns_to_microservices',1),(96,'2026_04_17_000000_create_cli_auth_sessions_table',1),(97,'2026_05_20_000000_create_pipeline_log_table',1),(98,'2026_06_17_000000_onprem_setup',2);
/*!40000 ALTER TABLE `migrations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `parameter_plan`
--

DROP TABLE IF EXISTS `parameter_plan`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `parameter_plan` (
  `planId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `parameterId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `value` json NOT NULL,
  `isInvisible` tinyint(1) NOT NULL DEFAULT '0',
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`planId`,`parameterId`),
  KEY `parameter_plan_parameterid_foreign` (`parameterId`),
  CONSTRAINT `parameter_plan_parameterid_foreign` FOREIGN KEY (`parameterId`) REFERENCES `parameters` (`id`) ON DELETE CASCADE,
  CONSTRAINT `parameter_plan_planid_foreign` FOREIGN KEY (`planId`) REFERENCES `cb_plans` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `parameter_plan`
--

LOCK TABLES `parameter_plan` WRITE;
/*!40000 ALTER TABLE `parameter_plan` DISABLE KEYS */;
INSERT INTO `parameter_plan` VALUES ('free-2023-01','core.notifications.logs.accessible','true',0,1700000000,1700000000),('free-2023-01','core.notifications.logs.retentionDays','7',0,1696429191,1696429191),('onprem','compliance.ccpa.enabled','false',0,1700000000,1700000000),('onprem','compliance.enabled','true',0,1700000000,1700000000),('onprem','compliance.gdpr.enabled','true',0,1700000000,1700000000),('onprem','compliance.hippa-baa.enabled','true',0,1700000000,1700000000),('onprem','compliance.pipeda.enabled','false',0,1700000000,1700000000),('onprem','compliance.soc2.enabled','true',0,1700000000,1700000000),('onprem','core.advanced.search.accessible','true',0,1700000000,1700000000),('onprem','core.call.enabled','true',0,1700000000,1700000000),('onprem','core.call.groups.audio.enabled','true',0,1700000000,1700000000),('onprem','core.call.groups.video.enabled','true',0,1700000000,1700000000),('onprem','core.call.live-streaming.enabled','true',0,1700000000,1700000000),('onprem','core.call.logs.enabled','true',0,1700000000,1700000000),('onprem','core.call.one-on-one.audio.enabled','true',0,1700000000,1700000000),('onprem','core.call.one-on-one.video.enabled','true',0,1700000000,1700000000),('onprem','core.call.recording.enabled','true',0,1700000000,1700000000),('onprem','core.call.transcript.enabled','true',0,1700000000,1700000000),('onprem','core.chat.conversation.mark-as-read.enabled','true',0,1700000000,1700000000),('onprem','core.chat.enabled','true',0,1700000000,1700000000),('onprem','core.chat.groups.ban.enabled','true',0,1700000000,1700000000),('onprem','core.chat.groups.enabled','true',0,1700000000,1700000000),('onprem','core.chat.groups.kick.enabled','true',0,1700000000,1700000000),('onprem','core.chat.groups.password.enabled','true',0,1700000000,1700000000),('onprem','core.chat.groups.private.enabled','true',0,1700000000,1700000000),('onprem','core.chat.groups.public.enabled','true',0,1700000000,1700000000),('onprem','core.chat.groups.search.enabled','true',0,1700000000,1700000000),('onprem','core.chat.localization.enabled','true',0,1700000000,1700000000),('onprem','core.chat.mentions-feed.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.custom.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.delete.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.edit.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.history.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.media.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.receipts.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.replies.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.search.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.threads.enabled','true',0,1700000000,1700000000),('onprem','core.chat.messages.unread-count.enabled','true',0,1700000000,1700000000),('onprem','core.chat.one-on-one.enabled','true',0,1700000000,1700000000),('onprem','core.chat.reactions-feed.enabled','true',0,1700000000,1700000000),('onprem','core.chat.tags.conversations.enabled','true',0,1700000000,1700000000),('onprem','core.chat.tags.groups.enabled','true',0,1700000000,1700000000),('onprem','core.chat.tags.users.enabled','true',0,1700000000,1700000000),('onprem','core.chat.threads-feed.enabled','true',0,1700000000,1700000000),('onprem','core.chat.typing-indicator.enabled','true',0,1700000000,1700000000),('onprem','core.chat.unread-message-count.accessible','true',0,1700000000,1700000000),('onprem','core.chat.unread-message-count.enabled','false',0,1700000000,1700000000),('onprem','core.chat.users.block.enabled','true',0,1700000000,1700000000),('onprem','core.chat.users.list.enabled','true',0,1700000000,1700000000),('onprem','core.chat.users.presence.enabled','true',0,1700000000,1700000000),('onprem','core.chat.users.search.enabled','true',0,1700000000,1700000000),('onprem','core.chat.voice-notes.enabled','true',0,1700000000,1700000000),('onprem','core.conversations.advanced.search.enabled','true',0,1700000000,1700000000),('onprem','core.conversations.updateOnCallActivity','false',0,1700000000,1700000000),('onprem','core.conversations.updateOnCustomMessage','true',0,1700000000,1700000000),('onprem','core.conversations.updateOnGroupActions','true',0,1700000000,1700000000),('onprem','core.conversations.updateOnMessageActions','false',0,1700000000,1700000000),('onprem','core.conversations.updateOnReplies','true',0,1700000000,1700000000),('onprem','core.messages.advanced.search.enabled','true',0,1700000000,1700000000),('onprem','core.moderation.advanced.accessible','false',0,1700000000,1700000000),('onprem','core.moderation.advanced.enabled','false',0,1700000000,1700000000),('onprem','core.notifications.email.accessible','true',0,1700000000,1700000000),('onprem','core.notifications.email.advanced.enabled','true',0,1700000000,1700000000),('onprem','core.notifications.email.advanced.included','[\"feature.enable\", \"providers.add\", \"preferences\", \"templates\"]',0,1700000000,1700000000),('onprem','core.notifications.email.enabled','false',0,1700000000,1700000000),('onprem','core.notifications.logs.accessible','true',0,1700000000,1700000000),('onprem','core.notifications.logs.disableAfterDays','7',0,1700000000,1700000000),('onprem','core.notifications.logs.retentionDays','7',0,1696429191,1696429191),('onprem','core.notifications.push.accessible','true',0,1700000000,1700000000),('onprem','core.notifications.push.advanced.enabled','true',0,1700000000,1700000000),('onprem','core.notifications.push.advanced.included','[\"preferences\", \"templates\", \"providers.multiple\"]',0,1700000000,1700000000),('onprem','core.notifications.push.enabled','false',0,1700000000,1700000000),('onprem','core.notifications.sms.accessible','true',0,1700000000,1700000000),('onprem','core.notifications.sms.advanced.enabled','true',0,1700000000,1700000000),('onprem','core.notifications.sms.advanced.included','[\"feature.enable\", \"providers.add\", \"preferences\", \"templates\"]',0,1700000000,1700000000),('onprem','core.notifications.sms.enabled','false',0,1700000000,1700000000),('onprem','core.notifications.unreadBadgeCount.accessible','false',0,1688738923,1688738923),('onprem','core.notifications.unreadBadgeCount.enabled','false',0,1688738923,1688738923),('onprem','core.threads.updateOnMessageActions','false',0,1700000000,1700000000),('onprem','core.websocket.custom.enabled','false',0,1700000000,1700000000),('onprem','customer_notification_thresholds','{\"reporting_threshold\": 80, \"reporting_threshold_jump\": \"int\"}',0,1700000000,1700000000),('onprem','customersupport.chatwoot.enabled','true',0,1700000000,1700000000),('onprem','customersupport.intercom.enabled','true',0,1700000000,1700000000),('onprem','customersupport.zapier.enabled','true',0,1700000000,1700000000),('onprem','dashboard.analytics.advanced.enabled','false',0,1700000000,1700000000),('onprem','dashboard.analytics.insights.url','\"https://insights.cometchat.io/insights?mode=getUrl&appId=%s\"',0,1700000000,1700000000),('onprem','dashboard.analytics.usage.enabled','true',0,1700000000,1700000000),('onprem','dashboard.audit.logs.enabled','true',0,1700000000,1700000000),('onprem','dashboard.enabled','true',0,1700000000,1700000000),('onprem','dashboard.groups.management.enabled','true',0,1700000000,1700000000),('onprem','dashboard.insights.audio.enabled','true',0,1700000000,1700000000),('onprem','dashboard.insights.groups.enabled','true',0,1700000000,1700000000),('onprem','dashboard.insights.messages.enabled','true',0,1700000000,1700000000),('onprem','dashboard.insights.users.enabled','true',0,1700000000,1700000000),('onprem','dashboard.insights.video.enabled','true',0,1700000000,1700000000),('onprem','dashboard.messages.moderation.enabled','true',0,1700000000,1700000000),('onprem','dashboard.settings.included','[\"core.conversations.updateOnGroupActions\", \"core.conversations.updateOnReplies\", \"core.threads.updateOnMessageActions\", \"core.conversations.updateOnCallActivity\", \"core.conversations.updateOnMessageActions\", \"core.conversations.updateOnCustomMessage\", \"core.notifications.push.accessible\", \"core.notifications.push.enabled\", \"core.notifications.push.advanced.enabled\", \"core.notifications.push.advanced.included\", \"features.security.file-access.enabled\", \"core.notifications.email.accessible\", \"core.notifications.email.enabled\", \"core.notifications.email.advanced.enabled\", \"core.notifications.sms.accessible\", \"core.notifications.sms.enabled\", \"core.notifications.sms.advanced.enabled\", \"core.notifications.push.email.included\", \"core.notifications.sms.email.included\", \"features.moderation.advanced.enabled\", \"core.notifications.logs.enabledAtMS\", \"core.notifications.logs.disabledAtMS\", \"core.advanced.search.enabled\", \"core.chat.unread-message-count.enabled\", \"core.notifications.sms.advanced.included\", \"core.notifications.email.advanced.included\"]',0,1700000000,1700000000),('onprem','dashboard.sso.enabled','true',0,1700000000,1700000000),('onprem','dashboard.team.management.enabled','true',0,1700000000,1700000000),('onprem','dashboard.users.management.enabled','true',0,1700000000,1700000000),('onprem','deployment.enabled','true',0,1700000000,1700000000),('onprem','deployment.on-premise.enabled','false',0,1700000000,1700000000),('onprem','deployment.private-cloud.enabled','false',0,1700000000,1700000000),('onprem','deployment.shared-cloud.enabled','true',0,1700000000,1700000000),('onprem','extension_avatar','\"features.ux.avatar.enabled\"',0,1700000000,1700000000),('onprem','extension_broadcast','\"features.ue.video-broadcasting.enabled\"',0,1700000000,1700000000),('onprem','extension_chatwoot','\"customersupport.chatwoot.enabled\"',0,1700000000,1700000000),('onprem','extension_data-masking','\"features.moderation.data-masking.enabled\"',0,1700000000,1700000000),('onprem','extension_disappearing-messages','\"features.security.disappearing-messages.enabled\"',0,1700000000,1700000000),('onprem','extension_document','\"features.collaboration.document.enabled\"',0,1700000000,1700000000),('onprem','extension_e2ee','\"security.end-to-end-encryption.enabled\"',0,1700000000,1700000000),('onprem','extension_email-notification','\"features.notifications.email-notification.enabled\"',0,1700000000,1700000000),('onprem','extension_email-replies','\"features.ue.email-replies.enabled\"',0,1700000000,1700000000),('onprem','extension_emojis','\"features.ue.emojis.enabled\"',0,1700000000,1700000000),('onprem','extension_gifs-gfycat','\"features.ue.gfycat.enabled\"',0,1700000000,1700000000),('onprem','extension_gifs-giphy','\"features.ue.giphy.enabled\"',0,1700000000,1700000000),('onprem','extension_gifs-tenor','\"features.ue.tenor.enabled\"',0,1700000000,1700000000),('onprem','extension_human-moderation','\"features.moderation.inflight-message-moderation.enabled\"',0,1700000000,1700000000),('onprem','extension_image-moderation','\"features.moderation.image-moderation.enabled\"',0,1700000000,1700000000),('onprem','extension_intercom','\"customersupport.intercom.enabled\"',0,1700000000,1700000000),('onprem','extension_link-preview','\"features.ux.link-preview.enabled\"',0,1700000000,1700000000),('onprem','extension_live-migration-applozic','\"features.lm.live-migration-applozic.enabled\"',0,1700000000,1700000000),('onprem','extension_mentions','\"features.ue.mentions.enabled\"',0,1700000000,1700000000),('onprem','extension_message-shortcuts','\"features.ux.message-shortcuts.enabled\"',0,1700000000,1700000000),('onprem','extension_message-translation','\"features.ue.message-translation.enabled\"',0,1700000000,1700000000),('onprem','extension_pin-message','\"features.ux.messages.pinned.enabled\"',0,1700000000,1700000000),('onprem','extension_polls','\"features.ue.polls.enabled\"',0,1700000000,1700000000),('onprem','extension_profanity-filter','\"features.moderation.profanity-filter.enabled\"',0,1700000000,1700000000),('onprem','extension_push-notification','\"features.notifications.push-notification.enabled\"',0,1700000000,1700000000),('onprem','extension_reactions','\"features.ue.reactions.enabled\"',0,1700000000,1700000000),('onprem','extension_reminders','\"features.ue.reminders.enabled\"',0,1700000000,1700000000),('onprem','extension_report-message','\"features.moderation.report-message.enabled\"',0,1700000000,1700000000),('onprem','extension_report-user','\"features.moderation.report-user.enabled\"',0,1700000000,1700000000),('onprem','extension_rich-media','\"features.ux.rich-media-preview.enabled\"',0,1700000000,1700000000),('onprem','extension_save-message','\"features.ux.messages.saved.enabled\"',0,1700000000,1700000000),('onprem','extension_sentiment-analysis','\"features.moderation.sentiment-analysis.enabled\"',0,1700000000,1700000000),('onprem','extension_slow-mode','\"features.moderation.slow-mode.enabled\"',0,1700000000,1700000000),('onprem','extension_smart-reply','\"features.ue.smart-replies.enabled\"',0,1700000000,1700000000),('onprem','extension_sms-notification','\"features.notifications.sms-notification.enabled\"',0,1700000000,1700000000),('onprem','extension_stickers','\"features.ue.stickers.enabled\"',0,1700000000,1700000000),('onprem','extension_stickers-stipop','\"features.ue.stipop.enabled\"',0,1700000000,1700000000),('onprem','extension_thumbnail-generation','\"features.ux.thumbnail-generation.enabled\"',0,1700000000,1700000000),('onprem','extension_url-shortener-bitly','\"features.ux.url-shortener-bitly.enabled\"',0,1700000000,1700000000),('onprem','extension_url-shortener-tinyurl','\"features.ux.url-shortener.enabled\"',0,1700000000,1700000000),('onprem','extension_virus-malware-scanner','\"features.moderation.malware-scanner.enabled\"',0,1700000000,1700000000),('onprem','extension_voice-transcription','\"features.ux.voice-transcription.enabled\"',0,1700000000,1700000000),('onprem','extension_whiteboard','\"features.collaboration.whiteboard.enabled\"',0,1700000000,1700000000),('onprem','extension_widget','\"integrations.chat-widget.enabled\"',0,1700000000,1700000000),('onprem','extension_xss-filter','\"features.moderation.xss-filter.enabled\"',0,1700000000,1700000000),('onprem','feature.posthog_usage_tracking.enabled','false',0,1700000000,1700000000),('onprem','feature.usage_notifications.enabled.global','false',0,1700000000,1700000000),('onprem','feature.usage_notifications.external_email_enabled','false',0,1700000000,1700000000),('onprem','feature.usage_notifications.internal_eod_report_enabled','false',0,1700000000,1700000000),('onprem','features.advanced-plus.webhooks.accessible','true',0,1700000000,1700000000),('onprem','features.advanced-plus.webhooks.enabled','true',0,1700000000,1700000000),('onprem','features.advanced-plus.webhooks.included','[\"recording_generated\", \"user_connection_status_changed\", \"message_reaction_added\", \"message_reaction_removed\", \"user_mentioned\", \"message_delivery_receipt\", \"message_read_receipt\", \"message_delivered_to_all\", \"message_read_by_all\"]',0,1700000000,1700000000),('onprem','features.advanced.webhooks.accessible','true',0,1700000000,1700000000),('onprem','features.advanced.webhooks.enabled','true',0,1700000000,1700000000),('onprem','features.advanced.webhooks.included','[\"call_started\", \"meeting_started\", \"call_participant_joined\", \"call_initiated\", \"call_ended\", \"call_participant_left\", \"meeting_participant_joined\", \"meeting_participant_left\", \"meeting_ended\", \"group_created\", \"group_updated\", \"group_deleted\", \"group_member_joined\", \"group_member_left\", \"group_member_banned\", \"group_member_unbanned\", \"group_member_added\", \"group_member_kicked\", \"group_member_scope_changed\", \"group_owner_transferred\", \"user_blocked\", \"user_unblocked\", \"recording_generated\", \"moderation_engine_approved\", \"moderation_engine_blocked\", \"moderation_manual_approved\", \"call_busy\", \"call_cancelled\", \"call_unanswered\", \"call_rejected\"]',0,1700000000,1700000000),('onprem','features.ai.accessible','true',0,1700000000,1700000000),('onprem','features.ai.bots.accessible','true',0,1700000000,1700000000),('onprem','features.ai.bots.enabled','true',0,1700000000,1700000000),('onprem','features.ai.conversation-starter.accessible','true',0,1700000000,1700000000),('onprem','features.ai.conversation-starter.enabled','false',0,1700000000,1700000000),('onprem','features.ai.conversation-summary.accessible','true',0,1700000000,1700000000),('onprem','features.ai.conversation-summary.enabled','false',0,1700000000,1700000000),('onprem','features.ai.enabled','true',0,1700000000,1700000000),('onprem','features.ai.personalities.accessible','true',0,1700000000,1700000000),('onprem','features.ai.personalities.enabled','true',0,1700000000,1700000000),('onprem','features.ai.smart-replies.accessible','true',0,1700000000,1700000000),('onprem','features.ai.smart-replies.enabled','false',0,1700000000,1700000000),('onprem','features.basic.webhooks.accessible','true',0,1700000000,1700000000),('onprem','features.basic.webhooks.enabled','true',0,1700000000,1700000000),('onprem','features.basic.webhooks.included','[\"message_sent\", \"message_edited\", \"message_deleted\"]',0,1700000000,1700000000),('onprem','features.bots.enabled','true',0,1700000000,1700000000),('onprem','features.calls.webhooks.accessible','true',0,1700000000,1700000000),('onprem','features.calls.webhooks.enabled','true',0,1700000000,1700000000),('onprem','features.calls.webhooks.included','[\"call_started\", \"meeting_started\", \"call_participant_joined\", \"call_initiated\", \"call_ended\", \"call_participant_left\", \"meeting_participant_joined\", \"meeting_participant_left\", \"meeting_ended\"]',0,1700000000,1700000000),('onprem','features.collaboration.document.enabled','true',0,1700000000,1700000000),('onprem','features.collaboration.enabled','true',0,1700000000,1700000000),('onprem','features.collaboration.whiteboard.enabled','true',0,1700000000,1700000000),('onprem','features.data.cross-platform-sync.enabled','true',0,1700000000,1700000000),('onprem','features.data.enabled','true',0,1700000000,1700000000),('onprem','features.data.export.enabled','true',0,1700000000,1700000000),('onprem','features.data.global-cdn.enabled','true',0,1700000000,1700000000),('onprem','features.data.import.enabled','true',0,1700000000,1700000000),('onprem','features.data.live-migration.enabled','true',0,1700000000,1700000000),('onprem','features.data.multi-device-support.enabled','true',0,1700000000,1700000000),('onprem','features.data.remote-sync.enabled','true',0,1700000000,1700000000),('onprem','features.groups.webhooks.accessible','true',0,1700000000,1700000000),('onprem','features.groups.webhooks.enabled','true',0,1700000000,1700000000),('onprem','features.groups.webhooks.included','[\"group_created\", \"group_updated\", \"group_deleted\", \"group_member_joined\", \"group_member_left\", \"group_member_banned\", \"group_member_unbanned\", \"group_member_added\", \"group_member_kicked\", \"group_member_scope_changed\", \"group_owner_transferred\"]',0,1700000000,1700000000),('onprem','features.interactive.card-message.enabled','true',0,1700000000,1700000000),('onprem','features.interactive.custom-message.enabled','true',0,1700000000,1700000000),('onprem','features.interactive.form-message.enabled','true',0,1700000000,1700000000),('onprem','features.interactive.location-sharing.enabled','true',0,1700000000,1700000000),('onprem','features.interactive.meeting-scheduler.enabled','true',0,1700000000,1700000000),('onprem','features.lm.live-migration-applozic.enabled','true',0,1700000000,1700000000),('onprem','features.messages.webhooks.accessible','true',0,1700000000,1700000000),('onprem','features.messages.webhooks.enabled','true',0,1700000000,1700000000),('onprem','features.messages.webhooks.included','[\"message_sent\", \"message_edited\", \"message_deleted\"]',0,1700000000,1700000000),('onprem','features.moderation.advanced-plus.rules.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.advanced-plus.rules.included','[\"sentence-similarity\", \"explicit-or-sexual-content\", \"fraud-or-scam-indicators\", \"graphic-violence-or-gore\", \"hate-or-harassment\", \"minor-safety-and-exploitation\", \"privacy-or-personal-data\", \"self-harm-or-suicidal-content\", \"terrorism-or-extremist-promotion\", \"explicit-inappropriate-content\", \"hate-harassment\", \"impersonation-fraud\", \"non-consensual-sexual-content\", \"privacy-sensitive-info\", \"self-harm-suicidal-content\", \"spam-scam\", \"violent-threats\", \"open-ai\", \"custom-api\"]',0,1700000000,1700000000),('onprem','features.moderation.advanced.accessible','true',0,1700000000,1700000000),('onprem','features.moderation.advanced.conditions.included','3',0,1700000000,1700000000),('onprem','features.moderation.advanced.enabled','false',0,1700000000,1700000000),('onprem','features.moderation.advanced.filters.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.advanced.filters.included','[\"sender\", \"receiver\"]',0,1700000000,1700000000),('onprem','features.moderation.advanced.keywords.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.advanced.keywords.included','[\"platform-circumvention\", \"spam-detection\", \"scam-detection\"]',0,1700000000,1700000000),('onprem','features.moderation.advanced.rule-creation.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.advanced.rules.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.advanced.rules.included','[\"image-moderation\", \"video-moderation\", \"toxicity\", \"sentiment\", \"spam-detection\", \"scam-detection\", \"platform-circumvention\"]',0,1700000000,1700000000),('onprem','features.moderation.advanced.sentences.included','5',0,1700000000,1700000000),('onprem','features.moderation.basic.filters.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.basic.filters.included','[]',0,1700000000,1700000000),('onprem','features.moderation.basic.keywords.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.basic.keywords.included','[\"profanity-list\"]',0,1700000000,1700000000),('onprem','features.moderation.basic.rules.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.basic.rules.included','[\"profanity-filter\", \"contact_details_filter\", \"email_filter\"]',0,1700000000,1700000000),('onprem','features.moderation.data-masking.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.groups.ban.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.groups.kick.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.groups.moderators.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.image-moderation.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.inflight-message-moderation.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.keywords.limit','25',0,1700000000,1700000000),('onprem','features.moderation.keywords.sentences.limit','25',0,1700000000,1700000000),('onprem','features.moderation.live-message-moderation.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.malware-scanner.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.profanity-filter.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.report-message.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.report-user.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.rules.conditions.limit','25',0,1700000000,1700000000),('onprem','features.moderation.rules.filters.limit','25',0,1700000000,1700000000),('onprem','features.moderation.rules.limit','25',0,1700000000,1700000000),('onprem','features.moderation.sentiment-analysis.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.slow-mode.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.users.block.enabled','true',0,1700000000,1700000000),('onprem','features.moderation.xss-filter.enabled','true',0,1700000000,1700000000),('onprem','features.notifications.email-notification.enabled','true',0,1700000000,1700000000),('onprem','features.notifications.enabled','true',0,1700000000,1700000000),('onprem','features.notifications.push-notification.enabled','true',0,1700000000,1700000000),('onprem','features.notifications.sms-notification.enabled','true',0,1700000000,1700000000),('onprem','features.notifications.whatsapp.enabled','true',0,1700000000,1700000000),('onprem','features.security.disappearing-messages.enabled','true',0,1700000000,1700000000),('onprem','features.security.file-access.enabled','false',0,1700000000,1700000000),('onprem','features.ue.email-replies.enabled','true',0,1700000000,1700000000),('onprem','features.ue.emojis.enabled','true',0,1700000000,1700000000),('onprem','features.ue.enabled','true',0,1700000000,1700000000),('onprem','features.ue.gfycat.enabled','true',0,1700000000,1700000000),('onprem','features.ue.giphy.enabled','true',0,1700000000,1700000000),('onprem','features.ue.live-reactions.enabled','true',0,1700000000,1700000000),('onprem','features.ue.mentions.enabled','true',0,1700000000,1700000000),('onprem','features.ue.message-translation.enabled','true',0,1700000000,1700000000),('onprem','features.ue.polls.enabled','true',0,1700000000,1700000000),('onprem','features.ue.reactions.enabled','true',0,1700000000,1700000000),('onprem','features.ue.reminders.enabled','true',0,1700000000,1700000000),('onprem','features.ue.slow-mode.enabled','true',0,1700000000,1700000000),('onprem','features.ue.smart-replies.enabled','true',0,1700000000,1700000000),('onprem','features.ue.sms-replies.enabled','true',0,1700000000,1700000000),('onprem','features.ue.stickers.enabled','true',0,1700000000,1700000000),('onprem','features.ue.stipop.enabled','true',0,1700000000,1700000000),('onprem','features.ue.tenor.enabled','true',0,1700000000,1700000000),('onprem','features.ue.video-broadcasting.enabled','true',0,1700000000,1700000000),('onprem','features.users.webhooks.accessible','true',0,1700000000,1700000000),('onprem','features.users.webhooks.enabled','true',0,1700000000,1700000000),('onprem','features.users.webhooks.included','[\"user_blocked\", \"user_unblocked\"]',0,1700000000,1700000000),('onprem','features.ux.avatar.enabled','true',0,1700000000,1700000000),('onprem','features.ux.bookmark-message.enabled','true',0,1700000000,1700000000),('onprem','features.ux.enabled','true',0,1700000000,1700000000),('onprem','features.ux.link-preview.enabled','true',0,1700000000,1700000000),('onprem','features.ux.message-shortcuts.enabled','true',0,1700000000,1700000000),('onprem','features.ux.messages.pinned.enabled','true',0,1700000000,1700000000),('onprem','features.ux.messages.saved.enabled','true',0,1700000000,1700000000),('onprem','features.ux.rich-media-preview.enabled','true',0,1700000000,1700000000),('onprem','features.ux.thumbnail-generation.enabled','true',0,1700000000,1700000000),('onprem','features.ux.url-shortener-bitly.enabled','true',0,1700000000,1700000000),('onprem','features.ux.url-shortener.enabled','true',0,1700000000,1700000000),('onprem','features.ux.voice-transcription.enabled','true',0,1700000000,1700000000),('onprem','features.visual-builder.accessible','true',0,1700000000,1700000000),('onprem','features.visual-builder.enabled','true',0,1700000000,1700000000),('onprem','features.webhooks.accessible','true',0,1700000000,1700000000),('onprem','features.webhooks.enabled','true',0,1700000000,1700000000),('onprem','features.webhooks.in-flight.enabled','true',0,1700000000,1700000000),('onprem','features.webhooks.post-event.enabled','true',0,1700000000,1700000000),('onprem','file.count.max','104857600',0,1700000000,1700000000),('onprem','file.size.max','104857600',0,1700000000,1700000000),('onprem','groups.size.max','100000',0,1700000000,1700000000),('onprem','integrations.analytics-api.enabled','true',0,1700000000,1700000000),('onprem','integrations.app-mgmt-api.enabled','false',0,1700000000,1700000000),('onprem','integrations.chat-api.enabled','true',0,1700000000,1700000000),('onprem','integrations.chat-widget.enabled','true',0,1700000000,1700000000),('onprem','integrations.client-sdk.enabled','true',0,1700000000,1700000000),('onprem','integrations.enabled','true',0,1700000000,1700000000),('onprem','integrations.gdpr-api.enabled','true',0,1700000000,1700000000),('onprem','integrations.multi-tenant-reports.enabled','true',0,1700000000,1700000000),('onprem','integrations.rest-api.enabled','true',0,1700000000,1700000000),('onprem','integrations.ui-kit.enabled','true',0,1700000000,1700000000),('onprem','integrations.usage-api.enabled','false',0,1700000000,1700000000),('onprem','integrations.usage-reports.enabled','true',0,1700000000,1700000000),('onprem','internal_notification_thresholds','{\"reporting_threshold\": 80, \"reporting_threshold_jump\": \"int\"}',0,1700000000,1700000000),('onprem','messages.archival.period','6',0,1700000000,1700000000),('onprem','overages.attendees.cbaddon','false',0,1700000000,1700000000),('onprem','overages.attendees.enabled','false',0,1700000000,1700000000),('onprem','overages.attendees.included','false',0,1700000000,1700000000),('onprem','overages.calling.audio.cbaddon','false',0,1700000000,1700000000),('onprem','overages.calling.audio.included','2500',0,1700000000,1700000000),('onprem','overages.calling.enabled','false',0,1700000000,1700000000),('onprem','overages.calling.included','2500',0,1700000000,1700000000),('onprem','overages.calling.recording.cbaddon','false',0,1700000000,1700000000),('onprem','overages.calling.video.cbaddon','false',0,1700000000,1700000000),('onprem','overages.calling.video.included','2500',0,1700000000,1700000000),('onprem','overages.ccu.cbaddon','false',0,1700000000,1700000000),('onprem','overages.ccu.enabled','false',0,1700000000,1700000000),('onprem','overages.ccu.included','25',0,1700000000,1700000000),('onprem','overages.enabled','false',0,1700000000,1700000000),('onprem','overages.mau.cbaddon','false',0,1700000000,1700000000),('onprem','overages.mau.enabled','false',0,1700000000,1700000000),('onprem','overages.mau.included','\"10000\"',0,1700000000,1781780288),('onprem','plan.cancellation.disabled','true',0,1700000000,1700000000),('onprem','ratelimit.app','100000',0,1700000000,1700000000),('onprem','ratelimit.core','10000',0,1700000000,1700000000),('onprem','ratelimit.standard','20000',0,1700000000,1700000000),('onprem','resetTermOnPlanChange','true',0,1700000000,1700000000),('onprem','security.enabled','true',0,1700000000,1700000000),('onprem','security.encryption.rest.enabled','true',0,1700000000,1700000000),('onprem','security.encryption.transit.enabled','true',0,1700000000,1700000000),('onprem','security.end-to-end-encryption.enabled','true',0,1700000000,1700000000),('onprem','security.rbac.api.enabled','true',0,1700000000,1700000000),('onprem','support.agreement.service-level.enabled','false',0,1700000000,1700000000),('onprem','support.community.enabled','true',0,1700000000,1700000000),('onprem','support.customization.enabled','false',0,1700000000,1700000000),('onprem','support.email.enabled','true',0,1700000000,1700000000),('onprem','support.email.priority.enabled','true',0,1700000000,1700000000),('onprem','support.enabled','true',0,1700000000,1700000000),('onprem','support.event.live.enabled','true',0,1700000000,1700000000),('onprem','support.implementation.enabled','true',0,1700000000,1700000000),('onprem','support.manager.enabled','true',0,1700000000,1700000000),('onprem','support.slack.private.enabled','false',0,1700000000,1700000000),('onprem','team-mgmt.enabled','true',0,1700000000,1700000000);
/*!40000 ALTER TABLE `parameter_plan` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `parameters`
--

DROP TABLE IF EXISTS `parameters`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `parameters` (
  `id` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `dataType` enum('boolean','int','float','string','stringArray','intArray','floatArray','mixedArray','JSON') COLLATE utf8mb4_unicode_ci NOT NULL,
  `availableValues` json DEFAULT NULL,
  `defaultValue` json DEFAULT NULL,
  `title` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  PRIMARY KEY (`id`),
  KEY `parameters_datatype_index` (`dataType`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `parameters`
--

LOCK TABLES `parameters` WRITE;
/*!40000 ALTER TABLE `parameters` DISABLE KEYS */;
INSERT INTO `parameters` VALUES ('ADMIN_API_HOST','string',NULL,NULL,'Chat API Host','Chat API Host'),('agents.credits.included','int',NULL,NULL,'MAU Included','The number of monthly active users included.'),('agents.starter-credits.included','int',NULL,NULL,'MAU Included','The number of monthly active users included.'),('bots.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable bots feature.'),('calling.audio.enabled','boolean','[true, false]','true',NULL,'The flag to enable/disable audio calling features.'),('calling.audio.minutes','int',NULL,'1000000',NULL,'The number that indicates audio calling minutes. The value `0` indicates unlimited calling minutes.'),('calling.enabled','boolean','[true, false]','true',NULL,'The flag to enable/disable calling features.'),('calling.group.enabled','boolean','[true, false]','true',NULL,'The flag to enable/disable calling features for groups.'),('calling.group.size','int',NULL,'15',NULL,'The number of participants in a group call.'),('calling.groups.enabled','boolean','[true, false]','true',NULL,'The flag to enable/disable calling features for groups.'),('calling.livestream.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable livestream for a call.'),('calling.minutes','int',NULL,'1000000',NULL,'The number that indicates combined audio/video calling minutes. The value `0` indicates unlimited calling minutes.'),('calling.overage.enabled','boolean','[true, false]','true',NULL,'The flag to enable calling overages.'),('calling.recording.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable recording.'),('calling.screenshare.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable screenshare.'),('calling.video.enabled','boolean','[true, false]','true',NULL,'The flag to enable/disable video calling features.'),('calling.video.minutes','int',NULL,'1000000',NULL,'The number that indicates video calling minutes. The value `0` indicates unlimited calling minutes.'),('ccu','int',NULL,'50',NULL,'The number of allowed concurrent users. The value `0` indicates unlimited ccu.'),('compliance.ccpa.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable CCPA'),('compliance.enabled','boolean','[true, false]','true','Compliance','Enables compliances'),('compliance.gdpr.enabled','boolean','[true, false]','true','GDPR compliance','Enables GDPR compliance.'),('compliance.hippa-baa.enabled','boolean','[true, false]','true','HIPPA-BAA compliance','Enables HIPPA-BAA compliance.'),('compliance.pipeda.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable CCPA'),('compliance.soc2.enabled','boolean','[true, false]','true','SOC2 compliance','Enables SOC2 compliance.'),('core.advanced.search.accessible','boolean','[true, false]','false',NULL,'The flag to enable/disable Advanced search feature'),('core.advanced.search.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable Advanced search feature'),('core.call.enabled','boolean','[true, false]','true','Voice & Video Calling/Conferencing','Enables Voice & Video Calling/Conferencing'),('core.call.groups.audio.enabled','boolean','[true, false]','true','Group Audio call','Allows group audio call.'),('core.call.groups.video.enabled','boolean','[true, false]','true','Group Video call','Allows group video call.'),('core.call.live-streaming.enabled','boolean','[true, false]','true','Live Streaming','Enables Live streaming.'),('core.call.logs.enabled','boolean','[true, false]','true','Call logs','Access call logs and recording on the dashboard as well as automatically access and download them using APIs'),('core.call.one-on-one.audio.enabled','boolean','[true, false]','true','Audio call','Allows audio call.'),('core.call.one-on-one.video.enabled','boolean','[true, false]','true','Video call','Allows video call.'),('core.call.recording.enabled','boolean','[true, false]','true','Call recording','Enables call recording.'),('core.call.transcript.enabled','boolean','[true, false]','true','Transcripts','Enables option to provide transcripts'),('core.chat.conversation.mark-as-read.enabled','boolean','[true, false]','true','Ability to mark the entire conversation as read','Ability to mark the entire conversation as read'),('core.chat.enabled','boolean','[true, false]','true','Core Chat Features','Enables Core Chat Features'),('core.chat.groups.ban.enabled','boolean','[true, false]','true','Ability to Ban, unban or kick users from groups','Ability to Ban, unban or kick users from groups'),('core.chat.groups.enabled','boolean','[true, false]','true','Group Chat','Enables group chat.'),('core.chat.groups.kick.enabled','boolean','[true, false]','true','Ability to Ban, unban or kick users from groups','Ability to Ban, unban or kick users from groups'),('core.chat.groups.password.enabled','boolean','[true, false]','true','Password Protected Group for a Group Chat','Allows password protected groups for group chat.'),('core.chat.groups.private.enabled','boolean','[true, false]','true','Private Group for a Group Chat','Allows private groups for group chat.'),('core.chat.groups.public.enabled','boolean','[true, false]','true','Public Group for a Group Chat','Allows public groups for group chat.'),('core.chat.groups.search.enabled','boolean','[true, false]','true','Groups Search','Enables groups search.'),('core.chat.localization.enabled','boolean','[true, false]','true','Localize the app according to your language/country','Localize the app according to your language/country'),('core.chat.mentions-feed.enabled','boolean','[true, false]','true','Feed of all messages which have a mention including unread mentions','Feed of all messages which have a mention including unread mentions'),('core.chat.messages.custom.enabled','boolean','[true, false]','true','Custom Messages','Allows custom messages.'),('core.chat.messages.delete.enabled','boolean','[true, false]','true','Ability to edit or delete a message','Ability to edit or delete a message'),('core.chat.messages.edit.enabled','boolean','[true, false]','true','Ability to edit or delete a message','Ability to edit or delete a message'),('core.chat.messages.history.enabled','boolean','[true, false]','true','History messages','Allows fetching historical messages'),('core.chat.messages.hydrate-entities-latest.enabled','boolean',NULL,'false','Hydrate message entities','Hydrate message entities'),('core.chat.messages.mark-as-read.enabled','boolean','[true, false]','true','Ability to mark a conversation up to a message as read','Ability to mark a conversation up to a message as read'),('core.chat.messages.mark-as-unread.enabled','boolean','[true, false]','true','Mark as unread','Ability to mark all messages from a particular message as unread in a conversation or a thread'),('core.chat.messages.media.enabled','boolean','[true, false]','true','Multimedia Messages','Allows multimedia messages.'),('core.chat.messages.quoted-replies.enabled','boolean','[true, false]','true','Localize the app according to your language/country','Localize the app according to your language/country'),('core.chat.messages.receipts.enabled','boolean','[true, false]','true','Message Delivery/Read Receipts','Enables melivery/read receipts for a message.'),('core.chat.messages.replies.enabled','boolean','[true, false]','true','Replies to a Message','Allows reeplying to a message.'),('core.chat.messages.search.enabled','boolean','[true, false]','true','Messages Search','Enables messages search.'),('core.chat.messages.threads.enabled','boolean','[true, false]','true','User to User Chat','Enables threaded chats.'),('core.chat.messages.unread-count.enabled','boolean','[true, false]','true','Unread Message Count','Allows unread count to be visible in messages.'),('core.chat.one-on-one.enabled','boolean','[true, false]','true','User to User Chat','Enables user to user chat.'),('core.chat.reactions-feed.enabled','boolean','[true, false]','true','Reactions feed','Feed of all reactions applied on the logged in users\'s messages'),('core.chat.tags.conversations.enabled','boolean','[true, false]','true','Tag conversations with custom identifiers to search them faster or display by different categories','Tag conversations with custom identifiers to search them faster or display by different categories'),('core.chat.tags.groups.enabled','boolean','[true, false]','true','Tag users and groups with custom identifiers to search them faster or display by different categories','Tag users and groups with custom identifiers to search them faster or display by different categories'),('core.chat.tags.users.enabled','boolean','[true, false]','true','Tag users and groups with custom identifiers to search them faster or display by different categories','Tag users and groups with custom identifiers to search them faster or display by different categories'),('core.chat.threads-feed.enabled','boolean','[true, false]','true','Threads feed','Feed of all threads with their latest message and unread counts per thread'),('core.chat.typing-indicator.enabled','boolean','[true, false]','true','Typing Indicator','Enables typing indicators.'),('core.chat.unread-mentions-count.enabled','boolean','[true, false]','true','Total unread mentions across all conversations','Total unread mentions across all conversations'),('core.chat.unread-message-count.accessible','boolean','[true, false]','false',NULL,'The flag to enable/disable new unread message count feature.'),('core.chat.unread-message-count.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable new unread message count feature.'),('core.chat.unread-thread-count.enabled','boolean','[true, false]','true','Count of number of unread threads across conversations','Count of number of unread threads across conversations'),('core.chat.users.block.enabled','boolean','[true, false]','true','Ability for users to block other users','Ability for users to block other users'),('core.chat.users.list.enabled','boolean','[true, false]','true','User Listing','Allows users to be listed via SDKs.'),('core.chat.users.presence.enabled','boolean','[true, false]','true','User Presence','Enables user presence.'),('core.chat.users.search.enabled','boolean','[true, false]','true','Users Search','Enables users search.'),('core.chat.voice-notes.enabled','boolean','[true, false]','false','Voice notes','Allows voice notes.'),('core.conversations.advanced.search.accessible','boolean','[true, false]','false',NULL,'The flag to enable/disable Advanced search feature'),('core.conversations.advanced.search.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable Advanced search feature'),('core.conversations.updateOnCallActivity','boolean','[true, false]','false','Update conversation on custom message','Update conversation on custom message'),('core.conversations.updateOnCustomMessage','boolean','[true, false]','true','Update conversation on custom message','Update conversation on custom message'),('core.conversations.updateOnGroupActions','boolean','[true, false]','true','Update conversation on custom message','Update conversation on custom message'),('core.conversations.updateOnMessageActions','boolean','[true, false]','false','Update conversation on custom message','Update conversation on custom message'),('core.conversations.updateOnReplies','boolean','[true, false]','true','Update conversation on custom message','Update conversation on custom message'),('core.messages.advanced.search.accessible','boolean','[true, false]','false',NULL,'The flag to enable/disable Advanced search feature'),('core.messages.advanced.search.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable Advanced search feature'),('core.messages.decrementReplyCountOnDelete','boolean','[true, false]','false','Update conversation on custom message','Update conversation on custom message'),('core.moderation.advanced.accessible','boolean','[true, false]','false','Advanced Moderation','Advanced Moderation'),('core.moderation.advanced.enabled','boolean','[true, false]','false','Advanced Moderation','Advanced Moderation'),('core.notifications.email.accessible','boolean','[true, false]','true','Email Notification Accessible','Email Notification'),('core.notifications.email.advanced.enabled','boolean','[true, false]','false','Email Notification Enabled','Email Notification'),('core.notifications.email.advanced.included','stringArray','\"[feature.enable\\\"\"','\"providers.add\"','preferences','templates]\"'),('core.notifications.email.enabled','boolean','[true, false]','false','Email Notification Enabled','Email Notification'),('core.notifications.logs.accessible','boolean','[true, false]','false','Notification logging','The feature is accessible in the advanced plan.'),('core.notifications.logs.disableAfterDays','int',NULL,'7','Default: 7. Can be changed.','Default: 7. Can be changed.'),('core.notifications.logs.disabledAtMS','int',NULL,'7','Timestamp when the logging feature was disabled either by the customer or programmatically.','Timestamp when the logging feature was disabled either by the customer or programmatically.'),('core.notifications.logs.enabledAtMS','int',NULL,'7','Timestamp when the logging feature was enabled. Either from the dashboard or from the API explorer.','Timestamp when the logging feature was enabled. Either from the dashboard or from the API explorer.'),('core.notifications.logs.retentionDays','int',NULL,'7','Default: 7. Can be changed.','Default: 7. Can be changed.'),('core.notifications.push.accessible','boolean','[true, false]','true','Core push notification','Core push notification'),('core.notifications.push.advanced.enabled','boolean','[true, false]','false','Core notification','Core notification'),('core.notifications.push.advanced.included','stringArray','\"[preferences\\\"\"','\"templates\"','providers.multiple]\"','NULL'),('core.notifications.push.enabled','boolean','[true, false]','false','Core notification','Core notification'),('core.notifications.sms.accessible','boolean','[true, false]','true','Email Notification Enabled','Email Notification'),('core.notifications.sms.advanced.enabled','boolean','[true, false]','false','Email Notification Enabled','Email Notification'),('core.notifications.sms.advanced.included','stringArray','\"[feature.enable\\\"\"','\"providers.add\"','preferences','templates]\"'),('core.notifications.sms.enabled','boolean','[true, false]','false','Email Notification Enabled','Email Notification'),('core.notifications.unreadBadgeCount.accessible','boolean','[true, false]','false','SMS notification','Enables SMS notification.'),('core.notifications.unreadBadgeCount.enabled','boolean','[true, false]','false','Email notification','Enables Email notification.'),('core.threads.decrementReplyCountOnDelete','boolean','[true, false]','false','Update conversation on custom message','Update conversation on custom message'),('core.threads.updateOnMessageActions','boolean','[true, false]','false','Update conversation on custom message','Update conversation on custom message'),('core.websocket.custom.enabled','boolean','[true, false]','true','Custom Websocket','Control the presence of your users by taking full control of the websockets'),('custom.plan.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable custom plan'),('customer_notification_thresholds','JSON',NULL,NULL,NULL,'Customer Notification Threshold'),('customersupport.chatwoot.enabled','boolean','[true, false]','false','Chatwoot','Connect and exchange messages between CometChat and Chatwoot'),('customersupport.intercom.enabled','boolean','[true, false]','true','Intercom','Connect and exchange messages between CometChat and Intercom'),('customersupport.zapier.enabled','boolean','[true, false]','true','Zapier','Connect and exchange messages between CometChat and Intercom'),('customTab','JSON',NULL,NULL,'Custom Tab','Custom Tab'),('dashboard.analytics.advanced.enabled','boolean','[true, false]','false','Advanced Analytics','Enables Advanced Analytics.'),('dashboard.analytics.insights.url','string',NULL,'\"https://1xin24420h.execute-api.eu-west-1.amazonaws.com/test/anonymous-embed-sample?mode=getUrl&appId=%s\\\"\\\"\"','Dashboard insights URL','Dashboard Insights URL'),('dashboard.analytics.usage.enabled','boolean','[true, false]','true','Analytics Usage','Enables Analytics Usage.'),('dashboard.audit.logs.enabled','boolean','[true, false]','true','Audit Logs','Enables Audit Logs.'),('dashboard.chat-api-host','string',NULL,NULL,'Chat API Host','Chat API Host'),('dashboard.chat-api-version','string',NULL,NULL,'Chat API Version','Chat API Version'),('dashboard.customTabs','stringArray',NULL,NULL,'Custom Tab in Dashboard','Custom Tab in Dashboard'),('dashboard.enabled','boolean','[true, false]','true','Dashboard Settings','Enables dashboard settings'),('dashboard.groups.management.enabled','boolean','[true, false]','true','Groups Management','Enables Groups Management.'),('dashboard.insights.audio.enabled','boolean','[true, false]','true','Audio Insights','Data insights for total call duration, concurrent calls heatmap, statistics of number of users in a call or call duration'),('dashboard.insights.groups.enabled','boolean','[true, false]','true','Group Insights','Data insights for top users and groups, CCU heatmap, online frequency distribution, user engagement post signup, user retention graph, user abandon analysis , new signups data.'),('dashboard.insights.messages.enabled','boolean','[true, false]','true','Message Insights','Data insights for messaging activity, messages send/delivered/read heatmaps, text messages exchanged prior to sending images or media, activity by user or group conversations, conversations declining or nearing chrun, average messages exchanged, message types being sent, conversations resulting in a call, number of words or characters per message, number of messages resulting in a thread.'),('dashboard.insights.users.enabled','boolean','[true, false]','true','User Insights','Data insights for top users and groups, CCU heatmap, online frequency distribution, user engagement post signup, user retention graph, user abandon analysis , new signups data.'),('dashboard.insights.video.enabled','boolean','[true, false]','true','Video Insights','Data insights for total call duration, concurrent calls heatmap, statistics of number of users in a call or call duration'),('dashboard.messages.moderation.enabled','boolean','[true, false]','true','Messages Moderation','Enables Messages Moderation.'),('dashboard.section.plan.includes','JSON',NULL,NULL,NULL,'Plan include section of dashboard'),('dashboard.settings.included','stringArray','\"[core.conversations.updateOnGroupActions\\\"\"','\"core.conversations.updateOnReplies\"','core.threads.updateOnMessageActions','core.conversations.updateOnCallActivity'),('dashboard.sso.enabled','boolean','[true, false]','true','SSO','Enables SSO.'),('dashboard.team.management.enabled','boolean','[true, false]','true','Team Management','Enables Team Management.'),('dashboard.users.management.enabled','boolean','[true, false]','true','Users Management','Enables Users Management.'),('deployment.enabled','boolean','[true, false]','true','Deployment','Enables deployment options'),('deployment.on-premise.enabled','boolean','[true, false]','true','On Premise Deployment','Enables On Premise Deployment.'),('deployment.private-cloud.enabled','boolean','[true, false]','true','Private Cloud Deployment','Enables Private Cloud Deployment.'),('deployment.shared-cloud.enabled','boolean','[true, false]','true','Shared Cloud Deployment','Enables Shared Cloud Deployment.'),('disableWebsocketConnection','boolean','[true, false]','false','Disable Websocket Connection','Disable Websocket Connection'),('extension_avatar','string',NULL,'\"features.ux.avatar.enabled\\\"\\\"\"','Avatar','Upload an avatar image for your profile'),('extension_broadcast','string',NULL,'\"features.ue.video-broadcasting.enabled\\\"\\\"\"','Video Broadcasting','Real-time live video streaming & broadcasting to 1000s of viewers'),('extension_chatwoot','string',NULL,'\"customersupport.chatwoot.enabled\\\"\\\"\"','Chatwoot','Connect and exchange messages between CometChat and Chatwoot'),('extension_data-masking','string',NULL,'\"features.moderation.data-masking.enabled\\\"\\\"\"','Data Masking','Hide phone numbers, email addresses and other sensitive information in messages.'),('extension_disappearing-messages','string',NULL,'\"features.security.disappearing-messages.enabled\\\"\\\"\"','Disappearing messages','Delete messages automatically after a certain time'),('extension_document','string',NULL,'\"features.collaboration.document.enabled\\\"\\\"\"','Collaborative document','Allows you create and share documents for collaboration'),('extension_e2ee','string',NULL,'\"security.end-to-end-encryption.enabled\\\"\\\"\"','End-to-end Encryption','Ensure only your users can read what is sent and nobody in between'),('extension_email-notification','string',NULL,'\"features.notifications.email-notification.enabled\\\"\\\"\"','Email Notification','Notify users via email for unread messages.'),('extension_email-replies','string',NULL,'\"features.ue.email-replies.enabled\\\"\\\"\"','Email replies','Reply to texts directly via emails'),('extension_emojis','string',NULL,'\"features.ue.emojis.enabled\\\"\\\"\"','Emojis','Emojis for web'),('extension_gifs-gfycat','string',NULL,'\"features.ue.gfycat.enabled\\\"\\\"\"','Gfycat','Get the best GIFS for all your conversations'),('extension_gifs-giphy','string',NULL,'\"features.ue.giphy.enabled\\\"\\\"\"','Giphy','Be Animated'),('extension_gifs-tenor','string',NULL,'\"features.ue.tenor.enabled\\\"\\\"\"','Tenor','Bring personality to your conversations'),('extension_human-moderation','string',NULL,'\"features.moderation.inflight-message-moderation.enabled\\\"\\\"\"','In-flight Message Moderation','Manually moderate content to ensure a safe messaging environment.'),('extension_image-moderation','string',NULL,'\"features.moderation.image-moderation.enabled\\\"\\\"\"','Image Moderation','AI-powered image moderation to detect unsafe content.'),('extension_intercom','string',NULL,'\"customersupport.intercom.enabled\\\"\\\"\"','Intercom','Connect and exchange messages between CometChat and Intercom'),('extension_link-preview','string',NULL,'\"features.ux.link-preview.enabled\\\"\\\"\"','Link Preview','Generate meta description for URLs.'),('extension_live-migration-applozic','string',NULL,'\"features.lm.live-migration-applozic.enabled\\\"\\\"\"','Applozic','Real-time chat data sync between CometChat & Applozic'),('extension_mentions','string',NULL,'\"features.ue.mentions.enabled\\\"\\\"\"','Mentions','Mention users in conversations'),('extension_message-shortcuts','string',NULL,'\"features.ux.message-shortcuts.enabled\\\"\\\"\"','Message shortcuts','Send pre-defined messages using shortcuts e.g. !hello'),('extension_message-translation','string',NULL,'\"features.ue.message-translation.enabled\\\"\\\"\"','Message Translation','Translate text messages in different languages on-the-fly.'),('extension_pin-message','string',NULL,'\"features.ux.messages.pinned.enabled\\\"\\\"\"','Pin Message','Pin message for all the users in a conversation.'),('extension_polls','string',NULL,'\"features.ue.polls.enabled\\\"\\\"\"','Polls','Polls to quickly ask for opinions in chats'),('extension_profanity-filter','string',NULL,'\"features.moderation.profanity-filter.enabled\\\"\\\"\"','Profanity Filter','Detect and censor profanity in messages.'),('extension_push-notification','string',NULL,'\"features.notifications.push-notification.enabled\\\"\\\"\"','Push Notification','Notify users via push notifications.'),('extension_reactions','string',NULL,'\"features.ue.reactions.enabled\\\"\\\"\"','Reactions','React to an individual message with a specific emotion quickly.'),('extension_reminders','string',NULL,'\"features.ue.reminders.enabled\\\"\\\"\"','Reminders','Create reminders for messages or anything else'),('extension_report-message','string',NULL,'\"features.moderation.report-message.enabled\\\"\\\"\"','Report Message','Enable users to report messages in chat'),('extension_report-user','string',NULL,'\"features.moderation.report-user.enabled\\\"\\\"\"','Report User','Enable users to report other users'),('extension_rich-media','string',NULL,'\"features.ux.rich-media-preview.enabled\\\"\\\"\"','Rich Media','Generate rich media previews for all popular sites'),('extension_save-message','string',NULL,'\"features.ux.messages.saved.enabled\\\"\\\"\"','Save Message','Save messages in one-on-one and group conversations for only for a user'),('extension_sentiment-analysis','string',NULL,'\"features.moderation.sentiment-analysis.enabled\\\"\\\"\"','Sentiment Analysis','AI-powered sentiment analysis for messages.'),('extension_slow-mode','string',NULL,'\"features.moderation.slow-mode.enabled\\\"\\\"\"','Slow Mode','Slow down messages to make them legible!'),('extension_smart-reply','string',NULL,'\"features.ue.smart-replies.enabled\\\"\\\"\"','Smart Replies','Suggest ML-powered ready replies for messages.'),('extension_sms-notification','string',NULL,'\"features.notifications.sms-notification.enabled\\\"\\\"\"','SMS notification','Notify users via sms for unread messages.'),('extension_stickers','string',NULL,'\"features.ue.stickers.enabled\\\"\\\"\"','Stickers','Send & manage stickers'),('extension_stickers-stipop','string',NULL,'\"features.ue.stipop.enabled\\\"\\\"\"','Stipop','Be Animated'),('extension_thumbnail-generation','string',NULL,'\"features.ux.thumbnail-generation.enabled\\\"\\\"\"','Thumbnail generation','Generate thumbnails for images and videos.'),('extension_url-shortener-bitly','string',NULL,'\"features.ux.url-shortener-bitly.enabled\\\"\\\"\"','Shorten your unwieldly links into more manageable and useable URLs.','Bitly helps you convert your long website links into short, manageable URLs that are reliable, secure and never expire.'),('extension_url-shortener-tinyurl','string',NULL,'\"features.ux.url-shortener.enabled\\\"\\\"\"','Shorten your unwieldly links into more manageable and useable URLs.','TinyURL helps you convert your long website links into short, manageable URLs that are reliable, secure and never expire.'),('extension_virus-malware-scanner','string',NULL,'\"features.moderation.malware-scanner.enabled\\\"\\\"\"','Virus Malware Scanner','Scan user uploaded files for viruses, malware, phishing, spam and other malicious content'),('extension_voice-transcription','string',NULL,'\"features.ux.voice-transcription.enabled\\\"\\\"\"','Voice Transcription','Transcribe Audio Messages Using Powerful Neural Network Models.'),('extension_whiteboard','string',NULL,'\"features.collaboration.whiteboard.enabled\\\"\\\"\"','Collaborative whiteboard','Allows you create and share whiteboards for collaboration'),('extension_widget','string',NULL,'\"integrations.chat-widget.enabled\\\"\\\"\"','Chat Widget','Drag-n-drop chat plugin for your website'),('extension_xss-filter','string',NULL,'\"features.moderation.xss-filter.enabled\\\"\\\"\"','XSS Filter','Sanitize messages to prevent a cross-site scripting attack'),('extensions.domain','stringArray','\"[cometchat.io\\\"\"','\"cometchat-staging.com\"','cc-cluster-2.io]\"','cometchat.io\"\"'),('features.advanced-plus.webhooks.accessible','boolean','[true, false]','true','Webhooks & Bots','Enables webhooks and bots'),('features.advanced-plus.webhooks.enabled','boolean','[true, false]','false','Advanced Webhooks','Advanced Webhooks'),('features.advanced-plus.webhooks.included','stringArray','\"[recording_generated\\\"\"','\"user_connection_status_changed\"','message_reaction_added','message_reaction_removed'),('features.advanced.moderation.accessible','boolean','[true, false]','false','Advanced Moderation','Advanced Moderation'),('features.advanced.moderation.enabled','boolean','[true, false]','false','Advanced Moderation','Advanced Moderation'),('features.advanced.webhooks.accessible','boolean','[true, false]','true','Webhooks & Bots','Enables webhooks and bots'),('features.advanced.webhooks.enabled','boolean','[true, false]','false','Advanced Webhooks','Advanced Webhooks'),('features.advanced.webhooks.included','stringArray','\"[call_started\\\"\"','\"meeting_started\"','call_participant_joined','call_initiated'),('features.ai.accessible','boolean','[true, false]','false',NULL,'Allows access to AI features.'),('features.ai.assist-bot.accessible','boolean','[true, false]','false',NULL,'Allows access to AI - Assist Bot feature.'),('features.ai.assist-bot.enabled','boolean','[true, false]','false',NULL,'Enables/Disables AI - Assist Bot feature.'),('features.ai.bots.accessible','boolean','[true, false]','false',NULL,'Allows access to AI - Bots feature.'),('features.ai.bots.enabled','boolean','[true, false]','false',NULL,'Enables/Disables AI - Bots feature.'),('features.ai.conversation-starter.accessible','boolean','[true, false]','false',NULL,'Allows access to AI - Conversation Starter feature.'),('features.ai.conversation-starter.enabled','boolean','[true, false]','false',NULL,'Enables/Disables AI - Conversation Starter feature.'),('features.ai.conversation-summary.accessible','boolean','[true, false]','false',NULL,'Allows access to AI - Conversation Summary feature.'),('features.ai.conversation-summary.enabled','boolean','[true, false]','false',NULL,'Enables/Disables AI - Conversation Summary feature.'),('features.ai.enabled','boolean','[true, false]','false',NULL,'Enables/Disables AI features.'),('features.ai.grammar-tone-helper.enabled','boolean','[true, false]','true','Grammar & tone helper','Use AI to correct grammer and fix tone'),('features.ai.personalities.accessible','boolean','[true, false]','false',NULL,'Allows access to AI - Smart Replies feature.'),('features.ai.personalities.enabled','boolean','[true, false]','false',NULL,'Enables/Disables AI -  Smart Replies feature.'),('features.ai.smart-replies.accessible','boolean','[true, false]','false',NULL,'Allows access to AI - Smart Replies feature.'),('features.ai.smart-replies.enabled','boolean','[true, false]','false',NULL,'Enables/Disables AI -  Smart Replies feature.'),('features.basic.webhooks.accessible','boolean','[true, false]','true','Webhooks & Bots','Enables webhooks and bots'),('features.basic.webhooks.enabled','boolean','[true, false]','false','Advanced Webhooks','Advanced Webhooks'),('features.basic.webhooks.included','stringArray','\"[message_sent\\\"\"','\"message_edited\"','message_deleted','after_feed_item_sent'),('features.bots.enabled','boolean','[true, false]','true','Bots','Enables Bots.'),('features.calls.webhooks.accessible','boolean','[true, false]','true','Calling webhooks','Webhhok events for calls or meetings being initiated, started, participant joining and leaving, calls or meetings ended'),('features.calls.webhooks.enabled','boolean','[true, false]','true','Calling webhooks','Webhhok events for calls or meetings being initiated, started, participant joining and leaving, calls or meetings ended'),('features.calls.webhooks.included','stringArray','\"[call_started\\\"\"','\"meeting_started\"','call_participant_joined','call_initiated'),('features.campaigns.accessible','boolean','[true, false]','true','Campaigns Accessible','The flag to enable/disable Campaigns Accessible feature.'),('features.campaigns.enabled','boolean','[true, false]','true','Campaigns Enabled','The flag to enable/disable Campaigns feature.'),('features.collaboration.document.enabled','boolean','[true, false]','true','Document','Enables collaborative document.'),('features.collaboration.enabled','boolean','[true, false]','true','Collaboration','Enables Collaboration Features'),('features.collaboration.whiteboard.enabled','boolean','[true, false]','true','Whiteboard','Enables collaborative whiteboard.'),('features.data.cross-platform-sync.enabled','boolean','[true, false]','true','Cross Platform Sync','Enables Cross Platform Sync.'),('features.data.enabled','boolean','[true, false]','true','Data Features','Enables data features'),('features.data.export.enabled','boolean','[true, false]','true','Data Export','Allows Data Export.'),('features.data.global-cdn.enabled','boolean','[true, false]','true','Global CDN','Allows Global CDN.'),('features.data.import.enabled','boolean','[true, false]','true','Data Import','Allows Data Import.'),('features.data.live-migration.enabled','boolean','[true, false]','true','Live Migration','Allows Live Migration.'),('features.data.multi-device-support.enabled','boolean','[true, false]','true','Multi Device Support','Enables Multi Device Support.'),('features.data.remote-sync.enabled','boolean','[true, false]','true','Remote Sync','Allows Remote Sync.'),('features.groups.webhooks.accessible','boolean','[true, false]','true','Groups webhooks','Webhook events for group creation or deletion, members joined, added, left, banned, unbanned, removed, group being updated or ownership transferred.'),('features.groups.webhooks.enabled','boolean','[true, false]','true','Groups webhooks','Webhook events for group creation or deletion, members joined, added, left, banned, unbanned, removed, group being updated or ownership transferred.'),('features.groups.webhooks.included','stringArray','\"[group_created\\\"\"','\"group_updated\"','group_deleted','group_member_joined'),('features.interactive.card-message.enabled','boolean','[true, false]','true','Interactive card message','Send a card with options to select from (eg. RSVP yes/no quesionarie)'),('features.interactive.custom-message.enabled','boolean','[true, false]','true','Interactive custom message','Share custom interactive messages as per your use case and workflow'),('features.interactive.form-message.enabled','boolean','[true, false]','true','Interactive form message','Send a web like form with an action URL via messaging, and which can be filled up in chat.'),('features.interactive.location-sharing.enabled','boolean','[true, false]','true','Ability to share location','Ability to share location'),('features.interactive.meeting-scheduler.enabled','boolean','[true, false]','true','Interactive meeting scheduler message','Send an interactive timeslot selector from a list of time options or via a ICS file'),('features.lm.live-migration-applozic.enabled','boolean','[true, false]','true','Applozic','Real-time chat data sync between CometChat & Applozic'),('features.messages.webhooks.accessible','boolean','[true, false]','true','Messages webhooks','Webhook events for messages sent, edited or deleted'),('features.messages.webhooks.enabled','boolean','[true, false]','true','Messages webhooks','Webhook events for messages sent, edited or deleted'),('features.messages.webhooks.included','stringArray','\"[message_sent\\\"\"','\"message_edited\"','message_deleted]\"','NULL'),('features.moderation.advanced-plus.rules.enabled','boolean','[true, false]','false','Advanced Moderation','Advanced Moderation'),('features.moderation.advanced-plus.rules.included','stringArray','\"[sentence-similarity\\\"\"','\"explicit-or-sexual-content\"','fraud-or-scam-indicators','graphic-violence-or-gore'),('features.moderation.advanced.accessible','boolean','[true, false]','false','Advanced Moderation','Advanced Moderation'),('features.moderation.advanced.conditions.included','int',NULL,'10','Advanced Moderation','Advanced Moderation'),('features.moderation.advanced.enabled','boolean','[true, false]','false','Advanced Moderation','Advanced Moderation'),('features.moderation.advanced.filters.enabled','boolean','[true, false]','false','Advanced Moderation','Advanced Moderation'),('features.moderation.advanced.filters.included','stringArray','\"[sender\\\"\"','\"receiver]\\\"\"',NULL,'Advanced Moderation'),('features.moderation.advanced.keywords.enabled','boolean','[true, false]','false','Advanced Keywords','Advanced Keywords'),('features.moderation.advanced.keywords.included','stringArray','\"[platform-circumvention\\\"]\\\"\"',NULL,'Advanced Moderation','Advanced Moderation'),('features.moderation.advanced.rule-creation.enabled','boolean','[true, false]','false','Advanced Moderation','Advanced Moderation'),('features.moderation.advanced.rules.enabled','boolean','[true, false]','false','Advanced Rules','Advanced Rules'),('features.moderation.advanced.rules.included','stringArray','\"[image-moderation\\\"\"','\"video-moderation\"','toxicity','sentiment-analysis]\"'),('features.moderation.advanced.sentences.included','int',NULL,'5','Advanced Moderation','Advanced Moderation'),('features.moderation.basic.filters.enabled','boolean','[true, false]','false','Basic Filters','Basic Filters'),('features.moderation.basic.filters.included','stringArray','[]',NULL,'Basic Filters','Basic Filters'),('features.moderation.basic.keywords.enabled','boolean','[true, false]','false','Advanced Keywords','Advanced Keywords'),('features.moderation.basic.keywords.included','stringArray','\"[profanity-list\\\"]\\\"\"',NULL,'Advanced Moderation','Advanced Moderation'),('features.moderation.basic.rules.enabled','boolean','[true, false]','false','Filters Moderation','Filters Moderation'),('features.moderation.basic.rules.included','stringArray','\"[text-profanity-filter\\\"\"','\"contact_details_filter\"','email_filter]\"','NULL'),('features.moderation.data-masking.enabled','boolean','[true, false]','true','Data Masking','Enables Data Masking.'),('features.moderation.enabled','boolean','[true, false]','true','Moderation','Enables moderation features.'),('features.moderation.groups.ban.enabled','boolean','[true, false]','true','Ban ability in groups','Enables ability to ban members.'),('features.moderation.groups.kick.enabled','boolean','[true, false]','true','Kick ability in groups','Enables ability to kick members.'),('features.moderation.groups.moderators.enabled','boolean','[true, false]','true','Group moderation','Enables Group moderation.'),('features.moderation.image-moderation.enabled','boolean','[true, false]','true','Image moderation','Enables Image moderation.'),('features.moderation.independent.accessible','boolean','[true, false]','false','Independent Moderation','Independent Moderation'),('features.moderation.inflight-message-moderation.enabled','boolean','[true, false]','true','Inflight Message moderation','Enables Inflight Message moderation.'),('features.moderation.keywords.limit','int',NULL,'5','Advanced Moderation','Advanced Moderation'),('features.moderation.keywords.sentences.limit','int',NULL,'5','Advanced Moderation','Advanced Moderation'),('features.moderation.live-message-moderation.enabled','boolean','[true, false]','true','View in-flight and historical messages and take actions on them on the admin dashboard','View in-flight and historical messages and take actions on them on the admin dashboard'),('features.moderation.malware-scanner.enabled','boolean','[true, false]','true','Malware Scanner','Enables Malware Scanner.'),('features.moderation.profanity-filter.enabled','boolean','[true, false]','true','Profanity Filter','Enables Profanity filter.'),('features.moderation.report-message.enabled','boolean','[true, false]','true','Report Message','Enable users to report messages in chat'),('features.moderation.report-user.enabled','boolean','[true, false]','true','Report User','Enable users to report other users'),('features.moderation.rules.conditions.limit','int',NULL,'5','Advanced Moderation','Advanced Moderation'),('features.moderation.rules.filters.limit','int',NULL,'5','Advanced Moderation','Advanced Moderation'),('features.moderation.rules.limit','int',NULL,'5','Advanced Moderation','Advanced Moderation'),('features.moderation.sentiment-analysis.enabled','boolean','[true, false]','true','Sentiment Analysis','Enables Sentiment Analysis.'),('features.moderation.slow-mode.enabled','boolean','[true, false]','true','Slow Mode','Slow down messages to make them legible!'),('features.moderation.users.block.enabled','boolean','[true, false]','true','User-to-user Blocking','Enables user-to-user blocking.'),('features.moderation.xss-filter.enabled','boolean','[true, false]','true','XSS Filter','Enables XSS filter.'),('features.notifications.email-notification.enabled','boolean','[true, false]','true','Email notification','Enables Email notification.'),('features.notifications.enabled','boolean','[true, false]','true','Notifications','Enables Notification Features.'),('features.notifications.push-notification.enabled','boolean','[true, false]','true','Push notification','Enables Push notification.'),('features.notifications.sms-notification.enabled','boolean','[true, false]','true','SMS notification','Enables SMS notification.'),('features.notifications.whatsapp.enabled','boolean','[true, false]','true','Ability to Ban, unban or kick users from groups','Ability to Ban, unban or kick users from groups'),('features.posthog_usage_tracking.enabled','boolean',NULL,'false','Post hog usage tracking','Post hog usage tracking'),('features.rbac.accessible','boolean',NULL,'false','RBAC feature accessibility','RBAC feature accessibility'),('features.rbac.enabled','boolean',NULL,'false','RBAC feature accessibility','RBAC feature accessibility'),('features.security.disappearing-messages.enabled','boolean','[true, false]','true','Disappearing messages','Delete messages automatically after a certain time'),('features.security.file-access.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable secure file access feature'),('features.security.presigned-mode.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable secure file access feature'),('features.security.presigned-mode.max.ttl','int',NULL,'2592000',NULL,'The number of members in a team.'),('features.security.presigned-mode.min.ttl','int',NULL,'900',NULL,'The number of members in a team.'),('features.security.presigned-mode.ttl','int',NULL,'86400',NULL,'The number of members in a team.'),('features.ue.email-replies.enabled','boolean','[true, false]','true','Email replies','Enables email replies.'),('features.ue.emojis.enabled','boolean','[true, false]','true','Emojis','Enables Emojis.'),('features.ue.enabled','boolean','[true, false]','true','User Engagement','Enables user engagement features'),('features.ue.gfycat.enabled','boolean','[true, false]','true','Gfycat','Enables Gfycat'),('features.ue.giphy.enabled','boolean','[true, false]','true','Giphy','Enabled Giphy.'),('features.ue.live-reactions.enabled','boolean','[true, false]','true','Live Reactions','Enables Live Reactions.'),('features.ue.mentions.enabled','boolean','[true, false]','true','Mentions','Enables Mentions.'),('features.ue.message-translation.enabled','boolean','[true, false]','true','Message Translation','Enables Message Translation.'),('features.ue.polls.enabled','boolean','[true, false]','true','Polls','Enables polls.'),('features.ue.reactions.enabled','boolean','[true, false]','true','Reactions','Enables Reactions.'),('features.ue.reminders.enabled','boolean','[true, false]','true','Reminders','Create reminders for messages or anything else'),('features.ue.slow-mode.enabled','boolean','[true, false]','true','Prevent spamming by restricting users from sending a lot of messages in a short time interval','Prevent spamming by restricting users from sending a lot of messages in a short time interval'),('features.ue.smart-replies.enabled','boolean','[true, false]','true','Smart replies','Enables smart replies.'),('features.ue.sms-replies.enabled','boolean','[true, false]','true','Ability to Ban, unban or kick users from groups','Ability to Ban, unban or kick users from groups'),('features.ue.stickers.enabled','boolean','[true, false]','true','Stickers','Enables Stickers.'),('features.ue.stipop.enabled','boolean','[true, false]','true','Stipop','Enables Stipop'),('features.ue.tenor.enabled','boolean','[true, false]','true','Tenor','Enabled Tenor.'),('features.ue.video-broadcasting.enabled','boolean','[true, false]','true','Video Broadcasting','Real-time live video streaming & broadcasting to 1000s of viewers'),('features.usage_notifications.enabled.global','boolean',NULL,'false','Controls whether the entire usage notification system is active for all apps.','Controls whether the entire usage notification system is active for all apps.'),('features.usage_notifications.external_email_enabled','boolean',NULL,'false','Controls sending external customer emails','Controls sending external customer emails'),('features.usage_notifications.internal_eod_report_enabled','boolean',NULL,'false','Controls sending internal end-of-day reports','Controls sending internal end-of-day reports'),('features.users.webhooks.accessible','boolean','[true, false]','true','Users webhooks','Webhook events for users blocked or unblocked by other users'),('features.users.webhooks.enabled','boolean','[true, false]','true','Users webhooks','Webhook events for users blocked or unblocked by other users'),('features.users.webhooks.included','stringArray','\"[user_blocked\\\"\"','\"user_unblocked]\\\"\"',NULL,'User Webhooks'),('features.ux.avatar.enabled','boolean','[true, false]','true','Avatar','Upload an avatar image for your profile'),('features.ux.bookmark-message.enabled','boolean','[true, false]','true','Save a message for a particular user for its quick retrieval','Save a message for a particular user for its quick retrieval'),('features.ux.enabled','boolean','[true, false]','true','User Experience','Enables user experience features'),('features.ux.link-preview.enabled','boolean','[true, false]','true','Link preview','Enables Link preview'),('features.ux.message-shortcuts.enabled','boolean','[true, false]','true','Message shortcuts','Send pre-defined messages using shortcuts e.g. !hello'),('features.ux.messages.pinned.enabled','boolean','[true, false]','true','Pinned messages','Allows messages to be pinned.'),('features.ux.messages.saved.enabled','boolean','[true, false]','true','Save Messages','Allows messages to be saved.'),('features.ux.rich-media-preview.enabled','boolean','[true, false]','true','Rich Media Preview','Enables Rich Media Preview.'),('features.ux.thumbnail-generation.enabled','boolean','[true, false]','true','Thumbnail Generation','Enables Thumbnail generation'),('features.ux.url-shortener-bitly.enabled','boolean','[true, false]','false','Shorten your unwieldly links into more manageable and useable URLs.','Bitly helps you convert your long website links into short, manageable URLs that are reliable, secure and never expire.'),('features.ux.url-shortener.enabled','boolean','[true, false]','false','Shorten your unwieldly links into more manageable and useable URLs.','TinyURL helps you convert your long website links into short, manageable URLs that are reliable, secure and never expire.'),('features.ux.voice-transcription.enabled','boolean','[true, false]','true','Voice transcription','Enables Voice transcription.'),('features.visual-builder.accessible','boolean','[true, false]','true','Advanced Moderation','Advanced Moderation'),('features.visual-builder.enabled','boolean','[true, false]','true','Webhooks & Bots','Enables webhooks and bots'),('features.webhooks.accessible','boolean','[true, false]','true','Webhooks & Bots','Enables webhooks and bots'),('features.webhooks.enabled','boolean','[true, false]','true','Webhooks & Bots','Enables webhooks and bots'),('features.webhooks.in-flight.enabled','boolean','[true, false]','true','Webhooks Inflight','Enables Webhooks Inflight.'),('features.webhooks.post-event.enabled','boolean','[true, false]','true','Webhooks Post Event','Enables webhooks post event.'),('features.webhooks.standard.enabled','boolean','[true, false]','false','Standard Webhooks','Standard Webhooks'),('features.webhooks.standard.included','stringArray','\"[message_sent\\\"\"','\"message_edited\"','message_deleted','user_blocked'),('file.count.max','int',NULL,'10','Max number of files','Max number of files'),('file.size.max','int',NULL,'104857600','Max File Size','Max File Size'),('group.large.size','int',NULL,'300',NULL,'The number of members in a group.'),('groups.global-receipts.max','int',NULL,'300','Max File Size','Max File Size'),('groups.notifications.email.max','int',NULL,'30','Max File Size','Max File Size'),('groups.notifications.push.max','int',NULL,'1000','Max File Size','Max File Size'),('groups.notifications.sms.max','int',NULL,'30','Max File Size','Max File Size'),('groups.receipts-ack-by-all.max','int',NULL,'300','Max File Size','Max File Size'),('groups.receipts-db-write.max','int',NULL,'300','Max File Size','Max File Size'),('groups.receipts-real-time.max','int',NULL,'300','Max File Size','Max File Size'),('groups.size','int',NULL,'10000',NULL,'The number of members in a group.'),('groups.size.max','int',NULL,NULL,'Max Group Size','Maximum allowed members in a group.'),('groups.transient-message-real-time.max','int',NULL,'300','Max File Size','Max File Size'),('groups.typing-indicator-real-time.max','int',NULL,'300','Max File Size','Max File Size'),('groups.unread-count.max','int',NULL,'300','Max File Size','Max File Size'),('pushEventMetricsToKafka','boolean','[true, false]','false','Push Events metrics to kafka','Push Events metrics to kafka'),('ratelimit.app','int',NULL,'100000','App Operations','Rate Limit for App'),('ratelimit.core','int',NULL,'10000','Core Operations','Rate Limit for Core Operations'),('ratelimit.standard','int',NULL,'20000','Standard Operations','Rate Limit for Standard Operations'),('security.rbac.api.enabled','boolean','[true, false]','true','RBAC API','Enables RBAC API.'),('team-mgmt.enabled','boolean','[true, false]','false',NULL,'The flag to enable/disable team management feature.'),('team-mgmt.team.size','int',NULL,'10',NULL,'The number of members in a team.'),('telemetry.remotelogging','JSON',NULL,'\"{enabled\\\": true\"','categories: [\"websocket\"','network');
/*!40000 ALTER TABLE `parameters` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `regionmeta`
--

DROP TABLE IF EXISTS `regionmeta`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `regionmeta` (
  `regionId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `key` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `value` json NOT NULL,
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  `deletedAt` int DEFAULT NULL,
  PRIMARY KEY (`regionId`,`key`),
  KEY `regionmeta_createdat_index` (`createdAt`),
  KEY `regionmeta_updatedat_index` (`updatedAt`),
  KEY `regionmeta_deletedat_index` (`deletedAt`),
  CONSTRAINT `regionmeta_regionid_foreign` FOREIGN KEY (`regionId`) REFERENCES `regions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `regionmeta`
--

LOCK TABLES `regionmeta` WRITE;
/*!40000 ALTER TABLE `regionmeta` DISABLE KEYS */;
INSERT INTO `regionmeta` VALUES ('onprem','useSSL','1',1663248017,1663248017,NULL);
/*!40000 ALTER TABLE `regionmeta` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `regions`
--

DROP TABLE IF EXISTS `regions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `regions` (
  `id` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `isActive` tinyint(1) NOT NULL DEFAULT '0',
  `isPrivate` tinyint(1) NOT NULL DEFAULT '0',
  `isInvisible` tinyint(1) NOT NULL DEFAULT '0',
  `hash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `regions_name_index` (`name`),
  KEY `regions_hash_index` (`hash`),
  KEY `regions_isactive_index` (`isActive`),
  KEY `regions_isprivate_index` (`isPrivate`),
  KEY `regions_isinvisible_index` (`isInvisible`),
  KEY `regions_createdat_index` (`createdAt`),
  KEY `regions_updatedat_index` (`updatedAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `regions`
--

LOCK TABLES `regions` WRITE;
/*!40000 ALTER TABLE `regions` DISABLE KEYS */;
INSERT INTO `regions` VALUES ('onprem','On-Prem','On-prem single region',1,0,0,'16e8039b35',1781704675,1781704675),('us','On-Prem','On-prem single region',1,0,0,'e262093ee37fb72acb8c9b13ca86304c34fd8213',1781704675,1781704675);
/*!40000 ALTER TABLE `regions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `trigger_filters`
--

DROP TABLE IF EXISTS `trigger_filters`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `trigger_filters` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `triggerId` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `key` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  PRIMARY KEY (`id`),
  KEY `trigger_filters_triggerid_index` (`triggerId`),
  KEY `trigger_filters_key_index` (`key`),
  CONSTRAINT `trigger_filters_triggerid_foreign` FOREIGN KEY (`triggerId`) REFERENCES `hooks` (`hook`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=47 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `trigger_filters`
--

LOCK TABLES `trigger_filters` WRITE;
/*!40000 ALTER TABLE `trigger_filters` DISABLE KEYS */;
INSERT INTO `trigger_filters` VALUES (1,'before_message','sender','Filters messages as per the sender.'),(2,'before_message','receiver','Filters messages as per the receiver.'),(3,'before_message','receiverType','Filters messages as per the receiverType.'),(4,'before_message','hasText','Checks for text in the message body.'),(5,'before_message','hasAttachments','Checks for the attachments in the message body.'),(6,'before_message','mimeType','Fiters the message as per the mime Type.'),(7,'before_message','hasImage','Checks for atleast one image in the attachments.'),(8,'before_message','hasVideo','Checks for atleast one video in the attachments.'),(9,'before_message','hasImageOrVideo','Checks for atleast one video or image in the attachments.'),(10,'before_message','category','Filters messages as per the message category.'),(11,'before_message','type','Filters messages as per the message type.'),(12,'after_message','sender','Filters messages as per the sender.'),(13,'after_message','receiver','Filters messages as per the receiver.'),(14,'after_message','receiverType','Filters messages as per the receiverType.'),(15,'after_message','hasText','Checks for text in the message body.'),(16,'after_message','hasAttachments','Checks for the attachments in the message body.'),(17,'after_message','mimeType','Fiters the message as per the mime Type.'),(18,'after_message','hasImage','Checks for atleast one image in the attachments.'),(19,'after_message','hasVideo','Checks for atleast one video in the attachments.'),(20,'after_message','hasImageOrVideo','Checks for atleast one video or image in the attachments.'),(21,'after_message','category','Filters messages as per the message category.'),(22,'after_message','type','Filters messages as per the message type.'),(23,'after_message','hasReceiverEmail','Checks for email within private metadata.'),(24,'after_message','hasReceiverContactNumber','Checks for contact number within private metadata.'),(25,'after_auth_token_created','hasFCMDeviceToken','Checks if authToken has FCM Device Token.'),(26,'after_message','notSenderOnly','Checks if message is not from blocked user.'),(27,'after_auth_token_created','hasFCMDeviceToken','Checks if authToken has FCM Device Token.'),(28,'after_message','notSenderOnly','Checks if message is not from blocked user.'),(29,'after_message','hasAudio','Checks for atleast one audio in the attachments.'),(30,'before_message','hasAudio','Checks for atleast one audio in the attachments.'),(31,'before_message_edited','sender','Filters messages as per the sender.'),(32,'before_message_edited','receiver','Filters messages as per the receiver.'),(33,'before_message_edited','receiverType','Filters messages as per the receiverType.'),(34,'before_message_edited','hasText','Checks for text in the message body.'),(35,'before_message_edited','hasAttachments','Checks for the attachments in the message body.'),(36,'before_message_edited','mimeType','Fiters the message as per the mime Type.'),(37,'before_message_edited','hasImage','Checks for atleast one image in the attachments.'),(38,'before_message_edited','hasVideo','Checks for atleast one video in the attachments.'),(39,'before_message_edited','hasImageOrVideo','Checks for atleast one video or image in the attachments.'),(40,'before_message_edited','category','Filters messages as per the message category.'),(41,'before_message_edited','type','Filters messages as per the message type.'),(42,'before_message_edited','hasAudio','Checks for atleast one audio in the attachments.'),(43,'after_message','hasVideo','Checks for at least one video in the attachments.'),(44,'after_message','hasImageOrVideo','Checks for at least one video or image in the attachments.'),(45,'after_message','category','Filters messages as per the message category.'),(46,'after_message','type','Filters messages as per the message type.');
/*!40000 ALTER TABLE `trigger_filters` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contactNumber` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `password` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `authChangedAt` int DEFAULT NULL,
  `inviteCode` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `emailVerified` tinyint(1) NOT NULL DEFAULT '0',
  `isTestAccount` tinyint(1) NOT NULL DEFAULT '0',
  `paidAtleastOnce` tinyint(1) NOT NULL DEFAULT '0',
  `pooledBilling` tinyint(1) DEFAULT NULL,
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  `deletedAt` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `users_email_unique` (`email`),
  KEY `users_invitecode_index` (`inviteCode`),
  KEY `users_createdat_index` (`createdAt`),
  KEY `users_updatedat_index` (`updatedAt`),
  KEY `users_deletedat_index` (`deletedAt`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `webhooks`
--

DROP TABLE IF EXISTS `webhooks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `webhooks` (
  `id` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `webhookURL` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `isActive` tinyint(1) NOT NULL DEFAULT '0',
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `createdAt` int NOT NULL,
  `updatedAt` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `webhooks_id_unique` (`id`),
  KEY `webhooks_createdat_index` (`createdAt`),
  KEY `webhooks_updatedat_index` (`updatedAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `webhooks`
--

LOCK TABLES `webhooks` WRITE;
/*!40000 ALTER TABLE `webhooks` DISABLE KEYS */;
/*!40000 ALTER TABLE `webhooks` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-06-19 12:29:36
