
/***************************************************/
/**          create_new_table_scripts             **/
/**                                               **/
/**                                               **/
/***************************************************/

/*==============================================================*/
/* Deployment Database: datatrak_bgt_agt                        */
/*==============================================================*/

IF OBJECT_ID('dbo.system_dbversion') IS NULL
CREATE TABLE system_dbversion
(
    dbversion_id varchar(50) NOT NULL,
    date_modified datetime2 NOT NULL DEFAULT (getdate()),
    CONSTRAINT PK_sys_dbversion PRIMARY KEY CLUSTERED (dbversion_id)
)

declare @version varchar(50),
        @oldversion varchar(50),
        @newversion varchar(50)

set @oldversion = 'v1.2.0-B26'		
set @newversion = 'v1.2.1-B00'

IF NOT EXISTS (SELECT 'X' FROM system_dbversion)
BEGIN
INSERT INTO system_dbversion( dbversion_id )
  VALUES ( @newversion )
END
  
set @version = ( select rtrim(ltrim(dbversion_id)) from system_dbversion where dbversion_id like @oldversion + '%' )

if (@version is NULL)

raiserror('Deployment aborted due to incompatible MIS version!!!',20,-1) WITH LOG

else

print 'Proceed with the deployment as correct MIS version is being used...'

-- ------------------------------------------------------
-- current_db_version_tracker: 1.2.1-b00
-- SQL Server version:	Microsoft SQL Server 2019 (RTM-CU4) (KB4548597) - 15.0.4033.1 (X64)
--                      Mar 14 2020 16:10:35 
--                      Copyright (C) 2019 Microsoft Corporation
--                      Developer Edition (64-bit) on Linux (CentOS Linux 8 (Core)) <X64>
--
-- ------------------------------------------------------
--
-- New tables creation within database 'datatrak_bgt_agt' as follows:
--      + customers_imgs
--
-- ------------------------------------------------------

IF OBJECT_ID('dbo.customers_imgs') IS NULL
BEGIN
    CREATE TABLE customers_imgs
    (
        [customer_id] [varchar](9) NOT NULL,
        [db_index] [int] NOT NULL
        CONSTRAINT [PK_customers_imgs] PRIMARY KEY CLUSTERED ([customer_id],[db_index])
    )

    IF OBJECT_ID('dbo.customers_imgs') IS NOT NULL
        PRINT '<<< CREATED TABLE customers_imgs >>>'
    ELSE
        PRINT '<<< FAILED CREATING TABLE customers_imgs >>>'
END
ELSE
BEGIN
    PRINT '<<< TABLE customers_imgs is existed already >>>'
END
GO
