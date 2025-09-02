
/***************************************************/
/**          2_datatrak_alter_table_scripts.sql             **/
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

IF NOT EXISTS (
    SELECT 1 
    FROM games 
    WHERE game_id = 106
)
BEGIN
    INSERT INTO games (game_id, game_name, selling_enabled_game, date_modified)
    VALUES (106, 'Lotto 535', 1, [dbo].f_getcustom_date());

    PRINT '<<< INSERTED: FastDraw 535 (game_id = 106) into games table >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED: FastDraw 535 (game_id = 106) already exists in games table >>>';
END
GO

DECLARE @sql NVARCHAR(MAX);
DECLARE @fk_name NVARCHAR(128);

-- Get the foreign key name
SELECT @fk_name = fk.name,
       @sql = 'ALTER TABLE in_proc_transaction_activities DROP CONSTRAINT [' + fk.name + ']'
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
JOIN sys.tables t_parent ON fk.referenced_object_id = t_parent.object_id
JOIN sys.columns c_parent ON fkc.referenced_column_id = c_parent.column_id AND c_parent.object_id = t_parent.object_id
JOIN sys.tables t_child ON fk.parent_object_id = t_child.object_id
JOIN sys.columns c_child ON fkc.parent_column_id = c_child.column_id AND c_child.object_id = t_child.object_id
WHERE 
    t_parent.name = 'in_proc_tickets'
    AND c_parent.name = 'ticket_id'
    AND t_child.name = 'in_proc_transaction_activities'
    AND c_child.name = 'ticket_id';

-- Execute if constraint is found
IF @sql IS NOT NULL
BEGIN
    PRINT 'Found and dropping foreign key constraint: ' + @fk_name;
    EXEC sp_executesql @sql;
    PRINT 'Successfully dropped foreign key: ' + @fk_name;
END
ELSE
BEGIN
    PRINT 'No matching foreign key constraint found between in_proc_transaction_activities.ticket_id and in_proc_tickets.ticket_id.';
END


-- Check if index 'IX_customers_id_agent_id_status' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_customers_id_agent_id_status'  
        AND object_id = OBJECT_ID('dbo.customers')
)
BEGIN
    DROP INDEX IX_customers_id_agent_id_status 
	ON dbo.customers
    PRINT '<<< DROPPED INDEX dbo.IX_customers_id_agent_id_status >>>';
END
GO
/******************************************************************************
* Object: IX_customers_id_agent_id_status.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.customers.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_customers_id_agent_id_status' if it does not already exist
CREATE NONCLUSTERED INDEX IX_customers_id_agent_id_status
    ON dbo.customers (
        customer_id,
	    agent_id,
	    customer_status_id
    )
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_customers_id_agent_id_status'  
        AND object_id = OBJECT_ID('dbo.customers')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_customers_id_agent_id_status >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_customers_id_agent_id_status >>>';
END
GO

--Rebuild and organize indexes on the table
--ALTER INDEX ALL ON customers REBUILD;
--UPDATE STATISTICS customers

-- Check if index 'IX_in_proc_tickets_created_date_game_draw_id' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_tickets_created_date_game_draw_id'  
        AND object_id = OBJECT_ID('dbo.in_proc_tickets')
)
BEGIN
    DROP INDEX IX_in_proc_tickets_created_date_game_draw_id 
	ON dbo.in_proc_tickets
    PRINT '<<< DROPPED INDEX dbo.IX_in_proc_tickets_created_date_game_draw_id >>>';
END
GO
/******************************************************************************
* Object: IX_in_proc_tickets_created_date_game_draw_id.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.in_proc_tickets.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_in_proc_tickets_created_date_game_draw_id' if it does not already exist
CREATE NONCLUSTERED INDEX IX_in_proc_tickets_created_date_game_draw_id
    ON dbo.in_proc_tickets (
        date_created,
        game_id,
        draw_id
    )
    INCLUDE (customer_id)
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_tickets_created_date_game_draw_id'  
        AND object_id = OBJECT_ID('dbo.in_proc_tickets')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_in_proc_tickets_created_date_game_draw_id >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_in_proc_tickets_created_date_game_draw_id >>>';
END
GO

-- Check if index 'IX_in_proc_tickets_game_draw_id' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_tickets_game_draw_id'  
        AND object_id = OBJECT_ID('dbo.in_proc_tickets')
)
BEGIN
    DROP INDEX IX_in_proc_tickets_game_draw_id 
	ON dbo.in_proc_tickets
    PRINT '<<< DROPPED INDEX dbo.IX_in_proc_tickets_game_draw_id >>>';
END
GO
/******************************************************************************
* Object: IX_in_proc_tickets_game_draw_id.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.in_proc_tickets.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_in_proc_tickets_game_draw_id' if it does not already exist
CREATE NONCLUSTERED INDEX IX_in_proc_tickets_game_draw_id
    ON dbo.in_proc_tickets (
        game_id,
        draw_id
    )
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_tickets_game_draw_id'  
        AND object_id = OBJECT_ID('dbo.in_proc_tickets')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_in_proc_tickets_game_draw_id >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_in_proc_tickets_game_draw_id >>>';
END
GO

-- Check if index 'IX_in_proc_tickets_pnlcnt_tsn_agntpystatus' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_tickets_pnlcnt_tsn_agntpystatus'  
        AND object_id = OBJECT_ID('dbo.in_proc_tickets')
)
BEGIN
    DROP INDEX IX_in_proc_tickets_pnlcnt_tsn_agntpystatus 
	ON dbo.in_proc_tickets
    PRINT '<<< DROPPED INDEX dbo.IX_in_proc_tickets_pnlcnt_tsn_agntpystatus >>>';
END
GO
/******************************************************************************
* Object: IX_in_proc_tickets_pnlcnt_tsn_agntpystatus.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.in_proc_tickets.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_in_proc_tickets_pnlcnt_tsn_agntpystatus' if it does not already exist
CREATE NONCLUSTERED INDEX IX_in_proc_tickets_pnlcnt_tsn_agntpystatus
    ON dbo.in_proc_tickets (
        panel_count,
        tsn,
        agnt_wnng_pymnt_status
    )
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_tickets_pnlcnt_tsn_agntpystatus'  
        AND object_id = OBJECT_ID('dbo.in_proc_tickets')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_in_proc_tickets_pnlcnt_tsn_agntpystatus >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_in_proc_tickets_pnlcnt_tsn_agntpystatus >>>';
END
GO

-- Check if index 'IX_in_proc_transaction_activities_status_receipt_agent' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_transaction_activities_status_receipt_agent'  
        AND object_id = OBJECT_ID('dbo.in_proc_transaction_activities')
)
BEGIN
    DROP INDEX IX_in_proc_transaction_activities_status_receipt_agent 
	ON dbo.in_proc_transaction_activities
    PRINT '<<< DROPPED INDEX dbo.IX_in_proc_transaction_activities_status_receipt_agent >>>';
END
GO
/******************************************************************************
* Object: IX_in_proc_transaction_activities_status_receipt_agent.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.in_proc_transaction_activities.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_in_proc_transaction_activities_status_receipt_agent' if it does not already exist
CREATE NONCLUSTERED INDEX IX_in_proc_transaction_activities_status_receipt_agent
    ON dbo.in_proc_transaction_activities (
        transaction_status_id,
        agent_confirmed_receipt,
        agent_id
    )
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_transaction_activities_status_receipt_agent'  
        AND object_id = OBJECT_ID('dbo.in_proc_transaction_activities')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_in_proc_transaction_activities_status_receipt_agent >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_in_proc_transaction_activities_status_receipt_agent >>>';
END
GO

-- Check if index 'IX_in_proc_transaction_activities_ticket_type_agent_trans_status' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_transaction_activities_ticket_type_agent_trans_status'  
        AND object_id = OBJECT_ID('dbo.in_proc_transaction_activities')
)
BEGIN
    DROP INDEX IX_in_proc_transaction_activities_ticket_type_agent_trans_status 
	ON dbo.in_proc_transaction_activities
    PRINT '<<< DROPPED INDEX dbo.IX_in_proc_transaction_activities_ticket_type_agent_trans_status >>>';
END
GO
/******************************************************************************
* Object: IX_in_proc_transaction_activities_ticket_type_agent_trans_status.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.in_proc_transaction_activities.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_in_proc_transaction_activities_ticket_type_agent_trans_status' if it does not already exist
CREATE NONCLUSTERED INDEX IX_in_proc_transaction_activities_ticket_type_agent_trans_status
    ON dbo.in_proc_transaction_activities (
        ticket_id,
        transaction_type_id,
        agent_confirmed_receipt,
        processed_trans_flag,
        transaction_status_id
    )
    INCLUDE (error_status_id)
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_in_proc_transaction_activities_ticket_type_agent_trans_status'  
        AND object_id = OBJECT_ID('dbo.in_proc_transaction_activities')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_in_proc_transaction_activities_ticket_type_agent_trans_status >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_in_proc_transaction_activities_ticket_type_agent_trans_status >>>';
END
GO

-- Check if index 'IX_tickets_created_date_game_draw_id' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_tickets_created_date_game_draw_id'  
        AND object_id = OBJECT_ID('dbo.tickets')
)
BEGIN
    DROP INDEX IX_tickets_created_date_game_draw_id 
	ON dbo.tickets
    PRINT '<<< DROPPED INDEX dbo.IX_tickets_created_date_game_draw_id >>>';
END
GO
/******************************************************************************
* Object: IX_tickets_created_date_game_draw_id.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.tickets.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_tickets_created_date_game_draw_id' if it does not already exist
CREATE NONCLUSTERED INDEX IX_tickets_created_date_game_draw_id
    ON dbo.tickets (
        date_created, 
        game_id, 
        draw_id
    )
    INCLUDE (customer_id)
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_tickets_created_date_game_draw_id'  
        AND object_id = OBJECT_ID('dbo.tickets')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_tickets_created_date_game_draw_id >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_tickets_created_date_game_draw_id >>>';
END
GO

-- Check if index 'IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus'  
        AND object_id = OBJECT_ID('dbo.tickets')
)
BEGIN
    DROP INDEX IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus 
	ON dbo.tickets
    PRINT '<<< DROPPED INDEX dbo.IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus >>>';
END
GO
/******************************************************************************
* Object: IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.tickets.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus' if it does not already exist
CREATE NONCLUSTERED INDEX IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus
    ON dbo.tickets (
       draw_date, 
       agnt_wnng_upload_status, 
       agnt_wnng_pymnt_status
    )
    INCLUDE (game_id, draw_id, customer_id)
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus'  
        AND object_id = OBJECT_ID('dbo.tickets')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_tickets_drawdt_agntwnngstatus_agntwnngpymntstatus >>>';
END
GO

-- Check if index 'IX_tickets_game_draw_wngstatus_betresulttype' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_tickets_game_draw_wngstatus_betresulttype'  
        AND object_id = OBJECT_ID('dbo.tickets')
)
BEGIN
    DROP INDEX IX_tickets_game_draw_wngstatus_betresulttype 
	ON dbo.tickets
    PRINT '<<< DROPPED INDEX dbo.IX_tickets_game_draw_wngstatus_betresulttype >>>';
END
GO
/******************************************************************************
* Object: IX_tickets_game_draw_wngstatus_betresulttype.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.tickets.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_tickets_game_draw_wngstatus_betresulttype' if it does not already exist
CREATE NONCLUSTERED INDEX IX_tickets_game_draw_wngstatus_betresulttype
    ON dbo.tickets (
        game_id, 
        draw_id, 
        agnt_wnng_upload_status, 
        bet_result_type_id
    )
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_tickets_game_draw_wngstatus_betresulttype'  
        AND object_id = OBJECT_ID('dbo.tickets')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_tickets_game_draw_wngstatus_betresulttype >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_tickets_game_draw_wngstatus_betresulttype >>>';
END
GO

-- Check if index 'IX_transaction_activities_status_agnt_conf_receipt_id' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_transaction_activities_status_agnt_conf_receipt_id'  
        AND object_id = OBJECT_ID('dbo.transaction_activities')
)
BEGIN
    DROP INDEX IX_transaction_activities_status_agnt_conf_receipt_id 
	ON dbo.transaction_activities
    PRINT '<<< DROPPED INDEX dbo.IX_transaction_activities_status_agnt_conf_receipt_id >>>';
END
GO
/******************************************************************************
* Object: IX_transaction_activities_status_agnt_conf_receipt_id.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.transaction_activities.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_transaction_activities_status_agnt_conf_receipt_id' if it does not already exist
CREATE NONCLUSTERED INDEX IX_transaction_activities_status_agnt_conf_receipt_id
    ON dbo.transaction_activities (
        transaction_status_id, 
        agent_confirmed_receipt, 
        agent_id
    )
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_transaction_activities_status_agnt_conf_receipt_id'  
        AND object_id = OBJECT_ID('dbo.transaction_activities')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_transaction_activities_status_agnt_conf_receipt_id >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_transaction_activities_status_agnt_conf_receipt_id >>>';
END
GO

-- Check if index 'IX_transaction_activities_tickt_type_agent' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_transaction_activities_tickt_type_agent'  
        AND object_id = OBJECT_ID('dbo.transaction_activities')
)
BEGIN
    DROP INDEX IX_transaction_activities_tickt_type_agent 
	ON dbo.transaction_activities
    PRINT '<<< DROPPED INDEX dbo.IX_transaction_activities_tickt_type_agent >>>';
END
GO
/******************************************************************************
* Object: IX_transaction_activities_tickt_type_agent.
* Type: Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.transaction_activities.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_transaction_activities_tickt_type_agent' if it does not already exist
CREATE NONCLUSTERED INDEX IX_transaction_activities_tickt_type_agent
    ON dbo.transaction_activities (
        ticket_id, 
        transaction_type_id, 
        agent_id
    )
    INCLUDE (transaction_status_id)
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_transaction_activities_tickt_type_agent'  
        AND object_id = OBJECT_ID('dbo.transaction_activities')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_transaction_activities_tickt_type_agent >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_transaction_activities_tickt_type_agent >>>';
END
GO

-- Check if index 'IX_win_header_data_gid_did_ps_sta_dd' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_win_header_data_gid_did_ps_sta_dd'  
        AND object_id = OBJECT_ID('dbo.winning_header_data')
)
BEGIN
    DROP INDEX IX_win_header_data_gid_did_ps_sta_dd 
	ON dbo.winning_header_data
    PRINT '<<< DROPPED INDEX dbo.IX_win_header_data_gid_did_ps_sta_dd >>>';
END
GO
/******************************************************************************
* Object:            IX_win_header_data_gid_did_ps_sta_dd.
* Type:              Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.winning_header_data.
*
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2358: Header Text Update.    
*******************************************************************************/
-- Create the index 'IX_win_header_data_gid_did_ps_sta_dd' if it does not already exist
CREATE NONCLUSTERED INDEX IX_win_header_data_gid_did_ps_sta_dd
    ON dbo.winning_header_data (
        game_id,
        draw_id,
        process_status,
        draw_date,
        file_version,
        send_to_all_agents
    )
    INCLUDE (bingo_report_generated);
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_win_header_data_gid_did_ps_sta_dd'  
        AND object_id = OBJECT_ID('dbo.winning_header_data')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_win_header_data_gid_did_ps_sta_dd >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_win_header_data_gid_did_ps_sta_dd >>>';
END
GO

-- Check if index 'IX_winning_upload_gid_did_ps_sta' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_winning_upload_gid_did_ps_sta'  
        AND object_id = OBJECT_ID('dbo.winning_upload_status')
)
BEGIN
    DROP INDEX IX_winning_upload_gid_did_ps_sta
    ON dbo.winning_upload_status
    PRINT '<<< DROPPED INDEX dbo.IX_winning_upload_gid_did_ps_sta >>>';
END
GO
/******************************************************************************
* Object:            IX_winning_upload_gid_did_ps_sta.
* Type:              Nonclustered Index.
* Description:       
* Impacted Table(s): dbo.winning_upload_status.
*  
* Update(s) History: 
*   PTR 2379 : DB optimization for PWS, PDRS, TDRS & TWS
*	PTR 2358 : Header Text Update.	
*****************************************************************************/
CREATE NONCLUSTERED INDEX IX_winning_upload_gid_did_ps_sta
    ON dbo.winning_upload_status (
        game_id, 
        draw_id, 
        agent_id, 
        upload_status
    )
-- Verify index creation and print appropriate status message
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_winning_upload_gid_did_ps_sta'  
        AND object_id = OBJECT_ID('dbo.winning_upload_status')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.IX_winning_upload_gid_did_ps_sta >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.IX_winning_upload_gid_did_ps_sta >>>';
END
GO

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'PK_win_header'  
        AND object_id = OBJECT_ID('dbo.winning_header_data')
)
BEGIN
    ALTER TABLE dbo.winning_header_data 
    DROP CONSTRAINT PK_win_header;
    PRINT '<<< DROPPED INDEX dbo.PK_win_header >>>';
END
GO
/******************************************************************************
* Object:            PK_win_header.
* Type:              Clustered Index.
* Description:       
* Impacted Table(s): dbo.winning_header_data.
*
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2358: Header Text Update.    
*******************************************************************************/
ALTER TABLE winning_header_data
    ADD CONSTRAINT PK_win_header PRIMARY KEY CLUSTERED 
    (
        game_id,
        draw_id,
	    draw_date,
        file_version
    )
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'PK_win_header'  
        AND object_id = OBJECT_ID('dbo.winning_header_data')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.PK_win_header >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.PK_win_header >>>';
END
GO

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'PK_win_upoad_status'  
        AND object_id = OBJECT_ID('dbo.winning_upload_status')
)
BEGIN
    ALTER TABLE dbo.winning_upload_status 
    DROP CONSTRAINT PK_win_upoad_status;
    PRINT '<<< DROPPED INDEX dbo.PK_win_upoad_status >>>';
END
GO
/******************************************************************************
* Object:            PK_win_upoad_status.
* Type:              Clustered Index.
* Description:       
* Impacted Table(s): dbo.winning_upload_status.
*
* Update(s) History: 
*   PTR 2379: DB optimization for PWS, PDRS, TDRS & TWS
*   PTR 2358: Header Text Update.    
*******************************************************************************/
ALTER TABLE winning_upload_status
    ADD CONSTRAINT PK_win_upoad_status PRIMARY KEY CLUSTERED 
    (
        game_id,
        draw_id,
        agent_id,
	    draw_date,
        file_version 
    )
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'PK_win_upoad_status'  
        AND object_id = OBJECT_ID('dbo.winning_upload_status')
)
BEGIN
    PRINT '<<< CREATED INDEX dbo.PK_win_upoad_status >>>';
END
ELSE
BEGIN
    PRINT '<<< FAILED CREATING INDEX dbo.PK_win_upoad_status >>>';
END
GO

-- Check if index 'idx_in_proc_tickets' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'idx_in_proc_tickets'  
        AND object_id = OBJECT_ID('dbo.in_proc_tickets')
)
BEGIN 
    DROP INDEX idx_in_proc_tickets on dbo.in_proc_tickets
    PRINT '<<< DROPPED INDEX dbo.idx_in_proc_tickets >>>'
END
GO

-- Check if index 'idx_tickets' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'idx_tickets'  
        AND object_id = OBJECT_ID('dbo.tickets')
)
BEGIN 
    DROP INDEX idx_tickets on dbo.tickets
    PRINT '<<< DROPPED INDEX dbo.idx_tickets >>>'
END
GO

-- Check if index 'idx_trans_activities' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'idx_trans_activities'  
        AND object_id = OBJECT_ID('dbo.in_proc_transaction_activities')
)
BEGIN 
    DROP INDEX idx_trans_activities on dbo.in_proc_transaction_activities
    PRINT '<<< DROPPED INDEX dbo.idx_trans_activities >>>'
END
GO

-- Check if index 'idx_trans_activities' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'idx_trans_activities'  
        AND object_id = OBJECT_ID('dbo.transaction_activities')
)
BEGIN 
    DROP INDEX idx_trans_activities on dbo.transaction_activities
    PRINT '<<< DROPPED INDEX dbo.transaction_activities >>>'
END
GO

-- Check if index 'idx_trans_activities_ticid' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'idx_trans_activities_ticid'  
        AND object_id = OBJECT_ID('dbo.in_proc_transaction_activities')
)
BEGIN 
    DROP INDEX idx_trans_activities_ticid on dbo.in_proc_transaction_activities
    PRINT '<<< DROPPED INDEX dbo.idx_trans_activities_ticid >>>'
END
GO

-- Check if index 'idx_trans_activities_ticid' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'idx_trans_activities_ticid'  
        AND object_id = OBJECT_ID('dbo.transaction_activities')
)
BEGIN 
    DROP INDEX idx_trans_activities_ticid on dbo.transaction_activities
    PRINT '<<< DROPPED INDEX dbo.transaction_activities >>>'
END
GO

-- Check if index 'idx_in_proc_tickets' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'idx_trans_actv_ttid_tid'  
        AND object_id = OBJECT_ID('dbo.transaction_activities')
)
BEGIN 
    DROP INDEX idx_trans_actv_ttid_tid on dbo.transaction_activities
    PRINT '<<< DROPPED INDEX dbo.idx_trans_actv_ttid_tid >>>'
END
GO

-- Check if index 'nci_tickets_vtid1' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'nci_tickets_vtid1'  
        AND object_id = OBJECT_ID('dbo.tickets')
)
BEGIN 
    DROP INDEX nci_tickets_vtid1 on dbo.tickets
    PRINT '<<< DROPPED INDEX dbo.nci_tickets_vtid1 >>>'
END
GO

-- Check if index 'trans_ticket_actv_type_index' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'trans_ticket_actv_type_index'  
        AND object_id = OBJECT_ID('dbo.in_proc_transaction_activities')
)
BEGIN 
    DROP INDEX trans_ticket_actv_type_index on dbo.in_proc_transaction_activities
    PRINT '<<< DROPPED INDEX dbo.trans_ticket_actv_type_index >>>'
END
GO

-- Check if index 'trans_ticket_actv_type_index' exists and drop it if found
IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'trans_ticket_actv_type_index'  
        AND object_id = OBJECT_ID('dbo.transaction_activities')
)
BEGIN 
    DROP INDEX trans_ticket_actv_type_index on dbo.transaction_activities
    PRINT '<<< DROPPED INDEX dbo.trans_ticket_actv_type_index >>>'
END
GO

