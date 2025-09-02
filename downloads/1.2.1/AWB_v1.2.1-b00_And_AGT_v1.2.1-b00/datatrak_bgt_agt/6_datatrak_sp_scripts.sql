/***************************************************/
/**          Create/update sp_scripts             **/
/**                                               **/
/**                                               **/
/***************************************************/

/*==============================================================*/
/* Deployment Database: datatrak_bgt_agt                        */
/*==============================================================*/

declare @version varchar(50),
        @oldversion varchar(50)
		
set @oldversion = 'v1.2.0-B26'
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

IF OBJECT_ID('dbo.p_upload_image') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_upload_image
    IF OBJECT_ID('dbo.p_upload_image') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_upload_image >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_upload_image >>>'
END
GO
/******************************************************************************
* Object: p_upload_image
* Type: Stored Procedure
* Callers: EAgent WebService
* Usage: Upload an image for the customers
*  
* Previous Fix(es) :
*
* Current Fix(es) : 
*	PTR 2274
*****************************************************************************/
CREATE PROCEDURE p_upload_image
    @agentId VARCHAR(8),        -- Required 
    @custId VARCHAR(9),         -- Required
    @imageDisplay VARCHAR(1),   -- Required, "f" for Front, "b" for Back
    @ImageString VARCHAR(MAX),  -- Required
    @agent_hostname VARCHAR(MAX) -- Required
AS
BEGIN
    DECLARE @Rev INT
    DECLARE @imageId VARCHAR(36)=NEWID()
    DECLARE @indx INT
    DECLARE @sql_query NVARCHAR(MAX)

    -- Prevent extra result sets from interfering
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- Ensures automatic rollback on error

    -- Validate image size (1MB limit)
    IF LEN(@ImageString) > 1364972
    BEGIN
        SELECT '-1', 'Image size exceeds the limit!';
        RETURN;
    END

    -- Validate agent existence
    IF NOT EXISTS (
        SELECT 1 
        FROM agents WITH (NOLOCK) 
        WHERE agent_id = @agentId 
            AND agent_host_name = @agent_hostname)
    BEGIN
        SELECT '-1', 'Invalid Agent!';
        RETURN;
    END

    -- Validate customer existence
    IF NOT EXISTS (
        SELECT 1 
        FROM customers WITH (NOLOCK) 
        WHERE customer_id = @custId 
            AND agent_id = @agentId)
    BEGIN
        SELECT '-1', 'Invalid Customer!';
        RETURN;
    END

    -- Fetch the database index
    SELECT @indx = [value] FROM system_config WHERE [key] = 'img_db_index';

    BEGIN TRY
        BEGIN TRANSACTION
            -- **Insert image into respective images table using `sp_executesql`**
            SET @sql_query = N'
                INSERT INTO datatrak_bgt_agt_img_' + CAST(@indx AS NVARCHAR) + N'.dbo.images 
                (image_id, customer_id, image_display, image_string, agent_id, date_modified) 
                VALUES (@imageId, @custId, @imageDisplay, @ImageString, @agentId, [dbo].f_getcustom_date())';

            EXEC sp_executesql @sql_query, 
                N'@imageId UNIQUEIDENTIFIER, @custId VARCHAR(9), @imageDisplay VARCHAR(1), @ImageString VARCHAR(MAX), @agentId VARCHAR(8)',
                @imageId, @custId, @imageDisplay, @ImageString, @agentId;

            SET @Rev = @@ROWCOUNT;

            -- merge to avoid race condition instead to if notexists and insert
            MERGE INTO customers_imgs AS tgt
            USING(SELECT @custId AS customer_id, @indx AS db_index) AS src
            ON tgt.customer_id = src.customer_id AND tgt.db_index = src.db_index
            WHEN NOT MATCHED THEN
                INSERT (customer_id, db_index) VALUES (src.customer_id, src.db_index);
        
        COMMIT TRAN
        SELECT @Rev, 'Upload Successful!';
    END TRY
    BEGIN CATCH
        IF @@trancount > 0
            ROLLBACK TRANSACTION

        SELECT CONCAT('-1', ERROR_NUMBER(),':',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_upload_image') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_upload_image >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_upload_image >>>'
GO


IF OBJECT_ID('dbo.p_get_customer_details') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_customer_details
    IF OBJECT_ID('dbo.p_get_customer_details') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_customer_details >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_customer_details >>>'
END
GO
/******************************************************************************
* Object: p_get_customer_details
* Type: Stored Procedure
* Callers: EAgent WebService
* Usage: Closes the customer account
*  
* Previous Fix(es) :
*	PTR 2280
*
* Current Fix(es) : 
*	PTR 2280 - Adding missing BEGIN/COMMIT TRANS
*****************************************************************************/
CREATE PROCEDURE p_get_customer_details
    @custId varchar(9),				-- required
    @agentId varchar(8),			-- required
    @agent_hostname varchar(max)	-- required	
AS 
BEGIN
    DECLARE @result varchar(max)

    BEGIN TRY
        BEGIN TRAN
            IF NOT EXISTS (SELECT agent_id FROM agents WITH (NOLOCK) WHERE agent_id = @agentId and agent_host_name = @agent_hostname) 
            BEGIN
                SET @result = '-1'
                SELECT @result AS 'result','Invalid Agent'
            END
            ELSE
                IF NOT EXISTS (SELECT customer_id FROM customers WITH (NOLOCK) WHERE customer_id = @custId and agent_id =@agentId) 
                BEGIN
                    SET @result = '-1'
                    SELECT @result AS 'result','Invalid Customer'
                END
                ELSE
                BEGIN
                    SELECT customer_id,IIF(customer_Status_id <>5,mobile,mobile_closed) AS 'mobile', customer_status_id, email_id, id_number, identity_proof_type_id, issued_date, issuing_counTRY 
                    FROM customers WITH (NOLOCK) WHERE customer_id = @custId and agent_id = @agentId
                END

        COMMIT TRAN
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION

        SET @result = CONCAT('-1:',' message = ', ERROR_NUMBER(),':',ERROR_MESSAGE())
        SELECT @result AS 'result'
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_get_customer_details') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_customer_details >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_customer_details >>>'
GO