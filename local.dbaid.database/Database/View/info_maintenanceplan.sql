﻿/*
Copyright (C) 2015 Datacom
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007
*/

CREATE VIEW [info].[maintenanceplan]
WITH ENCRYPTION
AS
SELECT [P].[name] AS [plan_name]
	,[plan_description].[string] AS [plan_description]
	,[S].[subplan_name]
	,[subplan_description].[string] AS [subplan_description]
	,[J].[job_id]
	,[J].[name] AS [job_name]
	,[P].[owner]
	,[P].[create_date]
FROM [msdb].[dbo].[sysmaintplan_plans] [P]
	INNER JOIN [msdb].[dbo].[sysmaintplan_subplans] [S]
		ON [P].[id] = [S].[plan_id]
	INNER JOIN [msdb].[dbo].[sysjobs] [J]
		ON [S].[job_id] = [J].[job_id]
	CROSS APPLY [dbo].[cleanstring]([P].[description]) [plan_description]
	CROSS APPLY [dbo].[cleanstring]([S].[subplan_description]) [subplan_description]
