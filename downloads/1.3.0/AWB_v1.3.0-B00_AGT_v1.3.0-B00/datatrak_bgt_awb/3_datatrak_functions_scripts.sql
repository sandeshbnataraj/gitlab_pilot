
/***************************************************/
/**          3_datatrak_functions_scripts.sql             **/
/**                                               **/
/**                                               **/
/***************************************************/

/*==============================================================*/
/* Deployment Database: datatrak_bgt_awb                        */
/*==============================================================*/

declare @version varchar(50),
        @oldversion varchar(50)
		
set @oldversion = 'v1.2.1-B00'
set @version = ( select rtrim(ltrim(dbversion_id)) from system_dbversion where dbversion_id like @oldversion + '%' )

if (@version is NULL)

raiserror('Deployment aborted due to incompatible DB version!!!',20,-1) WITH LOG

else

print 'Proceed with the deployment as correct DB version is being used...'

-- ------------------------------------------------------
-- current_db_version_tracker: 'v1.3.0-B00'
-- SQL Server version:	Microsoft SQL Server 2019 (RTM-CU4) (KB4548597) - 15.0.4033.1 (X64)
--                      2025-04-10 20:42:42 
--                      Copyright (C) 2019 Microsoft Corporation
--                      Developer Edition (64-bit) on Linux (CentOS Linux 8 (Core)) <X64>
--
-- ------------------------------------------------------

