/*==============================================================*/
/* Deployment Database: datatrak_bgt_agt                        */
/*==============================================================*/

declare @version varchar(50),
        @oldversion varchar(50)
		
set @oldversion = 'v1.2.1-B00'
set @version = ( select rtrim(ltrim(dbversion_id)) from system_dbversion where dbversion_id like @oldversion + '%' )

if (@version is NULL)

raiserror('Deployment aborted due to incompatible DTA version!!!',20,-1) WITH LOG

else

print 'Proceed with the deployment as correct DTA version is being used...'

-- ------------------------------------------------------------------------------------------------
--
-- Initial Version, 31-Oct-2022 
--
-- Target:      datatrak_bgt_agt
-- Description: DTA version updates to system_dbversion table
--
-- Expected output is in the form (as follows);
--
--    INFO: Processing system_dbversion table
--    INFO: Updating New DTA version into system_dbversion
--    INFO: Successfully finished processing system_dbversion
--
--
-- ------------------------------------------------------------------------------------------------
--

SET NOCOUNT ON

PRINT 'INFO: Processing system_dbversion table'

declare @mis_database_version varchar(50)
declare @bmis_database_version varchar(50)
declare @amis_database_version varchar(50)
declare @bdate_modified varchar(19)
declare @adate_modified varchar(19)
declare @RowsAffected int
declare @Action varchar(13)

SET @mis_database_version = 'v1.3.0-B00'

IF EXISTS (SELECT 'X' FROM system_dbversion WHERE dbversion_id = @mis_database_version)
BEGIN
  PRINT 'WARNING INFO: Unable to update system_dbversion table where dbversion_id = "' + @mis_database_version + '" already exists!!'
END
ELSE
IF EXISTS (SELECT 'X' FROM system_dbversion)
BEGIN
SELECT @bmis_database_version = dbversion_id,
       @bdate_modified = convert(varchar(19),date_modified,107) 
from system_dbversion

PRINT ''

  PRINT ' Before Image of DTA Database Version is "' + @bmis_database_version + '" dated on ' + @bdate_modified 
  PRINT ' ==============================================='
  
PRINT ''

  SET @Action = 'Update'
  PRINT 'INFO: Updating existing DTA version on system_dbversion'

  PRINT ''
  
  UPDATE system_dbversion
  SET dbversion_id = @mis_database_version,
	  date_modified = getdate()
  
  SET @RowsAffected = @@ROWCOUNT

 IF @RowsAffected > 0
	PRINT '+++ SUCCESS: Updated "' + convert(varchar(4),@RowsAffected) + '" row/s into system_dbversion table.'
 ELSE
	PRINT '### WARNING: "' + convert(varchar(4),@RowsAffected) + ' " row/s updated into system_dbversion table.'
	
PRINT ''

  SELECT @amis_database_version = dbversion_id,
         @adate_modified = convert(varchar(19),date_modified,107)
  FROM system_dbversion
  
  PRINT ' After Image of DTA Database Version is "' + @amis_database_version + '" dated on ' + @adate_modified
  PRINT ' =============================================='

PRINT ''

END
ELSE
BEGIN

  SET @Action = 'Insert'
  PRINT 'INFO: Inserting new DTA version into system_dbversion'
  
  INSERT INTO system_dbversion( dbversion_id, date_modified )
  VALUES ( @mis_database_version, getdate() )
  
  SET @RowsAffected = @@ROWCOUNT

 IF @RowsAffected > 0
	PRINT '+++ SUCCESS: Inserted "' + convert(varchar(4),@RowsAffected) + '" row/s into system_dbversion table.'
 ELSE
	PRINT '### WARNING: "' + convert(varchar(4),@RowsAffected) + ' " row/s inserted into system_dbversion table.'

PRINT ''

  SELECT @amis_database_version = dbversion_id,
         @adate_modified = convert(varchar(19),date_modified,107)
  FROM system_dbversion
  
  PRINT ' After Image of DTA Database Version is "' + @amis_database_version + '" dated on ' + @adate_modified
  PRINT ' =============================================='

PRINT ''

END

SET NOCOUNT OFF
GO
