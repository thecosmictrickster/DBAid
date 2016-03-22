﻿/*
Copyright (C) 2015 Datacom
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007
*/

CREATE PROCEDURE [check].[backup]
WITH ENCRYPTION
AS
BEGIN
SET NOCOUNT ON;

	DECLARE @check TABLE([message] NVARCHAR(4000)
						,[state] NVARCHAR(8));

	DECLARE @to_backup INT;
	DECLARE @not_backup INT;
	DECLARE @version NUMERIC(18,10) 
	DECLARE @cluster NVARCHAR(MAX)

	SET @version = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))

	IF @version >= 11
	  BEGIN
		SELECT @cluster = [cluster_name]
		FROM [sys].[dm_hadr_cluster]
	  END

	IF @version >= 11 AND @cluster IS NOT NULL
	BEGIN
		SELECT @to_backup=COUNT(*) FROM [dbo].[config_database] [D]
						CROSS APPLY(SELECT [sys].[fn_hadr_backup_is_preferred_replica]([D].[db_name]) AS [IsPreferredBackupReplicaNow]) AS [AG_backup]
							WHERE [backup_frequency_hours] > 0 AND LOWER([db_name]) NOT IN (N'tempdb') AND [AG_backup].[IsPreferredBackupReplicaNow] > 0

		SELECT @not_backup=COUNT(*) FROM [dbo].[config_database] [D] 
						CROSS APPLY(SELECT [sys].[fn_hadr_backup_is_preferred_replica]([D].[db_name]) AS [IsPreferredBackupReplicaNow]) AS [AG_backup]
							WHERE [backup_frequency_hours] = 0 AND LOWER([db_name]) NOT IN (N'tempdb') OR [AG_backup].[IsPreferredBackupReplicaNow] = 0

		;WITH Backups
		AS
		(
			SELECT ROW_NUMBER() OVER (PARTITION BY [D].[name] ORDER BY [B].[backup_finish_date] DESC) AS [row]
				,[D].[database_id]
				,[B].[backup_finish_date]
				,[B].[type]
				,[AG_backup].IsPreferredBackupReplicaNow
			FROM [sys].[databases] [D]
				LEFT JOIN [msdb].[dbo].[backupset] [B]
					ON [D].[name] = [B].[database_name]
						AND [B].[type] IN ('D', 'I')
						AND [B].[is_copy_only] = 0
				CROSS APPLY(SELECT [sys].[fn_hadr_backup_is_preferred_replica]([D].[name]) AS [IsPreferredBackupReplicaNow]) AS [AG_backup]
		)
		INSERT INTO @check
		SELECT N'database=' 
				+ QUOTENAME([D].[db_name])
				+ N'; last_backup=' 
				+ ISNULL(REPLACE(CONVERT(NVARCHAR(20), [B].[backup_finish_date], 120), N' ', N'T'), N'NEVER')
				+ N'; type=' 
				+ CASE [type] WHEN 'D' THEN 'FULL' WHEN 'I' THEN 'DIFFERENTIAL' ELSE 'UNKNOWN' END
				+ N'; backups_missed=' 
				+ ISNULL(CAST(CAST(DATEDIFF(HOUR, [B].[backup_finish_date], GETDATE()) / [D].[backup_frequency_hours] AS INT) AS VARCHAR(5)), 'ALL')
			,[S].[state]
		FROM Backups [B]
			INNER JOIN [dbo].[config_database] [D]
				ON [B].[database_id] = [D].[database_id]
			CROSS APPLY (SELECT CASE WHEN ([B].[backup_finish_date] IS NULL OR DATEDIFF(HOUR, [B].[backup_finish_date], GETDATE()) > ([D].[backup_frequency_hours])) THEN [D].[backup_state_alert] ELSE N'OK' END AS [state]) [S]
		WHERE [B].[row] = 1
			AND [D].[backup_frequency_hours] > 0
			AND LOWER([D].[db_name]) NOT IN (N'tempdb')
			AND [S].[state] NOT IN (N'OK')
			AND [B].[IsPreferredBackupReplicaNow] = 1
		ORDER BY [D].[db_name]
	END
	ELSE
	BEGIN
		SELECT @to_backup=COUNT(*) FROM [dbo].[config_database] WHERE [backup_frequency_hours] > 0 AND LOWER([db_name]) NOT IN (N'tempdb')
		SELECT @not_backup=COUNT(*) FROM [dbo].[config_database] WHERE [backup_frequency_hours] = 0 AND LOWER([db_name]) NOT IN (N'tempdb')

		;WITH Backups
		AS
		(
			SELECT ROW_NUMBER() OVER (PARTITION BY [D].[name] ORDER BY [B].[backup_finish_date] DESC) AS [row]
				,[D].[database_id]
				,[B].[backup_finish_date]
				,[B].[type]
			FROM [sys].[databases] [D]
				LEFT JOIN [msdb].[dbo].[backupset] [B]
					ON [D].[name] = [B].[database_name]
						AND [B].[type] IN ('D', 'I')
						AND [B].[is_copy_only] = 0
		)
		INSERT INTO @check
		SELECT N'database=' 
				+ QUOTENAME([D].[db_name])
				+ N'; last_backup=' 
				+ ISNULL(REPLACE(CONVERT(NVARCHAR(20), [B].[backup_finish_date], 120), N' ', N'T'), N'NEVER')
				+ N'; type=' 
				+ CASE [type] WHEN 'D' THEN 'FULL' WHEN 'I' THEN 'DIFFERENTIAL' ELSE 'UNKNOWN' END
				+ N'; backups_missed=' 
				+ ISNULL(CAST(CAST(DATEDIFF(HOUR, [B].[backup_finish_date], GETDATE()) / [D].[backup_frequency_hours] AS INT) AS VARCHAR(5)), 'ALL')
			,[S].[state]
		FROM Backups [B]
			INNER JOIN [dbo].[config_database] [D]
				ON [B].[database_id] = [D].[database_id]
			CROSS APPLY (SELECT CASE WHEN ([B].[backup_finish_date] IS NULL OR DATEDIFF(HOUR, [B].[backup_finish_date], GETDATE()) > ([D].[backup_frequency_hours])) THEN [D].[backup_state_alert] ELSE N'OK' END AS [state]) [S]
		WHERE [B].[row] = 1
			AND [D].[backup_frequency_hours] > 0
			AND LOWER([D].[db_name]) NOT IN (N'tempdb')
			AND [S].[state] NOT IN (N'OK')
		ORDER BY [D].[db_name]
	END
	IF (SELECT COUNT(*) FROM @check) < 1
		INSERT INTO @check VALUES(CAST(@to_backup AS NVARCHAR(10)) + N' database(s) monitored, ' + CAST(@not_backup AS NVARCHAR(10)) + N' database(s) opted-out', N'NA');

	SELECT [message], [state] 
	FROM @check;
END