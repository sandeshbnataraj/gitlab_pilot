
/***************************************************/
/**          3_datatrak_functions_scripts.sql             **/
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

IF OBJECT_ID('dbo.f_get_lotto535_in_proc_panel_data') IS NOT NULL
BEGIN 
    DROP FUNCTION dbo.f_get_lotto535_in_proc_panel_data;
    IF OBJECT_ID('dbo.f_get_lotto535_in_proc_panel_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING FUNCTION dbo.f_get_lotto535_in_proc_panel_data >>>';
    ELSE
        PRINT '<<< DROPPED FUNCTION dbo.f_get_lotto535_in_proc_panel_data >>>';
END;
GO
/****************************************************************************** 
* Object: f_get_lotto535_in_proc_panel_data. 
* Type: Function. 
* Caller(s): AMA. 
* Description: Returns panel data for Lotto 5/35 based on ticket_id.
* Impacted Table(s): in_proc_coresys_update_panels_lotto535. 
*                    in_proc_panels_lotto535. 
*  
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
*****************************************************************************/
CREATE FUNCTION [dbo].[f_get_lotto535_in_proc_panel_data]
(
    @ticketId VARCHAR(33) -- Required parameter
)
RETURNS TABLE
AS
RETURN
(
    SELECT panel_id,
		ticket_id,
		selected_numbers,
		selected_bonus_numbers,
		cost,
		quick_pick,
		summary,
		panel_number,
		date_modified
    FROM in_proc_coresys_update_panels_lotto535 WITH(NOLOCK)
    WHERE ticket_id = @ticketId

    UNION ALL

    SELECT panel_id,
		ticket_id,
		selected_numbers,
		selected_bonus_numbers,
		cost,
		quick_pick,
		'' AS 'summary',
		panel_number,
		date_modified
    FROM in_proc_panels_lotto535 WITH(NOLOCK)
    WHERE ticket_id = @ticketId 
      AND NOT EXISTS (
          SELECT 1 FROM in_proc_coresys_update_panels_lotto535 WITH(NOLOCK)
          WHERE ticket_id = @ticketId
      )
);
GO
IF OBJECT_ID('dbo.f_get_lotto535_in_proc_panel_data') IS NOT NULL
    PRINT '<<< CREATED FUNCTION dbo.f_get_lotto535_in_proc_panel_data >>>';
ELSE
    PRINT '<<< FAILED CREATING FUNCTION dbo.f_get_lotto535_in_proc_panel_data >>>';
GO

IF OBJECT_ID('dbo.f_get_lotto535_panel_data') IS NOT NULL
BEGIN 
    DROP FUNCTION dbo.f_get_lotto535_panel_data;
    IF OBJECT_ID('dbo.f_get_lotto535_panel_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING FUNCTION dbo.f_get_lotto535_panel_data >>>';
    ELSE
        PRINT '<<< DROPPED FUNCTION dbo.f_get_lotto535_panel_data >>>';
END;
GO
/****************************************************************************** 
* Object: f_get_lotto535_panel_data. 
* Type: Function. 
* Caller(s): AMA. 
* Description: Returns panel data for Lotto 5/35 based on ticket_id.
* Impacted Table(s): coresys_update_panels_lotto535, panels_lotto535. 
*  
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
*****************************************************************************/
CREATE FUNCTION [dbo].[f_get_lotto535_panel_data]
(
    @ticketId VARCHAR(33) -- Required parameter
)
RETURNS TABLE
AS
RETURN
(
    SELECT panel_id,
		ticket_id,
		selected_numbers,
		selected_bonus_numbers,
		cost,
		quick_pick,
		summary,
		panel_number,
		date_modified
    FROM coresys_update_panels_lotto535 WITH(NOLOCK)
    WHERE ticket_id = @ticketId

    UNION ALL

    SELECT panel_id,
		ticket_id,
		selected_numbers,
		selected_bonus_numbers,
		cost,
		quick_pick,
		'' AS 'summary',
		panel_number,
		date_modified
    FROM panels_lotto535 WITH(NOLOCK)
    WHERE ticket_id = @ticketId 
      AND NOT EXISTS (
          SELECT 1 FROM coresys_update_panels_lotto535 WITH(NOLOCK)
          WHERE ticket_id = @ticketId
      )
);
GO
IF OBJECT_ID('dbo.f_get_lotto535_panel_data') IS NOT NULL
    PRINT '<<< CREATED FUNCTION dbo.f_get_lotto535_panel_data >>>';
ELSE
    PRINT '<<< FAILED CREATING FUNCTION dbo.f_get_lotto535_panel_data >>>';
GO

IF OBJECT_ID('dbo.f_oss_confirmed_tickets') IS NOT NULL
BEGIN 
    DROP FUNCTION dbo.f_oss_confirmed_tickets;
    IF OBJECT_ID('dbo.f_oss_confirmed_tickets') IS NOT NULL
        PRINT '<<< FAILED DROPPING FUNCTION dbo.f_oss_confirmed_tickets >>>';
    ELSE
        PRINT '<<< DROPPED FUNCTION dbo.f_oss_confirmed_tickets >>>';
END;
GO
/****************************************************************************** 
* Object: f_oss_confirmed_tickets. 
* Type: Function. 
* Caller(s): Transfer Ticket Data Service (TTDS) 
* Description: The procedure "p_get_oss_confirmed_tickets" invoked by TTDS retrieves 
              'Completed/Error' sell and pay transactions by calling this function. 
* Impacted Table(s): in_proc_tickets. 
                     in_proc_transaction_activities. 
                     agents.
*  
* Update(s) History: 
* PTR 2383 : DB: New Game Lotto 5/35 Development 
*****************************************************************************/
CREATE FUNCTION [dbo].[f_oss_confirmed_tickets]
(
    @nRecordsRetrieved INT,
    @agent_confirmed_receipt INT,
    @agent_host_name VARCHAR(255)
)
RETURNS TABLE
AS
RETURN
(
    WITH base_completed_sell_pay AS
    (
        SELECT 
            ta.transaction_activity_id,
            t.ticket_id,
            ta.agent_id,
            ta.transaction_type_id,
            t.customer_id,
            t.game_id,
            t.sub_game_id,
            ta.transaction_status_id,
            t.vtid1,
            ta.oss_processed_date,
            t.draw_date,
            t.draw_id,
            ta.oss_updated_cost,
            ta.oss_agent_account_bal,
            e.error_status_description,
            t.system_number
        FROM in_proc_transaction_activities ta WITH (NOLOCK)
            INNER JOIN in_proc_tickets t WITH (NOLOCK)
                ON ta.ticket_id = t.ticket_id
            INNER JOIN agents a WITH (NOLOCK) 
                ON a.agent_id = ta.agent_id
                AND a.agent_host_name = @agent_host_name
            LEFT JOIN error_status e WITH (NOLOCK)
                ON e.error_status_id = ta.error_status_id
        WHERE ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f' --sell
                AND ta.agent_confirmed_receipt = @agent_confirmed_receipt
                AND ta.processed_trans_flag = 0
                AND ta.transaction_status_id IN ('45318a66-0ff0-11e7-9454-b083feaf6ace', '6a56bdfb-0ff0-11e7-9454-b083feaf6ace') -- Completed, Error

        UNION ALL
        
        SELECT 
            ta.transaction_activity_id,
            t.ticket_id,
            ta.agent_id,
            ta.transaction_type_id,
            t.customer_id,
            t.game_id,
            t.sub_game_id,
            ta.transaction_status_id,
            t.vtid1,
            ta.oss_processed_date,
            t.draw_date,
            t.draw_id,
            ta.oss_updated_cost,
            ta.oss_agent_account_bal,
            e.error_status_description,
            t.system_number
        FROM in_proc_transaction_activities ta WITH (NOLOCK)
            INNER JOIN  in_proc_tickets t WITH (NOLOCK)
                ON t.ticket_id = ta.ticket_id
                AND t.agnt_wnng_pymnt_status IN ('9996c3ca-7b38-4b7c-97f6-4c9755a3ff96','077fcc2a-724d-4d7f-990f-61b497773dd8')      
            INNER JOIN agents a WITH (NOLOCK) 
                ON a.agent_id = ta.agent_id
                AND a.agent_host_name = @agent_host_name
            INNER JOIN error_status e WITH (NOLOCK)
                ON e.error_status_id = ta.error_status_id
        WHERE ta.transaction_type_id = '966ead14-255c-4de4-b67d-28bd452582ea' --pay
                AND ta.agent_confirmed_receipt = @agent_confirmed_receipt
                AND ta.processed_trans_flag = 0
    )

    SELECT TOP (@nRecordsRetrieved) 
        transaction_activity_id,
        ticket_id,
        agent_id,
        transaction_type_id,
        --ticket details
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
    FROM base_completed_sell_pay
);
GO
IF OBJECT_ID('dbo.f_oss_confirmed_tickets') IS NOT NULL
    PRINT '<<< CREATED FUNCTION dbo.f_oss_confirmed_tickets >>>';
ELSE
    PRINT '<<< FAILED CREATING FUNCTION dbo.f_oss_confirmed_tickets >>>';
GO

IF OBJECT_ID('dbo.f_get_pending_trans_activities') IS NOT NULL
BEGIN 
    DROP FUNCTION dbo.f_get_pending_trans_activities;
    IF OBJECT_ID('dbo.f_get_pending_trans_activities') IS NOT NULL
        PRINT '<<< FAILED DROPPING FUNCTION dbo.f_get_pending_trans_activities >>>';
    ELSE
        PRINT '<<< DROPPED FUNCTION dbo.f_get_pending_trans_activities >>>';
END;
GO
/******************************************************************************
* Object: f_get_pending_trans_activities.
* Type: Function.
* Caller(s): DataTrakTransService (DTTS)
* Description: The procedure "p_get_pending_trans_activities" invoked by DTTS retrieves 
              'Not processed' sell and pay transactions by calling this function.	
* Impacted Table(s): in_proc_tickets.
                     in_proc_transaction_activities.
                     transaction_types.
                     customers.
*  
* Update(s) History: 
* PTR 2383 : DB: New Game Lotto 5/35 Development 	
*****************************************************************************/
CREATE FUNCTION [dbo].[f_get_pending_trans_activities]
(
    @nRecordsRetrieved INT
)
RETURNS TABLE
AS
RETURN
(
    WITH base_nt_processed_sell_pay AS
    (
        SELECT TOP (@nRecordsRetrieved) 
            ta.transaction_activity_id, 
            ta.transaction_type_id, 
            ta.transaction_status_id, 
            ta.agent_id,
            tck.ticket_id, 
            tck.msn, 
            tck.customer_id, 
            co.reg_region, 
            tck.vtid2, 
            tck.vtid1,
            tck.cost AS 'amount', 
            ta.transaction_date
        FROM in_proc_tickets tck WITH (NOLOCK)
            INNER JOIN in_proc_transaction_activities ta WITH (NOLOCK) 
                ON ta.ticket_id = tck.ticket_id
                AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f' --sell
                AND ta.agent_confirmed_receipt = 0
                AND ta.transaction_status_id = '0ab02c66-0fef-11e7-9454-b083feaf6ace' -- Not_Processed
            INNER JOIN transaction_types tt WITH (NOLOCK)
                ON tt.transaction_type_id = ta.transaction_type_id
            INNER JOIN customers co WITH (NOLOCK) 
                ON co.customer_id = tck.customer_id
        WHERE tck.panel_count > 0   
            AND tck.tsn IS NULL
        ORDER BY ta.transaction_date ASC

        UNION ALL
        
        SELECT TOP (@nRecordsRetrieved) 
            ta.transaction_activity_id, 
            ta.transaction_type_id, 
            ta.transaction_status_id, 
            ta.agent_id,
            tck.ticket_id, 
            tck.msn, 
            tck.customer_id, 
            co.reg_region, 
            tck.vtid2, 
            tck.vtid1,
            tck.cost AS 'amount', 
            ta.transaction_date
        FROM in_proc_tickets tck WITH (NOLOCK)
            INNER JOIN in_proc_transaction_activities ta WITH (NOLOCK) 
                ON ta.ticket_id = tck.ticket_id
                AND ta.transaction_type_id = '966ead14-255c-4de4-b67d-28bd452582ea' --pay
                AND ta.agent_confirmed_receipt = 0
                AND ta.transaction_status_id = '0ab02c66-0fef-11e7-9454-b083feaf6ace' -- Not_Processed
                AND ta.error_status_id IS NULL
            INNER JOIN transaction_types tt WITH (NOLOCK)
                ON tt.transaction_type_id = ta.transaction_type_id
            INNER JOIN customers co WITH (NOLOCK) 
                ON co.customer_id = tck.customer_id
        WHERE tck.panel_count > 0   
            AND (tck.agnt_wnng_pymnt_status IS NULL OR tck.agnt_wnng_pymnt_status = 'aa0cfb5c-2902-414e-897a-dc376371ccf8')
        ORDER BY ta.transaction_date ASC
    )
    SELECT 
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
    FROM base_nt_processed_sell_pay
    --ORDER BY transaction_date ASC
);
GO
IF OBJECT_ID('dbo.f_get_pending_trans_activities') IS NOT NULL
    PRINT '<<< CREATED FUNCTION dbo.f_get_pending_trans_activities >>>';
ELSE
    PRINT '<<< FAILED CREATING FUNCTION dbo.f_get_pending_trans_activities >>>';
GO

