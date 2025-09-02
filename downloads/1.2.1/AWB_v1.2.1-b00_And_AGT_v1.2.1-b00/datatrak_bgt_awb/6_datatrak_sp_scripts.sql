/***************************************************/
/**          Create/update sp_scripts             **/
/**                                               **/
/**                                               **/
/***************************************************/

/*==============================================================*/
/* Deployment Database: datatrak_bgt_awb                        */
/*==============================================================*/

declare @version varchar(50),
        @oldversion varchar(50)
		
set @oldversion = 'v1.2.0-B08'
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

IF OBJECT_ID('dbo.p_get_customer_img_uploads') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_customer_img_uploads
    IF OBJECT_ID('dbo.p_get_customer_img_uploads') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_customer_img_uploads >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_customer_img_uploads >>>'
END
GO
/******************************************************************************
* Object: p_get_customer_img_uploads
* Type: Stored Procedure
* Callers: AMA
* Usage: retrieves customer image details
*  
* Previous Fix(es) :
*
* Current Fix(es) : 
*	PTR 2274
*****************************************************************************/
CREATE PROCEDURE p_get_customer_img_uploads
(
    @customer_id	varchar(9) --required
)
AS
BEGIN
    DECLARE @indx int
    DECLARE @cnt int
    DECLARE @img_indx int
    DECLARE @sql_query1 varchar(max)
    DECLARE @sql_query2 varchar(max)
    DECLARE @sql_query3 varchar(max)
    DECLARE @sql_query4 varchar(max)
    DECLARE @Tablevar TABLE ( image_index INT )

    CREATE TABLE #temp_imgs 
    (
        customer_id varchar(9),
        image_display varchar(1),
        image_string varchar(max),
        date_modified datetime2
    )

    CREATE TABLE #temp_img_idx 
    (
        image_db_index int
    )

    SET @sql_query2 = CONCAT ('INSERT INTO #temp_img_idx (image_db_index) SELECT db_index FROM ',dbo.f_get_dbname(),'customers_imgs WHERE customer_id = ''',@customer_id,'''')
    EXEC (@sql_query2)
	
    SELECT @cnt = COUNT(*) FROM #temp_img_idx
	
    --Add imges from datatrak_bgt_agt_img_xx to temp table #temp_img_idx
    WHILE @cnt > 0
    BEGIN
        SELECT TOP 1 @img_indx = image_db_index FROM #temp_img_idx

        SET @sql_query3 = CONCAT ('INSERT INTO #temp_imgs (customer_id, image_display, image_string, date_modified)
                                       SELECT img2.customer_id as ''customer_id''
                                             ,img2.image_display as ''image_display''
                                             ,img2.image_string as ''image_string''
                                             ,img2.date_modified as ''date_modified''
                                       FROM datatrak_bgt_agt_img_',@img_indx,'.dbo.images img2 WITH (NOLOCK) 
                                       WHERE img2.customer_id = ''',@customer_id,'''')

        EXEC (@sql_query3)

        --delete the top after getting all images
        DELETE FROM #temp_img_idx WHERE image_db_index = @img_indx
        SET @cnt -= 1
    END

    --Add images from datatrak_bgt_agt db to temp table #temp_img_idx
    IF OBJECT_ID('datatrak_bgt_agt.dbo.images') IS NOT NULL
    BEGIN
        SET @sql_query4 = CONCAT ('INSERT INTO #temp_imgs (customer_id, image_display, image_string, date_modified)
                                   SELECT customer_id, image_display as ''image_display'',
                                   image_string as ''image_string'',date_modified  
                                   FROM ',dbo.f_get_dbname(),'images img1 WITH (NOLOCK)
                                   WHERE img1.customer_id = ''',@customer_id,'''')

        EXEC (@sql_query4)
    END

    SELECT * FROM #temp_imgs

    DROP TABLE #temp_imgs
    DROP TABLE #temp_img_idx
END
GO
IF OBJECT_ID('dbo.p_get_customer_img_uploads') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_customer_img_uploads >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_customer_img_uploads >>>'
GO
