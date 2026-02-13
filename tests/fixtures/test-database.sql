-- Sample database for testing deployment and database import
-- This provides basic tables to test import functionality

CREATE TABLE IF NOT EXISTS `users` (
  `uid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(128) NOT NULL,
  `langcode` varchar(12) NOT NULL DEFAULT 'en',
  `preferred_langcode` varchar(12) NOT NULL DEFAULT '',
  `preferred_admin_langcode` varchar(12),
  `name` varchar(60) NOT NULL DEFAULT '',
  `mail` varchar(254),
  `init` varchar(254),
  `pass` varchar(255),
  `status` tinyint(4) NOT NULL DEFAULT '1',
  `created` int(11) NOT NULL DEFAULT '0',
  `changed` int(11) NOT NULL DEFAULT '0',
  `access` int(11) NOT NULL DEFAULT '0',
  `login` int(11),
  `timezone` varchar(32) DEFAULT NULL,
  PRIMARY KEY (`uid`),
  UNIQUE KEY `users_field__uuid__value` (`uuid`),
  KEY `users_field__mail__value` (`mail`),
  KEY `users_changed` (`changed`),
  KEY `users_created` (`created`)
);

-- Insert test users
INSERT INTO `users` VALUES 
(0, '', 'en', '', NULL, '', NULL, '', 'a1b2c3d4e5f6g7h8', 0, 1, 1, 0, 0, NULL),
(1, '12345678-1234-1234-1234-123456789012', 'en', '', NULL, 'admin', 'admin@example.com', 'admin@example.com', 'a1b2c3d4e5f6g7h8', 1, 1707830400, 1707830400, 1707830400, 1707830400, 'UTC');

CREATE TABLE IF NOT EXISTS `config` (
  `collection` varchar(255) NOT NULL DEFAULT '',
  `name` varchar(255) NOT NULL,
  `data` longblob NOT NULL,
  PRIMARY KEY (`collection`,`name`)
);

CREATE TABLE IF NOT EXISTS `key_value` (
  `collection` varchar(128) NOT NULL,
  `name` varchar(128) NOT NULL,
  `value` longblob NOT NULL,
  PRIMARY KEY (`collection`,`name`)
);

INSERT INTO `key_value` VALUES 
('system.site', 'uuid', 0x733a33363a2238616439616263612d356464632d343736302d616630362d376334633438613062633935223b);
