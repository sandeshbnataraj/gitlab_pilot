
/***************************************************/
/**          6_datatrak_sp_scripts.sql             **/
/**                                               **/
/**                                               **/
/***************************************************/

/*==============================================================*/
/* Deployment Database: datatrak_bgt_agt                        */
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

IF OBJECT_ID('dbo.p_add_draw_data') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_add_draw_data;
    IF OBJECT_ID('dbo.p_add_draw_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_add_draw_data >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_add_draw_data >>>';
END;
GO
/******************************************************************************
* Object: p_add_draw_data.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS)
* Description: DTTS calls the procedure to add draw data to the draw_data table.
* Impacted Table(s): draw_data. 
*
* Update(s) History:
* PTR 2383 : DB: New Game Lotto 5/35 Development
* PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
* PTR 2358: Header Text Update.
* PTR 2126: Selling ticket: Ticket has no VTID1, OSS Timestamp, Ticket cost
* PTR 2151: DBs-Need to Optimize or Prevent Deadlock in SPs using the Draw Data table
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_add_draw_data]
    @gameId INT,
    @drawTableNumber INT, 
    @in_vales VARCHAR(MAX)
AS
BEGIN
    -- Declare variables
    DECLARE @error_message NVARCHAR(MAX);
    DECLARE @errorNumber INT;
	DECLARE @sql_insert NVARCHAR(MAX);
	DECLARE @result INT;
	DECLARE @message VARCHAR(MAX);

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Ensure transactions are rolled back in case of any exception

    BEGIN TRY
        BEGIN TRANSACTION;
            -- Acquire application lock for the gameId
            EXEC p_spgetapplock @gameId;

            -- Delete all records from draw_data for the specified game_id
            DELETE FROM draw_data 
            WHERE game_id = @gameId;

            -- Update the draw table number in system_properties
            UPDATE sp SET sp.table_number = @drawTableNumber 
            FROM system_properties sp
            WHERE sp.system_properties_id = 1;

            -- Insert new draw data into draw_data table
            SET @sql_insert = 'INSERT INTO draw_data (draw_data_id, draw_id, draw_date, draw_table_number, jackpot, jackpotcf, jackpot2, selling_enabled_global, game_enabled, game_id, play_type, risk_flag) VALUES ' 
                                + @in_vales;

            EXEC sp_executesql @sql_insert;
            
            -- Check if the insert was successful
            IF @@ROWCOUNT > 0
            BEGIN
                SET @result = 1;
                SET @message = 'Successfully Added Draw data';
            END
            ELSE
            BEGIN
                SET @result = -1;
                SET @message = 'Failed to Add Draw data';
            END;

            SELECT @result, @message;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH 
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        -- Handle specific SQL errors with custom messages
        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT(@errorNumber, '=>',  @error_message)
        END;

        -- Throw custom error for specific SQL errors
        IF @errorNumber IN (1204,1205,1222)
        BEGIN
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            -- Return generic error message
            SELECT '-1', @error_message;
        END;
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.p_add_draw_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_add_draw_data >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_add_draw_data >>>';
GO

IF OBJECT_ID('dbo.p_add_tickets_to_staging') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_add_tickets_to_staging;
    IF OBJECT_ID('dbo.p_add_tickets_to_staging') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_add_tickets_to_staging >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_add_tickets_to_staging >>>';
END
GO
/******************************************************************************
* Object: p_add_tickets_to_staging.
* Type: Stored Procedure.
* Caller(s): Transfer Ticket Data Service (TTDS).
* Description: Called when TTDS is brought up or restarted to populate the `staging_move_tickets` table 
*              with tickets that are ready to be moved into the permanent table.
* Impacted Table(s): staging_move_tickets.
*                    in_proc_tickets.
*                    in_proc_transaction_activities.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Procedure Headers 
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_add_tickets_to_staging]
AS
BEGIN
    DECLARE @errorNumber INT;
    DECLARE @error_message NVARCHAR(MAX);
    
    -- Declare parameter for transaction type ID for sell type
    DECLARE @transactionTypeId UNIQUEIDENTIFIER = 'edf85abc-754b-11e6-9924-64006a4ba62f';

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    BEGIN TRY
        BEGIN TRANSACTION
            -- Insert into staging_move_tickets
            INSERT INTO staging_move_tickets (
                ticket_id,
                game_id,
                date_modified
            )
            SELECT  -- Select from in_proc_tickets and in_proc_transaction_activities
                intck.ticket_id,
                intck.game_id,
                intck.date_modified
            FROM in_proc_tickets intck 
                INNER JOIN in_proc_transaction_activities inta
                    ON intck.ticket_id = inta.ticket_id
                    AND inta.transaction_type_id = @transactionTypeId
                    AND inta.agent_confirmed_receipt = 1
            WHERE NOT EXISTS ( -- do not add tickets if already exists in staging_move_tickets
                SELECT 1
                FROM staging_move_tickets smt WITH (SNAPSHOT)
                WHERE smt.ticket_id = intck.ticket_id
            );
        COMMIT TRANSACTION
        
        -- Return result after transaction is committed 
        SELECT '1' AS 'result', 'Tickets added to staging successfully' AS 'message';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
            
        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT(@errorNumber, '=>', @error_message)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN     
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1' AS 'result', @error_message AS 'message';
        END
    END CATCH;
END
GO
IF OBJECT_ID('dbo.p_add_tickets_to_staging') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_add_tickets_to_staging >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_add_tickets_to_staging >>>';
GO

IF OBJECT_ID('dbo.p_check_inProc_tickets_for_pws') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_check_inProc_tickets_for_pws;
    IF OBJECT_ID('dbo.p_check_inProc_tickets_for_pws') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_check_inProc_tickets_for_pws >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_check_inProc_tickets_for_pws >>>';
END
GO
/******************************************************************************
* Object: p_check_inProc_tickets_for_pws.
* Type: Stored Procedure.
* Caller(s): Process Winners Service (PWS).
* Description: PWS calls this procedure to check if there are tickets in in_proc_tickets table
               for the input GameId and DrawId.
* Impacted Table(s): in_proc_tickets. 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2356: Keep 'NOLOCK' because the condition check and data retrieval are performed 
*				on column(s) that do not change frequently.
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2171: Selling ticket: Lost winning files
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_check_inProc_tickets_for_pws]
    @gameId INT,
    @drawId INT
AS
BEGIN
    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query

    IF EXISTS (
        SELECT 1 
        FROM in_proc_tickets WITH (NOLOCK) 
        WHERE game_id = @gameId 
            AND draw_id = @drawId
    )
    OR EXISTS (
        SELECT 1 
        FROM tickets_details_mem WITH (NOLOCK) 
        WHERE game_id = @gameId 
            AND draw_id = @drawId
    )
    BEGIN
        SELECT '1' AS 'ticket_id', 'Has tickets in in_proc_tickets table';
    END
    ELSE
    BEGIN
        SELECT '-1', 'No tickets in in_proc_tickets table';
    END
END;
GO
IF OBJECT_ID('dbo.p_check_inProc_tickets_for_pws') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_check_inProc_tickets_for_pws >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_check_inProc_tickets_for_pws >>>';
GO


IF OBJECT_ID('dbo.p_check_pending_pay') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_check_pending_pay;
    IF OBJECT_ID('dbo.p_check_pending_pay') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_check_pending_pay >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_check_pending_pay >>>';
END;
GO
/******************************************************************************
* Object: p_check_pending_pay.
* Type: Stored Procedure.
* Caller(s): Process Winners Service (PWS).
* Description: Check if the ticket has been processed for pay or not. 
* Impacted Table(s): in_proc_transaction_activities.
*                   transaction_activities.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2356: Remove 'NOLOCK' to get the committed in_proc table & keep on permanset table since the staus would 
*                 would already be updated. 
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_check_pending_pay]
    @ticket_id    VARCHAR(36)
AS
BEGIN
    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    
    DECLARE @transactionStatusId UNIQUEIDENTIFIER;
    -- Transaction type ID for pay
    DECLARE @transactionTypeId UNIQUEIDENTIFIER = '966ead14-255c-4de4-b67d-28bd452582ea'; 
    -- Transaction status ID for completed and error
    DECLARE @transactionStatusIdCompleted UNIQUEIDENTIFIER = '6a56bdfb-0ff0-11e7-9454-b083feaf6ace'; -- completed status
    DECLARE @transactionStatusIdError UNIQUEIDENTIFIER = '45318a66-0ff0-11e7-9454-b083feaf6ace'; -- error status

    -- Check if ticket_id exists in in_proc_transaction_activities
    SELECT TOP 1 @transactionStatusId = transaction_status_id
    FROM in_proc_transaction_activities
    WHERE ticket_id = @ticket_id
        AND transaction_type_id = @transactionTypeId;

    -- Check if ticket_id exists in transaction_activities
    IF @transactionStatusId IS NULL
    BEGIN
        SELECT TOP 1 @transactionStatusId = transaction_status_id
        FROM transaction_activities WITH(NOLOCK)
        WHERE ticket_id = @ticket_id
            AND transaction_type_id = @transactionTypeId;
    END;
    
    -- Check if transaction status is completed or error
    If @transactionStatusId IN (@transactionStatusIdCompleted, @transactionStatusIdError)
    BEGIN
        SELECT '-1','Completed processing';
    END
    ELSE
    BEGIN
        SELECT '1';
    END;
END;
GO
IF OBJECT_ID('dbo.p_check_pending_pay') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_check_pending_pay >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_check_pending_pay >>>';
GO


IF OBJECT_ID('dbo.p_confirm_sent_to_agent') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_confirm_sent_to_agent
    IF OBJECT_ID('dbo.p_confirm_sent_to_agent') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_confirm_sent_to_agent >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_confirm_sent_to_agent >>>'
END
GO
/******************************************************************************
* Object:                p_confirm_sent_to_agent.
* Type:                  Stored Procedure.
* Caller(s):             TDRS (Transfer Draw Result Service).
* Description:           The service calls this procedure after successfully sending the draw data to the agent WS.
*
*                       Insert a record into the send_winnings_to_agent table if no record from the agent
*                       currently exists.
* Impacted Table(s):     send_winnings_to_agent.
*  
* Update(s) History:
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Keep 'NOLOCK' because the condition check and data retrieval are performed 
*               on column(s) that do not change frequently.
*   PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
*   PTR 2358: Header Text Update.
*   PTR 2283: TransferWinnersService: p_get_oss_agent_noupld_winning_tickets deadlock
*   PTR 2179: DBs - The “pending” showing in the draw results transfer on AMA
*   PTR 2185: Transfer draw result
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_confirm_sent_to_agent]
    @file_version   VARCHAR(20),-- required
    @game_id        INT,        -- required
    @draw_id        INT,        -- required
    @draw_date      DATETIME2,       -- required
    @agent_id       VARCHAR(8)  -- required
AS
BEGIN
    DECLARE @thwErrMsg VARCHAR(500)
    DECLARE @result VARCHAR(255)
    DECLARE @row_count INT

    SET XACT_ABORT ON --rollback transaction
    SET NOCOUNT ON   -- Disable row count messages for performance

    IF EXISTS (
        SELECT 1 
        FROM send_winnings_to_agent
        WHERE file_version = @file_version
            AND game_id = @game_id 
            AND draw_date = @draw_date
            AND draw_id = @draw_id 
            AND agent_id = @agent_id
        )
    BEGIN
        SELECT '1','Already Sent'
        RETURN;
    END
    ELSE IF EXISTS (
        SELECT 1
        FROM winning_header_data
        WHERE game_id = @game_id
            AND draw_id = @draw_id 
            AND draw_date = @draw_date
            AND file_version = @file_version
            AND send_to_all_agents = 1
        )
    BEGIN
        SELECT '1','Send_to_all_agents is set to 1'
        RETURN;
    END

    BEGIN TRY 
        BEGIN TRAN                      
            INSERT INTO send_winnings_to_agent (file_version,game_id,draw_id,draw_date,agent_id) 
                VALUES (@file_version,@game_id,@draw_id,@draw_date,@agent_id)

            SET @row_count = @@ROWCOUNT
        COMMIT TRAN

        -- return after commit
        IF @row_count > 0
        BEGIN
            SELECT '1','Added Successfully'
        END
        ELSE
        BEGIN
            SELECT '-1','Failed to add data'
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION

        IF ERROR_NUMBER() IN (1204, -- SqlOutOfLocks
                              1205, -- SqlDeadlockVictim
                              1222 -- SqlLockRequestTimeout
                              )
        BEGIN
            SET @thwErrMsg = CAST(ERROR_NUMBER() AS NVARCHAR) + ': A SqlOutOfLocks/Deadlock/LockRequestTimeout occurred';
            THROW 60000, @thwErrMsg, 1
        END
        ELSE
        BEGIN
            SET @result = CONCAT('-81:',' message = ', ERROR_NUMBER(),':',ERROR_MESSAGE())
            SELECT '-1',@result AS 'result'
        END
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_confirm_sent_to_agent') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_confirm_sent_to_agent >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_confirm_sent_to_agent >>>'
GO


IF OBJECT_ID('dbo.p_count_existing_winning_header') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_count_existing_winning_header
    IF OBJECT_ID('dbo.p_count_existing_winning_header') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_count_existing_winning_header >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_count_existing_winning_header >>>'
END
GO
/******************************************************************************
* Object:                p_count_existing_winning_header.
* Type:                  Stored Procedure.
* Caller(s):             Transfer Draw Result Service.
* Description:           Retrieve the count of records in the winning_header_data 
*                        table WHERE the process_status flag IS SET to 1.
* Impacted Table(s):     winning_header_data.
*  
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Remove 'NOLOCK' because we need to count the records with a process status set to '1'.
*   PTR 2358: Header Text Update.    
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_count_existing_winning_header]
    @game_id INT,        -- required
    @draw_id INT        -- required
AS
BEGIN
    SELECT count(*) 
    FROM winning_header_data
    WHERE game_id = @game_id 
        AND draw_id = @draw_id 
        AND process_status = 1
END
GO
IF OBJECT_ID('dbo.p_count_existing_winning_header') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_count_existing_winning_header >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_count_existing_winning_header >>>'
GO


IF OBJECT_ID('dbo.p_create_coresys_update_panels') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_coresys_update_panels
    IF OBJECT_ID('dbo.p_create_coresys_update_panels') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_coresys_update_panels >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_coresys_update_panels >>>'
END
GO
/******************************************************************************
* Object: p_create_coresys_update_panels.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: 
* Impacted Table(s): in_proc_coresys_update_panels.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2292: DB: Duplicate panels in in_proc tables
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_create_coresys_update_panels] (
    @ticketId VARCHAR(36), 
    @quickpick TINYINT,
    @selected_nums VARCHAR(255), 
    @bonus_num INT, 
    @cost MONEY, 
    @summary VARCHAR(MAX), 
    @pnl_numb INT
)
AS
BEGIN
    DECLARE @panelId VARCHAR(36);
    DECLARE @error_number INT;
    DECLARE @error_message VARCHAR(MAX);

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs
    
    BEGIN TRY
        BEGIN TRANSACTION
            DELETE FROM in_proc_coresys_update_panels 
                WHERE coresys_update_panel_id = @panelId
                AND panel_number = @pnl_numb;;

            SET @panelId = NEWID();
            INSERT INTO in_proc_coresys_update_panels (coresys_update_panel_id, ticket_id, selected_numbers, cost, quick_pick, 
                        bonus_number, summary, panel_number, date_modified)
            VALUES (@panelId, @ticketId, @selected_nums, @cost, @quickpick, 
                        @bonus_num, @summary, @pnl_numb, [dbo].f_getcustom_date());
        COMMIT TRANSACTION

        SELECT 'Panel created' AS 'panel_id';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @error_number
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @error_number,'=>',@error_message)
        END;

        IF @error_number IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
            -- Throw custom error message
            THROW 60000, @error_message, 1;
        ELSE
            SELECT @error_message AS 'panel_id';
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_create_coresys_update_panels') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_coresys_update_panels >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_coresys_update_panels >>>'
GO


IF OBJECT_ID('dbo.p_create_coresys_update_panels_3d') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_coresys_update_panels_3d
    IF OBJECT_ID('dbo.p_create_coresys_update_panels_3d') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_coresys_update_panels_3d >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_coresys_update_panels_3d >>>'
END
GO
/******************************************************************************
* Object: p_create_coresys_update_panels_3d.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: 
* Impacted Table(s): in_proc_coresys_update_panels_3d.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2292: DB: Duplicate panels in in_proc tables
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_create_coresys_update_panels_3d]
    @ticketId VARCHAR(36),
    @quickpick TINYINT,
    @cost MONEY,
    @summary VARCHAR(MAX),
    @sel_numbers_count INT,
    @pnl_numb INT,
    @selected_numbers NVARCHAR(MAX)
AS
BEGIN
    DECLARE @panelId VARCHAR(36);
    DECLARE @error_number INT;
    DECLARE @error_message VARCHAR(MAX);

    SET XACT_ABORT ON; -- SET on to rollback automatically
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION	
            DELETE in_proc_coresys_update_panels_3d
            WHERE in_proc_coresys_update_panels_3d_panel_id = @panelId
                AND panel_number = @pnl_numb;
            
            SET @panelId = NEWID();
            INSERT INTO in_proc_coresys_update_panels_3d (in_proc_coresys_update_panels_3d_panel_id, ticket_id, quick_pick, 
                        cost,summary, sel_numbers_count, panel_number, date_modified, selected_numbers)
                VALUES (@panelId, @ticketId, @quickpick, 
                        @cost, @summary, @sel_numbers_count, @pnl_numb, [dbo].f_getcustom_date(), @selected_numbers);
        COMMIT TRANSACTION

        SELECT 'Panel created' AS 'panel_id';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @error_number
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @error_number,'=>',@error_message)
        END;

        IF @error_number IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
            -- Throw custom error message
            THROW 60000, @error_message, 1;
        ELSE
            SELECT @error_message AS 'panel_id';
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_create_coresys_update_panels_3d') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_coresys_update_panels_3d >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_coresys_update_panels_3d >>>'
GO


IF OBJECT_ID('dbo.p_create_coresys_update_panels_bingo') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_coresys_update_panels_bingo
    IF OBJECT_ID('dbo.p_create_coresys_update_panels_bingo') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_coresys_update_panels_bingo >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_coresys_update_panels_bingo >>>'
END
GO
/******************************************************************************
* Object: p_create_coresys_update_panels_bingo.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: 
* Impacted Table(s): in_proc_coresys_update_panels_bingo.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2292: DB: Duplicate panels in in_proc tables
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_create_coresys_update_panels_bingo]
(
    @ticketId varchar(36), 
    @play_type int,
    @cost money,
    @summary nvarchar(200), 
    @pnl_numb int
)
AS
BEGIN
    DECLARE @panelId VARCHAR(36);
    DECLARE @error_number INT;
    DECLARE @error_message VARCHAR(MAX);

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs
    
    BEGIN try
        BEGIN TRANSACTION
            delete from in_proc_coresys_update_panels_bingo 
                where panel_id = @panelId
                AND panel_number = @pnl_numb;;

            SET @panelId = newId();
            insert into in_proc_coresys_update_panels_bingo (panel_id, ticket_id, cost, play_type, summary, panel_number,date_modified)
                VALUES(@panelId, @ticketId, @cost,  @play_type, @summary, @pnl_numb,[dbo].f_getcustom_date());
        COMMIT TRANSACTION

        SELECT 'Panel created' AS 'panel_id';
    END try
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @error_number
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @error_number,'=>',@error_message)
        END;

        IF @error_number IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
            -- Throw custom error message
            THROW 60000, @error_message, 1;
        ELSE
            SELECT @error_message AS 'panel_id';
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_create_coresys_update_panels_bingo') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_coresys_update_panels_bingo >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_coresys_update_panels_bingo >>>'
GO


IF OBJECT_ID('dbo.p_create_coresys_update_panels_lotto535') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_coresys_update_panels_lotto535
    IF OBJECT_ID('dbo.p_create_coresys_update_panels_lotto535') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_coresys_update_panels_lotto535 >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_coresys_update_panels_lotto535 >>>'
END
GO
/******************************************************************************
* Object: p_create_coresys_update_panels_lotto535
* Type: Stored Procedure
* Caller(s): DataTrak Trans Service (DTTS)
* Description: The service will call this store procedure 2 times:
*              First, before sending ticket to OSS, the SP updates the DTA DB with default
*              panel data (as a placeholder) before other method(s) in the service sends them
*              to OSS.
*
*              Second, after receiving ticket data from OSS, the SP updates the DTA DB
*              (in_proc) with OSS processed panel data before TTDS updates them into the
*              permanent tables.
*
*              If there is an existing row for the same (ticket_id, panel_number), that row
*              will be deleted first before inserting a new one.
* Impacted Table(s): in_proc_coresys_update_panels_lotto535
*
* Update(s) History:
*   PTR 2383 : DB: New Game Lotto 5/35 Development
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_create_coresys_update_panels_lotto535]
    @ticket_id VARCHAR(36),
    @quick_pick TINYINT,
    @selected_numbers VARCHAR(100),
	@selected_bonus_numbers VARCHAR(100),
	@cost MONEY,
    @summary VARCHAR(MAX),
    @pnl_numb INT
AS
BEGIN
    DECLARE @error_number INT
    DECLARE @error_message VARCHAR(MAX)

    SET XACT_ABORT ON; -- SET on to rollback automatically
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION
            DELETE FROM in_proc_coresys_update_panels_lotto535 
            WHERE ticket_id = @ticket_id 
                and panel_number = @pnl_numb;
                
            INSERT INTO in_proc_coresys_update_panels_lotto535 (ticket_id, quick_pick, selected_numbers, selected_bonus_numbers, cost, panel_number, summary, date_modified)
                VALUES (@ticket_id, @quick_pick, @selected_numbers, @selected_bonus_numbers, @cost, @pnl_numb, @summary, [dbo].f_getcustom_date());
        COMMIT TRANSACTION

        -- response after successful commit
        SELECT 'Panel created' AS 'panel_id';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @error_number
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @error_number,'=>',@error_message)
        END;

        IF @error_number IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
            -- Throw custom error message
            THROW 60000, @error_message, 1;
        ELSE
            SELECT @error_message AS 'panel_id';
    END CATCH
END;
GO
IF OBJECT_ID('dbo.p_create_coresys_update_panels_lotto535') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_coresys_update_panels_lotto535 >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_coresys_update_panels_lotto535 >>>'
GO


IF OBJECT_ID('dbo.p_create_coresys_winning_payments') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_coresys_winning_payments
    IF OBJECT_ID('dbo.p_create_coresys_winning_payments') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_coresys_winning_payments >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_coresys_winning_payments >>>'
END
GO
/******************************************************************************
* Object: p_create_coresys_winning_payments.
* Type: Stored Procedure.
* Caller(s): Process Winners Service (PWS).
* Description: Called when a winning ticket is processed to update the winning payment details in the database. 
* Impacted Table(s): in_proc_coresys_winning_payments. 
*                   in_proc_transaction_activities.
*                   coresys_winning_payments.
*                   in_proc_tickets.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2126: Selling ticket: Ticket has no VTID1, OSS Timestamp, Ticket cost
* PTR 2219: DB: Deadlock issue happened between DTTS & TTDS caused PAY ticket failed to update data completely
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_create_coresys_winning_payments] 
    @ticketId VARCHAR(36), 
    @transActivityId VARCHAR(36),
    @oss_date DATETIME2(7), 
    @oss_payment_amount MONEY, 
    @agentId VARCHAR(8), 
    @agentBal MONEY
AS
BEGIN
    DECLARE @errorNumber INT;
    DECLARE @error_message VARCHAR(MAX);
    DECLARE @rowCount INT = 0;

    DECLARE @transactionStatusIdComp UNIQUEIDENTIFIER = '6a56bdfb-0ff0-11e7-9454-b083feaf6ace'; -- status: completed
    DECLARE @agntWinningPaymentStatuscomp UNIQUEIDENTIFIER = '077fcc2a-724d-4d7f-990f-61b497773dd8'; -- completed

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    BEGIN TRY
        BEGIN TRANSACTION
            -- Insert winning payment details into in_proc_coresys_winning_payments
            INSERT INTO in_proc_coresys_winning_payments (
                ticket_id, 
                oss_winning_amount, 
                oss_payment_amount, 
                oss_winning_tax, 
                oss_processed_date, 
                date_modified
            )
            SELECT ticket_id,
                oss_winning_amount,
                @oss_payment_amount,
                oss_winning_tax,
                @oss_date,
                dbo.f_getcustom_date()
            FROM coresys_winning_payments 
            WHERE ticket_id = @ticketId;

            -- Updating is unnecessary as the updated record can be inserted above.
            -- Update winning payment details in in_proc_coresys_winning_payments
            /*UPDATE cw 
            SET oss_payment_amount = @oss_payment_amount, 
                oss_processed_date = @oss_date, 
                date_modified = dbo.f_getcustom_date()
            FROM in_proc_coresys_winning_payments cw 
            WHERE cw.ticket_id = @ticketId;*/

            -- Update agent account balance in in_proc_agents
            UPDATE in_proc_tickets 
                SET agnt_wnng_pymnt_status = @agntWinningPaymentStatuscomp -- completed
            WHERE ticket_id = @ticketId;
            
            -- Update transaction status in in_proc_transaction_activities
            UPDATE in_proc_transaction_activities 
                SET transaction_status_id = @transactionStatusIdComp,  -- status: completed
                    oss_agent_account_bal = @agentBal  
            WHERE transaction_activity_id = @transActivityId;
            -- not necessary to check since transaction_activity_id is unique and a primary key
            /*WHERE ticket_id = @ticketId
                AND transaction_activity_id = @transActivityId
                AND transaction_type_id = '966ead14-255c-4de4-b67d-28bd452582ea'   -- payout transaction type*/
        COMMIT TRANSACTION
        
        -- Return success only after commit
        SELECT '1' AS 'result';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @errorNumber,'=>',@error_message)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT @error_message AS 'result';
        END
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_create_coresys_winning_payments') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_coresys_winning_payments >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_coresys_winning_payments >>>'
GO



IF OBJECT_ID('dbo.p_create_ticket') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_ticket;
    IF OBJECT_ID('dbo.p_create_ticket') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_ticket >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_ticket >>>';
END;
GO
/******************************************************************************
* Object: p_create_ticket.
* Type: Stored Procedure.
* Caller(s): EAgent Web Service 1,2,3 (EWS).
* Description: Creates a ticket in the Database.
* Impacted Table(s): agents.
*                   customers.
*                   games.
*                   draw_data.
*                   in_proc_tickets.
*                   in_proc_transaction_activities.
*                   tickets.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I) 
* PTR 2356: 'NOLOCK' has been removed from statements that depend on columns such as 
*            panelCount to ensure we receive updated data.(drawdata) It has been retained on other statements
*            since those values do not change frequently enough to have an impact.
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.
* PTR 2267: TransTcktService: Ticket cant send to agent.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_create_ticket]
    @customer_id		VARCHAR(9),
    @game_id			INT,
    @drawoffSET			INT,
    @ticket_cost		MONEY,
    @system_number		INT,
    @sub_game			INT,
    @vtid			    VARCHAR(56),
    @transId			VARCHAR(36),
    @agent_id			VARCHAR(8),
    @agent_code			VARCHAR(1),
    @num_of_panels		INT,
    @agent_host_name	VARCHAR(MAX)
AS
BEGIN
    DECLARE @error_message VARCHAR(5000);
    DECLARE @validationError NVARCHAR(255);
    DECLARE @rowCount INT = 0;
    DECLARE @transaction_activity_id VARCHAR(36);
    DECLARE @panelCount INT;
    DECLARE @gameId INT;
    DECLARE @vtid2 VARCHAR(40);

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    BEGIN TRY 
        -- Combine Validations
        SELECT TOP 1 @validationError = 
            CASE 
                WHEN a2.agent_id IS NULL THEN 'Invalid Agent Code in Transaction ID'
                WHEN c.customer_id IS NULL THEN 'Invalid/Inactive Customer'
                WHEN g.game_id IS NULL THEN 'Game Disabled'
                WHEN (dd.selling_enabled_global IS NULL OR dd.selling_enabled_global = 0) THEN 'Global Selling Disabled'
                WHEN (dd.game_enabled IS NULL OR dd.game_enabled = 0) THEN 'Game Disabled'
                ELSE NULL
            END
        FROM agents a WITH (NOLOCK)
        LEFT JOIN customers c WITH(NOLOCK) --WITH (INDEX (ncidx_customers), NOLOCK)
            ON c.customer_id = @customer_id
            AND c.agent_id = @agent_id
            AND c.customer_status_id = 1
        LEFT JOIN games g WITH (NOLOCK)
            ON g.game_id = @game_id
            AND g.selling_enabled_game = 1
        LEFT JOIN draw_data dd
            ON dd.game_id = @game_id
		LEFT JOIN agents a2 
			ON a2.agent_id = @agent_id 
            AND a2.agent_host_name = @agent_host_name 
            AND a2.agent_code = @agent_code;

        -- Check for validation errors
        IF @validationError IS NOT NULL
        BEGIN
            SELECT '-1', @validationError;
            RETURN;
        END;

        SELECT TOP 1 @panelCount = panel_count,
            @gameId = game_id,
            @vtid2 = vtid2
        FROM in_proc_tickets WITH (NOLOCK)
        WHERE ticket_id = @transId;

        IF (
            @panelCount IS NULL 
                AND @gameId IS NULL
                AND @vtid2 IS NULL
        )
        BEGIN
            SELECT TOP 1 @panelCount = panel_count,
                @gameId = game_id,
                @vtid2 = vtid2
            FROM tickets WITH (NOLOCK)
            WHERE ticket_id = @transId;
        END;

        IF @panelCount IS NOT NULL
        BEGIN
            IF @panelCount > 0 -- if panel_count is greater than 0, which menas the ticket is processed completely by EAgent WS
            BEGIN
                SELECT 2, @transId;
                RETURN;
            END
            ELSE IF @panelCount = 0 -- if panel_count is 0, which menas the ticket is not completely processed by EAgent WS
            BEGIN
                SELECT 1, @transId;
                RETURN;
            END
            ELSE
            BEGIN
                SELECT -1,'Invalid Transaction'; -- if panel_count is less than 0, which menas the ticket is not valid
                RETURN;
            END;
        END;
        
        IF @gameId IS NOT NULL AND @gameId <> @game_id
        BEGIN
            SELECT -1,'Duplicate ticket id with different game ids';
            RETURN;
        END;
        
        IF @vtid2 IS NOT NULL AND @vtid2 <> @vtid
        BEGIN
            SELECT -1,'Duplicate ticket id with different vtid2(s)';
            RETURN;
        END;

        -- declare variables for transaction type and status
        DECLARE @trsactionTypeId UNIQUEIDENTIFIER = 'edf85abc-754b-11e6-9924-64006a4ba62f'; -- trsanction type sell
        DECLARE @transactionStatusId UNIQUEIDENTIFIER = '0ab02c66-0fef-11e7-9454-b083feaf6ace'; -- transaction status 'Not Processed'
    
        BEGIN TRANSACTION
            
            ---transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f'
            -- Insert the transaction activity details into in_proc_transaction_activities
            -- Insert the ticket details into in_proc_tickets
            INSERT INTO in_proc_tickets ( ticket_id, customer_id, game_id, sub_game_id, system_number, draw_offset, vtid2, cost, 
                    bet_result_type_id, panel_count, date_modified, date_created )
                VALUES ( @transId, @customer_id, @game_id, @sub_game, @system_number, @drawoffset, @vtid, @ticket_cost,
                    0, @num_of_panels, dbo.f_getcustom_date(), dbo.f_getcustom_date() );

            -- Use NEWSEQUENTIALID() instead of NEWID() to avoid fragmentation
            -- generate transaction_activity_id
            SET @transaction_activity_id = NEWID();
			INSERT INTO in_proc_transaction_activities ( transaction_activity_id, ticket_id, transaction_date, transaction_type_id, agent_id, date_modified, transaction_status_id )
                VALUES ( @transaction_activity_id, @transId, dbo.f_getcustom_date(), @trsactionTypeId, @agent_id,dbo.f_getcustom_date(), @transactionStatusId );
        COMMIT TRANSACTION

        -- response after successful insert
        SELECT '1',@transId;       
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @error_message = CONCAT('-81', ':', ERROR_NUMBER(), '=>',  ERROR_MESSAGE());
        SELECT '-1',@error_message;
    END CATCH; 
END;
GO
IF OBJECT_ID('dbo.p_create_ticket') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_ticket >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_ticket >>>';
GO



IF OBJECT_ID('dbo.p_create_ticket_panels') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_ticket_panels;
    IF OBJECT_ID('dbo.p_create_ticket_panels') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_ticket_panels >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_ticket_panels >>>';
END
GO
/******************************************************************************
* Object: p_create_ticket_panels.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: Add panel lotto data into in_proc_panels table.
* Impacted Table(s): in_proc_panels.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
* PTR 2358: Header Text Update.
* PTR 2292: DB: Duplicate panels in in_proc tables.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_create_ticket_panels]
    @ticketId VARCHAR(36),
    @cost MONEY,
    @numbers VARCHAR(75),
    @quickPick TINYINT,
    @pnl_number INT
AS
BEGIN
    DECLARE @panel_id UNIQUEIDENTIFIER;
    DECLARE @errorNumber INT;
    DECLARE @error_message VARCHAR(5000);

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- SET on to rollback automatically 

    BEGIN TRY 
        BEGIN TRANSACTION;
            -- changed to to using NEWSEQUENTIALID() instead of NEWID() to avoid fragmentation
            SET @panel_id = NEWID();			
            INSERT INTO in_proc_panels (panel_id, ticket_id, SELECTed_numbers, cost, quick_pick, panel_number, date_modified)
            VALUES(@panel_id, @ticketId, @numbers, @cost, @quickPick, @pnl_number, dbo.f_getcustom_date());
        COMMIT TRAN;

        -- return the panel_id after successful insert    
        SELECT '1', 'Panel Created Successfully';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @errorNumber, '=>',  @error_message)
        END;

        --IF @error LIKE '%UNIQUE KEY CONSTRAINT ''UK_in_proc_panels_panel_number''%'
        IF @errorNumber = 2627 -- Violation of PRIMARY KEY constraint
        BEGIN
            SELECT '1', 'UNIQUE/PRIMARY KEY violation on Existing Panel';
        END
        ELSE IF @errorNumber in (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1', @error_message;
        END 
    END CATCH;
END
GO
IF OBJECT_ID('dbo.p_create_ticket_panels') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_ticket_panels >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_ticket_panels >>>';
GO


IF OBJECT_ID('dbo.p_create_ticket_panels_3d') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_ticket_panels_3d
    IF OBJECT_ID('dbo.p_create_ticket_panels_3d') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_ticket_panels_3d >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_ticket_panels_3d >>>'
END
GO
/******************************************************************************
* Object: p_create_ticket_panels_3d.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: Insert a new panel into in_proc_panels_3d table.
* Impacted Table(s): in_proc_panels_3d.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2292: DB: Duplicate panels in in_proc tables
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_create_ticket_panels_3d]
    @ticketId VARCHAR(36),
    @cost MONEY,
    @quickPick TINYINT,
    @sel_numbers_count INT,
    @pnl_number INT,
    @selected_numbers NVARCHAR(MAX)
AS
BEGIN
    DECLARE @panelId UNIQUEIDENTIFIER;
    DECLARE @errorNumber INT;
    DECLARE @error_message VARCHAR(5000);

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Stop the message that shows the count of the number of rows affected by a query

    -- since we have a foreign key contraint and unique contraints on ticket_id and panel number not necessary to check for them here!
    BEGIN TRY
        BEGIN TRANSACTION
            --changed to to using NEWSEQUENTIALID() instead of NEWID() to avoid fragmentation
            SET @panelId = NEWID()
            INSERT INTO in_proc_panels_3d (in_proc_panels_3d_panel_id, ticket_id, cost, quick_pick, sel_numbers_count, panel_number, date_modified, selected_numbers)
            VALUES(@panelId, @ticketId, @cost, @quickPick, @sel_numbers_count, @pnl_number, dbo.f_getcustom_date(), @selected_numbers);
        COMMIT TRAN
        -- return the panel_id after successful insert
        SELECT '1', 'Panel Created Successfully';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @errorNumber, '=>',  @error_message)
        END;

        --IF @error_message LIKE '%UNIQUE KEY CONSTRAINT ''UK_in_proc_panels_3d_panel_number''%'
        IF @errorNumber = 2627 -- Unique constraint violation
        BEGIN
            SELECT '1', 'UNIQUE/PRIMARY KEY violation on Existing Panel';
        END
        ELSE IF @errorNumber in (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1', @error_message;
        END
    END CATCH;
END
GO
IF OBJECT_ID('dbo.p_create_ticket_panels_3d') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_ticket_panels_3d >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_ticket_panels_3d >>>'
GO


IF OBJECT_ID('dbo.p_create_ticket_panels_bingo') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_ticket_panels_bingo;
    IF OBJECT_ID('dbo.p_create_ticket_panels_bingo') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_ticket_panels_bingo >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_ticket_panels_bingo >>>';
END
GO
/******************************************************************************
* Object: p_create_ticket_panels_bingo.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: Add panel bingo data into in_proc_panels_bingo table.
* Impacted Table(s): in_proc_panels_bingo.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2292: DB: Duplicate panels in in_proc tables
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_create_ticket_panels_bingo]
    @ticketId VARCHAR(36),
    @cost MONEY,
    @play_type INT,
    @pnl_number INT
AS
BEGIN
    DECLARE @panel_id UNIQUEIDENTIFIER;
    DECLARE @errorNumber INT;
    DECLARE @error_message VARCHAR(5000);
    
    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- SET on to rollback automatically on error

    BEGIN TRY 
        BEGIN TRANSACTION
            -- changed to to using NEWSEQUENTIALID() instead of NEWID() to avoid fragmentation
            SET @panel_id = NEWID();
            INSERT INTO in_proc_panels_bingo (panel_id, ticket_id, cost, play_type, panel_number, date_modified)
            VALUES(@panel_id, @ticketId, @cost, @play_type, @pnl_number, dbo.f_getcustom_date());
        COMMIT TRANSACTION
            
        -- return the panel_id after successful insert
        SELECT '1', 'Panel Created Successfully';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @errorNumber, '=>',  @error_message)
        END;

        --IF @error LIKE '%Violation of PRIMARY KEY constraint%'
        IF @errorNumber = 2627 -- Violation of PRIMARY KEY constraint
        BEGIN
            SELECT '1', 'UNIQUE/PRIMARY KEY violation on Existing Panel';
        END
        ELSE IF @errorNumber in (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1', @error_message;
        END
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_create_ticket_panels_bingo') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_ticket_panels_bingo >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_ticket_panels_bingo >>>'
GO


IF OBJECT_ID('dbo.p_create_ticket_panels_lotto535') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_ticket_panels_lotto535;
    IF OBJECT_ID('dbo.p_create_ticket_panels_lotto535') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_ticket_panels_lotto535 >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_ticket_panels_lotto535 >>>';
END
GO
/******************************************************************************
* Object: p_create_ticket_panels_lotto535
* Type: Stored Procedure
* Caller(s): EAgent WebService (EWS)
* Description: Service will call this when adding new panel(s) during creating
*              ticket for game Lotto 535.
* Impacted Table(s): in_proc_panels_lotto535
*
* Update(s) History:
*   PTR 2383 : DB: New Game Lotto 5/35 Development
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_create_ticket_panels_lotto535]
    @ticket_id VARCHAR(36),
    @quick_pick TINYINT,
    @pnl_number INT,
    @selected_numbers VARCHAR(100),
    @selected_bonus_numbers VARCHAR(100),
    @cost MONEY
AS
BEGIN
    DECLARE @rev INT;

    SET XACT_ABORT ON; -- SET on to rollback automatically
    SET NOCOUNT ON;  

    BEGIN TRY
        BEGIN TRANSACTION
            INSERT INTO in_proc_panels_lotto535 (ticket_id, quick_pick, panel_number, selected_numbers, selected_bonus_numbers, cost, date_modified)
                VALUES(@ticket_id, @quick_pick, @pnl_number, @selected_numbers, @selected_bonus_numbers, @cost, dbo.f_getcustom_date());
        COMMIT TRAN

        -- response after successful commit
        SELECT '1', 'Panel created';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @error_number INT;
        DECLARE @error_message VARCHAR(MAX);

        -- Capture error details
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        --not necessary since we handle -1 and error message for all errors
        /*IF @error_number = 547 -- FOREIGN KEY constraint "FK_in_proc_panels_lotto535_ticket_id"
        BEGIN
            SET @rev = -1
            SELECT @Rev,'Invalid Ticket'
        END*/
        IF @error_number = 2627 -- UNIQUE KEY CONSTRAINT ''UQ_in_proc_panels_lotto535_ticket_panel'''
        BEGIN
            SELECT '1','Existing Panel';
        END
        ELSE
        BEGIN
            SET @error_message = CONCAT('TRANSACTION Error:', @error_number,'=>',@error_message);
            SELECT '-1', @error_message;
        END
    END CATCH
END;
GO
IF OBJECT_ID('dbo.p_create_ticket_panels_lotto535') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_ticket_panels_lotto535 >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_ticket_panels_lotto535 >>>';
GO


IF OBJECT_ID('dbo.p_create_winning_header_data') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_winning_header_data
    IF OBJECT_ID('dbo.p_create_winning_header_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_winning_header_data >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_winning_header_data >>>'
END
GO
/*****************************************************************************
* Object: p_create_winning_header_data
* Type: Stored Procedure
* Callers: PWS (Process Winners Service)
* Usage: Updates winning header table with prize_level and winning_numbers
* 
* previous Fix(es) : 
*
* current Fix(es):
*   PTR 2379 : DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2353 : Enable Xact_abort to ensure transactions are rolled back in case of any exception.
*   PTR 2358 : Header Text Update
*   PTR 2322 : DBs: IR 231014 - Bingo Draw Results not Sent to Agents    
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_create_winning_header_data]
    @service_flag VARCHAR(1),        -- required
    @file_version VARCHAR(20),        -- required
    @game_id INT,            -- required
    @draw_id INT,            -- required
    @draw_date DATETIME2,        -- required
    @winning_numbers VARCHAR(150),    -- required
    @prize_level NVARCHAR(max)     -- required
AS
BEGIN
    DECLARE @result VARCHAR(255)
    DECLARE @send_to_all_agents INT = -1 -- ref to bingo draw results
    DECLARE @row_count INT
    DECLARE @bingo_report INT = -1
    DECLARE @thwErrMsg VARCHAR(max)
    DECLARE @lockvar VARCHAR(max)

    SET XACT_ABORT ON -- Automatically roll back on any error 

    IF @game_id IN (105, 106)
    BEGIN
        SET @bingo_report = 0
        SET @send_to_all_agents = 0
    END

    BEGIN TRY 
        BEGIN TRAN
            -- Lock the object for synchronization
            SET @lockvar = CAST(@game_id AS VARCHAR) + CAST(@draw_id AS VARCHAR)
            EXEC p_spgetapplock @lockvar

            IF NOT EXISTS (
                SELECT 1 FROM winning_header_data WITH(NOLOCK) 
                WHERE game_id = @game_id 
                    AND draw_id = @draw_id 
                    AND draw_date = @draw_date -- Avoid unnecessary conversions
                    AND file_version = @file_version)
            BEGIN
                INSERT INTO winning_header_data (file_version, game_id, draw_date, draw_id, winning_numbers, date_modified, process_status, prize_level, send_to_all_agents, bingo_report_generated)
                    VALUES (@file_version, @game_id, @draw_date, @draw_id, @winning_numbers, [dbo].f_getcustom_date(), 0, @prize_level, @send_to_all_agents, @bingo_report)

                SET @row_count = @@ROWCOUNT
            END
            ELSE
            BEGIN
                -- For Process Winners Service
                IF @service_flag = 'w'
                BEGIN
                    UPDATE winning_header_data 
                    SET prize_level = @prize_level, 
                        draw_date = @draw_date 
                    WHERE game_id = @game_id 
                        AND draw_id = @draw_id 
                        AND draw_date = @draw_date -- Avoid unnecessary conversions
                        AND file_version = @file_version

                    SET @row_count = @@ROWCOUNT
                END
                -- For Process Draw Results Service
                ELSE IF @service_flag = 'd'
                BEGIN
                    UPDATE winning_header_data 
                    SET winning_numbers = @winning_numbers
                    WHERE game_id = @game_id 
                        AND draw_id = @draw_id 
                        AND draw_date = @draw_date
                        AND file_version = @file_version

                    SET @row_count = @@ROWCOUNT
                END
            END
        COMMIT TRAN

        IF @row_count > 0
        BEGIN
            SELECT '1' , 'Successfully Updated'
        END
        ELSE
        BEGIN
            SELECT '-1', 'Update Failed' 
        END
    END TRY
    BEGIN CATCH
    -- Handle any errors by rolling back the transaction
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION
        END

        IF ERROR_NUMBER() IN (1204, -- SqlOutOfLocks
                              1205, -- SqlDeadlockVictim
                              1222 -- SqlLockRequestTimeout
                              )
        BEGIN
            SET @thwErrMsg = CAST(ERROR_NUMBER() AS NVARCHAR) + ': A SqlOutOfLocks/Deadlock/LockRequestTimeout occurred';
            THROW 60000, @thwErrMsg, 1
        END
        ELSE
        Begin
            SET @result = CONCAT('-81:',' message = ', ERROR_NUMBER(),':',ERROR_MESSAGE())
            SELECT '-1',@result as 'result'
        END
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_create_winning_header_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_winning_header_data >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_winning_header_data >>>'
GO


IF OBJECT_ID('dbo.p_create_winning_upload_status') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_create_winning_upload_status
    IF OBJECT_ID('dbo.p_create_winning_upload_status') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_create_winning_upload_status >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_create_winning_upload_status >>>'
END
GO
/******************************************************************************
* Object:                p_create_winning_upload_status.
* Type:                  Stored Procedure.
* Caller(s):             Process Winners Service (PWS).
* Description:           Insert a record into the winning_upload_status table if it doesn't already exist.
* Impacted Table(s):     winning_upload_status.
*  
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Keep 'NOLOCK' since the condition check is on a column(s) that does not change frequently.
*   PTR 2358: Header Text Update.
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_create_winning_upload_status]
    @file_version VARCHAR(20),   -- required
    @game_id INT,                 -- required
    @draw_id INT,                 -- required
    @draw_date DATETIME2,         -- required
    @agent_id VARCHAR(8)         -- required
AS
BEGIN
    DECLARE @row_count INT
    DECLARE @errorNumber INT;
    DECLARE @error_message VARCHAR(MAX);

    SET NOCOUNT ON;  
    SET XACT_ABORT ON; --rollback transaction

    IF EXISTS (
        SELECT 1 
        FROM winning_upload_status WITH(NOLOCK)
        WHERE game_id = @game_id  
            AND draw_id = @draw_id 
            AND agent_id = @agent_id
    )
    BEGIN
        SELECT '1','Already EXISTS'
        RETURN;
    END

    BEGIN TRY
        BEGIN TRAN
            -- Insert new record
            INSERT INTO winning_upload_status 
                (file_version,game_id,draw_date,draw_id,agent_id,upload_status,date_modified) 
            VALUES
                (@file_version,@game_id,@draw_date,@draw_id,@agent_id,0,dbo.f_getcustom_date())
        
            SET @row_count = @@ROWCOUNT
        COMMIT TRAN

        --return after success
        IF @row_count > 0
        BEGIN
            SELECT '1','Data Added Successfully'
        END
        ELSE
        BEGIN
            SELECT '-1','Failed to add data'
        END
    END TRY
    -- Check whether the update was successful
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION

        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-1', ':', @errorNumber,'=>',@error_message)
        END;

        SELECT @error_message
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_create_winning_upload_status') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_create_winning_upload_status >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_create_winning_upload_status >>>'
GO


IF OBJECT_ID('dbo.p_delete_ticket') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_delete_ticket
    IF OBJECT_ID('dbo.p_delete_ticket') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_delete_ticket >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_delete_ticket >>>'
END
GO
/******************************************************************************
* Object: p_delete_ticket.
* Type: Stored Procedure.
* Caller(s): DataTrakTranservce (DTTS).
* Description: Deletes the ticket from the in_proc tables.
* Impacted Table(s): in_proc_tickets.
*                    in_proc_coresys_update_panels.
*                    in_proc_coresys_update_panels_3d.
*                    in_proc_coresys_update_panels_bingo.
*                    in_proc_coresys_update_panels_lotto535.
*                    in_proc_panels.
*                    in_proc_panels_3d.
*                    in_proc_panels_bingo.
*                    in_proc_panels_lotto535.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2356: Remove 'NOLOCK' to get the commited data. 
* PTR 2358: Header Text Update.
* PTR 2294: EAgentWS: IR - 230420 - eTicket Pending
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_delete_ticket]
    -- Add the parameters for the stored procedure here
    @ticket_id			VARCHAR(36)
AS
BEGIN
    DECLARE @thwErrMsg VARCHAR(100);
    DECLARE @game_id INT;
    DECLARE @res_from_query INT = 0;
    DECLARE @paneCount INT;
    DECLARE @tableName VARCHAR(50);
    DECLARE @rowCount INT;
    DECLARE @query NVARCHAR(MAX);

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    BEGIN TRY
        -- get game_id and panel_count
        SELECT TOP 1 @game_id = game_id,
            @paneCount = panel_count
        FROM in_proc_tickets
        WHERE ticket_id = @ticket_id;

        -- check if ticket exists
        IF @game_id IS NULL AND @paneCount IS NULL
        BEGIN
            SELECT '2','Ticket does not exist in in_proc table';
            RETURN;
        END;
        
        -- check if ticcket has panel count > 0
        IF @paneCount IS NOT NULL AND @paneCount > 0
        BEGIN
            SELECT '2','Cannot delete because the ticket is not an error and will be processed by DTTS';
            RETURN;
        END ;

        -- select the in_proc_coresys tables based on game_id
        SET @tableName = CASE WHEN @game_id IN (100,101) THEN 'in_proc_coresys_update_panels'
            WHEN @game_id IN (102,103) THEN 'in_proc_coresys_update_panels_3d'
            WHEN @game_id IN (105) THEN 'in_proc_coresys_update_panels_bingo'
            WHEN @game_id IN (106) THEN 'in_proc_coresys_update_panels_lotto535'
            ELSE NULL
        END;

        -- if tablename is null, return invalid game_id
        IF @tableName IS NOT NULL
        BEGIN
            -- Construct dynamic SQL for checking existence
            SET @query = 'IF EXISTS (SELECT 1 FROM ' + @tableName + 
                ' WHERE ticket_id = @ticket_id) ' +
                'SET @res_from_query = 1 ELSE SET @res_from_query = 0';

            -- Execute dynamic SQL
            EXEC sp_executesql @query, N'@res_from_query INT OUTPUT, @ticket_id NVARCHAR(36)', 
                @res_from_query OUTPUT, @ticket_id;
        END;
        ELSE
        BEGIN
            SELECT '2','Invalid game_id';
            RETURN;
        END;

        -- check if ticket exists in in_proc_coresys table
        IF @res_from_query = 1
        BEGIN
            SELECT '2','Cannot delete because the ticket is not an error and will be processed by DTTS';
            RETURN;
        END;

        -- delete ticket from in_proc tables
        BEGIN TRANSACTION
            DELETE FROM in_proc_panels WHERE ticket_id = @ticket_id;
            DELETE FROM in_proc_panels_3d WHERE ticket_id = @ticket_id;
            DELETE FROM in_proc_panels_bingo WHERE ticket_id = @ticket_id;
            DELETE FROM in_proc_panels_lotto535 WHERE ticket_id = @ticket_id;
            DELETE FROM in_proc_transaction_activities WHERE ticket_id = @ticket_id;
            DELETE FROM in_proc_tickets WHERE ticket_id = @ticket_id;
        COMMIT TRANSACTION

        -- return after transaction is committed
        SELECT '1','Deleted successfully';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SELECT '-1',CONCAT('-81', ':', ERROR_NUMBER(),'=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_delete_ticket') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_delete_ticket >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_delete_ticket >>>'
GO


IF OBJECT_ID('dbo.p_get_all_winning_draw_id') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_all_winning_draw_id
    IF OBJECT_ID('dbo.p_get_all_winning_draw_id') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_all_winning_draw_id >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_all_winning_draw_id >>>'
END
GO
/******************************************************************************
* Object:                p_get_all_winning_draw_id.
* Type:                  Stored Procedure.
* Caller(s):             EAgent WebService.
* Description:           Retrieve the drawId from the winning_header_data table for bingo.
* Impacted Table(s):     winning_header_data.
*  
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Remove 'NOLOCK' because we need to retrieve the drawId after updating the send_to_all_agents flag.
*   PTR 2358: Header Text Update.    
*******************************************************************************/
CREATE PROCEDURE dbo.p_get_all_winning_draw_id
AS
BEGIN
    SELECT draw_id 
    FROM winning_header_data 
    WHERE game_id IN (105,106) 
        AND send_to_all_agents = 0; -- 105: bingo; 106: lotto 5/35
END
GO
IF OBJECT_ID('dbo.p_get_all_winning_draw_id') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_all_winning_draw_id >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_all_winning_draw_id >>>'
GO

IF OBJECT_ID('dbo.p_get_core_update_panel_lotto535_data_srch') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_core_update_panel_lotto535_data_srch;
    IF OBJECT_ID('dbo.p_get_core_update_panel_lotto535_data_srch') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_core_update_panel_lotto535_data_srch >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_core_update_panel_lotto535_data_srch >>>';
END;
GO
/****************************************************************************
* Object: p_get_core_update_panel_lotto535_data_srch
* Type: Stored Procedure
* Caller(s): DataTrak Trans Service (DTTS)
* Description: At the start of the service, this SP will be called so that
*              ticket panel(s) data can be retrieved for retransmission if
*              there were tickets for retransmission.
* Impacted Table(s): N/A
*
* Update(s) History:
*   PTR 2383 : DB: New Game Lotto 5/35 Development
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_core_update_panel_lotto535_data_srch]
    @ticket_id VARCHAR(36)
AS
BEGIN

    SET NOCOUNT ON;

    SELECT
        selected_numbers,
        selected_bonus_numbers,
        quick_pick,
        panel_number,
        cost
    FROM in_proc_coresys_update_panels_lotto535 WITH (NOLOCK)
    WHERE ticket_id = @ticket_id
    ORDER BY panel_number;
END;
GO
IF OBJECT_ID('dbo.p_get_core_update_panel_lotto535_data_srch') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_core_update_panel_lotto535_data_srch >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_core_update_panel_lotto535_data_srch >>>';
GO


IF OBJECT_ID('dbo.p_get_coresys_panel_count') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_coresys_panel_count;
    IF OBJECT_ID('dbo.p_get_coresys_panel_count') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_coresys_panel_count >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_coresys_panel_count >>>';
END;
GO
/******************************************************************************
* Object: p_get_coresys_panel_count.
* Type: Stored Procedure.
* Caller(s): Datatrak Trans Service (DTTS).
* Description: To get number of panels in in_proc_coresys table(s) for the input ticketId.
* Impacted Table(s): in_proc_coresys_update_panels.
*                    in_proc_coresys_update_panels_3d.
*                    in_proc_coresys_update_panels_bingo.
*                    tickets. 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2356: Keep 'NOLOCK' because the condition check and data retrieval are performed 
*				on column(s) that do not change frequently.
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2220: Selling ticket: Lost winning files
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_get_coresys_panel_count]
(
    @ticketId	VARCHAR(36)		--required
)
AS
BEGIN
    DECLARE @gameId INT;

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query

    SELECT @gameId = game_id 
    FROM tickets WITH(NOLOCK) 
    WHERE ticket_id = @ticketId;

    IF (@gameId IN (100,101))
    BEGIN
        SELECT COUNT(*) 
        FROM in_proc_coresys_update_panels in_cp WITH(NOLOCK) 
        WHERE in_cp.summary <> '' OR in_cp.summary IS NOT NULL
            AND in_cp.ticket_id = @ticketId;
    END;
    ELSE IF (@gameId IN (101,102))
    BEGIN
        SELECT COUNT(*) 
        FROM in_proc_coresys_update_panels_3d in_cp WITH(NOLOCK) 
        WHERE in_cp.summary <> '' OR in_cp.summary IS NOT NULL
            AND in_cp.ticket_id = @ticketId;
    END;
    ELSE IF (@gameId IN (105))
    BEGIN
        SELECT COUNT(*) 
        FROM in_proc_coresys_update_panels_bingo in_cp WITH(NOLOCK) 
        WHERE in_cp.summary <> '' OR in_cp.summary IS NOT NULL
            AND in_cp.ticket_id = @ticketId;
    END;
END;
GO
IF OBJECT_ID('dbo.p_get_coresys_panel_count') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_coresys_panel_count >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_coresys_panel_count >>>';
GO


IF OBJECT_ID('dbo.p_get_in_proc_oss_confirmed_tickets') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_in_proc_oss_confirmed_tickets
    IF OBJECT_ID('dbo.p_get_in_proc_oss_confirmed_tickets') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_in_proc_oss_confirmed_tickets >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_in_proc_oss_confirmed_tickets >>>'
END
GO
----------------- NOT IN USE -----------------
/******************************************************************************
* Object: p_get_in_proc_oss_confirmed_tickets.
* Type: Stored Procedure.
* Caller(s): Transfer Ticket Data Service (TTDS)
* Description: To get OSS confirmed tickets that are moved back into in_proc for pay.
* Impacted Table(s): in_proc_tickets.
*                    in_proc_transaction_activities.
*                    agents.
*                    error_status.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_in_proc_oss_confirmed_tickets]
(
    @agent_host_name	VARCHAR(MAX)		--required
)
AS
BEGIN
    
    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query

    SELECT 
        in_t.ticket_id,
        in_ta.transaction_type_id,
        in_ta.transaction_activity_id,
        in_ta.agent_id,
        --ticket details
        in_t.customer_id AS 'custid',
        in_t.game_id AS 'gameid',
        in_t.sub_game_id AS 'subgame',
        in_ta.transaction_status_id AS 'status',
        in_t.vtid1 AS 'vtid1',
        in_ta.oss_processed_date AS 'oss_processed_date',
        in_t.draw_date AS 'drawdate',
        in_t.draw_id AS 'drawid',
        in_ta.oss_updated_cost AS 'tcst',
        in_ta.oss_agent_account_bal AS 'agntbal',
        e.error_status_description AS 'error',
        in_t.system_number AS 'system'
    FROM in_proc_tickets in_t
        INNER JOIN in_proc_transaction_activities in_ta --WITH (INDEX(idx_trans_activities), NOLOCK) 
            ON in_ta.ticket_id = in_t.ticket_id
            AND in_ta.processed_trans_flag = 1
        INNER JOIN agents a
            ON a.agent_id = in_ta.agent_id
            AND a.agent_host_name = @agent_host_name
        LEFT JOIN error_status e 
                ON e.error_status_id = in_ta.error_status_id
    WHERE NOT EXISTS(
            SELECT 1 
            FROM tickets t WITH (NOLOCK)
            WHERE t.ticket_id = in_t.ticket_id
        );
END
GO
IF OBJECT_ID('dbo.p_get_in_proc_oss_confirmed_tickets') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_in_proc_oss_confirmed_tickets >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_in_proc_oss_confirmed_tickets >>>'
GO


IF OBJECT_ID('dbo.p_get_num_of_winning_files') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_num_of_winning_files
    IF OBJECT_ID('dbo.p_get_num_of_winning_files') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_num_of_winning_files >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_num_of_winning_files >>>'
END
GO
/******************************************************************************
* Object:                p_get_num_of_winning_files.
* Type:                  Stored Procedure.
* Caller(s):
* Description:           Retrieve num_of winning files from winning_upload_status.
* Impacted Table(s):     winning_upload_status.
*
* Update(s) History:
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Remove 'NOLOCK' since we need to get the committed data.
*   PTR 2358: Header Text Update.
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_get_num_of_winning_files]     
    @game_id INT,
    @draw_id INT,
    @agent_id VARCHAR(8)
AS
BEGIN
    SELECT 
        num_files_to_be_uploaded, 
        num_files_uploaded 
    FROM winning_upload_status
    WHERE game_id = @game_id 
        AND draw_id = @draw_id 
        AND agent_id = @agent_id
END
GO
IF OBJECT_ID('dbo.p_get_num_of_winning_files') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_num_of_winning_files >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_num_of_winning_files >>>'
GO


IF OBJECT_ID('dbo.p_get_oss_agent_noupld_winning_tickets') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets
    IF OBJECT_ID('dbo.p_get_oss_agent_noupld_winning_tickets') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets >>>'
END
GO
/******************************************************************************
* Object:                p_get_oss_agent_noupld_winning_tickets.
* Type:                  Stored Procedure.
* Caller(s):             
* Description:           Retrieve records FROM winning_header_data WHERE the process_status flag IS SET to 1.
* Impacted Table(s):     winning_header_data
*                        tickets.
*                        transaction_activities.
*  
* Update(s) History:
*   Hot fix: revert the check on filter !! (2025-02-27)
*   PTR 2381: TWS: Prevent looping of the SP call delaying the main thread of resources
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Remove 'NOLOCK' FROM the winning_header_data table because we need to obtain the data based on the committed bet_result_type_id value.
*   PTR 2358: Header Text Update.
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_get_oss_agent_noupld_winning_tickets]
(
    @agent_id	        VARCHAR(10),		--required
    @game_id	        VARCHAR(10),   --required
    @draw_id	        VARCHAR(10),		--required
    @nRecordsRetrieved INT
)
AS
BEGIN
    SELECT TOP (@nRecordsRetrieved) 
        tck.ticket_id, 
        ta.agent_id, 
        tck.customer_id, 
        tck.game_id, 
        tck.draw_id, 
        tck.draw_date
    FROM winning_header_data w
        INNER JOIN tickets tck WITH (NOLOCK) 
            ON tck.game_id = w.game_id  
            AND tck.draw_id = w.draw_id
        INNER JOIN transaction_activities ta WITH (NOLOCK) 
            ON ta.ticket_id = tck.ticket_id
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f' --sell	
            AND ta.agent_id = @agent_id	
    WHERE 
        tck.game_id = @game_id AND
        tck.draw_id = @draw_id AND
        tck.agnt_wnng_upload_status = '141b82f5-127d-4846-8e3a-4aa9c4ee75e8' AND
        tck.bet_result_type_id > 0 AND
        w.process_status = 1
	--ORDER BY ta.agent_id,tck.draw_id
END
GO
IF OBJECT_ID('dbo.p_get_oss_agent_noupld_winning_tickets') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets >>>'
GO

IF OBJECT_ID('dbo.p_get_oss_agent_noupld_winning_tickets_count') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets_count
    IF OBJECT_ID('dbo.p_get_oss_agent_noupld_winning_tickets_count') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets_count >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets_count >>>'
END
GO
/******************************************************************************
* Object: p_get_oss_agent_noupld_winning_tickets_count.
* Type: Stored Procedure.
* Caller(s): Process Winners Service (PWS).
* Description: Returns the count of winning tickets that are not uploaded for a specific agent.
* Impacted Table(s): tickets.
*                    transaction_activities.
*                    winning_header_data.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I) 
* PTR 2356: Remove NOLOCK to get commited data
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_get_oss_agent_noupld_winning_tickets_count]
(
    @agent_id	        VARCHAR(8),		--required
    @game_id	        INT,            --required
    @draw_id	        INT		        --required
)
AS
BEGIN
    DECLARE @agntWinningPymtStatus UNIQUEIDENTIFIER = '141b82f5-127d-4846-8e3a-4aa9c4ee75e8' -- Not Uploaded
    DECLARE @transactionTypeId UNIQUEIDENTIFIER = 'edf85abc-754b-11e6-9924-64006a4ba62f' -- Sell

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query  

    SELECT COUNT(tck.ticket_id) AS tickets_count
    FROM tickets tck
    WHERE tck.game_id = @game_id
        AND tck.draw_id = @draw_id
        AND tck.agnt_wnng_upload_status = @agntWinningPymtStatus  
        AND tck.bet_result_type_id > 0
        AND EXISTS (
            SELECT 1
            FROM winning_header_data w
            WHERE w.game_id = tck.game_id 
                AND w.draw_id = tck.draw_id
                AND w.process_status = 1
        )
        AND EXISTS (
            SELECT 1
            FROM transaction_activities ta
            WHERE ta.ticket_id = tck.ticket_id
                AND ta.transaction_type_id = @transactionTypeId -- Sell
                AND ta.agent_id = @agent_id
        );
END
GO
IF OBJECT_ID('dbo.p_get_oss_agent_noupld_winning_tickets_count') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets_count >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_agent_noupld_winning_tickets_count >>>'
GO


IF OBJECT_ID('dbo.p_get_oss_confirmed_panel_details') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_confirmed_panel_details
    IF OBJECT_ID('dbo.p_get_oss_confirmed_panel_details') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_confirmed_panel_details >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_confirmed_panel_details >>>'
END
GO
/******************************************************************************
* Object: p_get_oss_confirmed_panel_details.
* Type: Stored Procedure.
* Caller(s): Transfer Ticket Data Service (TTDS) 			
* Description: Called by TTDS to retrieve panel details(lotto). 			
* Impacted Table(s): in_proc_coresys_update_panels.
*                    in_proc_panels.	
*
* Update(s) History: 
* PTR 2356: Rmove 'NOLOCK' to get commited data.
* PTR 2358: Header Text Update.
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_oss_confirmed_panel_details]
(
    @ticket_id	varchar(36) = ''   --required
)
AS
BEGIN
    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query

    IF EXISTS (
        SELECT 1 
        FROM in_proc_coresys_update_panels 
        WHERE ticket_id = @ticket_id
    )
    BEGIN
        SELECT p.coresys_update_panel_id AS 'panel_id', 
            p.panel_number,
            p.selected_numbers,
            p.cost, 
            p.quick_pick, 
            p.bonus_number
        FROM in_proc_coresys_update_panels p
        WHERE p.ticket_id = @ticket_id
        ORDER BY p.panel_number ASC
    END
    ELSE
    BEGIN
        SELECT p.panel_id AS 'panel_id', 
            p.panel_number,
            p.selected_numbers,
            p.cost, 
            p.quick_pick, 
            p.bonus_number
        FROM in_proc_panels p
        WHERE p.ticket_id = @ticket_id
        ORDER BY p.panel_number ASC
    END
END
GO
IF OBJECT_ID('dbo.p_get_oss_confirmed_panel_details') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_confirmed_panel_details >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_confirmed_panel_details >>>'
GO



IF OBJECT_ID('dbo.p_get_oss_confirmed_panel_lotto535_details') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_confirmed_panel_lotto535_details;
    IF OBJECT_ID('dbo.p_get_oss_confirmed_panel_lotto535_details') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_confirmed_panel_lotto535_details >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_confirmed_panel_lotto535_details >>>';
END;
GO
/****************************************************************************
* Object: p_get_oss_confirmed_panel_lotto535_details
* Type: Stored Procedure
* Caller(s): Trans Ticket Data Service (TTDS)
* Description: Service will call this when sending ticket data back to agents.
*              This store will get list of OSS confirmed panel(s) for Lotto 535.
* Impacted Table(s): N/A
*
* Update(s) History:
*   PTR 2383 : DB: New Game Lotto 5/35 Development
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_oss_confirmed_panel_lotto535_details]
    @ticket_id VARCHAR(36)
AS
BEGIN

    SET NOCOUNT ON;

	IF EXISTS (
        SELECT 1 
        FROM in_proc_coresys_update_panels_lotto535 
        WHERE ticket_id = @ticket_id
    )
	BEGIN
		SELECT 
			panel_id,
			selected_numbers,
			selected_bonus_numbers,
			cost,
			quick_pick,
			panel_number
		FROM in_proc_coresys_update_panels_lotto535 WITH (NOLOCK)
		WHERE ticket_id = @ticket_id
		ORDER BY panel_number;
	END
    ELSE
    BEGIN
		SELECT 
			panel_id,
			selected_numbers,
			selected_bonus_numbers,
			cost,
			quick_pick,
			panel_number
		FROM in_proc_panels_lotto535 WITH (NOLOCK)
		WHERE ticket_id = @ticket_id
		ORDER BY panel_number;
	END
END;
GO
IF OBJECT_ID('dbo.p_get_oss_confirmed_panel_lotto535_details') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_confirmed_panel_lotto535_details >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_confirmed_panel_lotto535_details >>>';
GO


IF OBJECT_ID('dbo.p_get_oss_confirmed_ticket_details') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_confirmed_ticket_details
    IF OBJECT_ID('dbo.p_get_oss_confirmed_ticket_details') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_confirmed_ticket_details >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_confirmed_ticket_details >>>'
END
GO
------------------------------------------------------------Not in use------------------------------------------------------------
CREATE PROCEDURE [dbo].[p_get_oss_confirmed_ticket_details]
(
    @ticket_id	varchar(36) = ''   --required
)
AS
BEGIN
    SELECT  t.customer_id AS 'custid'
            ,t.ticket_id AS 'transid'
            ,t.game_id AS 'gameid'
            ,t.sub_game_id AS 'subgame'
            ,ta.transaction_status_id AS 'status'
            ,iif(t.vtid1 IS NULL,'',t.vtid1) AS 'vtid1'
            ,iif(ta.oss_processed_date IS NULL,'',convert(varchar,ta.oss_processed_date,112)) AS 'date'
            ,iif(ta.oss_processed_date IS NULL,'',REPLACE(CONVERT(varchar(5), ta.oss_processed_date, 108), ':', '')) AS 'time'
            ,iif(t.draw_date IS NULL,'',convert(varchar,t.draw_date,112)) AS 'drawdate'
            ,iif(t.draw_id IS NULL,'', RIGHT('00000'+CAST(t.draw_id AS VARCHAR(7)),7)) AS 'drawid'
            ,iif(ta.oss_updated_cost IS NULL , 0 , cast(round(ta.oss_updated_cost,0)AS bigint)) AS 'tcst'
            ,iif(ta.oss_agent_account_bal IS NULL,0,cast(round(ta.oss_agent_account_bal,0)AS bigint)) AS 'agntbal'
            ,iif(e.error_status_description IS NULL, '',e.error_status_description) AS 'error'
            --
            ,t.system_number AS 'system'
    FROM in_proc_tickets t WITH (NOLOCK)
        INNER JOIN in_proc_transaction_activities ta WITH (NOLOCK) ON ta.ticket_id = t.ticket_id
        LEFT JOIN error_status e ON e.error_status_id = ta.error_status_id
    WHERE t.ticket_id = @ticket_id
END
GO
IF OBJECT_ID('dbo.p_get_oss_confirmed_ticket_details') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_confirmed_ticket_details >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_confirmed_ticket_details >>>'
GO


IF OBJECT_ID('dbo.p_get_oss_confirmed_tickets') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_confirmed_tickets
    IF OBJECT_ID('dbo.p_get_oss_confirmed_tickets') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_confirmed_tickets >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_confirmed_tickets >>>'
END
GO
/******************************************************************************
* Object: p_get_oss_confirmed_tickets.
* Type: Stored Procedure.
* Caller(s): Transfer Ticket Data Service (TTDS)
* Description: TTDS calls the procedure to retrieve Completed/Error transactions. 
               These transactions are then moved from in_proc tables to permanent tables.  		
* Impacted Table(s): in_proc_transaction_activities.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
* PTR 2308: DBs: BGT Requested to Merge All Undeployed DB Release into One
* PTR 2316: DTA: Processing Ticket - 22 tickets can not process when stop SQL Database
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_oss_confirmed_tickets]
(
    @agent_host_name	varchar(255)		--required
)
As
BEGIN
    DECLARE @error_message NVARCHAR(4000);
    DECLARE @errorNumber INT;
    DECLARE @nRecordsRetrieved INT = 100; -- number of records to retrieve
    DECLARE @agent_confirmed_receipt INT = 0; -- to select only records with agent_confirmed_receipt = 0 ( not picked by TTDS )

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    DECLARE @tempComplTrans TABLE (
        transaction_activity_id VARCHAR(36),
        ticket_id VARCHAR(36),
        agent_id VARCHAR(8),
        transaction_type_id VARCHAR(36),
        customer_id VARCHAR(9),
        game_id INT,
        sub_game_id INT,
        transaction_status_id VARCHAR(36),
        vtid1 VARCHAR(50),
        oss_processed_date DATETIME2(7),
        draw_date DATETIME2(7),
        draw_id INT,
        oss_updated_cost MONEY,
        oss_agent_account_bal MONEY,
        error_status_description NVARCHAR(MAX),
        system_number INT
    );

    BEGIN TRY
        INSERT INTO @tempComplTrans (
            transaction_activity_id,
            ticket_id,
            agent_id,
            transaction_type_id,
            customer_id,
            game_id,
            sub_game_id,
            transaction_status_id,
            vtid1,
            oss_processed_date,
            draw_date,
            draw_id,
            oss_updated_cost,
            oss_agent_account_bal,
            error_status_description,
            system_number
        ) SELECT 
            transaction_activity_id,
            ticket_id, 
            agent_id,
            transaction_type_id,
            customer_id,
            game_id,
            sub_game_id,
            transaction_status_id,
            vtid1,
            oss_processed_date,
            draw_date,
            draw_id,
            oss_updated_cost,
            oss_agent_account_bal,
            error_status_description,
            system_number
        FROM dbo.f_oss_confirmed_tickets(@nRecordsRetrieved, @agent_confirmed_receipt, @agent_host_name);
  
        BEGIN TRANSACTION
            --Update agent confirmed receipt status to processing
            UPDATE in_proc_ta
            SET agent_confirmed_receipt = 2
            FROM in_proc_transaction_activities in_proc_ta 
                INNER JOIN @tempComplTrans oc 
                    ON in_proc_ta.transaction_activity_id = oc.transaction_activity_id;
        COMMIT TRANSACTION

        --return to the caller
        SELECT 
            transaction_activity_id, 
            ticket_id, 
            agent_id,
            transaction_type_id,
            --ticket details
            customer_id AS 'custid',
            game_id AS 'gameid',
            sub_game_id AS 'subgame',
            transaction_status_id AS 'status',
            vtid1 AS 'vtid1',
            oss_processed_date AS 'oss_processed_date',
            draw_date AS 'drawdate',
            draw_id AS 'drawid',
            oss_updated_cost AS 'tcst',
            oss_agent_account_bal AS 'agntbal',
            error_status_description AS 'error',
            system_number AS 'system'
        FROM @tempComplTrans;
    END TRY
    BEGIN catch
         -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        -- Handle specific SQL errors with custom messages
        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT(@errorNumber, '=>',  @error_message)
        END;
        -- Throw custom error for specific SQL errors
        IF @errorNumber IN (1204,1205,1222)
        BEGIN
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            -- Return generic error message
            SELECT '-1', @error_message;
        END
    END catch;
END;
GO
IF OBJECT_ID('dbo.p_get_oss_confirmed_tickets') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_confirmed_tickets >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_confirmed_tickets >>>'
GO


IF OBJECT_ID('dbo.p_get_oss_noupld_draws') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_noupld_draws
    IF OBJECT_ID('dbo.p_get_oss_noupld_draws') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_noupld_draws >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_noupld_draws >>>'
END
GO
/******************************************************************************
* Object:                p_get_oss_noupld_draws.
* Type:                  Stored Procedure.
* Caller(s):             Transfer Winner Service (TWS).
* Description:           Returns draw ids to be transfered to agents
* Impacted Table(s):     
*  
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Remove 'NOLOCK' to ensure we retrieve the updated data based on Process Status and Upload Status flag values.
*   PTR 2358: Header Text Update.
*   PTR 2297: TWS: IR 230513 - PW Abnormal winning file
*   PTR 2184: Transfer winner service
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_get_oss_noupld_draws]
    @agent_id VARCHAR(8)
AS
BEGIN
    DECLARE @agent_count INT
    DECLARE @draw_game_count INT
    DECLARE @draw_id INT
    DECLARE @game_id INT

    SET XACT_ABORT ON --rollback transaction

    -- Use a table variable instead of a temporary table
    DECLARE @temp_pending TABLE (
        game_id INT,
        draw_id INT,
        agent_id VARCHAR(8)
    );

    BEGIN TRY
        -- Populate the table variable with relevant data
        INSERT INTO @temp_pending (game_id, draw_id, agent_id)
        SELECT wnhd.game_id, wnhd.draw_id, upld.agent_id
        FROM winning_header_data wnhd
        LEFT JOIN winning_upload_status upld
            ON upld.game_id = wnhd.game_id 
            AND upld.draw_id = wnhd.draw_id
            AND upld.agent_id = @agent_id       
        WHERE wnhd.process_status = 1
			AND (upld.upload_status IS NULL OR upld.upload_status = 0)

        BEGIN TRANSACTION
            -- PTR#2297 Update status to processing
            UPDATE wus
            SET wus.upload_status = 2
            FROM winning_upload_status wus
            INNER JOIN @temp_pending tpen
                ON wus.game_id = tpen.game_id 
                AND wus.draw_id = tpen.draw_id
                AND wus.agent_id = tpen.agent_id;
        COMMIT TRAN
    END TRY
    BEGIN CATCH
        IF @@trancount > 0
            ROLLBACK TRANSACTION
    END CATCH

    --return to the caller
    SELECT * FROM @temp_pending;
END
GO
IF OBJECT_ID('dbo.p_get_oss_noupld_draws') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_noupld_draws >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_noupld_draws >>>'
GO

IF OBJECT_ID('dbo.p_get_oss_noupld_draws_pending') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_noupld_draws_pending
    IF OBJECT_ID('dbo.p_get_oss_noupld_draws_pending') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_noupld_draws_pending >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_noupld_draws_pending >>>'
END
GO
/******************************************************************************
* Object:                p_get_oss_noupld_draws_pending.
* Type:                  Stored Procedure.
* Caller(s):             Transfer Winner Service (TWS).
* Description:           Retrieves draw IDs that are in the process of being transferred to agents.
* Impacted Table(s):     

* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Remove 'NOLOCK' to ensure updated data retrieval based on Process Status and Upload Status flag values.
*   PTR 2358: Header Text Update.
*   PTR 2297: TWS: IR 230513 - PW Abnormal winning file
*   PTR 2184: Transfer winner service
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_get_oss_noupld_draws_pending]
    @agent_id VARCHAR(8)
AS 
BEGIN
    -- Retrieve game_id and draw_id where process_status is 1 and upload_status is 2 for the given agent_id
    SELECT wnhd.game_id, wnhd.draw_id
    FROM winning_header_data wnhd
    LEFT JOIN winning_upload_status upld 
        ON upld.game_id = wnhd.game_id  
        AND upld.draw_id = wnhd.draw_id
        AND upld.agent_id = @agent_id
        AND upld.upload_status = 2
    WHERE wnhd.process_status = 1;
END
GO
IF OBJECT_ID('dbo.p_get_oss_noupld_draws_pending') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_noupld_draws_pending >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_noupld_draws_pending >>>'
GO


IF OBJECT_ID('dbo.p_get_oss_noupld_draws_tckt_count') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_noupld_draws_tckt_count;
    IF OBJECT_ID('dbo.p_get_oss_noupld_draws_tckt_count') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_noupld_draws_tckt_count >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_noupld_draws_tckt_count >>>';
END;
GO
/******************************************************************************
* Object: p_get_oss_noupld_draws_tckt_count.
* Type: Stored Procedure.
* Caller(s): Process Winners Service (PWS).
* Description: 
* Impacted Table(s): tickets.
*                    transaction_activities.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2356: Keep 'NOLOCK' since we are not updating the data.
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON	
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)		
* PTR 2358: Header Text Update.
* PTR 2184: New Procedure to get the count of tickets that are not uploaded for a draw.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_get_oss_noupld_draws_tckt_count]
    @agent_id	VARCHAR(8),
	@draw_id	INT,
	@game_id	INT
AS
BEGIN
    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query;
    
    DECLARE @agntWinningUploadStatus UNIQUEIDENTIFIER = '141b82f5-127d-4846-8e3a-4aa9c4ee75e8'; -- Not Uploaded;
    DECLARE @transactionTypeId UNIQUEIDENTIFIER = 'edf85abc-754b-11e6-9924-64006a4ba62f'; -- Sell;

    SELECT COUNT(tck.ticket_id) AS tickets_count
    FROM tickets tck WITH(NOLOCK) 
    WHERE tck.game_id = @game_id 
        AND tck.draw_id = @draw_id
        AND tck.agnt_wnng_upload_status = @agntWinningUploadStatus
        AND tck.bet_result_type_id > 0
        AND EXISTS (
            SELECT 1
            FROM transaction_activities ta WITH(NOLOCK)
            WHERE ta.ticket_id = tck.ticket_id
                AND ta.transaction_type_id = @transactionTypeId
                AND ta.agent_id = @agent_id
        );
END;
GO
IF OBJECT_ID('dbo.p_get_oss_noupld_draws_tckt_count') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_noupld_draws_tckt_count >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_noupld_draws_tckt_count >>>';
GO

IF OBJECT_ID('dbo.p_get_oss_noupld_winning_tickets') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_oss_noupld_winning_tickets;
    IF OBJECT_ID('dbo.p_get_oss_noupld_winning_tickets') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_oss_noupld_winning_tickets >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_oss_noupld_winning_tickets >>>';
END;
GO
/******************************************************************************
* Object: p_get_oss_noupld_winning_tickets.
* Type: Stored Procedure.
* Caller(s): Process Winners Service (PWS).
* Description: 
* Impacted Table(s): tickets.
*                    transaction_activities.
*                    agents.
*                    winning_header_data.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2356: Remove 'NOLOCK' to get committed data. 
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_get_oss_noupld_winning_tickets]
(
    @agent_host_name	VARCHAR(MAX)		--required
)
AS
BEGIN
    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query;
    
    DECLARE @agntWinningUploadStatus UNIQUEIDENTIFIER = '141b82f5-127d-4846-8e3a-4aa9c4ee75e8'; -- Not Uploaded;
    DECLARE @transactionTypeId UNIQUEIDENTIFIER = 'edf85abc-754b-11e6-9924-64006a4ba62f'; -- Sell;

    SELECT tck.ticket_id, 
        ta.agent_id, 
        tck.customer_id, 
        tck.game_id, 
        tck.draw_id, 
        tck.draw_date
    FROM winning_header_data w
        INNER JOIN tickets tck
            ON w.game_id = tck.game_id
            AND w.draw_id = tck.draw_id
            AND tck.agnt_wnng_upload_status = @agntWinningUploadStatus
            AND tck.bet_result_type_id > 0
            AND w.process_status = 1
        INNER JOIN transaction_activities ta
            ON ta.ticket_id = tck.ticket_id
            AND ta.transaction_type_id = @transactionTypeId
        INNER JOIN agents a
            ON a.agent_id = ta.agent_id
            AND a.agent_host_name = @agent_host_name;
END;
GO
IF OBJECT_ID('dbo.p_get_oss_noupld_winning_tickets') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_oss_noupld_winning_tickets >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_oss_noupld_winning_tickets >>>';
GO


IF OBJECT_ID('dbo.p_get_panel_lotto535_data') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_panel_lotto535_data;
    IF OBJECT_ID('dbo.p_get_panel_lotto535_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_panel_lotto535_data >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_panel_lotto535_data >>>';
END;
GO
/******************************************************************************
* Object: p_get_panel_lotto535_data
* Type: Stored Procedure
* Caller(s): DataTrak Trans Service (DTTS)
* Description: At the start of the service, this SP will be called so that
*              ticket panel(s) data can be retrieved for retransmission if
*              there were tickets for retransmission.
*
*              The SP retrieves the list of panel data for Lotto 535 from
*              the (in_proc) panel table.
* Impacted Table(s): N/A
*
* Update(s) History:
*   PTR 2383 : DB: New Game Lotto 5/35 Development
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_panel_lotto535_data]
    @ticket_id VARCHAR(36)
AS
BEGIN

    SET NOCOUNT ON;

    SELECT
        selected_numbers,
        selected_bonus_numbers,
        cost,
        quick_pick
    FROM in_proc_panels_lotto535 WITH (NOLOCK) 
    WHERE ticket_id = @ticket_id 
    ORDER BY panel_number;
END;
GO
IF OBJECT_ID('dbo.p_get_panel_lotto535_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_panel_lotto535_data >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_panel_lotto535_data >>>';
GO


IF OBJECT_ID('dbo.p_get_pending_trans_activities') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_pending_trans_activities
    IF OBJECT_ID('dbo.p_get_pending_trans_activities') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_pending_trans_activities >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_pending_trans_activities >>>'
END
GO
/******************************************************************************
* Object: p_get_pending_trans_activities.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS)
* Description: DTTS calls the procedure to retrieve pending transactions. 
               These transactions are then updated from "Not Processed" to "Processing" status and returned to the caller.  		
* Impacted Table(s): in_proc_transaction_activities.
*  
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.		
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_pending_trans_activities] @nRecordsRetrieved INT
AS
BEGIN
    DECLARE @error_message NVARCHAR(4000);
    DECLARE @errorNumber INT;

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    BEGIN TRY
        -- Declare the table variable
        DECLARE @tempPendingTrans TABLE (
            transaction_activity_id VARCHAR(36),
            transaction_type_id VARCHAR(36),
            transaction_status_id VARCHAR(36),
            agent_id VARCHAR(8),
            ticket_id VARCHAR(36),
            msn INT,
            customer_id VARCHAR(9),
            reg_region VARCHAR(50),
            vtid2 VARCHAR(50),
            vtid1 VARCHAR(50),
            amount MONEY,
            transaction_date DATETIME2(7)
        );

        -- Populate the table variable
        INSERT INTO @tempPendingTrans (
            transaction_activity_id,
            transaction_type_id,
            transaction_status_id,
            agent_id,
            ticket_id,
            msn,
            customer_id,
            reg_region,
            vtid2,
            vtid1,
            amount,
            transaction_date
        ) SELECT 
            pt.transaction_activity_id,
            pt.transaction_type_id,
            pt.transaction_status_id,
            pt.agent_id,
            pt.ticket_id,
            pt.msn,
            pt.customer_id,
            pt.reg_region,
            pt.vtid2,
            pt.vtid1,
            pt.amount,
            pt.transaction_date
        FROM dbo.f_get_pending_trans_activities(@nRecordsRetrieved) pt;

        DECLARE @transactionStatusId UNIQUEIDENTIFIER = 'ed1bc7ec-0fef-11e7-9454-b083feaf6ace'; -- Not Processed status
        BEGIN TRANSACTION
            --Update status to processing
            UPDATE in_proc_ta   
            SET transaction_status_id = @transactionStatusId
            FROM in_proc_transaction_activities in_proc_ta
            INNER JOIN @tempPendingTrans pt 
                ON in_proc_ta.transaction_activity_id = pt.transaction_activity_id;
        COMMIT TRANSACTION

        --return to the caller
        SELECT * 
        FROM @tempPendingTrans;
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        -- Handle specific SQL errors with custom messages
        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT(@errorNumber, '=>',  @error_message)
        END;

        -- Throw custom error
        THROW 60000, @error_message, 1;
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.p_get_pending_trans_activities') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_pending_trans_activities >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_pending_trans_activities >>>'
GO


IF OBJECT_ID('dbo.p_get_sell_ticket_hwid') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_sell_ticket_hwid
    IF OBJECT_ID('dbo.p_get_sell_ticket_hwid') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_sell_ticket_hwid >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_sell_ticket_hwid >>>'
END
GO
/******************************************************************************
* Object: p_get_sell_ticket_hwid.
* Type: Stored Procedure.
* Caller(s): Process Winners Service (PWS).
* Description: 
* Impacted Table(s): 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2356: Remove NOLOCK so to get commited Data.
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_get_sell_ticket_hwid] 
    @custId INT, 
    @ticketId VARCHAR(36)
AS
BEGIN
    DECLARE @transactionTypeId UNIQUEIDENTIFIER = 'edf85abc-754b-11e6-9924-64006a4ba62f'; -- Sell type
    DECLARE @transactionStatusId UNIQUEIDENTIFIER = '6a56bdfb-0ff0-11e7-9454-b083feaf6ace'; -- Completed status

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query

    SELECT tck.hwid 
    FROM in_proc_tickets tck
    WHERE tck.ticket_id = @ticketId
        AND EXISTS (
            SELECT 1 
            FROM in_proc_transaction_activities ta
            WHERE ta.ticket_id = tck.ticket_id AND
                ta.transaction_type_id = @transactionTypeId AND -- Sell type
                ta.transaction_status_id =  @transactionStatusId -- Completed status
        );  
END
GO
IF OBJECT_ID('dbo.p_get_sell_ticket_hwid') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_sell_ticket_hwid >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_sell_ticket_hwid >>>'
GO

IF OBJECT_ID('dbo.p_get_ttds_pending_tickets') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_ttds_pending_tickets
    IF OBJECT_ID('dbo.p_get_ttds_pending_tickets') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_ttds_pending_tickets >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_ttds_pending_tickets >>>'
END
GO
/******************************************************************************
* Object: p_get_ttds_pending_tickets.
* Type: Stored Procedure.
* Caller(s): Transfer Ticket Data Service (TTDS)
* Description: TTDS calls the procedure to retrieve Completed/Error transactions. 
               Those which has agent_confirmed_receipt = 2. 		
* Impacted Table(s): 
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.	
* PTR 2283: DTA: Processing Ticket - 22 tickets can not process when stop SQL Database
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_ttds_pending_tickets]
(
    @agent_host_name	varchar(255)		--required
)
AS
BEGIN
    DECLARE @nRecordsRetrieved INT = 1000000000 -- to select all records
    DECLARE @agent_confirmed_receipt INT = 2  -- to select only records with agent_confirmed_receipt = 2 (picked by TTDS previously) 

    SELECT 
        transaction_activity_id, 
        ticket_id, 
        agent_id,
        transaction_type_id,
        --ticket details
        customer_id AS 'custid',
        ticket_id AS 'transid',
        game_id AS 'gameid',
        sub_game_id AS 'subgame',
        transaction_status_id AS 'status',
        vtid1 AS 'vtid1',
        oss_processed_date AS 'oss_processed_date',
        draw_date AS 'drawdate',
        draw_id AS 'drawid',
        oss_updated_cost AS 'tcst',
        oss_agent_account_bal AS 'agntbal',
        error_status_description AS 'error',
        system_number AS 'system'
    FROM dbo.f_oss_confirmed_tickets(@nRecordsRetrieved, @agent_confirmed_receipt, @agent_host_name)
END
GO
IF OBJECT_ID('dbo.p_get_ttds_pending_tickets') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_ttds_pending_tickets >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_ttds_pending_tickets >>>'
GO


IF OBJECT_ID('dbo.p_get_uploaded_and_pending_files') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_uploaded_and_pending_files;
    IF OBJECT_ID('dbo.p_get_uploaded_and_pending_files') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_uploaded_and_pending_files >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_uploaded_and_pending_files >>>';
END;
GO
/******************************************************************************
* Object:                p_get_uploaded_and_pending_files.
* Type:                  Stored Procedure.
* Caller(s):             Transfer Winners Service (TWS)
* Description:           
* Impacted Table(s):     
*
* Update(s) History:
*   PTR 2381: TWS: Prevent looping of the SP call delaying the main thread of resources     
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_get_uploaded_and_pending_files]
    @game_id INT,            -- required
    @draw_id INT,            -- required
    @agent_id VARCHAR(8)        -- required
AS
BEGIN
    SELECT 
        num_files_to_be_uploaded, 
        num_files_uploaded
    FROM winning_upload_status WITH (NOLOCK)
    WHERE game_id = @game_id 
        AND draw_id = @draw_id 
        AND agent_id = @agent_id
END
GO
IF OBJECT_ID('dbo.p_get_uploaded_and_pending_files') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_uploaded_and_pending_files >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_uploaded_and_pending_files >>>';
GO

IF OBJECT_ID('dbo.p_get_winning_game_draw_id') IS NOT NULL
BEGIN; 
    DROP PROCEDURE dbo.p_get_winning_game_draw_id;
    IF OBJECT_ID('dbo.p_get_winning_game_draw_id') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_winning_game_draw_id >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_winning_game_draw_id >>>'
END
GO
/******************************************************************************
* Object: p_get_winning_game_draw_id.
* Type: Stored Procedure.
* Caller(s): 
* Description: Get draw and gameId.
* Impacted Table(s): winning_header_data.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I) 
* PTR 2356: Remove Nolock to get committed data.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_get_winning_game_draw_id]
(
    @gameId		INT,		-- required
    @draw_id	INT,
    @agent_id   VARCHAR(9)	-- required
)
AS
BEGIN
    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query

    IF EXISTS (
        SELECT 1 
        FROM v_send_winnings_to_agent WITH (NOLOCK)
        WHERE game_id = @gameId 
            AND draw_id = @draw_id
            AND agent_id = @agent_id 
    )
    BEGIN
        SELECT '' AS 'game_id', '' AS 'draw_id', '' AS 'draw_date';
        RETURN;
    END
    
    SELECT  game_id, 
        draw_id, 
        draw_date
    FROM winning_header_data WITH (NOLOCK)
    WHERE game_id = @gameId 
        AND draw_id = @draw_id
        AND send_to_all_agents = 0;
        --AND (agent_id <> @agent_id OR agent_id IS NULL);
END
GO
IF OBJECT_ID('dbo.p_get_winning_game_draw_id') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_winning_game_draw_id >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_winning_game_draw_id >>>'
GO



IF OBJECT_ID('dbo.p_get_winning_header_data') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_winning_header_data
    IF OBJECT_ID('dbo.p_get_winning_header_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_winning_header_data >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_winning_header_data >>>'
END
GO
/******************************************************************************
* Object:                p_get_winning_header_data.
* Type:                  Stored Procedure.
* Caller(s):             
* Description:           
* Impacted Table(s):     

* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Remove 'NOLOCK' since we need to get the updated data. (NOTE: change * to specific column names)
*   PTR 2358: Header Text Update.    
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_get_winning_header_data]
    @game_id INT,        -- required
    @draw_id INT        -- required
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT file_version
        ,game_id
        ,draw_date
        ,draw_id
        ,winning_numbers
        ,date_modified
        ,process_status
        ,prize_level
        ,send_to_all_agents
        ,bingo_report_generated 
    FROM winning_header_data
    WHERE game_id = @game_id 
        AND draw_id = @draw_id
END
GO
IF OBJECT_ID('dbo.p_get_winning_header_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_winning_header_data >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_winning_header_data >>>'
GO


IF OBJECT_ID('dbo.p_get_winning_tickets_for_payment') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_winning_tickets_for_payment
    IF OBJECT_ID('dbo.p_get_winning_tickets_for_payment') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_winning_tickets_for_payment >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_winning_tickets_for_payment >>>'
END
GO
/******************************************************************************
* Object: p_get_winning_tickets_for_payment.
* Type: Stored Procedure.
* Caller(s): Process Winners Service (PWS).
* Description: 
* Impacted Table(s): 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2356: Keep 'NOLOCK' because thi procedure is called only after PWS is done processing.
*				Remove Nolock from winning_header_data since we need the updated value for the process_status flag.
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_get_winning_tickets_for_payment]
    @drawId INT,
    @gameId INT,
    @agentId VARCHAR(8)=NULL
AS
BEGIN
    -- SET NOCOUNT ON to stop the message that shows the count of the number of rows
    SET NOCOUNT ON

    SELECT tck.ticket_id,
        tck.customer_id,
        cu.agent_id,
        tck.draw_id,
        tck.game_id
    FROM tickets tck WITH (NOLOCK)
        INNER JOIN coresys_winning_payments cs WITH (NOLOCK) 
            ON cs.ticket_id = tck.ticket_id 
        INNER JOIN customers cu WITH (NOLOCK) 
            ON cu.customer_id = tck.customer_id
            AND (cu.agent_id = @agentId OR @agentId IS NULL)
	WHERE game_id = @gameId
	    AND draw_id = @drawId
	    AND tck.agnt_wnng_pymnt_status IS NULL
        AND bet_result_type_id BETWEEN 1 AND 2;
END
GO
IF OBJECT_ID('dbo.p_get_winning_tickets_for_payment') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_winning_tickets_for_payment >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_winning_tickets_for_payment >>>'
GO

IF OBJECT_ID('dbo.p_get_winning_upload_status') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_winning_upload_status
    IF OBJECT_ID('dbo.p_get_winning_upload_status') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_winning_upload_status >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_winning_upload_status >>>'
END
GO
/******************************************************************************
* Object:                p_get_winning_upload_status.
* Type:                  Stored Procedure.
* Caller(s):             Transfer Winners Service (TWS)
* Description:           
* Impacted Table(s):     
*
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2356: Remove 'NOLOCK' since we need to get the updated data.
*   PTR 2358: Header Text Update.    
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_get_winning_upload_status]
    @game_id INT,            -- required
    @draw_id INT,            -- required
    @agent_id VARCHAR(8)        -- required
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT upload_status 
    FROM winning_upload_status WITH(NOLOCK)
    WHERE game_id = @game_id 
        AND draw_id = @draw_id 
        AND agent_id = @agent_id
END
GO
IF OBJECT_ID('dbo.p_get_winning_upload_status') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_winning_upload_status >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_winning_upload_status >>>'
GO


IF OBJECT_ID('dbo.p_set_agent_confirmed_receipt') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_set_agent_confirmed_receipt
    IF OBJECT_ID('dbo.p_set_agent_confirmed_receipt') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_set_agent_confirmed_receipt >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_set_agent_confirmed_receipt >>>'
END
GO
/******************************************************************************
* Object: p_set_agent_confirmed_receipt.
* Type: Stored Procedure.
* Caller(s): TransTicketDataService (TTDS).
* Description: Updates the agent_confirmed_receipt field in the in_proc_transaction_activities table to zero from 1
*              (i.e from confirmed to not confirmed).
* Impacted Table(s): in_proc_transaction_activities.
*                    
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set Xaact_abort ON
* PTR 2355: Minimize deadlocks and Timeouts
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.
* PTR 2126: catch deadlock and throw exception
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_set_agent_confirmed_receipt]
    @trans_id VARCHAR(36)
AS
BEGIN
    DECLARE @error_message VARCHAR(MAX);
    DECLARE @row_count INT;
	DECLARE @errorNumber INT;

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    BEGIN TRY
        BEGIN TRANSACTION
            UPDATE in_proc_transaction_activities 
                SET agent_confirmed_receipt = 0 
            WHERE ticket_id = @trans_id
                AND agent_confirmed_receipt = 1;
        COMMIT TRANSACTION

        -- return after commit
        SELECT '1','Update Successfully';
    END TRY
    BEGIN CATCH 
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        -- Handle specific SQL errors with custom messages
        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @errorNumber, '=>',  @error_message)
        END;

        IF ERROR_NUMBER() IN (1204,1205,1222)
        BEGIN
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1',@error_message;
        END
    END CATCH;
END
GO
IF OBJECT_ID('dbo.p_set_agent_confirmed_receipt') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_set_agent_confirmed_receipt >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_set_agent_confirmed_receipt >>>'
GO



IF OBJECT_ID('dbo.p_transfer_tickets_to_memory_table') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_transfer_tickets_to_memory_table
    IF OBJECT_ID('dbo.p_transfer_tickets_to_memory_table') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_transfer_tickets_to_memory_table >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_transfer_tickets_to_memory_table >>>'
END
GO
/******************************************************************************
* Object: p_transfer_tickets_to_memory_table.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: 
* Impacted Table(s): staging_move_tickets.
*                    in_proc_panels.
*                    in_proc_coresys_update_panels.
*                    in_proc_panels_3d.
*                    in_proc_coresys_update_panels_3d.
*                    in_proc_panels_bingo.
*                    in_proc_coresys_update_panels_bingo.
*                    in_proc_transaction_activities.
*                    in_proc_tickets.
*                    panels.
*                    coresys_update_panels.
*                    panels_3d.
*                    coresys_update_panels_3d.
*                    panels_bingo.
*                    coresys_update_panels_bingo.
*                    transaction_activities.
*                    tickets.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
* PTR 2358: Header Text Update.
* PTR 2126:
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_transfer_tickets_to_memory_table]
    @moveTicketLimit INT,
    @moveTimeLimit INT,
    @batchSize INT
AS
BEGIN
    DECLARE @ticketCount INT;
    DECLARE @earliestTicketSeconds INT;
	DECLARE @errorNumber INT;
	DECLARE @error_message varchar(max);

    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    SET DEADLOCK_PRIORITY LOW; -- choose me as the deadlock victim
    SET LOCK_TIMEOUT 5000; -- wait for 5 seconds for lock

    DECLARE @lockResult INT;

    IF NOT EXISTS (
        SELECT 1
        FROM staging_move_tickets
    )
    BEGIN
        SELECT '9' AS 'result', 'DB queue is Empty!' AS 'message';
        RETURN;
    END;

	BEGIN TRY
        BEGIN TRANSACTION
			-- Attempt to acquire transaction-level lock
			EXEC @lockResult = sp_getapplock 
				@Resource = 'p_transfer_tickets_to_memory_table', -- Logical resource name
				@LockMode = 'Exclusive', -- Ensure only one thread can acquire this lock
				@LockOwner = 'Transaction',-- Lock tied to the transaction
			    @LockTimeout = 1000; -- Fail after 1 second if lock cannot be acquired
			--SELECT @lockResult
			-- Check if the lock was successfully acquired
			IF @lockResult < 0
			BEGIN
				-- Return response to subsequent threads
				ROLLBACK TRANSACTION;  -- Rollback open transaction
				SELECT '1', 'Ticket Move to Memory Table(s) in progress.';
				RETURN;
			END;

			SELECT @ticketCount = COUNT(*),
				@earliestTicketSeconds = DATEDIFF(SECOND, MIN(date_modified), dbo.f_getcustom_date())
			FROM staging_move_tickets WITH(NOLOCK);

			IF @earliestTicketSeconds IS NULL OR (@ticketCount < @moveTicketLimit AND @earliestTicketSeconds < @moveTimeLimit)
            BEGIN
                ROLLBACK TRAN;
                SELECT '2', 'Ticket count or time threshold not reached yet';
                RETURN;
            END

            -- Populate the temporary table with tickets to move
            SELECT TOP (@batchSize) 
                ticket_id,
                game_id
            INTO #tickets_to_move
            FROM staging_move_tickets WITH (SNAPSHOT)
            WHERE moved_to_mem = 0; -- get tickets that have not been moved to memory table
        
            DECLARE @customDate DATETIME = dbo.f_getcustom_date(); -- Precalculate custom date

            -- Delete from in_proc table for lotto games
            DELETE FROM inpan
            OUTPUT
				DELETED.panel_id, tmp.game_id,
                DELETED.ticket_id, DELETED.selected_numbers, DELETED.cost,
                DELETED.quick_pick, DELETED.bonus_number, @customDate, 
				DELETED.panel_number
            INTO panel_details_mem (
				panel_id, game_id,
                ticket_id, selected_numbers, cost,
                quick_pick, bonus_number, date_modified, 
				panel_number
            ) 
			FROM in_proc_panels inpan
            INNER JOIN #tickets_to_move tmp
                ON inpan.ticket_id = tmp.ticket_id
                AND tmp.game_id IN (100, 101);

            DELETE FROM inpancor 
            OUTPUT
				DELETED.coresys_update_panel_id ,tmp.game_id,
                DELETED.ticket_id, DELETED.selected_numbers, DELETED.cost, 
                DELETED.quick_pick, DELETED.bonus_number, @customDate as 'date_modified', 
				DELETED.summary, DELETED.panel_number
            INTO coresys_panel_details_mem (
                panel_id, game_id,
                ticket_id, selected_numbers, cost,
                quick_pick, bonus_number, date_modified, 
				summary, panel_number
            )
			FROM in_proc_coresys_update_panels inpancor
            INNER JOIN #tickets_to_move tmp
                ON inpancor.ticket_id = tmp.ticket_id
                AND tmp.game_id IN (100, 101);

            -- Delete from in_proc for 3d games
            DELETE FROM inpan3d 
            OUTPUT
                DELETED.in_proc_panels_3d_panel_id, tmp.game_id,
                DELETED.ticket_id, DELETED.selected_numbers, DELETED.cost,
				DELETED.quick_pick, @customDate as 'date_modified', 
				DELETED.panel_number, DELETED.sel_numbers_count
            INTO panel_details_mem (
                panel_id, game_id,
                ticket_id, selected_numbers, cost,
                quick_pick, date_modified, panel_number,
				sel_numbers_count
            ) 
            FROM in_proc_panels_3d inpan3d
            INNER JOIN #tickets_to_move tmp
                ON inpan3d.ticket_id = tmp.ticket_id
                AND tmp.game_id IN (102, 103);

            DELETE FROM inpan3dcor  
            OUTPUT
                DELETED.in_proc_coresys_update_panels_3d_panel_id, tmp.game_id,
                DELETED.ticket_id, DELETED.selected_numbers, DELETED.cost,
                DELETED.quick_pick, @customDate as 'date_modified', 
				DELETED.summary, DELETED.panel_number, DELETED.sel_numbers_count
            INTO coresys_panel_details_mem (
                panel_id, game_id,
                ticket_id, selected_numbers, cost,
                quick_pick, date_modified, 
				summary, panel_number, sel_numbers_count
            )
            FROM in_proc_coresys_update_panels_3d inpan3dcor
            INNER JOIN #tickets_to_move tmp
                ON inpan3dcor.ticket_id = tmp.ticket_id
                AND tmp.game_id IN (102, 103);
            
            -- Delete from in_proc for bingo game
            DELETE FROM inpanbin 
            OUTPUT
                DELETEd.panel_id ,tmp.game_id,
                DELETED.ticket_id, DELETED.cost, 
				@customDate as 'date_modified', 
				DELETED.panel_number, DELETED.play_type
            INTO panel_details_mem (
                panel_id, game_id,
                ticket_id, cost,
                date_modified, 
				panel_number, play_type
            ) 
            FROM in_proc_panels_bingo inpanbin
            INNER JOIN #tickets_to_move tmp
                ON inpanbin.ticket_id = tmp.ticket_id
                AND tmp.game_id = 105;

            DELETE FROM inpanbincor
            OUTPUT 
                DELETED.panel_id, tmp.game_id,
                DELETED.ticket_id, DELETED.cost, 
				@customDate as 'date_modified', 
				DELETED.summary, DELETED.panel_number, DELETED.play_type
            INTO coresys_panel_details_mem (
                panel_id, game_id,
                ticket_id, cost,
                date_modified, 
				summary, panel_number, play_type
            )  
            FROM in_proc_coresys_update_panels_bingo inpanbincor
            INNER JOIN #tickets_to_move tmp
                ON inpanbincor.ticket_id = tmp.ticket_id
                AND tmp.game_id = 105;

            -- Delete from in_proc for lotto535 game
            DELETE FROM inpan535
            OUTPUT
                DELETED.panel_id, tmp.game_id,
                DELETED.ticket_id, DELETED.selected_numbers, DELETED.cost,
                DELETED.quick_pick, DELETED.selected_bonus_numbers, @customDate as 'date_modified', 
				DELETED.panel_number
            INTO panel_details_mem (
                panel_id, game_id,
                ticket_id, selected_numbers, cost,
                quick_pick, selcted_bonus, date_modified, 
				panel_number
            ) 
            FROM in_proc_panels_lotto535 inpan535
            INNER JOIN #tickets_to_move tmp
                ON inpan535.ticket_id = tmp.ticket_id
                AND tmp.game_id = 106;

            DELETE FROM inpancor535 
            OUTPUT
                DELETED.panel_id, tmp.game_id,
                DELETED.ticket_id, DELETED.selected_numbers, DELETED.cost, 
                DELETED.quick_pick, DELETED.selected_bonus_numbers, @customDate as 'date_modified', 
				DELETED.summary, DELETED.panel_number
            INTO coresys_panel_details_mem (
                panel_id, game_id,
                ticket_id, selected_numbers, cost,
                quick_pick, selcted_bonus, date_modified, 
				summary, panel_number
            )
            FROM in_proc_coresys_update_panels_lotto535 inpancor535
            INNER JOIN #tickets_to_move tmp
                ON inpancor535.ticket_id = tmp.ticket_id
                AND tmp.game_id =106;

            -- delete from in_proc tickets and populate tickets
            DELETE FROM intck 
            OUTPUT DELETED.ticket_id, DELETED.customer_id, DELETED.draw_id, DELETED.game_id, DELETED.sub_game_id, DELETED.system_number, DELETED.draw_date, DELETED.draw_offset,
                DELETED.hwid, DELETED.msn, DELETED.vtid1, DELETED.vtid2, DELETED.vtid2_encrypted, DELETED.tsn, DELETED.cost, DELETED.bet_result_type_id, DELETED.panel_count, DELETED.purge_date,
                @customDate, DELETED.date_created, DELETED.header_summary, DELETED.footer_summary, DELETED.agnt_wnng_pymnt_status, DELETED.agnt_wnng_upload_status
            INTO tickets_details_mem (
                ticket_id, customer_id, draw_id, game_id, sub_game_id, system_number, draw_date, draw_offset,
                hwid, msn, vtid1, vtid2, vtid2_encrypted, tsn, cost, bet_result_type_id, panel_count, purge_date, 
                date_modified, date_created, header_summary, footer_summary, agnt_wnng_pymnt_status, agnt_wnng_upload_status
            )
            FROM in_proc_tickets intck WITH(ROWLOCK)
            INNER JOIN #tickets_to_move tmp
                ON intck.ticket_id = tmp.ticket_id;

            -- delete from in_proc transaction_activities and populate transaction_activities
            DELETE inta 
            OUTPUT 
                DELETED.transaction_activity_id, DELETED.ticket_id, DELETED.transaction_date, DELETED.transaction_type_id, DELETED.oss_processed_date,
                DELETED.error_status_id, DELETED.oss_updated_cost, DELETED.total_cost_alter, DELETED.transaction_status_id, @customDate,
                DELETED.agent_id, DELETED.oss_agent_account_bal, 1, DELETED.oss_tax_amount
            INTO transaction_details_mem (
                transaction_activity_id, ticket_id, transaction_date, transaction_type_id, oss_processed_date,
                error_status_id, oss_updated_cost, total_cost_alter, transaction_status_id, date_modified,
                agent_id, oss_agent_account_bal, agent_confirmed_receipt, oss_tax_amount
            )
            FROM in_proc_transaction_activities inta WITH(ROWLOCK)
            INNER JOIN #tickets_to_move tmp
                ON inta.ticket_id = tmp.ticket_id;

        COMMIT TRANSACTION
            
        -- mark these tickets has moved in to memory table
        UPDATE stck 
        SET moved_to_mem = 1
		FROM staging_move_tickets stck
		INNER JOIN #tickets_to_move tmp
			ON stck.ticket_id = tmp.ticket_id;

        SELECT '1' AS 'result', 'Tickets moved successfully to Memory Table(s)' AS 'message';

		IF OBJECT_ID('tempdb..#tickets_to_move') IS NOT NULL
            DROP TABLE #tickets_to_move;
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81:', @errorNumber,':', @error_message)
        END;

        IF @errorNumber in (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1' AS 'result', @error_message AS 'message';
        END
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_transfer_tickets_to_memory_table') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_transfer_tickets_to_memory_table >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_transfer_tickets_to_memory_table >>>'
GO

IF OBJECT_ID('dbo.p_transfer_tickets_to_permanent_table') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_transfer_tickets_to_permanent_table
    IF OBJECT_ID('dbo.p_transfer_tickets_to_permanent_table') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_transfer_tickets_to_permanent_table >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_transfer_tickets_to_permanent_table >>>'
END
GO
/******************************************************************************
* Object: p_transfer_tickets_to_permanent_table.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: 
* Impacted Table(s): staging_move_tickets.
*                    in_proc_panels.
*                    in_proc_coresys_update_panels.
*                    in_proc_panels_3d.
*                    in_proc_coresys_update_panels_3d.
*                    in_proc_panels_bingo.
*                    in_proc_coresys_update_panels_bingo.
*                    in_proc_transaction_activities.
*                    in_proc_tickets.
*                    panels.
*                    coresys_update_panels.
*                    panels_3d.
*                    coresys_update_panels_3d.
*                    panels_bingo.
*                    coresys_update_panels_bingo.
*                    transaction_activities.
*                    tickets.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
* PTR 2358: Header Text Update.
* PTR 2126:
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_transfer_tickets_to_permanent_table]
    @batchSize INT -- Number of tickets to move in a batch
AS
BEGIN
    DECLARE @ticketCount INT;
    DECLARE @earliestTicketSeconds INT;
	DECLARE @errorNumber INT;
	DECLARE @error_message varchar(max);

    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    SET DEADLOCK_PRIORITY LOW; -- choose me as the deadlock victim
    SET LOCK_TIMEOUT 5000; -- wait for 5 seconds for lock

    DECLARE @lockResult INT;
	
	--SET TRANSACTION ISOLATION LEVEL SNAPSHOT; -- Set transaction isolation level to snapshot

	BEGIN TRY
        BEGIN TRANSACTION
			-- Attempt to acquire transaction-level lock
			EXEC @lockResult = sp_getapplock 
				@Resource = 'p_transfer_tikcets_to_permament_table', -- Logical resource name
				@LockMode = 'Exclusive', -- Ensure only one thread can acquire this lock
				@LockOwner = 'Transaction',-- Lock tied to the transaction
			    @LockTimeout = 1000; -- Fail after waiting 1 sec if lock cannot be acquired
			--SELECT @lockResult
			-- Check if the lock was successfully acquired
			IF @lockResult < 0
			BEGIN
				-- Return response to subsequent threads
				ROLLBACK TRANSACTION;  -- Rollback open transaction
				SELECT '1', 'Ticket Move to Permanent Table(s) in progress.';
				RETURN;
			END;

            -- Populate the temporary table with tickets to move
            SELECT TOP (@batchSize) 
                ticket_id,
                game_id
            INTO #tickets_to_perm
            FROM staging_move_tickets WITH (SNAPSHOT)
            WHERE moved_to_mem = 1; -- Tickets that have been moved to memory

            -- Check if there are tickets to move
            IF NOT EXISTS (
                SELECT 1 
                FROM #tickets_to_perm
            )
            BEGIN
                ROLLBACK TRAN;
                SELECT '2', 'No Tickets to move into permanent Table(s)';
                RETURN;
            END

            INSERT INTO tickets (
                ticket_id, customer_id, draw_id, game_id, sub_game_id, system_number, draw_date, draw_offset,
                hwid, msn, vtid1, vtid2, vtid2_encrypted, tsn, cost, bet_result_type_id, panel_count, purge_date,
                date_modified, date_created, header_summary, footer_summary, agnt_wnng_pymnt_status, agnt_wnng_upload_status
            ) 
            SELECT tdm.ticket_id, customer_id, draw_id, tdm.game_id, sub_game_id, system_number, draw_date, draw_offset,
                hwid, msn, vtid1, vtid2, vtid2_encrypted, tsn, cost, bet_result_type_id, panel_count, purge_date,
                date_modified, date_created, header_summary, footer_summary, agnt_wnng_pymnt_status, agnt_wnng_upload_status
            FROM tickets_details_mem tdm WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON tdm.ticket_id = tmp.ticket_id;

			--now insert panles ,coresys panels and transaction activities to permanent tbales from temp
			INSERT INTO panels (
                panel_id, ticket_id, selected_numbers, cost,
                quick_pick, bonus_number, date_modified, 
				panel_number
            ) 
			SELECT panel_id, pdt.ticket_id, selected_numbers, cost,
				quick_pick, bonus_number, 
				date_modified, panel_number   
			FROM panel_details_mem pdt WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON pdt.ticket_id = tmp.ticket_id
			    AND tmp.game_id IN (100,101);

            INSERT INTO coresys_update_panels (
                coresys_update_panel_id, ticket_id, selected_numbers, cost,
                quick_pick, bonus_number, date_modified, 
				summary, panel_number
            )
            SELECT panel_id, cpdt.ticket_id, selected_numbers, cost,
                quick_pick, bonus_number, date_modified,
                summary, panel_number
            FROM coresys_panel_details_mem cpdt WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON cpdt.ticket_id = tmp.ticket_id
                AND tmp.game_id IN (100,101);

            INSERT INTO panels_3d (
                panels_3d_panel_id, ticket_id, selected_numbers, cost,
                quick_pick, date_modified, panel_number,
				sel_numbers_count
            )
            SELECT panel_id, pdt.ticket_id, selected_numbers, cost,
                quick_pick, date_modified, panel_number,
                sel_numbers_count
            FROM panel_details_mem pdt WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON pdt.ticket_id = tmp.ticket_id
                AND tmp.game_id IN (102,103)

            INSERT INTO coresys_update_panels_3d (
                coresys_update_panels_3d_panel_id, ticket_id, selected_numbers, cost,
                quick_pick, date_modified, 
				summary, panel_number, sel_numbers_count
            )
            SELECT panel_id, cpdt.ticket_id, selected_numbers, cost,
                quick_pick, date_modified,
                summary, panel_number, sel_numbers_count
            FROM coresys_panel_details_mem cpdt WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON cpdt.ticket_id = tmp.ticket_id
                AND tmp.game_id IN (102,103);

            INSERT INTO panels_bingo (
                panel_id, ticket_id, cost,
                date_modified, 
				panel_number, play_type
            )
            SELECT panel_id, pdt.ticket_id, cost,
                date_modified,
                panel_number, play_type
            FROM panel_details_mem pdt WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON pdt.ticket_id = tmp.ticket_id
                AND tmp.game_id = 105;

            INSERT INTO coresys_update_panels_bingo (
                panel_id, ticket_id, cost,
                date_modified, 
				summary, panel_number, play_type
            )
            SELECT panel_id, cpdt.ticket_id, cost,
                date_modified,
                summary, panel_number, play_type
            FROM coresys_panel_details_mem cpdt WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON cpdt.ticket_id = tmp.ticket_id
                AND tmp.game_id = 105;

            INSERT INTO panels_lotto535 (
                ticket_id, selected_numbers, cost,
                quick_pick, selected_bonus_numbers, date_modified, 
				panel_number
            )
            SELECT pdt.ticket_id, selected_numbers, cost,
                quick_pick, selcted_bonus, date_modified,
                panel_number
            FROM panel_details_mem pdt WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON pdt.ticket_id = tmp.ticket_id
                AND tmp.game_id = 106;

            INSERT INTO coresys_update_panels_lotto535 (
                ticket_id, selected_numbers, cost,
                quick_pick, selected_bonus_numbers, date_modified, 
				summary, panel_number
            )
            SELECT cpdt.ticket_id, selected_numbers, cost,
                quick_pick, selcted_bonus, date_modified,
                summary, panel_number
            FROM coresys_panel_details_mem cpdt WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON cpdt.ticket_id = tmp.ticket_id
                AND tmp.game_id = 106;

            INSERT INTO transaction_activities (
                transaction_activity_id, ticket_id, transaction_date, transaction_type_id, oss_processed_date,
                error_status_id, oss_updated_cost, total_cost_alter, transaction_status_id, date_modified,
                agent_id, oss_agent_account_bal, agent_confirmed_receipt, oss_tax_amount
            )
            SELECT transaction_activity_id, tadm.ticket_id, transaction_date, transaction_type_id, oss_processed_date,
                error_status_id, oss_updated_cost, total_cost_alter, transaction_status_id, date_modified,
                agent_id, oss_agent_account_bal, agent_confirmed_receipt, oss_tax_amount
            FROM transaction_details_mem tadm WITH (SNAPSHOT)
            INNER JOIN #tickets_to_perm tmp
                ON tadm.ticket_id = tmp.ticket_id;
                
        COMMIT TRANSACTION
            
        -- Delete from panel memory
        DELETE pdt
        FROM panel_details_mem pdt
        INNER JOIN #tickets_to_perm tmp ON pdt.ticket_id = tmp.ticket_id;

        -- Delete from coresys panel memory
        DELETE cpdt
        FROM coresys_panel_details_mem cpdt
        INNER JOIN #tickets_to_perm tmp ON cpdt.ticket_id = tmp.ticket_id;

        -- Delete from transaction activity memory
        DELETE tadm
        FROM transaction_details_mem tadm
        INNER JOIN #tickets_to_perm tmp ON tadm.ticket_id = tmp.ticket_id;

        -- Delete from tickets memory
        DELETE tdm
        FROM tickets_details_mem tdm
        INNER JOIN #tickets_to_perm tmp ON tdm.ticket_id = tmp.ticket_id;

        -- Delete from staging
        DELETE stck
        FROM staging_move_tickets stck
        INNER JOIN #tickets_to_perm tmp ON stck.ticket_id = tmp.ticket_id;
            
        SELECT '1' AS 'result', 'Tickets moved successfully to Permanent Table(s)' AS 'message';

		IF OBJECT_ID('tempdb..#tickets_to_move') IS NOT NULL
            DROP TABLE #tickets_to_perm;
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81:', @errorNumber,':', @error_message)
        END;

        IF @errorNumber in (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1' AS 'result', @error_message AS 'message';
        END
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_transfer_tickets_to_permanent_table') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_transfer_tickets_to_permanent_table >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_transfer_tickets_to_permanent_table >>>'
GO

IF OBJECT_ID('dbo.p_update_agent_receipt_flag_after_ticketupdate') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_agent_receipt_flag_after_ticketupdate;
    IF OBJECT_ID('dbo.p_update_agent_receipt_flag_after_ticketupdate') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_agent_receipt_flag_after_ticketupdate >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_agent_receipt_flag_after_ticketupdate >>>';
END;
GO
/******************************************************************************
* Object: p_updates_from_oss.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: 
* Impacted Table(s): in_proc_transaction_activities.
*                    staging_move_tickets.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_agent_receipt_flag_after_ticketupdate]
    @ticketId VARCHAR(36),
    @gameId INT,
    @moveLimit INT,
    @timeLimit INT
AS 
BEGIN
    DECLARE @transactionActivityId VARCHAR(36);
    DECLARE @errorNumber INT;  
    DECLARE @error_message NVARCHAR(MAX);
    DECLARE @curr_date_time DATETIME2(7);
    DECLARE @rowCount INT = 0;
    
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @curr_date_time = dbo.f_getcustom_date();
    BEGIN TRY
        BEGIN TRANSACTION;
            UPDATE in_proc_transaction_activities 
            SET agent_confirmed_receipt = 1,
                date_modified = @curr_date_time
            WHERE ticket_id = @ticketId
                AND transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f';

            SET @rowCount = @@ROWCOUNT;

            IF @rowCount > 0
            BEGIN
                -- INSERT INTO staging_move_tickets
                INSERT INTO staging_move_tickets (
                    ticket_id,
                    game_id,
                    date_modified
                )
                VALUES (
                    @ticketId,
                    @gameId,
                    @curr_date_time
                );
            END;
        COMMIT TRANSACTION;

        -- RETURN success
        IF @rowCount > 0
            SELECT '1' AS 'result', 'Updated Successfully' AS 'message';
        ELSE
            SELECT '-1' AS 'result', 'No rows updated' AS 'message';
    END TRY
    BEGIN CATCH
        -- ROLLBACK TRANSACTION if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
            
        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @errorNumber, '=>',  @error_message)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- THROW custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1' AS 'result', @error_message AS 'message';
        END;
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.p_update_agent_receipt_flag_after_ticketupdate') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_agent_receipt_flag_after_ticketupdate >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_agent_receipt_flag_after_ticketupdate >>>';
GO


IF OBJECT_ID('dbo.p_update_coresys_win_payments_err') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_coresys_win_payments_err
    IF OBJECT_ID('dbo.p_update_coresys_win_payments_err') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_coresys_win_payments_err >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_coresys_win_payments_err >>>'
END
GO
/******************************************************************************
* Object: p_update_coresys_win_payments_err.
* Type: Stored Procedure.
* Caller(s): 
* Description: 
* Impacted Table(s): error_status.
*                    in_proc_tickets.
*                    in_proc_transaction_activities.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_coresys_win_payments_err] 
    @ticketId VARCHAR(36), 
    @transActivityId VARCHAR(36), 
    @errCode VARCHAR(5), 
    @errDesc NVARCHAR(MAX)
AS
BEGIN
    DECLARE @errId VARCHAR(36);
    DECLARE @rowCount INT;
    DECLARE @errorNumber INT;
    DECLARE @error_message VARCHAR(5000);

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON;  -- Rollback transaction if an error occurs

    DECLARE @winnigPaymentStatus UNIQUEIDENTIFIER  = '9996c3ca-7b38-4b7c-97f6-4c9755a3ff96'; -- 'Winning Payment Error' 
    DECLARE @transactionStatusId UNIQUEIDENTIFIER = '45318a66-0ff0-11e7-9454-b083feaf6ace'; -- Transaction Status 'completed'

    BEGIN TRY
        BEGIN TRANSACTION
            -- change to use NEWSEQUENTIALID() instead of NEWID() to avoid fragmentation
            SET @errId = NEWID()
            INSERT INTO error_status(
                error_status_id, 
                error_status_type_id, 
                error_status_code, 
                error_status_description, 
                date_modified
            )
            VALUES (
                @errId, 
                1, 
                @errCode, 
                @errDesc, 
                dbo.f_getcustom_date()
            );
            
            -- update in_proc_tickets to set the status to 'Winning Payment Error'
            UPDATE in_proc_tickets 
            SET agnt_wnng_pymnt_status = @winnigPaymentStatus 
            WHERE ticket_id = @ticketId;

            UPDATE ta 
                SET ta.transaction_status_id = @transactionStatusId
            FROM in_proc_transaction_activities ta
            WHERE ta.transaction_activity_id = @transActivityId;
        COMMIT TRANSACTION

        -- response after commit
        SELECT '1' AS 'result';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81:', @errorNumber, ':', @error_message)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
		ELSE
		BEGIN
            SELECT @error_message AS 'result';
        END
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.p_update_coresys_win_payments_err') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_coresys_win_payments_err >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_coresys_win_payments_err >>>'
GO


IF OBJECT_ID('dbo.p_update_cust') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_cust
    IF OBJECT_ID('dbo.p_update_cust') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_cust >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_cust >>>'
END
GO
/******************************************************************************
* Object: p_update_cust
* Type: Stored Procedure
* Callers: EAgent WebService
* Usage: Updates customer status
*  
* Previous Fix(es) :
*
* Current Fix(es) : 
*	PTR 2280
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_update_cust]
    @custId varchar(9),					-- required
    @agentId varchar(8),				-- required
    @mobile varchar(15)=NULL,				-- optional
    @sqlString nvarchar(max)
AS 
BEGIN
    DECLARE @result varchar(max)
    DECLARE @db_customer_status int
    DECLARE @sqlstmt nvarchar(max)
    DECLARE @finalsqlstmt NVARCHAR(max)
    DECLARE @res varchar(max)
    DECLARE @Count AS INT

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Use customer id to lock instead
    Exec p_spgetapplock @custId

    BEGIN TRY
        BEGIN TRANSACTION
            -- Mobile duplication check (if new mobile is provided) 
            IF @mobile IS NOT NULL
            BEGIN 
                IF EXISTS ( 
                SELECT TOP 1 customer_id
                FROM customers WITH (NOLOCK)
                WHERE customer_status_id <> 5
                    AND mobile = @mobile
                    AND customer_id <> @custId
                )
                BEGIN
                    SELECT '-1' AS 'result','Mobile Already Exists'
                    RETURN;
                END
            END

            -- Assemble the final SQL with parameter placeholders
            SET @finalsqlstmt = concat('UPDATE customers SET ',@sqlString ,' WHERE customer_id = ',@custId)
            EXEC (@finalsqlstmt)
            SELECT '1' AS 'result'          
            
        COMMIT TRANSACTION
        --END        
    END TRY
    BEGIN catch
        IF @@trancount > 0
            ROLLBACK TRANSACTION

        SET @result = CONCAT('message = ', ERROR_NUMBER(),':',ERROR_MESSAGE())
        SELECT '-1', @result AS 'result'
    END catch
END
GO
IF OBJECT_ID('dbo.p_update_cust') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_cust >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_cust >>>'
GO


IF OBJECT_ID('dbo.p_update_eod_trans_activities_status') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_eod_trans_activities_status
    IF OBJECT_ID('dbo.p_update_eod_trans_activities_status') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_eod_trans_activities_status >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_eod_trans_activities_status >>>'
END
GO
/******************************************************************************
* Object: p_update_eod_trans_activities_status.
* Type: Stored Procedure.
* Caller(s): 
* Description: 
* Impacted Table(s): error_status.
*                    in_proc_transaction_activities.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2126: 
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_eod_trans_activities_status]
    @transActivityId VARCHAR(36), 
    @transTypeId VARCHAR(36),
    @ticketId VARCHAR(36), 
    @status VARCHAR(32),
    @errStatusType INT, 
    @errCode VARCHAR(5), 
    @errDesc NVARCHAR(MAX)
AS
BEGIN
    DECLARE @statusID VARCHAR(36)
    DECLARE @errId VARCHAR(36)
    DECLARE @error_message VARCHAR(5000)
    DECLARE @rowCount INT
	DECLARE @errorNumber INT

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs
    
    BEGIN TRY
        -- Only process SELL transactions
        IF (@transTypeId = 'edf85abc-754b-11e6-9924-64006a4ba62f')
        BEGIN

            SET @statusID = 
                CASE @status
                    WHEN 'Not_Processed' THEN '0ab02c66-0fef-11e7-9454-b083feaf6ace'
                    WHEN 'Completed' THEN '6a56bdfb-0ff0-11e7-9454-b083feaf6ace'
                    WHEN 'Processing' THEN 'ed1bc7ec-0fef-11e7-9454-b083feaf6ace'
                    WHEN 'Error' THEN '45318a66-0ff0-11e7-9454-b083feaf6ace'
                END;

            BEGIN
                BEGIN TRANSACTION
                    IF (@errCode IS NOT NULL) 
                    BEGIN
                        -- Use NEWSEQUENTIALID() instead of NEWID() to avoid fragmentation
                        SET @errId = NEWID()
                        INSERT INTO error_status(error_status_id, error_status_type_id, error_status_code, error_status_description, date_modified)
                            VALUES (@errId, @errStatusType, @errCode, @errDesc, dbo.f_getcustom_date());
                    END;

                    ---- Clean up temp table containing temp_last_pending_transactions
                    --IF (@statusID = '6a56bdfb-0ff0-11e7-9454-b083feaf6ace' OR @statusID = 'ed1bc7ec-0fef-11e7-9454-b083feaf6ace' OR @statusID = '45318a66-0ff0-11e7-9454-b083feaf6ace')
                    --BEGIN
                    --    DELETE from temp_last_pending_transactions where ticket_id = @ticketId
                    --END

                    UPDATE ta 
                        SET ta.transaction_status_id = @statusID, 
                            ta.error_status_id = @errId
                    FROM in_proc_transaction_activities ta 
                    WHERE ta.transaction_activity_id = @transActivityId; -- its a primary key so no duplicate

                COMMIT TRANSACTION;

                -- response after commit
                SELECT '1' AS 'result';
            END;
        END;
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

         SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81:', ' message = ', ERROR_NUMBER(), ':', ERROR_MESSAGE())
        END;

        SELECT @error_message AS 'result';
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.p_update_eod_trans_activities_status') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_eod_trans_activities_status >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_eod_trans_activities_status >>>'
GO


IF OBJECT_ID('dbo.p_update_paid_ticket_trans_data') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_paid_ticket_trans_data
    IF OBJECT_ID('dbo.p_update_paid_ticket_trans_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_paid_ticket_trans_data >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_paid_ticket_trans_data >>>'
END
GO
/******************************************************************************
* Object: p_update_paid_ticket_trans_data.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: Update paid ticket details and move from in_proc_transaction_activities to transaction_activities table
* Impacted Table(s): 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB Optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB Optimization: Minimize Deadlocks and Timeouts (Part_I)
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_paid_ticket_trans_data] 
    @trans_activity_id VARCHAR(36),
    @ticketId VARCHAR(36)                                                
AS
BEGIN
    DECLARE @result VARCHAR(255)
    DECLARE @hwid VARCHAR(15)
    DECLARE @msn INT
    DECLARE @agnt_wnng_pymt_status VARCHAR(36)
    DECLARE @oss_processed_date DATETIME2
    DECLARE @thwErrMsg VARCHAR(250)

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    BEGIN TRY
        BEGIN TRANSACTION

            SELECT @hwid = hwid, 
                @msn = msn, 
                @agnt_wnng_pymt_status = agnt_wnng_pymnt_status 
            FROM in_proc_tickets WITH (NOLOCK) 
            WHERE ticket_id = @ticketId    

            UPDATE tickets 
                SET hwid = @hwid,
                    msn = @msn,
                    date_modified = dbo.f_getcustom_date(),
                    agnt_wnng_pymnt_status = @agnt_wnng_pymt_status
            WHERE ticket_id = @ticketId
        
            INSERT INTO transaction_activities
                (transaction_activity_id, ticket_id, transaction_date, transaction_type_id, oss_processed_date,
                 error_status_id, oss_updated_cost, total_cost_alter, transaction_status_id, date_modified, agent_id,
                 oss_agent_account_bal, agent_confirmed_receipt, oss_tax_amount)
            SELECT transaction_activity_id, ticket_id, transaction_date, transaction_type_id, oss_processed_date,
                   error_status_id, oss_updated_cost, total_cost_alter, transaction_status_id, dbo.f_getcustom_date(), agent_id,
                   oss_agent_account_bal, 1, oss_tax_amount
            FROM in_proc_transaction_activities WITH (NOLOCK) 
            WHERE transaction_activity_id = @trans_activity_id

            SELECT @oss_processed_date = oss_processed_date 
            FROM in_proc_coresys_winning_payments WITH (NOLOCK) 
            WHERE ticket_id = @ticketId 

            UPDATE coresys_winning_payments 
                SET oss_processed_date = @oss_processed_date,
                    date_modified = dbo.f_getcustom_date()
            WHERE ticket_id = @ticketId

            DELETE FROM in_proc_coresys_winning_payments WHERE ticket_id = @ticketId
            DELETE FROM in_proc_transaction_activities WHERE transaction_activity_id = @trans_activity_id
            DELETE FROM in_proc_tickets WHERE ticket_id = @ticketId

            SELECT '1', 'Move Completed'
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION

        IF ERROR_NUMBER() IN (1204, -- SqlOutOfLocks
                              1205, -- SqlDeadlockVictim
                              1222 -- SqlLockRequestTimeout
                              )
        BEGIN
            SET @thwErrMsg = CAST(ERROR_NUMBER() AS NVARCHAR) + ': A SqlOutOfLocks/Deadlock/LockRequestTimeout occurred';
            THROW 60000, @thwErrMsg, 1
        END
        ELSE
        BEGIN
            -- Delete if an exception
            SET @result = CONCAT('message = ', ERROR_NUMBER(), ':', ERROR_MESSAGE())
            SELECT '-1', @result AS 'result'
        END
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_update_paid_ticket_trans_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_paid_ticket_trans_data >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_paid_ticket_trans_data >>>'
GO


IF OBJECT_ID('dbo.p_update_panel_count') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_panel_count
    IF OBJECT_ID('dbo.p_update_panel_count') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_panel_count >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_panel_count >>>'
END
GO
/******************************************************************************
* Object: p_update_panel_count.
* Type: Stored Procedure.
* Caller(s): 
* Description: 
* Impacted Table(s): in_proc_tickets.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_panel_count]
(
    @ticket_id	VARCHAR(33) = '',   --required
	@panel_count INT
)
AS
BEGIN
	DECLARE @errorNumber INT;
	DECLARE @error_message VARCHAR(MAX);
    DECLARE @row_count INT;

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON;  -- Rollback transaction if an error occurs

    BEGIN TRY
        BEGIN TRANSACTION        
            UPDATE in_proc_tickets 
            SET panel_count = @panel_count 
            WHERE ticket_id = @ticket_id;

            SET @row_count = @@ROWCOUNT;            
        COMMIT TRANSACTION

        IF @row_count = 0
        BEGIN
            SELECT '-1','No record found for ticket_id = ' + @ticket_id;
        END
        ELSE
        BEGIN
            -- response after successful update
            SELECT '1','updated successfully';
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

       -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81:', ' message = ', @errorNumber, ':', @error_message)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1', @error_message;
        END
    END CATCH
END;
GO
IF OBJECT_ID('dbo.p_update_panel_count') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_panel_count >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_panel_count >>>'
GO



IF OBJECT_ID('dbo.p_update_payment_ticket') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_payment_ticket
    IF OBJECT_ID('dbo.p_update_payment_ticket') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_payment_ticket >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_payment_ticket >>>'
END
GO
/******************************************************************************
* Object: p_update_payment_ticket.
* Type: Stored Procedure.
* Caller(s): 
* Description: 
* Impacted Table(s): agents.
*                    customers.
*                    in_proc_tickets.
*                    tickets.
*                    transaction_activities.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_payment_ticket]
    @custId VARCHAR(9),		-- required
    @transId VARCHAR(32),	-- required
    @game_id INT,		-- required
    @agentId VARCHAR(8),	-- required
    @agent_hostname VARCHAR(255)	-- required
AS
BEGIN
    DECLARE @error_message VARCHAR(255);
    DECLARE @winType VARCHAR(1);
    DECLARE @agentCode VARCHAR(1);

    SET NOCOUNT ON; -- Do not return any rows affected
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    SET @agentCode = SUBSTRING(@transId,1,1);

    DECLARE @validationError NVARCHAR(255);

    DECLARE @transactionTypeId UNIQUEIDENTIFIER = '966ead14-255c-4de4-b67d-28bd452582ea'; -- payout type
    DECLARE @agentWinningStatusId UNIQUEIDENTIFIER = 'aa0cfb5c-2902-414e-897a-dc376371ccf8'; -- pending status

    BEGIN TRY
        -- Combined Validation for Agents, Customers, and In-Proc Tickets
        SELECT TOP 1 @validationError = 
            CASE 
                WHEN a.agent_id IS NULL THEN 'Invalid Agent!'
                WHEN c.customer_id IS NULL THEN 'Invalid Customer!'
                WHEN ipt.ticket_id IS NOT NULL THEN 'Ticket is being processed for Payout'
                ELSE NULL
            END
        FROM agents a WITH(NOLOCK)
        LEFT JOIN customers c WITH(NOLOCK)
            ON c.customer_id = @custId
                AND c.agent_id = @agentId
        LEFT JOIN in_proc_tickets ipt WITH(NOLOCK)
            ON ipt.ticket_id = @transId
                AND ipt.customer_id = @custId
        WHERE a.agent_id = @agentId
            AND a.agent_code = @agentCode
            AND a.agent_host_name = @agent_hostname;

        IF @validationError IS NOT NULL
        BEGIN
            SELECT '-1', @validationError;
            RETURN;
        END;

        -- Validate Ticket and Related Conditions
        SELECT TOP 1 @validationError = 
            CASE
                WHEN t.ticket_id IS NULL THEN 'Invalid Ticket ID!'
                WHEN t.bet_result_type_id IS NULL THEN 'Invalid Ticket ID!'
                WHEN t.bet_result_type_id NOT IN (1, 2, 3) THEN 'Not a Winner/Does Not Exist/No Result(s) Yet'
                WHEN t.bet_result_type_id = 3 THEN 'High Tier Payment Not Allowed'
                WHEN ta.ticket_id IS NOT NULL THEN 'Ticket has already been processed for Payout'
                ELSE NULL
            END
        FROM tickets t WITH (NOLOCK)
        LEFT JOIN transaction_activities ta 
            ON ta.ticket_id = t.ticket_id
        AND ta.transaction_type_id = @transactionTypeId -- payout
        WHERE t.ticket_id = @transId
            AND t.customer_id = @custId;

        IF @validationError IS NOT NULL
        BEGIN
            SELECT '-1', @validationError;
            RETURN;
        END;

        -- If all checks pass, then proceed with the transaction
        BEGIN TRANSACTION
            INSERT INTO in_proc_tickets (
                ticket_id, customer_id, draw_id, game_id, sub_game_id, system_number, draw_date, draw_offset,
                hwid, msn, vtid1, vtid2, vtid2_encrypted, tsn, cost, bet_result_type_id,
                panel_count, purge_date, date_modified, date_created, header_summary, footer_summary,
                agnt_wnng_pymnt_status, agnt_wnng_upload_status
            )				
            SELECT ticket_id, customer_id, draw_id, game_id, sub_game_id, system_number, draw_date, draw_offset,
                hwid, msn, vtid1, vtid2, vtid2_encrypted, tsn, cost, bet_result_type_id,
                panel_count, purge_date, dbo.f_getcustom_date(), date_created, header_summary, footer_summary,
                @agentWinningStatusId, agnt_wnng_upload_status 
            FROM tickets WITH (NOLOCK) 
            WHERE ticket_id = @transId;

            -- 077fcc2a-724d-4d7f-990f-61b497773dd8 - complete
            -- 9996c3ca-7b38-4b7c-97f6-4c9755a3ff96 - error
            -- Just return success because it exists: MV - 05/28/2020
            --IF @payStatus IS NOT NULL AND @payStatus IN ('9996c3ca-7b38-4b7c-97f6-4c9755a3ff96','077fcc2a-724d-4d7f-990f-61b497773dd8')
                -- aa0cfb5c-2902-414e-897a-dc376371ccf8 --> pending
            -- Instead of Updating use the value from the select statement above 12/29/24
            -- UPDATE in_proc_tickets SET agnt_wnng_pymnt_status ='aa0cfb5c-2902-414e-897a-dc376371ccf8' WHERE ticket_id = @transId

            -- aa0cfb5c-2902-414e-897a-dc376371ccf8 --> pending
            UPDATE tickets 
            SET agnt_wnng_pymnt_status = @agentWinningStatusId 
            WHERE ticket_id = @transId;

            -- Insert into in_proc_transaction_activities   
            INSERT INTO in_proc_transaction_activities (
                transaction_activity_id,
                ticket_id,
                transaction_date,
                transaction_type_id, 
                agent_id, 
                date_modified
            )
            VALUES (
                NEWID(),
                @transId,
                dbo.f_getcustom_date(),
                @transactionTypeId,  -- payout
                @agentId, 
                dbo.f_getcustom_date()
            );
        COMMIT TRANSACTION

        -- return after commit
        SELECT '1','Successfully Updated';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
 
        SET @error_message = CONCAT('-81:',' message = ', ERROR_NUMBER(),':',ERROR_MESSAGE());
        SELECT '-1',@error_message AS 'result';
    END CATCH
END;
GO
IF OBJECT_ID('dbo.p_update_payment_ticket') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_payment_ticket >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_payment_ticket >>>'
GO



IF OBJECT_ID('dbo.p_update_tickets_with_hwid') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_tickets_with_hwid;
    IF OBJECT_ID('dbo.p_update_tickets_with_hwid') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_tickets_with_hwid >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_tickets_with_hwid >>>';
END
GO
/******************************************************************************
* Object: p_update_tickets_with_hwid.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: update paid ticket details and move from in_proc_transaction_activities to transaction_activities table
* Impacted Table(s): in_proc_tickets.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_tickets_with_hwid] 
    @ticketId VARCHAR(36), 
    @in_hwId VARCHAR(36), 
    @in_msn INT
AS
BEGIN
    DECLARE @result VARCHAR(MAX);
    DECLARE @error_message VARCHAR(MAX);
    DECLARE @errorNumber INT;

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    BEGIN TRY
        BEGIN TRANSACTION;
            -- update ticket with hwid and msn
            UPDATE tck 
                SET tck.hwid = @in_hwId, 
                    tck.msn = @in_msn
            FROM in_proc_tickets tck
            WHERE tck.ticket_id = @ticketId;
        COMMIT TRANSACTION;

        -- return after successful update
        SELECT '1' AS 'result';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

         -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @errorNumber, '=>',  @error_message)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT @error_message AS 'result';
        END
    END CATCH;
END
GO
IF OBJECT_ID('dbo.p_update_tickets_with_hwid') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_tickets_with_hwid >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_tickets_with_hwid >>>';
GO


IF OBJECT_ID('dbo.p_update_trans_activities_status') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_trans_activities_status
    IF OBJECT_ID('dbo.p_update_trans_activities_status') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_trans_activities_status >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_trans_activities_status >>>'
END
GO
/******************************************************************************
* Object: p_update_trans_activities_status.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: update paid ticket details and move from in_proc_transaction_activities to transaction_activities table
* Impacted Table(s): 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2126: catch deadlock and throw exception
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_trans_activities_status] 
    @transActivityId VARCHAR(36), 
    @transTypeId VARCHAR(36),
    @ticketId VARCHAR(36), 
    @status VARCHAR(32),
    @errStatusType INT, 
    @errCode VARCHAR(5), 
    @errDesc NVARCHAR(MAX)
AS
BEGIN
    DECLARE @statusID VARCHAR(36);
    DECLARE @errId VARCHAR(36);
    DECLARE @result NVARCHAR(MAX);
    DECLARE @error_message VARCHAR(MAX);
    DECLARE @rowCount INT;
	DECLARE @errorNumber INT;

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON;  -- Rollback transaction if an error occurs

    --DECLARE @InsertedErrId  TABLE (error_status_id UNIQUEIDENTIFIER);

    BEGIN TRY
        SET @statusID = 
            CASE @status
                WHEN 'Not_Processed' THEN '0ab02c66-0fef-11e7-9454-b083feaf6ace'
                WHEN 'Completed' THEN '6a56bdfb-0ff0-11e7-9454-b083feaf6ace'
                WHEN 'Processing' THEN 'ed1bc7ec-0fef-11e7-9454-b083feaf6ace'
                WHEN 'Error' THEN '45318a66-0ff0-11e7-9454-b083feaf6ace'
            END;

        BEGIN
            BEGIN TRANSACTION
                IF (@errCode IS NOT NULL) 
                BEGIN
                    -- Use NEWSEQUENTIALID() instead of NEWID() to avoid fragmentation
                    SET @errId = NEWID()
                    INSERT INTO error_status(error_status_id, error_status_type_id, error_status_code, error_status_description, date_modified)
                        --OUTPUT INSERTED.error_status_id INTO @InsertedErrId
                        VALUES(@errId, @errStatusType, @errCode, @errDesc, dbo.f_getcustom_date());
                END;

                -- Retrieve the inserted ID into the scalar variable
                --SELECT TOP 1 @errId = error_status_id FROM @InsertedErrId;

                UPDATE ta 
                    SET ta.transaction_status_id = @statusID, 
                    ta.error_status_id = @errId
                FROM in_proc_transaction_activities ta 
                WHERE ta.transaction_activity_id = @transActivityId; -- its a primary key so no duplicate
                      --ta.ticket_id = @ticketId AND
                      --ta.transaction_type_id = @transTypeId;
            COMMIT TRANSACTION;

            SELECT '1' AS 'result';
        END;
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81:', ' message = ', @errorNumber, ':', @error_message)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT @error_message AS 'result';
        END;
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.p_update_trans_activities_status') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_trans_activities_status >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_trans_activities_status >>>'
GO


IF OBJECT_ID('dbo.p_update_trans_confirmation') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_trans_confirmation
    IF OBJECT_ID('dbo.p_update_trans_confirmation') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_trans_confirmation >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_trans_confirmation >>>'
END
GO
------------------------ NOT in USE ------------------------------
/******************************************************************************
* Object: p_update_trans_confirmation.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: update paid ticket details and move from in_proc_transaction_activities to transaction_activities table
* Impacted Table(s): 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2356: Keep 'NOLOCK' because thi procedure is called only after PWS is done processing.
*				Remove Nolock from winning_header_data since we need the updated value for the process_status flag.
* PTR 2358: Header Text Update.
* PTR 2126: catch deadlock and throw exception
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_trans_confirmation]
    @custId VARCHAR(9),
    @ticketId VARCHAR(36)
AS
BEGIN
    DECLARE @type_id VARCHAR(36)
    DECLARE @result NVARCHAR(MAX)

    SET @result = '-1'

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    BEGIN TRY
        SET @type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f'

        -- 45318a66-0ff0-11e7-9454-b083feaf6ace -error
        -- 6a56bdfb-0ff0-11e7-9454-b083feaf6ace -completed
        IF NOT EXISTS (
            SELECT tck.ticket_id  
            FROM tickets tck WITH (NOLOCK) JOIN transaction_activities ta 
                ON ta.ticket_id = tck.ticket_id 
            WHERE tck.ticket_id = @ticketId 
            AND tck.customer_id = @custId 
            AND (ta.transaction_status_id = '6a56bdfb-0ff0-11e7-9454-b083feaf6ace' 
                OR ta.transaction_status_id = '45318a66-0ff0-11e7-9454-b083feaf6ace')
        )
        BEGIN
            SET @result = '-1'
        END
        ELSE
        BEGIN
            BEGIN TRANSACTION
                UPDATE ta                   
                    SET ta.agent_confirmed_receipt = 1 
                FROM transaction_activities ta 
                    --JOIN tickets t ON ta.ticket_id = t.ticket_id 
                WHERE ta.ticket_id = @ticketId AND
                      --t.customer_id = @custId AND
                      ta.transaction_type_id = @type_id

                SET @result = CONCAT('', @@ROWCOUNT)
            COMMIT TRANSACTION
        END

        SELECT @result AS 'result'
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION

        SET @result = CONCAT('-81:', ' message = ', ERROR_NUMBER(), ':', ERROR_MESSAGE())
        SELECT @result AS 'result'
    END CATCH
-- Check whether the insert was successful
END
GO
IF OBJECT_ID('dbo.p_update_trans_confirmation') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_trans_confirmation >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_trans_confirmation >>>'
GO


IF OBJECT_ID('dbo.p_update_trans_status') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_trans_status
    IF OBJECT_ID('dbo.p_update_trans_status') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_trans_status >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_trans_status >>>'
END
GO
/******************************************************************************
* Object: p_update_trans_status.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: 
* Impacted Table(s): 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.
* PTR 2126: catch deadlock and throw exception
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_trans_status] 
    @transActivityId VARCHAR(36), 
    @transTypeId VARCHAR(36),
    @ticketId VARCHAR(36), 
    @status VARCHAR(32)
AS
BEGIN
    DECLARE @statusID VARCHAR(36)
    DECLARE @result NVARCHAR(MAX)
    DECLARE @thwErrMsg VARCHAR(MAX);
	DECLARE @errorNumber INT;

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs
    
    SET @result = '-1'

    BEGIN TRY
        SET @status = CASE @statusID 
            WHEN 'Reconciliation' THEN 'f2365d90-58b9-11e7-9454-b083feaf6ace'
            WHEN 'Not_Processed' THEN '0ab02c66-0fef-11e7-9454-b083feaf6ace'
            WHEN 'Completed' THEN '6a56bdfb-0ff0-11e7-9454-b083feaf6ace'
            WHEN 'Processing' THEN 'ed1bc7ec-0fef-11e7-9454-b083feaf6ace'
        END;

        BEGIN TRANSACTION
            UPDATE ta 
                SET ta.transaction_status_id = @statusID
            FROM in_proc_transaction_activities ta 
            WHERE ta.transaction_activity_id = @transActivityId -- Its a primary key
                -- ta.ticket_id = @ticketId AND
                -- ta.transaction_type_id = @transTypeId;
        COMMIT TRANSACTION

        -- sucess after commit
        SELECT '1' AS 'result'
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER()
        SET @thwErrMsg = ERROR_MESSAGE()

        SET @thwErrMsg = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @thwErrMsg)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @thwErrMsg)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @thwErrMsg)
            ELSE CONCAT('-81:', ' message = ', @errorNumber, ':', @thwErrMsg)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @thwErrMsg, 1
        END
        ELSE
        BEGIN
            SELECT @thwErrMsg AS 'result'
        END
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_update_trans_status') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_trans_status >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_trans_status >>>'
GO



IF OBJECT_ID('dbo.p_update_winning_header_data_upload_status') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_winning_header_data_upload_status
    IF OBJECT_ID('dbo.p_update_winning_header_data_upload_status') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_winning_header_data_upload_status >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_winning_header_data_upload_status >>>'
END
GO
/******************************************************************************
* Object:                p_update_winning_header_data_upload_status.
* Type:                  Stored Procedure.
* Caller(s):             Transfer Winners Service (TWS)
* Description:           
* Impacted Table(s):     
*  
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2358: Header Text Update.    
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_update_winning_header_data_upload_status]
    @file_version VARCHAR(20),        -- required
    @game_id INT,            -- required
    @draw_id INT,            -- required
    @draw_date DATETIME2,        -- required
    @agent_id VARCHAR(8)        -- required
AS
BEGIN
    DECLARE @errorNumber INT;
    DECLARE @error_message NVARCHAR(MAX);
    DECLARE @row_count INT;

    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION
            UPDATE winning_upload_status 
            SET upload_status = 1
            WHERE game_id = @game_id
                AND draw_id = @draw_id 
                AND agent_id = @agent_id 
                AND draw_date = @draw_date

            SET @row_count = @@ROWCOUNT
        COMMIT TRANSACTION

        IF @row_count > 0
        BEGIN
            -- Successful update
            SELECT '1', 'Data updated successfully';
        END
        ELSE
        BEGIN
            SELECT '-1', 'Data updated failed';
        END
    END TRY
    -- Check whether the UPDATE was successful
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION

         -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SELECT '-1',CONCAT(@errorNumber, '=>',  @error_message);
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_update_winning_header_data_upload_status') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_winning_header_data_upload_status >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_winning_header_data_upload_status >>>'
GO


IF OBJECT_ID('dbo.p_update_winning_ticket') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_winning_ticket
    IF OBJECT_ID('dbo.p_update_winning_ticket') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_winning_ticket >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_winning_ticket >>>'
END
GO
/******************************************************************************
* Object: p_update_winning_ticket.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: update paid ticket details and move from in_proc_transaction_activities to transaction_activities table
* Impacted Table(s): 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2156: Selling ticket: Ticket can not processed
* PTR 2171: Selling ticket: Lost winning files
* PTR 2217: Process Winner Service: stop â€“ start process winner service on bingo release software 
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_winning_ticket]
    @custId VARCHAR(9),
    @vtid1 VARCHAR(50),
    @flag TINYINT,
    @winningAmt MONEY,
    @tax MONEY,
    @payAmt MONEY
    -- add tax field
AS
BEGIN
    DECLARE @ticketId VARCHAR(36)
    DECLARE @agntWinningUploadStatus UNIQUEIDENTIFIER = '141b82f5-127d-4846-8e3a-4aa9c4ee75e8'; -- not uploaded

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows
    SET XACT_ABORT ON; -- SET on to rollback automatically on error

    -- Check if the ticket exists
    SELECT TOP 1 @ticketId = ticket_id
    FROM tickets WITH (NOLOCK)
    WHERE vtid1 = @vtid1 
        AND customer_id = @custId;

    IF @ticketId IS NULL
    BEGIN
        SELECT '-1' AS 'ticket_id'
        RETURN;
    END
    ELSE -- If the ticket exists, update the ticket
    BEGIN
        BEGIN TRY    
            BEGIN TRANSACTION                
                -- insert into coresys winning
                INSERT INTO coresys_winning_payments (
                    ticket_id, 
                    oss_winning_amount, 
                    oss_winning_tax, 
                    oss_payment_amount, 
                    date_modified
                )
                VALUES (
                    @ticketId, 
                    @winningAmt, 
                    @tax, 
                    @payAmt, 
                    dbo.f_getcustom_date()
                );

                UPDATE tickets 
                SET bet_result_type_id = @flag, 
                    agnt_wnng_upload_status = @agntWinningUploadStatus
                WHERE ticket_id = @ticketId;
            COMMIT TRANSACTION

            -- return success message after successful update
            SELECT @ticketId AS 'ticket_id';
        END TRY
        -- Check whether the update was successful
        BEGIN CATCH
            -- Rollback transaction if an error occurs and transaction is still open
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            SET @ticketId = CONCAT('-81:',' message = ', ERROR_NUMBER(),':',ERROR_MESSAGE());
            SELECT @ticketId AS ticket_id;
        END CATCH
    END
END
GO
IF OBJECT_ID('dbo.p_update_winning_ticket') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_winning_ticket >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_winning_ticket >>>'
GO


IF OBJECT_ID('dbo.p_update_winning_ticket_frm_winnings_holding') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_winning_ticket_frm_winnings_holding
    IF OBJECT_ID('dbo.p_update_winning_ticket_frm_winnings_holding') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_winning_ticket_frm_winnings_holding >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_winning_ticket_frm_winnings_holding >>>'
END
GO
/******************************************************************************
* Object: p_update_winning_ticket_frm_winnings_holding.
* Type: Stored Procedure.
* Caller(s): 
* Description: update paid ticket details and move from in_proc_transaction_activities to transaction_activities table
* Impacted Table(s): tickets.
*                    coresys_winning_payments.
*                    temp_winnings_holding.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_winning_ticket_frm_winnings_holding] 
    @game_draw_id		VARCHAR(36)
AS 
BEGIN
    
    DECLARE @error_message VARCHAR(MAX);    
	DECLARE @errorNumber INT;

    DECLARE @temp TABLE (
        win_type VARCHAR(1), 
        win_amnt MONEY, 
        tax_amnt MONEY, 
        pymnt_amnt MONEY,
        ticket_id VARCHAR(36)
    );

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs

    --INSERT INTO temp table variable
    INSERT INTO @temp 
    SELECT 
        tmp.winning_type, 
        tmp.winning_amount, 
        tmp.tax_amount, 
        tmp.payment_amount,
        tck.ticket_id
    FROM tickets tck WITH (NOLOCK) INNER JOIN 
        temp_winnings_holding tmp WITH (NOLOCK) 
            ON tmp.vtid1 = tck.vtid1 
			AND tmp.game_draw_id = @game_draw_id
            AND NOT EXISTS (  -- PTR 2217 to avoid adding the same ticket into the @temp
                SELECT 1 
                FROM coresys_winning_payments cw WITH (NOLOCK)
                WHERE cw.ticket_id = tck.ticket_id
            );

    BEGIN TRY
        BEGIN TRANSACTION
            --UPDATE tickets with appropriate winning_type and agent winning upload status
            UPDATE t 
                SET t.bet_result_type_id = t2.win_type, 
                    t.agnt_wnng_upload_status = '141b82f5-127d-4846-8e3a-4aa9c4ee75e8'
            FROM tickets t
                INNER JOIN @temp t2 
                    ON t.ticket_id = t2.ticket_id;

            -- ADD record INTO coresys_winning_payments table
            INSERT INTO coresys_winning_payments(
                ticket_id, 
                oss_winning_amount, 
                oss_winning_tax, 
                oss_payment_amount, 
                date_modified
            )
            SELECT 
                ticket_id, 
                win_amnt, 
                tax_amnt, 
                pymnt_amnt, 
                dbo.f_getcustom_date() 
            FROM @temp;

            -- PTR 2171
            -- Delete from temp_winnings_holding
            DELETE FROM temp_winnings_holding 
                WHERE game_draw_id = @game_draw_id;
        COMMIT TRANSACTION

        -- return after successful update
        SELECT '1', 'Successfully Updated';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81', ':', @errorNumber, '=>',  @error_message)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT '-1', @error_message;
        END
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.p_update_winning_ticket_frm_winnings_holding') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_winning_ticket_frm_winnings_holding >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_winning_ticket_frm_winnings_holding >>>'
GO



IF OBJECT_ID('dbo.p_update_winning_ticket_status') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_winning_ticket_status
    IF OBJECT_ID('dbo.p_update_winning_ticket_status') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_winning_ticket_status >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_winning_ticket_status >>>'
END
GO
/******************************************************************************
* Object: p_update_winning_ticket_status.
* Type: Stored Procedure.
* Caller(s): Process Winners Service (PWS).
* Description: updates the agnt_wnng_upload_status column in the tickets table to upladed status.
* Impacted Table(s): tickets.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_winning_ticket_status]
    @ticket_id VARCHAR(32)	-- required
AS
BEGIN
    DECLARE @error_message VARCHAR(MAX)
    DECLARE @rowCount INT;
    DECLARE @agntWinningUploadStatus UNIQUEIDENTIFIER = '90495e31-8da0-4d5a-852c-2a3838008203';  -- uploaded status
    
    SET NOCOUNT ON; -- SET off to prevent extra result sets
    SET XACT_ABORT ON; -- SET on to rollback automatically on error

    BEGIN TRY
        BEGIN TRAN;
            --EXEC p_spgetapplock 'tickets';
            UPDATE tickets 
            SET agnt_wnng_upload_status = @agntWinningUploadStatus
            WHERE ticket_id = @ticket_id;

            SET @rowCount = @@ROWCOUNT;
        COMMIT TRAN;

        -- return success message after successful update
        IF @rowCount > 0
            SELECT '1', 'Successfully Uploaded!';
        ELSE
            SELECT '-1', 'Failed to update ticket status!';
    END TRY
    BEGIN CATCH
         -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @error_message = CONCAT('message = ', ERROR_NUMBER(),':',ERROR_MESSAGE());
        SELECT '-1', @error_message AS 'result';
    END CATCH 
END
GO
IF OBJECT_ID('dbo.p_update_winning_ticket_status') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_winning_ticket_status >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_winning_ticket_status >>>'
GO


IF OBJECT_ID('dbo.p_update_wnng_ticket_status_blk') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_update_wnng_ticket_status_blk
    IF OBJECT_ID('dbo.p_update_wnng_ticket_status_blk') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_update_wnng_ticket_status_blk >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_update_wnng_ticket_status_blk >>>'
END
GO
/******************************************************************************
* Object: p_update_wnng_ticket_status_blk.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: 
* Impacted Table(s): 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2356: Keep 'NOLOCK' because the condition check and data retrieval are performed 
*				on column(s) that do not change frequently.
* PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
* PTR 2358: Header Text Update.
* PTR 2292: DB: Duplicate panels in in_proc tables
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_update_wnng_ticket_status_blk]
    @ticket_list VARCHAR(MAX)
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX)

    SET NOCOUNT ON; -- Stop the message that shows the count of the number of rows affected by a query
    SET XACT_ABORT ON; -- Rollback transaction if an error occurs
    
    BEGIN TRY
        BEGIN TRANSACTION
           SET @sql = 'UPDATE tickets SET agnt_wnng_upload_status = ''90495e31-8da0-4d5a-852c-2a3838008203'' 
            WHERE ticket_id IN ('+@ticket_list+')'
			
            EXEC sp_executesql @sql

        COMMIT TRAN

		SELECT '1','Update Successfully'
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION

        SELECT '-1', CONCAT('message = ', ERROR_NUMBER(),':',ERROR_MESSAGE())
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_update_wnng_ticket_status_blk') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_update_wnng_ticket_status_blk >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_update_wnng_ticket_status_blk >>>'
GO


IF OBJECT_ID('dbo.p_updates_from_oss') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_updates_from_oss
    IF OBJECT_ID('dbo.p_updates_from_oss') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_updates_from_oss >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_updates_from_oss >>>'
END
GO
/******************************************************************************
* Object: p_updates_from_oss.
* Type: Stored Procedure.
* Caller(s): DataTrakTransService (DTTS).
* Description: Updates the in_proc_tickets and in_proc_transaction_activities tables with the values received from OSS.
* Impacted Table(s): in_proc_tickets.
*                    in_proc_transaction_activities.
*                    agents.
*                    error_status.
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2358: Header Text Update.
* PTR 2126: catch block to handle deadlock and lock timeout errors.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_updates_from_oss]
    @ticketId VARCHAR(36), 
    @agentId VARCHAR(8), 
    @transActivityId VARCHAR(36), 
    @hw_id VARCHAR(36), 
    @tsn_num VARCHAR(50),
    @drawDate DATETIME2, 
    @sellCanceldate DATETIME2, 
    @inOSSCost MONEY, 
    @vtid1 VARCHAR(16),
    @encrypted_vtid2 VARCHAR(40), 
    @inOSSTaxAmount MONEY,
    @agentBal MONEY, 
    @drawId INT, 
    @headerSummary NVARCHAR(MAX), 
    @footerSummary NVARCHAR(MAX),
    @errCode VARCHAR(5), 
    @errDesc TEXT
AS
BEGIN
    DECLARE @errId VARCHAR(36);
    DECLARE @result VARCHAR(255);
    DECLARE @sqlquery VARCHAR(255);
    DECLARE @error_message VARCHAR(5000);
    DECLARE @errorNumber INT;

    --DECLARE @errIdTable TABLE (error_status_id VARCHAR(36));
    
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF (@errCode <> 0)
        BEGIN
            -- use NEWSEQUENTIALID() instead of NEWID() to avoid fragmentation
            SET @errId = NEWID();
            INSERT INTO error_status (
                error_status_id,
                error_status_code, 
                error_status_description
            )
            --OUTPUT INSERTED.error_status_id INTO @errIdTable
            VALUES(
                @errId,
                @errCode, 
                @errDesc
            );
            -- set error id
            --SELECT @errId = error_status_id FROM @errIdTable;
        END;
        
        IF (@agentId != '-1' AND @agentId IS NOT NULL)
        BEGIN
            UPDATE agents WITH(ROWLOCK) 
                SET agent_bal_from_oss = @agentBal 
            WHERE agent_id = @agentId;
        END;

        -- set variables to NULL if empty
        SET @tsn_num = NULLIF(@tsn_num, '');
        SET @drawDate = NULLIF(@drawDate, '');
        SET @vtid1 = NULLIF(@vtid1, '');
        SET @encrypted_vtid2 = NULLIF(@encrypted_vtid2, '');
        SET @sellCancelDate = NULLIF(@sellCancelDate, '');

        BEGIN TRANSACTION
            UPDATE tck WITH(ROWLOCK, UPDLOCK)
                SET tck.hwid = @hw_id, 
                    tck.tsn = @tsn_num, 
                    tck.draw_date = @drawDate, 
                    tck.draw_id = @drawId, 
                    tck.header_summary = @headerSummary, 
                    tck.footer_summary = @footerSummary, 
                    tck.vtid1 = @vtid1,
                    tck.vtid2_encrypted = @encrypted_vtid2, 
                    tck.date_modified = dbo.f_getcustom_date()
            FROM in_proc_tickets tck 
            WHERE tck.ticket_id = @ticketId;
		 
            UPDATE ta WITH(ROWLOCK, UPDLOCK)
                SET ta.oss_processed_date = @sellCancelDate, 
                ta.oss_updated_cost = @inOSSCost,
                ta.oss_tax_amount = @inOSSTaxAmount, 
                ta.oss_agent_account_bal = @agentBal, 
                ta.error_status_id = @errId, 
                ta.date_modified = dbo.f_getcustom_date()
            FROM in_proc_transaction_activities ta --WITH (INDEX(trans_ticket_actv_type_index))
            WHERE ta.transaction_activity_id = @transActivityId;
                -- AND ta.ticket_id = @ticketId
                -- AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f';   -- Sell transaction type
        COMMIT TRANSACTION

        -- return success message after successful update
        SELECT '1' AS 'result';
    END TRY
    BEGIN CATCH
        -- Rollback transaction if an error occurs and transaction is still open
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Capture error details
        SET @errorNumber = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();

        SET @error_message = CASE @errorNumber
            WHEN 1204 THEN CONCAT('1204: A SqlOutOfLocks occurred - ', @error_message)
            WHEN 1205 THEN CONCAT('1205: A SqlDeadlockVictim occurred - ', @error_message)
            WHEN 1222 THEN CONCAT('1222: A SqlLockRequestTimeout occurred - ', @error_message)
            ELSE CONCAT('-81:', ' message = ', @errorNumber, ':', @error_message)
        END;

        IF @errorNumber IN (1204, 1205, 1222) -- SqlOutOfLocks, SqlDeadlockVictim, SqlLockRequestTimeout
        BEGIN
            -- Throw custom error
            THROW 60000, @error_message, 1;
        END
        ELSE
        BEGIN
            SELECT @error_message AS 'result';
        END
    END CATCH;
END
GO
IF OBJECT_ID('dbo.p_updates_from_oss') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_updates_from_oss >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_updates_from_oss >>>'
GO


IF OBJECT_ID('dbo.p_verify_bingo_winning_report') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_verify_bingo_winning_report;
    IF OBJECT_ID('dbo.p_verify_bingo_winning_report') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_verify_bingo_winning_report >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_verify_bingo_winning_report >>>';
END;
GO
/******************************************************************************
* Object:                p_verify_bingo_winning_report.
* Type:                  Stored Procedure.
* Caller(s):             
* Description:           
* Impacted Table(s):     
*  
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
*   PTR 2358: Header Text Update.        
*******************************************************************************/
CREATE PROCEDURE [dbo].[p_verify_bingo_winning_report]
(
    @draw_id AS VARCHAR(max)='', --required
    @game_id AS VARCHAR(max)='', --required
    @result INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON; --no need to return row count
    SET XACT_ABORT ON; --rollback transaction

    BEGIN TRY 
        BEGIN TRANSACTION
            IF EXISTS (
                SELECT 1 
                FROM winning_header_data WITH (NOLOCK)
                WHERE game_id = @game_id  
                    AND draw_id = @draw_id 
                    AND bingo_report_generated = 0
            )
            BEGIN
                UPDATE winning_header_data 
                SET bingo_report_generated = 1 
                WHERE game_id = @game_id  
                    AND draw_id = @draw_id;
                
                SELECT @result = @@ROWCOUNT;
            END
            ELSE
            BEGIN
                SELECT @result = '-1';
            END
        COMMIT TRANSACTION
    END TRY    
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SELECT @result = '-1'; 
    END CATCH
END;
GO
IF OBJECT_ID('dbo.p_verify_bingo_winning_report') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_verify_bingo_winning_report >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_verify_bingo_winning_report >>>';
GO


