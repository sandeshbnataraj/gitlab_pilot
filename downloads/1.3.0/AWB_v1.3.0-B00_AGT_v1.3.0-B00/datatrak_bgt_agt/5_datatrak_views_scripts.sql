
/***************************************************/
/**          5_datatrak_views_scripts.sql             **/
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

IF OBJECT_ID('dbo.v_aw203') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_aw203;
    IF OBJECT_ID('dbo.v_aw203') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_aw203 >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_aw203 >>>';
END;
GO
/******************************************************************************
* Object: v_aw203
* Type: View
* Callers: AMA.
* Description: To retrieve all winning tickets.
* Impacted Table(s): winning_header_data.
*                   transaction_activities.
*                   tickets.
*                   coresys_winning_payments.
*                   games.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.   
*****************************************************************************/
CREATE VIEW [dbo].[v_aw203]
AS 
    SELECT ta.agent_id AS 'agentid',
        g.game_name AS 'gamename',
        wh.draw_id AS 'drawid',
        wh.draw_date AS 'drawdate',
	    COUNT(t.ticket_id) AS 'ticketcount',
        IIF(SUM(ta.oss_updated_cost) IS NULL,
        0,
        SUM(ta.oss_updated_cost)) AS 'salesamount',
	    0 AS 'paycount', 
        0 AS 'payamount',
        wh.date_modified AS datecreated
    FROM winning_header_data wh WITH(NOLOCK)
		LEFT JOIN tickets t WITH(NOLOCK) 
            ON t.game_id = wh.game_id  
            AND t.draw_id = wh.draw_id
		INNER JOIN games g WITH(NOLOCK) 
            ON g.game_id = wh.game_id
		LEFT JOIN transaction_activities ta WITH(NOLOCK) 
            ON ta.ticket_id = t.ticket_id 
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f'
            AND ta.transaction_status_id = '6a56bdfb-0ff0-11e7-9454-b083feaf6ace'        
    GROUP BY g.game_name, wh.draw_id, wh.draw_date, ta.agent_id, wh.date_modified

    UNION ALL

    SELECT ta.agent_id AS 'agentid', 
        g.game_name AS 'gamename', 
        t.draw_id AS 'drawid', 
        t.draw_date AS 'drawdate',
        0 AS 'ticketcount',
        0 AS 'salesamount',
        COUNT(cw.ticket_id) AS 'paycount', 
        IIF(SUM(cw.oss_payment_amount) IS NULL,
        0,
        SUM(cw.oss_payment_amount)) AS 'payamount',
        cw.oss_processed_date AS datecreated
    FROM winning_header_data wh WITH(NOLOCK)
		LEFT JOIN tickets t WITH(NOLOCK) 
             ON t.game_id = wh.game_id  
            AND t.draw_id = wh.draw_id
		INNER JOIN games g WITH(NOLOCK) 
            ON g.game_id = wh.game_id
		LEFT JOIN transaction_activities ta WITH(NOLOCK) 
            ON ta.ticket_id = t.ticket_id 
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f'
		    AND ta.transaction_status_id = '6a56bdfb-0ff0-11e7-9454-b083feaf6ace'
        LEFT JOIN coresys_winning_payments cw WITH(NOLOCK) 
            ON cw.ticket_id = t.ticket_id
    GROUP BY g.game_name, t.draw_id, t.draw_date, ta.agent_id, cw.oss_processed_date;
GO
IF OBJECT_ID('dbo.v_aw203') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_aw203 >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_aw203 >>>';
GO


IF OBJECT_ID('dbo.v_aw402') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_aw402;
    IF OBJECT_ID('dbo.v_aw402') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_aw402 >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_aw402 >>>';
END;
GO
/******************************************************************************
* Object: v_aw402
* Type: View
* Callers: AMA.
* Description: Report AW402.
* Impacted Table(s): tickets.
*                   transaction_activities.
*                   coresys_winning_payments.
*                   games.
*                   bet_result_types.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.   
*****************************************************************************/
CREATE VIEW [dbo].[v_aw402] 
AS 
    SELECT ta.agent_id,
        t.date_modified,
        t.customer_id,
        g.game_name,
        t.draw_id,
        t.draw_date,
        cw.oss_winning_amount,
        cw.oss_winning_tax,
        cw.oss_payment_amount,
        b.bet_result_desc,
        t.game_id,
        cw.ticket_id
    FROM coresys_winning_payments cw WITH (NOLOCK)
        INNER JOIN tickets t WITH (NOLOCK)
            ON cw.ticket_id = t.ticket_id
        INNER JOIN transaction_activities ta 
            ON ta.ticket_id = t.ticket_id
        INNER JOIN games g 
            ON g.game_id = t.game_id
        INNER JOIN bet_result_types b 
            ON b.bet_result_type_id = t.bet_result_type_id;
GO
IF OBJECT_ID('dbo.v_aw402') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_aw402 >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_aw402 >>>';
GO


IF OBJECT_ID('dbo.v_aw403') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_aw403;
    IF OBJECT_ID('dbo.v_aw403') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_aw403 >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_aw403 >>>';
END;
GO
/******************************************************************************
* Object: v_aw403
* Type: View
* Callers: AMA.
* Description: Report AW403.
* Impacted Table(s): tickets.
*                   transaction_activities.
*                   coresys_winning_payments.
*                   games.
*                   bet_result_types.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.   
*****************************************************************************/
CREATE VIEW [dbo].[v_aw403]
AS
    -- Only for Bingo18 (105)
    SELECT ta.agent_id,
        t.date_modified,
        t.customer_id,
        g.game_name,
        t.draw_id,
        cw.oss_winning_amount,
        cw.oss_winning_tax,
        cw.oss_payment_amount,
        b.bet_result_desc,
        t.game_id,
        cw.ticket_id
    FROM coresys_winning_payments cw WITH (NOLOCK)
        INNER JOIN tickets t WITH (NOLOCK)
            ON cw.ticket_id = t.ticket_id
        INNER JOIN transaction_activities ta WITH (NOLOCK)
            ON ta.ticket_id = t.ticket_id
        INNER JOIN games g 
            ON g.game_id = 105
        INNER JOIN bet_result_types b 
            ON b.bet_result_type_id = t.bet_result_type_id;
GO
IF OBJECT_ID('dbo.v_aw403') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_aw403 >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_aw403 >>>';
GO


IF OBJECT_ID('dbo.v_aw404') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_aw404;
    IF OBJECT_ID('dbo.v_aw404') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_aw404 >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_aw404 >>>';
END;
GO
/******************************************************************************
* Object: v_aw404
* Type: View
* Callers: AMA.
* Description: Report AW404.
* Impacted Table(s): tickets.
*                   transaction_activities.
*                   coresys_winning_payments.
*                   games.
*                   bet_result_types.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.   
*****************************************************************************/
CREATE VIEW [dbo].[v_aw404]
AS
    -- Only for Lotto535 (106)
    SELECT ta.agent_id,
        t.date_modified,
        t.customer_id,
        g.game_name,
        t.draw_id,
        cw.oss_winning_amount,
        cw.oss_winning_tax,
        cw.oss_payment_amount,
        b.bet_result_desc,
        t.game_id,
        cw.ticket_id
    FROM coresys_winning_payments cw WITH (NOLOCK)
        INNER JOIN tickets t WITH (NOLOCK)
            ON cw.ticket_id = t.ticket_id
        INNER JOIN transaction_activities ta WITH (NOLOCK)
            ON ta.ticket_id = t.ticket_id
        INNER JOIN games g 
            ON g.game_id = 106
        INNER JOIN bet_result_types b 
            ON b.bet_result_type_id = t.bet_result_type_id;
GO
IF OBJECT_ID('dbo.v_aw404') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_aw404 >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_aw404 >>>';
GO


IF OBJECT_ID('dbo.v_completed_butin_processing_data') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_completed_butin_processing_data;
    IF OBJECT_ID('dbo.v_completed_butin_processing_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_completed_butin_processing_data >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_completed_butin_processing_data >>>';
END;
GO
/******************************************************************************
* Object: v_completed_butin_processing_data
* Type: View
* Callers: DTTS.
* Description: Retrieve completed but in processing sell tickets.
* Impacted Table(s): tickets.
*                   transaction_activities.
*                   coresys_winning_payments.
*                   games.
*                   bet_result_types.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2358: Header Text Update.   
*****************************************************************************/
CREATE VIEW [dbo].[v_completed_butin_processing_data]
AS 
    SELECT TOP 100 PERCENT 
        ta.transaction_activity_id, 
        ta.ticket_id, 
        ta.transaction_type_id,
        tck.tsn, 
        ta.error_status_id, 
        tck.customer_id, 
        tck.system_number,
        tss.transaction_status_name, 
        tt.transaction_type_name, 
        tck.hwid,
        gm.game_name, 
        ta.oss_processed_date, 
        ta.transaction_date, 
        tck.panel_count, 
        tck.msn, 
        ta.transaction_status_id, 
        co.reg_region
    FROM in_proc_tickets tck
        INNER JOIN in_proc_transaction_activities ta
            ON tck.ticket_id = ta.ticket_id
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f' --sell
            AND ta.transaction_status_id = 'ed1bc7ec-0fef-11e7-9454-b083feaf6ace' --completed
            AND ta.oss_processed_date IS NOT NULL
        LEFT JOIN transaction_statuses tss 
            ON tss.transaction_status_id = ta.transaction_status_id
        LEFT JOIN transaction_types tt 
            ON tt.transaction_type_id = ta.transaction_type_id
        INNER JOIN games gm 
            ON tck.game_id = gm.game_id
        INNER JOIN customers co 
            ON co.customer_id = tck.customer_id
    --ORDER BY transaction_date
GO
IF OBJECT_ID('dbo.v_completed_butin_processing_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_completed_butin_processing_data >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_completed_butin_processing_data >>>';
GO


IF OBJECT_ID('dbo.v_in_proc_trans_history') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_in_proc_trans_history
    IF OBJECT_ID('dbo.v_in_proc_trans_history') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_in_proc_trans_history >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_in_proc_trans_history >>>'
END
GO
/******************************************************************************
* Object: v_in_proc_trans_history
* Type: View
* Callers: AMA.
* Description: To retrieve all ticket data.
* Impacted Table(s): tickets.
*                   transaction_activities.
*                   transaction_statuses. 
*                   error_status.
*                   games.
*                   in_proc_panels.
*                   in_proc_panels_3d.
*                   in_proc_panels_bingo.
*                   in_proc_panels_lotto535.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.  
* PTR 2237:
*****************************************************************************/
CREATE VIEW [dbo].[v_in_proc_trans_history]
AS 
    select tck.ticket_id, 
        tck.customer_id, /*tck.vtid2,*/ 
        ts.transaction_status_name, /*tck.bet_result_type_id, tck.header_summary, tck.footer_summary,*/
        ta.agent_confirmed_receipt as 'agent_transfer_status',
           /*tck.cost as 'estimated_cost',*/ 
        tck.game_id, 
        g.game_name, 
        tck.sub_game_id, 
        tck.system_number, 
        tck.draw_date, 
        tck.date_created as 'created_date',
        ta.oss_processed_date as 'oss_processed_date', 
        ta.oss_agent_account_bal,
        es.error_status_description, 
        ta.oss_updated_cost as 'actual_cost', 
        ta.agent_id, 
        tck.date_modified, 
        tck.draw_id, 
        tck.vtid1,
        ta.transaction_status_id
    FROM in_proc_tickets tck WITH (NOLOCK) 
        INNER JOIN in_proc_transaction_activities ta WITH (NOLOCK) 
            ON ta.ticket_id = tck.ticket_id 
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f'
        LEFT JOIN transaction_statuses ts WITH (NOLOCK)
            ON ta.transaction_status_id = ts .transaction_status_id 
        LEFT JOIN error_status es WITH (NOLOCK)
            ON ta.error_status_id = es.error_status_id 
        INNER JOIN games g WITH (NOLOCK)
            ON tck.game_id = g.game_id
GO
IF OBJECT_ID('dbo.v_in_proc_trans_history') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_in_proc_trans_history >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_in_proc_trans_history >>>'
GO



IF OBJECT_ID('dbo.v_in_proc_trans_history_with_panel_data') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_in_proc_trans_history_with_panel_data;
    IF OBJECT_ID('dbo.v_in_proc_trans_history_with_panel_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_in_proc_trans_history_with_panel_data >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_in_proc_trans_history_with_panel_data >>>';
END;
GO
/******************************************************************************
* Object: v_in_proc_trans_history_with_panel_data
* Type: View
* Callers: AMA.
* Description: To retrieve all ticket data with panel data.
* Impacted Table(s): tickets.
*                   transaction_activities.
*                   transaction_statuses. 
*                   error_status.
*                   games.
*                   in_proc_panels.
*                   in_proc_panels_3d.
*                   in_proc_panels_bingo.
*                   in_proc_panels_lotto535.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.  
* PTR 2237:
*****************************************************************************/
CREATE VIEW [dbo].[v_in_proc_trans_history_with_panel_data]
AS 
    SELECT tck.ticket_id,
        tck.customer_id, /*tck.vtid2,*/ 
        ts.transaction_status_name,/*tck.bet_result_type_id,tck.header_summary,tck.footer_summary,*/ 
        ta.agent_confirmed_receipt AS 'agent_transfer_status',
           /*tck.cost AS 'estimated_cost',*/ 
        tck.game_id, 
        g.game_name, 
        tck.sub_game_id, 
        tck.system_number, 
        tck.draw_date, 
        tck.date_created AS 'created_date',
        ta.oss_processed_date AS 'oss_processed_date', 
        ta.oss_agent_account_bal,
        es.error_status_description, 
        ta.oss_updated_cost AS 'actual_cost', 
        ta.agent_id, 
        tck.date_modified, 
        tck.draw_id, 
        tck.vtid1,
        ta.transaction_status_id,
        CASE 
            WHEN tck.game_id IN (100, 101) THEN panel_data_lotto.panel_data
            WHEN tck.game_id IN (102, 103) THEN panel_data_3d.panel_data
            WHEN tck.game_id = 105 THEN panel_data_bingo.panel_data
            WHEN tck.game_id = 106 THEN panel_data_lotto535.panel_data
            ELSE NULL
        END AS 'panel_data'
    FROM in_proc_tickets tck WITH (NOLOCK) 
        INNER JOIN in_proc_transaction_activities ta WITH (NOLOCK) 
            ON ta.ticket_id = tck.ticket_id
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f'
        INNER JOIN transaction_statuses ts 
            ON ta.transaction_status_id = ts.transaction_status_id
        LEFT JOIN error_status es  
            ON ta.error_status_id = es.error_status_id
        INNER JOIN games g 
            ON tck.game_id = g.game_id
        LEFT JOIN (
            SELECT ticket_id, 
                STRING_AGG(selected_numbers + '|' + CAST(panel_number AS VARCHAR), ';') AS panel_data
            FROM in_proc_panels WITH (NOLOCK)
            GROUP BY ticket_id
        ) panel_data_lotto
            ON tck.ticket_id = panel_data_lotto.ticket_id
        LEFT JOIN (
            SELECT ticket_id, 
                STRING_AGG(selected_numbers + '|' + CAST(panel_number AS VARCHAR), ';') AS panel_data
            FROM in_proc_panels_3d WITH (NOLOCK)
            GROUP BY ticket_id
        ) panel_data_3d
            ON tck.ticket_id = panel_data_3d.ticket_id
        LEFT JOIN (
            SELECT ticket_id, 
                STRING_AGG(CAST(play_type AS VARCHAR) + '|' + CAST(panel_number AS VARCHAR), ';') AS panel_data
            FROM in_proc_panels_bingo WITH (NOLOCK)
            GROUP BY ticket_id
        ) panel_data_bingo
            ON tck.ticket_id = panel_data_bingo.ticket_id
        LEFT JOIN (
            SELECT ticket_id, 
                STRING_AGG(selected_numbers  + ':' + selected_bonus_numbers +'|' + CAST(panel_number AS VARCHAR), ';') AS panel_data
            FROM in_proc_panels_lotto535 WITH (NOLOCK)
            GROUP BY ticket_id
        ) panel_data_lotto535
            ON tck.ticket_id = panel_data_lotto535.ticket_id;
GO
IF OBJECT_ID('dbo.v_in_proc_trans_history_with_panel_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_in_proc_trans_history_with_panel_data >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_in_proc_trans_history_with_panel_data >>>';
GO















IF OBJECT_ID('dbo.v_retransmit_trans_activities') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_retransmit_trans_activities;
    IF OBJECT_ID('dbo.v_retransmit_trans_activities') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_retransmit_trans_activities >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_retransmit_trans_activities >>>';
END;
GO
/******************************************************************************
* Object: v_retransmit_trans_activities
* Type: View
* Callers: AMA.
* Description: To retrieve all ticket data with panel data.
* Impacted Table(s): in_proc_tickets.
*                   in_proc_transaction_activities.
*                   transaction_types.
*                   customers.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2358: Header Text Update.  
* PTR 2220: 
* PTR 2266:
*****************************************************************************/
CREATE VIEW [dbo].[v_retransmit_trans_activities]
AS 
    SELECT ta.transaction_activity_id, 
       ta.transaction_type_id, 
       ta.transaction_status_id,
       tck.ticket_id, 
       tck.hwid, 
       tck.msn, 
       tck.customer_id, 
       co.reg_region, 
       tck.vtid2, 
       tck.vtid1,
       tck.cost as 'amount', 
       tck.game_id, 
       tck.system_number, 
       tck.draw_date, 
       ta.transaction_date,
       tt.transaction_type_name
    FROM in_proc_tickets tck WITH (NOLOCK)
        INNER JOIN in_proc_transaction_activities ta WITH (NOLOCK) 
              ON ta.ticket_id = tck.ticket_id
              AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f' --sell
              AND ta.agent_confirmed_receipt <> 1
              AND ta.transaction_status_id IN ('0ab02c66-0fef-11e7-9454-b083feaf6ace','ed1bc7ec-0fef-11e7-9454-b083feaf6ace') -- Not processed; Processing
        LEFT JOIN transaction_types tt 
              ON tt.transaction_type_id = ta.transaction_type_id
        INNER JOIN customers co 
              ON co.customer_id = tck.customer_id
    WHERE tck.hwid IS NOT NULL 
       AND tck.msn IS NOT NULL

    UNION ALL

    SELECT ta.transaction_activity_id, 
       ta.transaction_type_id, 
       ta.transaction_status_id,
       tck.ticket_id, 
       tck.hwid, 
       tck.msn, 
       tck.customer_id, 
       co.reg_region, 
       tck.vtid2, 
       tck.vtid1,
       '0' as 'amount', 
       tck.game_id, 
       tck.system_number, 
       tck.draw_date, 
       ta.transaction_date,
       tt.transaction_type_name
    FROM in_proc_tickets tck WITH (NOLOCK)
       INNER JOIN in_proc_transaction_activities ta WITH (NOLOCK) 
              ON ta.ticket_id = tck.ticket_id
              AND ta.transaction_type_id = '966ead14-255c-4de4-b67d-28bd452582ea' --pay
              AND ta.transaction_status_id IN ('0ab02c66-0fef-11e7-9454-b083feaf6ace','ed1bc7ec-0fef-11e7-9454-b083feaf6ace') 
       LEFT JOIN transaction_types tt 
              ON tt.transaction_type_id = ta.transaction_type_id
       INNER JOIN customers co 
              ON co.customer_id = tck.customer_id
    WHERE tck.tsn IS NULL 
       and ta.oss_processed_date IS NULL 
       AND tck.msn IS NOT NULL
GO
IF OBJECT_ID('dbo.v_retransmit_trans_activities') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_retransmit_trans_activities >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_retransmit_trans_activities >>>';
GO



IF OBJECT_ID('dbo.v_send_winnings_to_agent') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_send_winnings_to_agent;
    IF OBJECT_ID('dbo.v_send_winnings_to_agent') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_send_winnings_to_agent >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_send_winnings_to_agent >>>';
END;
GO
/******************************************************************************
* Object: v_send_winnings_to_agent
* Type: View
* Callers: Transafer Draw Results Service(TDRS).
* Description: To retrieve all ticket data with panel data.
* Impacted Table(s): winning_header_data.
*                   send_winnings_to_agent.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2358: Header Text Update. 
*****************************************************************************/
CREATE VIEW [dbo].[v_send_winnings_to_agent]
AS 
    SELECT  t.game_id,
        t.draw_id,
        t.draw_date,
        t.winning_numbers,
        sa.agent_id,
        t.file_version
    FROM  winning_header_data t WITH (NOLOCK)
        LEFT JOIN send_winnings_to_agent sa WITH (NOLOCK) 
            ON t.game_id IN (105,106)  
            AND sa.draw_id = t.draw_id
            AND sa.file_version = t.file_version;
GO
IF OBJECT_ID('dbo.v_send_winnings_to_agent') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_send_winnings_to_agent >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_send_winnings_to_agent >>>';
GO


IF OBJECT_ID('dbo.v_trans_history') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_trans_history
    IF OBJECT_ID('dbo.v_trans_history') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_trans_history >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_trans_history >>>'
END
GO
/******************************************************************************
* Object: v_trans_history
* Type: View
* Callers: AMA.
* Description: To retrieve all ticket data.
* Impacted Table(s): tickets.
*                   transaction_activities.
*                   transaction_statuses. 
*                   error_status.
*                   games.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.  
* PTR 2260: 
* PTR 2237:
*****************************************************************************/
CREATE VIEW [dbo].[v_trans_history]
AS 
    SELECT 
        tck.ticket_id, 
        tck.customer_id, /*tck.vtid2,*/ 
        ts.transaction_status_name,
        tck.bet_result_type_id,/*tck.header_summary,tck.footer_summary,*/
        ta.agent_confirmed_receipt AS 'agent_transfer_status',
        tck.cost AS 'estimated_cost', 
        tck.game_id, 
        g.game_name, 
        tck.sub_game_id, 
        tck.system_number, 
        tck.draw_date, 
        tck.date_created AS 'created_date',
        ta.oss_processed_date AS 'oss_processed_date', 
        ta.oss_agent_account_bal,
        es.error_status_description, 
        ta.oss_updated_cost AS 'actual_cost', 
        ta.agent_id, 
        tck.date_modified, 
        tck.draw_id, 
        tck.vtid1,
        ta.transaction_status_id
    FROM tickets tck WITH (NOLOCK) 
        INNER JOIN transaction_activities ta WITH (NOLOCK) 
            ON ta.ticket_id = tck.ticket_id
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f' -- sell
        LEFT JOIN transaction_statuses ts WITH (NOLOCK)
            ON ta.transaction_status_id = ts.transaction_status_id
        LEFT JOIN error_status es WITH (NOLOCK)
            ON ta.error_status_id = es.error_status_id
        INNER JOIN games g WITH (NOLOCK)
            ON tck.game_id = g.game_id

GO
IF OBJECT_ID('dbo.v_trans_history') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_trans_history >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_trans_history >>>'
GO



IF OBJECT_ID('dbo.v_trans_history_with_panel_data') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_trans_history_with_panel_data
    IF OBJECT_ID('dbo.v_trans_history_with_panel_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_trans_history_with_panel_data >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_trans_history_with_panel_data >>>'
END
GO
/******************************************************************************
* Object: v_trans_history
* Type: View
* Callers: AMA.
* Description: To retrieve all ticket data with panel data.
* Impacted Table(s): tickets.
*                   transaction_activities.
*                   transaction_statuses. 
*                   error_status.
*                   games.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.  
* PTR 2260: 
* PTR 2237:
*****************************************************************************/
CREATE VIEW [dbo].[v_trans_history_with_panel_data]
AS 
    SELECT tck.ticket_id, 
        tck.customer_id, /*tck.vtid2,*/ 
        ts.transaction_status_name,
        tck.bet_result_type_id,/*tck.header_summary,tck.footer_summary,*/
        ta.agent_confirmed_receipt AS 'agent_transfer_status',
        tck.cost AS 'estimated_cost', 
        tck.game_id, 
        g.game_name, 
        tck.sub_game_id, 
        tck.system_number, 
        tck.draw_date, 
        tck.date_created AS 'created_date',
        ta.oss_processed_date AS 'oss_processed_date', 
        ta.oss_agent_account_bal,
        es.error_status_description, 
        ta.oss_updated_cost AS 'actual_cost', 
        ta.agent_id, 
        tck.date_modified, 
        tck.draw_id, 
        tck.vtid1,
        ta.transaction_status_id,
        CASE 
            WHEN tck.game_id IN (100, 101) THEN panel_data_lotto.panel_data
            WHEN tck.game_id IN (102, 103) THEN panel_data_3d.panel_data
            WHEN tck.game_id = 105 THEN panel_data_bingo.panel_data
            WHEN tck.game_id = 106 THEN panel_data_lotto535.panel_data
            ELSE NULL
    END AS 'panel_data'
    FROM tickets tck WITH (NOLOCK) 
        INNER JOIN transaction_activities ta WITH (NOLOCK) 
            ON ta.ticket_id = tck.ticket_id
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f' -- sell
        INNER JOIN transaction_statuses ts WITH (NOLOCK) 
            ON ta.transaction_status_id = ts.transaction_status_id
        LEFT JOIN error_status es WITH (NOLOCK) 
            ON ta.error_status_id = es.error_status_id
        INNER JOIN games g WITH (NOLOCK) 
            ON tck.game_id = g.game_id
        LEFT JOIN (
            SELECT ticket_id, 
                STRING_AGG(selected_numbers + '|' + CAST(panel_number AS VARCHAR), ';') AS panel_data
            FROM coresys_update_panels WITH (NOLOCK)
            GROUP BY ticket_id
        ) panel_data_lotto
            ON tck.ticket_id = panel_data_lotto.ticket_id
        LEFT JOIN (
            SELECT ticket_id, 
                STRING_AGG(selected_numbers + '|' + CAST(panel_number AS VARCHAR), ';') AS panel_data
            FROM coresys_update_panels_3d WITH (NOLOCK)
            GROUP BY ticket_id
        ) panel_data_3d
            ON tck.ticket_id = panel_data_3d.ticket_id
        LEFT JOIN (
            SELECT ticket_id, 
                STRING_AGG(CAST(play_type AS VARCHAR) + '|' + CAST(panel_number AS VARCHAR), ';') AS panel_data
            FROM coresys_update_panels_bingo WITH (NOLOCK)
            GROUP BY ticket_id
        ) panel_data_bingo
            ON tck.ticket_id = panel_data_bingo.ticket_id
        LEFT JOIN (
            SELECT ticket_id, 
                STRING_AGG(selected_numbers + ':' + selected_bonus_numbers + '|' + CAST(panel_number AS VARCHAR), ';') AS panel_data
            FROM coresys_update_panels_lotto535 WITH (NOLOCK)
            GROUP BY ticket_id
        ) panel_data_lotto535
            ON tck.ticket_id = panel_data_lotto535.ticket_id;

GO
IF OBJECT_ID('dbo.v_trans_history_with_panel_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_trans_history_with_panel_data >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_trans_history_with_panel_data >>>'
GO



IF OBJECT_ID('dbo.v_winners_list') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_winners_list
    IF OBJECT_ID('dbo.v_winners_list') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_winners_list >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_winners_list >>>'
END
GO
/******************************************************************************
* Object: v_winners_list
* Type: View
* Callers: AMA.
* Description: To retrieve all winning tickets.
* Impacted Table(s): coresys_winning_payments.
*                   transaction_activities.
*                   tickets. 
*                   bet_result_types.
*                   misc_winning_statuses.
*                   transaction_statuses.
*                   games.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.   
* PTR 2237: AMA Export Excel: Exporting 10,000 or More Records Fail and Displays Error Message
*****************************************************************************/
CREATE VIEW [dbo].[v_winners_list]
AS
    SELECT tck.ticket_id, 
        tck.customer_id, 
        ta.agent_id, 
        cs.date_modified, 
        tck.draw_id,
        tck.game_id,
        g.game_name, /*ts.transaction_status_name,tck.bet_result_type_id,*/ 
        bt.bet_result_desc, 
        tck.agnt_wnng_upload_status AS 'agent_transfer_status', 
        ws.winning_status_desc AS 'winning_payment_status',
        tck.draw_date, 
        tck.date_created AS 'created_date',
        cs.oss_processed_date AS 'oss_processed_date', 
        es.error_status_description AS 'error_desc',
        cs.oss_payment_amount, 
        cs.oss_winning_amount,  
        cs.oss_winning_tax/*, ta.transaction_date*/
    FROM coresys_winning_payments cs WITH(NOLOCK)
        INNER JOIN tickets tck WITH(NOLOCK) 
            ON cs.ticket_id = tck.ticket_id
        INNER JOIN transaction_activities ta WITH(NOLOCK)
            ON ta.ticket_id = cs.ticket_id
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f'
        LEFT JOIN bet_result_types bt WITH(NOLOCK)
            ON tck.bet_result_type_id = bt.bet_result_type_id
        LEFT JOIN misc_winning_statuses ws WITH(NOLOCK)
            ON tck.agnt_wnng_pymnt_status = ws.winning_status_id
        LEFT JOIN error_status es WITH(NOLOCK)
            ON es.error_status_id = ta.error_status_id
        INNER JOIN games g WITH(NOLOCK)
            ON tck.game_id = g.game_id 
    /*FROM coresys_winning_payments cs WITH (NOLOCK) 
        INNER JOIN transaction_activities ta WITH (NOLOCK) 
            ON ta.ticket_id = cs.ticket_id
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f'
        LEFT JOIN tickets tck WITH (NOLOCK) 
            ON cs.ticket_id = tck.ticket_id
            AND tck.bet_result_type_id > 0
        LEFT JOIN bet_result_types bt WITH (NOLOCK) 
            ON tck.bet_result_type_id = bt.bet_result_type_id
        LEFT JOIN misc_winning_statuses ws WITH (NOLOCK) 
            ON tck.agnt_wnng_pymnt_status = ws.winning_status_id
        LEFT JOIN error_status es WITH (NOLOCK) 
            ON es.error_status_id = ta.error_status_id
        --LEFT JOIN transaction_statuses ts 
            --ON ta.transaction_status_id = ts.transaction_status_id
        LEFT JOIN games g WITH (NOLOCK) 
            ON tck.game_id = g.game_id*/

GO
IF OBJECT_ID('dbo.v_winners_list') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_winners_list >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_winners_list >>>'
GO

IF OBJECT_ID('dbo.v_winners_list_with_panel_data') IS NOT NULL
BEGIN 
    DROP VIEW dbo.v_winners_list_with_panel_data
    IF OBJECT_ID('dbo.v_winners_list_with_panel_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.v_winners_list_with_panel_data >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.v_winners_list_with_panel_data >>>'
END
GO
/******************************************************************************
* Object: v_winners_list_with_panel_data
* Type: View
* Callers: AMA.
* Description: To retrieve all winning tickets with panel data.
* Impacted Table(s): coresys_winning_payments.
*                   transaction_activities.
*                   tickets. 
*                   bet_result_types.
*                   misc_winning_statuses.
*                   transaction_statuses.
*                   games.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2410: AMA Search Optimizations
* PTR 2358: Header Text Update.   
* PTR 2237: AMA Export Excel: Exporting 10,000 or More Records Fail and Displays Error Message
*****************************************************************************/
CREATE VIEW [dbo].[v_winners_list_with_panel_data]
AS
    SELECT cs.ticket_id, 
        tck.customer_id, 
        ta.agent_id, 
        cs.date_modified, 
        tck.draw_id,
        tck.game_id,
        g.game_name, /*ts.transaction_status_name,*/
        /*tck.bet_result_type_id,*/ 
        bt.bet_result_desc, 
        tck.agnt_wnng_upload_status AS 'agent_transfer_status', 
        ws.winning_status_desc AS 'winning_payment_status',
        tck.draw_date, 
        tck.date_created AS 'created_date',
        cs.oss_processed_date AS 'oss_processed_date', 
        es.error_status_description AS 'error_desc',
        cs.oss_payment_amount, 
        cs.oss_winning_amount,  
        cs.oss_winning_tax, /*,ta.transaction_date*/
        CASE 
            WHEN tck.game_id IN (100, 101) THEN panel_data_lotto.panel_data
            WHEN tck.game_id IN (102, 103) THEN panel_data_3d.panel_data
            WHEN tck.game_id = 105 THEN panel_data_bingo.panel_data
            WHEN tck.game_id = 106 THEN panel_data_lotto535.panel_data
            ELSE NULL
        END AS 'panel_data'
    FROM coresys_winning_payments cs WITH (NOLOCK)
        INNER JOIN tickets tck WITH (NOLOCK) 
            ON cs.ticket_id = tck.ticket_id
        INNER JOIN transaction_activities ta WITH (NOLOCK) 
            ON ta.ticket_id = cs.ticket_id
            AND ta.transaction_type_id = 'edf85abc-754b-11e6-9924-64006a4ba62f'
        LEFT JOIN bet_result_types bt WITH (NOLOCK) 
            ON tck.bet_result_type_id = bt.bet_result_type_id
        LEFT JOIN misc_winning_statuses ws WITH (NOLOCK) 
            ON tck.agnt_wnng_pymnt_status = ws.winning_status_id
        LEFT JOIN error_status es WITH (NOLOCK) 
            ON es.error_status_id = ta.error_status_id
        INNER JOIN games g WITH (NOLOCK) 
            ON tck.game_id = g.game_id
        LEFT JOIN (
            SELECT p.ticket_id, 
               STRING_AGG(p.selected_numbers + '|' + CAST(p.panel_number AS VARCHAR), ';') AS panel_data
            FROM coresys_update_panels p WITH (NOLOCK)
            GROUP BY p.ticket_id 
        ) panel_data_lotto
            ON tck.ticket_id = panel_data_lotto.ticket_id
        LEFT JOIN (
            SELECT p_3d.ticket_id, 
               STRING_AGG(p_3d.selected_numbers + '|' + CAST(p_3d.panel_number AS VARCHAR), ';') AS panel_data
            FROM coresys_update_panels_3d p_3d WITH (NOLOCK)
            GROUP BY p_3d.ticket_id
        ) panel_data_3d
            ON tck.ticket_id = panel_data_3d.ticket_id
        LEFT JOIN (
            SELECT p_bingo.ticket_id, 
               STRING_AGG(CAST(p_bingo.play_type AS VARCHAR) + '|' + CAST(p_bingo.panel_number AS VARCHAR), ';') AS panel_data
            FROM coresys_update_panels_bingo p_bingo WITH (NOLOCK)
            GROUP BY p_bingo.ticket_id 
        ) panel_data_bingo
            ON tck.ticket_id = panel_data_bingo.ticket_id
        LEFT JOIN (
            SELECT p_lotto535.ticket_id, 
               STRING_AGG(p_lotto535.selected_numbers + ':' + p_lotto535.selected_bonus_numbers +'|' + CAST(p_lotto535.panel_number AS VARCHAR), ';') AS panel_data
            FROM coresys_update_panels_lotto535 p_lotto535 WITH (NOLOCK)
            GROUP BY p_lotto535.ticket_id 
        ) panel_data_lotto535
            ON tck.ticket_id = panel_data_lotto535.ticket_id;

GO
IF OBJECT_ID('dbo.v_winners_list_with_panel_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.v_winners_list_with_panel_data >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.v_winners_list_with_panel_data >>>'
GO

