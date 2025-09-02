
/***************************************************/
/**          6_datatrak_sp_scripts.sql             **/
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

IF OBJECT_ID('dbo.p_aw203_sales_by_draw') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_aw203_sales_by_draw
    IF OBJECT_ID('dbo.p_aw203_sales_by_draw') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_aw203_sales_by_draw >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_aw203_sales_by_draw >>>'
END
GO
/******************************************************************************
* Object: p_aw203_sales_by_draw
* Type: Stored Procedure
* Callers: AMA
* Usage: Get aw203 sales report
*  
* Previous fixes: PTR 2169
* Current fix(es):
*     PTR 2237
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_aw203_sales_by_draw]
(
    @startDate datetime2,	--required
    @endDate datetime2	--required
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Validate input dates
    IF (@startDate IS NULL OR @endDate IS NULL OR @startDate >= @endDate)
    BEGIN
        SELECT '-1', 'Invalid Start/End Date';
    END

    BEGIN TRY
        -- Construct the query
        DECLARE @sqlquery NVARCHAR(MAX);
        SET @sqlquery = CONCAT(
            'SELECT c.agentid, c.gamename, c.drawid, c.drawdate, ',
            'SUM(c.ticketcount) AS ticketcount, SUM(c.salesamount) AS salesamount, ',
            'SUM(c.paycount) AS paycount, SUM(c.payamount) AS payamount ',
            'FROM ', dbo.f_get_dbname(), 'v_aw203 c WITH (NOLOCK) ',
            'WHERE c.datecreated BETWEEN @startDate AND @endDate ',
            'GROUP BY c.gamename, c.drawid, c.drawdate, c.agentid ',
            'ORDER BY c.drawid;'
        );

        -- Execute the query with parameters
        EXEC sp_executesql 
            @sqlquery, 
            N'@startDate DATETIME2, @endDate DATETIME2',
            @startDate, @endDate;
    END TRY
    BEGIN CATCH
        -- Return error details
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_aw203_sales_by_draw') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_aw203_sales_by_draw >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_aw203_sales_by_draw >>>'
GO


IF OBJECT_ID('dbo.p_aw307_daily_new_customers') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_aw307_daily_new_customers
    IF OBJECT_ID('dbo.p_aw307_daily_new_customers') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_aw307_daily_new_customers >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_aw307_daily_new_customers >>>'
END
GO
/******************************************************************************
* Object: p_aw307_daily_new_customers.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: Get report aw307 new customers.
* Impacted View(s): customers.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
* PTR 2237: AMA Export Excel: Exporting 10,000 or More Records Fail and Displays Error Message
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_aw307_daily_new_customers]
(
    @startDate datetime2,	--required
    @endDate datetime2	--required
)
AS
BEGIN
    -- Enable optimal settings for transaction and execution
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Validate input parameters
        IF (@startDate IS NULL OR @endDate IS NULL OR @startDate >= @endDate)
        BEGIN
            SELECT 
                '-1' AS Status, 
                'Invalid Start/End Date' AS Message, 
                @startDate AS ProvidedStartDate, 
                @endDate AS ProvidedEndDate;
            RETURN;
        END

        -- Define the query using parameterized execution
        DECLARE @sqlquery NVARCHAR(MAX);
        SET @sqlquery = CONCAT(
            'SELECT c.agent_id AS agentid, c.customer_id AS customerid, ',
            'CASE WHEN c.customer_status_id = 5 THEN c.mobile_closed ELSE c.mobile END AS mobile ',
            'FROM ', dbo.f_get_dbname(), 'customers c WITH (NOLOCK) ',
            'WHERE c.created_date BETWEEN @startDate AND @endDate'
        );
     -- Execute the query with parameters
        EXEC sp_executesql 
            @sqlquery, 
            N'@startDate DATETIME2, @endDate DATETIME2',
            @startDate, @endDate;

    END TRY
    BEGIN CATCH
        -- Return error details
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_aw307_daily_new_customers') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_aw307_daily_new_customers >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_aw307_daily_new_customers >>>'
GO


IF OBJECT_ID('dbo.p_aw402_daily_winnings') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_aw402_daily_winnings
    IF OBJECT_ID('dbo.p_aw402_daily_winnings') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_aw402_daily_winnings >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_aw402_daily_winnings >>>'
END
GO
/******************************************************************************
* Object: p_aw402_daily_winnings.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: Get aw402 winnigs report (lotto and 3D).
* Impacted View(s): v_aw402.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
* PTR 2237: AMA Export Excel: Exporting 10,000 or More Records Fail and Displays Error Message
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_aw402_daily_winnings]
(
    @draw_id varchar(max)='', --required
    @game_id varchar(max)=''  --required
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Check for valid input
    IF (@draw_id IS NULL OR @game_id IS NULL OR @draw_id = '' OR @game_id = '')
    BEGIN
        SELECT '-1', 'Invalid input parameters';
        RETURN;
    END

    BEGIN TRY
        -- Convert input parameters into a temporary table
        DECLARE @temp TABLE (Draw NVARCHAR(50), Game NVARCHAR(50));

        -- convert input from 1,2,3 to ; ["1","2","3"] and insert to temp matching game and draw
        INSERT INTO @temp (Draw, Game)
        SELECT d.[value] AS Draw, g.[value] AS Game
        FROM OPENJSON(CONCAT('["', REPLACE(@draw_id, ',', '","'), '"]')) d
        INNER JOIN OPENJSON(CONCAT('["', REPLACE(@game_id, ',', '","'), '"]')) g
            ON d.[key] = g.[key];
    
        -- Check if there are any unprocessed draw/game combinations
        IF EXISTS (
            SELECT 1 
            FROM @temp t1
            WHERE NOT EXISTS (
                SELECT 1 
                FROM aw402_game_draw t2 
                WHERE t1.Game = t2.game_id AND t1.Draw = t2.draw_id
            )
        )
        BEGIN
            -- Insert unprocessed combinations into the permanent table
            --keep a record in the permanent table (erased at sod)
            INSERT INTO aw402_game_draw (draw_id, game_id)
            SELECT t1.Draw, t1.Game
            FROM @temp t1

            -- Generate the report
            DECLARE @sqlquery NVARCHAR(MAX) = CONCAT(
                'SELECT * FROM ', dbo.f_get_dbname(), 'v_aw402 c WITH (NOLOCK) ',
                'WHERE game_id IN (SELECT value FROM OPENJSON(''', @game_id, ''')) ',
                'AND draw_id IN (SELECT value FROM OPENJSON(''', @draw_id, '''))'
            );

            EXEC sp_executesql @sqlquery;
        END
        ELSE
        BEGIN
            SELECT '-1', 'Already processed';
        END
    END TRY
    BEGIN CATCH
         -- Return error details
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_aw402_daily_winnings') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_aw402_daily_winnings >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_aw402_daily_winnings >>>'
GO


IF OBJECT_ID('dbo.p_aw403_daily_winnings') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_aw403_daily_winnings
    IF OBJECT_ID('dbo.p_aw403_daily_winnings') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_aw403_daily_winnings >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_aw403_daily_winnings >>>'
END
GO
/******************************************************************************
* Object: p_aw403_daily_winnings.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: get aw403 winnigs report (bingo).
* Impacted View(s): v_aw403.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
* PTR 2086:
* PTR 2143:
* PTR 2237: AMA Export Excel: Exporting 10,000 or More Records Fail and Displays Error Message
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_aw403_daily_winnings]
(
    @draw_id  varchar(max)='', --required
    @game_id  varchar(max)=''	 --required
)
AS
BEGIN
   SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @sqlQuery NVARCHAR(MAX);
    DECLARE @sqlQueryDraw NVARCHAR(MAX);
    DECLARE @res INT;
	DECLARE @dbName NVARCHAR(255);
	DECLARE @verifyQuery NVARCHAR(MAX);

	SET @dbName = dbo.f_get_dbname();

    BEGIN TRY 
        -- Validate input parameters
        IF (@draw_id IS NULL OR @game_id IS NULL OR @draw_id = '' OR @game_id = '')
        BEGIN
            SELECT '-1', 'Invalid input parameters';
            RETURN;
        END

        BEGIN TRANSACTION

        -- Execute verification procedure 
		SET @verifyQuery = 'EXEC ' + @dbName + '.dbo.p_verify_bingo_winning_report @draw_id, @game_id, @result OUT';

		EXEC sp_executesql @verifyQuery, 
			N'@draw_id NVARCHAR(MAX), @game_id NVARCHAR(MAX), @result INT OUT',
			@draw_id, @game_id, @res OUT;


            IF (@res > 0)
            BEGIN
                -- Query to fetch report
                SET @sqlQuery = CONCAT(
                    'SELECT * FROM ', dbo.f_get_dbname(), 'v_aw403 c WITH (NOLOCK) ',
                    'WHERE game_id = @game_id AND draw_id = @draw_id'
                );

                -- Query to fetch draw date
                SET @sqlQueryDraw = CONCAT(
                    'SELECT draw_date FROM ', dbo.f_get_dbname(), 'winning_header_data c WITH (NOLOCK) ',
                    'WHERE game_id = @game_id AND draw_id = @draw_id'
                );

                -- Execute the queries
                EXEC sp_executesql @sqlQuery,
                    N'@game_id NVARCHAR(MAX), @draw_id NVARCHAR(MAX)',
                    @game_id, @draw_id;

                EXEC sp_executesql @sqlQueryDraw,
                    N'@game_id NVARCHAR(MAX), @draw_id NVARCHAR(MAX)',
                    @game_id, @draw_id;
            END
            ELSE
            BEGIN
                SELECT '-1' AS Status, 'Report Already Generated' AS Message;
            END
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@trancount > 0
            ROLLBACK TRANSACTION

        -- Return error details
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_aw403_daily_winnings') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_aw403_daily_winnings >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_aw403_daily_winnings >>>'
GO


IF OBJECT_ID('dbo.p_aw404_daily_winnings') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_aw404_daily_winnings
    IF OBJECT_ID('dbo.p_aw404_daily_winnings') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_aw404_daily_winnings >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_aw404_daily_winnings >>>'
END
GO
/******************************************************************************
* Object: p_aw404_daily_winnings.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: get aw404 winnigs report (lotto535).
* Impacted View(s): v_aw404.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_aw404_daily_winnings]
(
    @draw_id  varchar(max)='', --required
    @game_id  varchar(max)=''	 --required
)
AS
BEGIN
   SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @sqlQuery NVARCHAR(MAX);
    DECLARE @sqlQueryDraw NVARCHAR(MAX);
    DECLARE @res INT;

    BEGIN TRY 
        -- Validate input parameters
        IF (@draw_id IS NULL OR @game_id IS NULL OR @draw_id = '' OR @game_id = '')
        BEGIN
            SELECT '-1', 'Invalid input parameters';
            RETURN;
        END
        -- Query to fetch report
        SET @sqlQuery = CONCAT(
            'SELECT * FROM ', dbo.f_get_dbname(), 'v_aw404 c WITH (NOLOCK) ',
            'WHERE game_id = @game_id AND draw_id = @draw_id'
        );

            -- Query to fetch draw date
        SET @sqlQueryDraw = CONCAT(
            'SELECT draw_date FROM ', dbo.f_get_dbname(), 'winning_header_data c WITH (NOLOCK) ',
            'WHERE game_id = @game_id AND draw_id = @draw_id'
        );

        -- Execute the queries
        EXEC sp_executesql @sqlQuery,
            N'@game_id NVARCHAR(MAX), @draw_id NVARCHAR(MAX)',
                @game_id, @draw_id;

        EXEC sp_executesql @sqlQueryDraw,
            N'@game_id NVARCHAR(MAX), @draw_id NVARCHAR(MAX)',
                @game_id, @draw_id;
    END TRY
    BEGIN CATCH
        -- Return error details
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_aw404_daily_winnings') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_aw404_daily_winnings >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_aw404_daily_winnings >>>'
GO


IF OBJECT_ID('dbo.p_eod_transfer_tickets') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_eod_transfer_tickets
    IF OBJECT_ID('dbo.p_eod_transfer_tickets') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_eod_transfer_tickets >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_eod_transfer_tickets >>>'
END
GO
/******************************************************************************
* Object: p_eod_transfer_tickets.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: 
* Impacted Table(s): 
*
* Update(s) History:
* PTR 2383: DB: New Game Lotto 5/35 Development
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: Enable Xact_abort to ensure transactions are rolled back in case of any exception.
* PTR 2358: Header Text Update.
*******************************************************************************/ 
CREATE PROCEDURE [dbo].[p_eod_transfer_tickets]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @query NVARCHAR(MAX);

    BEGIN TRY
        SET @query = CONCAT('EXEC ',dbo.f_get_dbname(),'p_transfer_tickets_to_permanent_table 1, 1;');
        EXEC sp_executesql @query;
    END TRY
    BEGIN CATCH
        SELECT '-1', ERROR_MESSAGE();
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.p_eod_transfer_tickets') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_eod_transfer_tickets >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_eod_transfer_tickets >>>'
GO

---- NOT IN USE REMOVE----------------------
IF OBJECT_ID('dbo.p_get_bingo_draw_transfer_details') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_bingo_draw_transfer_details
    IF OBJECT_ID('dbo.p_get_bingo_draw_transfer_details') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_bingo_draw_transfer_details >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_bingo_draw_transfer_details >>>'
END
GO
/*CREATE PROCEDURE [dbo].[p_get_bingo_draw_transfer_details]
    -- Add the parameters for the stored procedure here
    @fileversion	varchar(20),
    @gameId		int,
    @drawId		int,
    @drawDate		datetime2
AS
BEGIN
    declare @finalsqlstmt varchar(max)

    set @finalsqlstmt = concat('select t.* from ',dbo.f_get_dbname(),' v_send_winnings_to_agent t with(nolock) 
                                where t.file_version = ''',@fileversion,''' and t.game_id = ''',@gameId,''' and t.draw_id = ''',@drawId,
									''' and t.draw_date = ''',@drawDate,''' ')

    exec (@finalsqlstmt)
END
GO
*/

-----------------------------
-- Previous Fixes
-- Recent Fixes
-- PTR 2057
-- PTR 2144 
-----------------------------
---- NOT IN USE REMOVE----------------------
IF OBJECT_ID('dbo.p_get_bingo_draw_transfers') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_bingo_draw_transfers
    IF OBJECT_ID('dbo.p_get_bingo_draw_transfers') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_bingo_draw_transfers >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_bingo_draw_transfers >>>'
END
GO
/*
CREATE PROCEDURE [dbo].[p_get_bingo_draw_transfers]
    -- Add the parameters for the stored procedure here
    @search		varchar(255)='',	--optional
    @startDate		datetime2 = '',		--optional
    @endDate		datetime2 = '',		--optional
    @page		int=1,			    --optional
    @pageSize		int=20				--optional
AS
BEGIN
    declare @finalsqlstmt varchar(max)
    declare @pageString varchar(max)
    declare @pageCount varchar(max)
    declare @viewName varchar(255)

    set @pageString =concat(' OFFSET ', @pageSize,' * (',@page,' - 1) ROWS FETCH NEXT ', @pageSize,' ROWS ONLY')

    If @search = '' or @search is null
	Begin
            If @startDate = ''
            Begin
                set @finalsqlstmt = concat('select * from ',dbo.f_get_dbname(),'winning_header_data with(nolock) 
                                            where send_to_all_agents = 0 and game_id = 105 order by draw_id desc ',@pageString)

                set @pageCount =concat('select count(draw_id) from ',dbo.f_get_dbname(),'winning_header_data
                                        where send_to_all_agents = 0 and game_id = 105 ')
            End
            Else
            Begin
                If @endDate <> ''
                Begin
                    set @finalsqlstmt = concat('select * from ',dbo.f_get_dbname(),'winning_header_data with(nolock)
                                                where draw_date between ''',@startDate,''' and ''',@endDate,''' and game_id = 105 order by draw_id desc ',@pageString)

                    set @pageCount =concat('select count(draw_id) from ',dbo.f_get_dbname(),'winning_header_data with(nolock)
                                            where draw_date between ''',@startDate,''' and ''',@endDate,''' and game_id = 105 ')
                End
                else
                    select '-1','Invalid Date range'
            End

            exec (@finalsqlstmt)
            exec (@pageCount)
	End
	Else
	Begin
            if (@startDate ='')
            BEGIN
                set @finalsqlstmt = concat('select * from ',dbo.f_get_dbname(),'winning_header_data with(nolock) 
                                            where ',@search ,' and game_id = 105 order by draw_id desc ',@pageString)

                set @pageCount =concat('select count(draw_id) from ',dbo.f_get_dbname(),'winning_header_data with(nolock) where ',@search )
            END
            else
            BEGIN
                if (@endDate <>'')
                BEGIN
                    set @finalsqlstmt = concat('select * from ',dbo.f_get_dbname(),' winning_header_data with(nolock) 
                                                where ',@search ,' and game_id = 105 and draw_date between ''',@startDate,''' and ''',@endDate,''' order by draw_id desc ',@pageString)

                    set @pageCount =concat('select count(draw_id) from ',dbo.f_get_dbname(),'winning_header_data with(nolock) 
                                            where ',@search,' and game_id = 105 and draw_date  between ''',@startDate,''' and ''',@endDate,'''' )
                END
                else
                    select '-1','Invalid Date range'
            END

            exec (@finalsqlstmt)
            exec (@pageCount)
	End
END
GO
*/

IF OBJECT_ID('dbo.p_get_draw_transfer_details') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_draw_transfer_details
    IF OBJECT_ID('dbo.p_get_draw_transfer_details') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_draw_transfer_details >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_draw_transfer_details >>>'
END
GO
/******************************************************************************
* Object: p_get_draw_transfer_details.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: 
* Impacted View(s): .
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_draw_transfer_details]
    @fileversion VARCHAR(20),
    @gameId INT,
    @drawId INT,
    @drawDate DATETIME2 
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @finalsqlstmt NVARCHAR(MAX);
    DECLARE @DbName NVARCHAR(255);

    -- Get the database name dynamically
    SET @DbName = dbo.f_get_dbname();

    SET @finalsqlstmt = N'
        SELECT t.* 
        FROM ' + @DbName + N'v_send_winnings_to_agent t WITH (NOLOCK) 
        WHERE t.file_version = @fileversion 
        AND t.game_id = @gameId 
        AND t.draw_id = @drawId 
        AND t.draw_date = @drawDate'; 

    EXEC sp_executesql 
        @finalsqlstmt, 
        N'@fileversion VARCHAR(20), @gameId INT, @drawId INT, @drawDate DATETIME2',
        @fileversion, @gameId, @drawId, @drawDate;
END;
GO
IF OBJECT_ID('dbo.p_get_draw_transfer_details') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_draw_transfer_details >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_draw_transfer_details >>>'
GO


IF OBJECT_ID('dbo.p_get_draw_transfers') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_draw_transfers
    IF OBJECT_ID('dbo.p_get_draw_transfers') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_draw_transfers >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_draw_transfers >>>'
END
GO
/******************************************************************************
* Object: p_get_draw_transfers.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: 
* Impacted View(s): 
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2358: Header Text Update.
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_draw_transfers]
    -- Add the parameters for the stored procedure here
    @gameId     INT = NULL,			   --Optional Game ID (105, 106, or NULL for both)
    @search     nvarchar(255) = NULL,  -- Optional Search Condition
    @startDate  datetime2 = NULL,      -- Optional Start Date
    @endDate    datetime2 = NULL,      -- Optional End Date
    @page       int = 1,               -- Pagination Page Number
    @pageSize   int = 20               -- Number of Records per Page
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @finalSqlStmt nvarchar(max);
    DECLARE @pageCountSql nvarchar(max);
    DECLARE @dbName nvarchar(255);

    -- Fetch dynamic database name
    SET @dbName = dbo.f_get_dbname();

    -- Validate date range
    IF @startDate IS NOT NULL AND @endDate IS NOT NULL AND @startDate > @endDate
    BEGIN
        SELECT '-1' AS Status, 'Invalid Date Range' AS Message;
        RETURN;
    END

     -- Construct pagination string
    DECLARE @pageString nvarchar(100);
    SET @pageString = CONCAT(' OFFSET ', @pageSize * (@page - 1), ' ROWS FETCH NEXT ', @pageSize, ' ROWS ONLY');

    -- Construct base query
    SET @finalSqlStmt = N'
        SELECT * FROM ' + @dbName + N'winning_header_data WITH (NOLOCK)
        WHERE ';

    SET @pageCountSql = N'
        SELECT COUNT(draw_id) FROM ' + @dbName + N'winning_header_data WITH (NOLOCK)
        WHERE ';

    -- Handle game_id condition
    IF @gameId IS NULL
    BEGIN
        SET @finalSqlStmt = @finalSqlStmt + N' game_id IN (105, 106) ';
        SET @pageCountSql = @pageCountSql + N' game_id IN (105, 106) ';
    END
    ELSE
    BEGIN
        SET @finalSqlStmt = @finalSqlStmt + N' game_id = @gameId ';
        SET @pageCountSql = @pageCountSql + N' game_id = @gameId ';
    END

    -- Apply additional filters
    IF @search IS NOT NULL AND @search <> ''
    BEGIN
        SET @finalSqlStmt = @finalSqlStmt + N' AND ' + @search;
        SET @pageCountSql = @pageCountSql + N' AND ' + @search;
    END

    IF @startDate IS NOT NULL AND @endDate IS NOT NULL
    BEGIN
        SET @finalSqlStmt = @finalSqlStmt + N' AND draw_date BETWEEN @startDate AND @endDate ';
        SET @pageCountSql = @pageCountSql + N' AND draw_date BETWEEN @startDate AND @endDate ';
    END

    SET @finalSqlStmt = @finalSqlStmt + N' ORDER BY draw_id DESC ' + @pageString;

    -- Execute dynamically built query safely with sp_executesql
    EXEC sp_executesql @finalSqlStmt, N'@gameId int, @startDate datetime2, @endDate datetime2', 
                                        @gameId, @startDate, @endDate;
                                        
    EXEC sp_executesql @pageCountSql, N'@gameId int, @startDate datetime2, @endDate datetime2', 
                                        @gameId, @startDate, @endDate;
END
GO
IF OBJECT_ID('dbo.p_get_draw_transfers') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_draw_transfers >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_draw_transfers >>>'
GO


IF OBJECT_ID('dbo.p_get_in_proc_panel_3d_data') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_in_proc_panel_3d_data
    IF OBJECT_ID('dbo.p_get_in_proc_panel_3d_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_in_proc_panel_3d_data >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_in_proc_panel_3d_data >>>'
END
GO
/******************************************************************************
* Object: p_get_in_proc_panel_3d_data.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: Get ticket history on AMA ticket_history page and for export excel.
* Impacted View(s): v_trans_history_with_panel_data.
*                    v_trans_history.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_in_proc_panel_3d_data]
    -- Add the parameters for the stored procedure here
    @ticketId VARCHAR(33)	-- required
AS
BEGIN
    IF EXISTS (
       SELECT 1
        FROM datatrak_bgt_agt.dbo.v_in_proc_coresys_panel_3d_data vw
        WHERE vw.ticket_id = @ticketId
    ) 
    BEGIN
        SELECT vw.in_proc_coresys_update_panels_3d_panel_id,
            vw.ticket_id,
            vw.selected_numbers,
            vw.quick_pick,
            vw.cost AS 'oss_cost',
            vw.summary,
            vw.sel_numbers_count,
            vw.panel_number,
            vw.date_modified,
            vw1.cost AS 'panel_3d_cost'
        FROM datatrak_bgt_agt.dbo.v_in_proc_coresys_panel_3d_data vw 
            INNER JOIN datatrak_bgt_agt.dbo.v_in_proc_panel_3d_data vw1 
                ON vw1.ticket_id = vw.ticket_id 
                AND vw1.panel_number = vw.panel_number
        WHERE vw.ticket_id = @ticketId 
        ORDER BY vw.panel_number ASC
    END
    ELSE
    BEGIN
        SELECT vw.in_proc_panels_3d_panel_id,
            vw.ticket_id,
            vw.selected_numbers,
            vw.quick_pick,
            vw1.cost AS 'oss_cost',
            vw.sel_numbers_count,
            vw.panel_number,
            vw.date_modified,
            vw.cost AS 'panel_3d_cost' 
        FROM datatrak_bgt_agt.dbo.v_in_proc_panel_3d_data vw 
            INNER JOIN datatrak_bgt_agt.dbo.v_in_proc_coresys_panel_3d_data vw1 
                ON vw1.ticket_id = vw.ticket_id 
                AND vw1.panel_number = vw.panel_number
        WHERE vw.ticket_id = @ticketId 
        ORDER BY vw.panel_number ASC
    END;
END
GO
IF OBJECT_ID('dbo.p_get_in_proc_panel_3d_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_in_proc_panel_3d_data >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_in_proc_panel_3d_data >>>'
GO



IF OBJECT_ID('dbo.p_get_in_proc_panel_lotto535_data') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_in_proc_panel_lotto535_data
    IF OBJECT_ID('dbo.p_get_in_proc_panel_lotto535_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_in_proc_panel_lotto535_data >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_in_proc_panel_lotto535_data >>>'
END
GO
/******************************************************************************
* Object: p_get_in_proc_panel_lotto535_data.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: 
* Impacted View(s): 
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_in_proc_panel_lotto535_data]
    @ticketId VARCHAR(33) -- Required parameter
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @query NVARCHAR(MAX);
   
	-- Construct the dynamic SQL query correctly
    SET @query = CONCAT(
        'SELECT * 
        FROM ',dbo.f_get_dbname(), 'f_get_lotto535_in_proc_panel_data(@ticketId);'
		);
    
    -- Execute the dynamic SQL query
    EXEC sp_executesql @query, N'@ticketId VARCHAR(33)', @ticketId;
END;
GO
IF OBJECT_ID('dbo.p_get_in_proc_panel_lotto535_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_in_proc_panel_lotto535_data >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_in_proc_panel_lotto535_data >>>'
GO


IF OBJECT_ID('dbo.p_get_panel_lotto535_data') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_get_panel_lotto535_data
    IF OBJECT_ID('dbo.p_get_panel_lotto535_data') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_get_panel_lotto535_data >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_get_panel_lotto535_data >>>'
END
GO
/******************************************************************************
* Object: p_get_panel_lotto535_data.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: 
* Impacted View(s): 
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_get_panel_lotto535_data]
    @ticketId VARCHAR(33) -- Required parameter
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @dbname NVARCHAR(100);
    DECLARE @query NVARCHAR(MAX);
    

    -- Construct the dynamic SQL query correctly
    SET @query = CONCAT(
        'SELECT * 
        FROM ',dbo.f_get_dbname(), 'f_get_lotto535_panel_data(@ticketId);'
		);

    -- Execute the dynamic SQL query
    EXEC sp_executesql @query, N'@ticketId VARCHAR(33)', @ticketId;
END;
GO
IF OBJECT_ID('dbo.p_get_panel_lotto535_data') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_get_panel_lotto535_data >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_get_panel_lotto535_data >>>'
GO

IF OBJECT_ID('dbo.p_in_proc_trans_history_srch') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_in_proc_trans_history_srch
    IF OBJECT_ID('dbo.p_in_proc_trans_history_srch') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_in_proc_trans_history_srch >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_in_proc_trans_history_srch >>>'
END
GO
/******************************************************************************
* Object: p_in_proc_trans_history_srch.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: Get ticket history on AMA ticket_history page and for export excel.
* Impacted View(s): v_in_proc_trans_history_with_panel_data.
*                    v_in_proc_trans_history.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
* PTR 2237: AMA Export Excel: Exporting 10,000 or More Records Fail and Displays Error Message
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_in_proc_trans_history_srch]
    -- Add the parameters for the stored procedure here
    @startDate	datetime2=NULL,	--optional
    @endDate	datetime2=NULL,	--optional
    @search	nvarchar(max)=NULL,	--optional
    @page	int=1,			    --optional
    @pageSize	int=20,			--optional
    @returnPanelData	int=0	--optional
AS
BEGIN
   SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Declare variables
    DECLARE @viewName NVARCHAR(MAX);
    DECLARE @whereClause NVARCHAR(MAX) = N'';
    DECLARE @finalSqlStmt NVARCHAR(MAX);
    DECLARE @countSqlStmt NVARCHAR(MAX);
    DECLARE @offset INT = @pageSize * (@page - 1);

     -- Determine view name
    SET @viewName =
        CASE 
            WHEN @returnPanelData = 1 THEN 
               'v_in_proc_trans_history_with_panel_data'
                ELSE 
                'v_in_proc_trans_history'
            END;

    -- Build WHERE clause dynamically
    IF @startDate IS NOT NULL AND @endDate IS NOT NULL
        SET @whereClause = CONCAT(@whereClause, 'created_date BETWEEN @startDate AND @endDate');

     -- Add search condition if provided
    IF @search IS NOT NULL
        SET @whereClause = CONCAT(
            CASE WHEN LEN(@whereClause) > 0 THEN @whereClause + ' AND ' ELSE '' END,
            @search
        );

    -- Finalize WHERE clause
    IF LEN(@whereClause) > 0
        SET @whereClause = CONCAT('WHERE ', @whereClause);

    -- Construct main query
    SET @finalSqlStmt = CONCAT(
        'SELECT * FROM ', dbo.f_get_dbname(), @viewName, ' WITH (NOLOCK) ',
        @whereClause, 
        ' ORDER BY created_date DESC OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY;'
    );

    -- Construct count query for the first page
    IF @page = 1
    BEGIN
        SET @countSqlStmt = CONCAT(
            'SELECT COUNT(ticket_id) AS TotalCount FROM ', dbo.f_get_dbname(), @viewName, ' WITH (NOLOCK) ',
            @whereClause, ';'
        );
    END

    -- Execute queries
    BEGIN TRY
        EXEC sp_executesql @finalSqlStmt,
            N'@startDate DATETIME2, @endDate DATETIME2, @offset INT, @pageSize INT',
            @startDate, @endDate, @offset, @pageSize;

        IF @page = 1 -- Count query only needed on the first page
        BEGIN
            EXEC sp_executesql @countSqlStmt,
                N'@startDate DATETIME2, @endDate DATETIME2',
                @startDate, @endDate;
        END
    END TRY
    BEGIN CATCH
        -- Return error details
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_in_proc_trans_history_srch') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_in_proc_trans_history_srch >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_in_proc_trans_history_srch >>>'
GO


IF OBJECT_ID('dbo.p_trans_history_srch') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_trans_history_srch
    IF OBJECT_ID('dbo.p_trans_history_srch') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_trans_history_srch >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_trans_history_srch >>>'
END
GO
/******************************************************************************
* Object: p_trans_history_srch.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: Get ticket history on AMA ticket_history page and for export excel.
* Impacted View(s): v_trans_history_with_panel_data.
*                    v_trans_history.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
* PTR 2237: AMA Export Excel: Exporting 10,000 or More Records Fail and Displays Error Message
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_trans_history_srch]
    -- Add the parameters for the stored procedure here
    @startDate       DATETIME2 = NULL,   -- optional
    @endDate         DATETIME2 = NULL,   -- optional
    @search          NVARCHAR(MAX) = NULL,   -- optional
    @page            INT = 1,   -- optional
    @pageSize        INT = 20,   -- optional
    @returnPanelData INT = 0   -- optional
AS
BEGIN
    -- Declare variables
    DECLARE @viewName NVARCHAR(MAX);
    DECLARE @offset INT = @pageSize * (@page - 1);
    DECLARE @whereClause NVARCHAR(MAX) = N'';
	DECLARE @baseQuery NVARCHAR(max)
	DECLARE @countQuery NVARCHAR(MAX)

    SET NOCOUNT ON; 

    -- Determine which view to use
    SET @viewName = 
        CASE 
            WHEN @returnPanelData = 1 
                THEN 'v_trans_history_with_panel_data'
            ELSE 'v_trans_history'
        END;
    
    -- Build WHERE clause dynamically
    IF @startDate IS NOT NULL AND @endDate IS NOT NULL
        SET @whereClause = CONCAT(@whereClause, 'created_date BETWEEN @startDate AND @endDate');

     -- Add search condition if provided
    IF @search IS NOT NULL 
        SET @whereClause = CONCAT(
            CASE WHEN LEN(@whereClause) > 0 THEN @whereClause + ' AND ' ELSE '' END,
            @search
        );

    -- Finalize WHERE clause
    IF LEN(@whereClause) > 0
        SET @whereClause = CONCAT('WHERE ', @whereClause);

    -- Construct main query with pagination
    SET @baseQuery = CONCAT(
        'SELECT * FROM ', dbo.f_get_dbname(), @viewName, ' WITH (NOLOCK) ',
        @whereClause, 
        ' ORDER BY created_date DESC OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY;'
    );

    -- Construct count query for the first page
    IF @page = 1
    BEGIN
        SET @countQuery = CONCAT(
            'SELECT COUNT(ticket_id) AS TotalCount FROM ', dbo.f_get_dbname(), @viewName, ' WITH (NOLOCK) ',
            @whereClause, ';'
        );
    END

    -- Execute queries
    BEGIN TRY
        -- Execute main query
        EXEC sp_executesql @baseQuery, 
            N'@startDate DATETIME2, @endDate DATETIME2, @offset INT, @pageSize INT',
            @startDate, @endDate, @offset, @pageSize;

        -- Execute count query if on the first page
        IF @page = 1
            EXEC sp_executesql @countQuery, 
                N'@startDate DATETIME2, @endDate DATETIME2',
                @startDate, @endDate;
    END TRY
    BEGIN CATCH
        -- Return error details
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_trans_history_srch') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_trans_history_srch >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_trans_history_srch >>>'
GO



IF OBJECT_ID('dbo.p_trans_history_srch_count') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_trans_history_srch_count
    IF OBJECT_ID('dbo.p_trans_history_srch_count') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_trans_history_srch_count >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_trans_history_srch_count >>>'
END
GO
/******************************************************************************
* Object: p_trans_history_srch_count.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: Retrieve ticket count for the AMA ticket_history page button.
* Impacted View(s): tickets.
*                    games.
*                    transaction_activities.
*                    error_status.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
* PTR 2359: Gitlab Issue# 2
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_trans_history_srch_count]
    @search				NVARCHAR(MAX)='',	--optional
    @boolIncludeTransActivities		INT=1
AS
BEGIN
    -- Declare variables
    DECLARE @finalSqlStmt NVARCHAR(MAX);
    DECLARE @baseQuery NVARCHAR(MAX);
    DECLARE @whereClause NVARCHAR(MAX) = '';

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Build the WHERE clause dynamically
    IF LEN(@search) > 0
        SET @whereClause = CONCAT('WHERE ', @search);

    -- Construct the base query based on @boolIncludeTransActivities
    IF @boolIncludeTransActivities = 0
    BEGIN
        SET @baseQuery = CONCAT(
            'SELECT COUNT(tck.ticket_id) AS tickets_count ',
            'FROM ', dbo.f_get_dbname(), 'tickets tck WITH (NOLOCK) ',
            'LEFT JOIN ', dbo.f_get_dbname(), 'games g WITH (NOLOCK) 
                ON tck.game_id = g.game_id ',
            @whereClause
        );
    END
    ELSE
    BEGIN
        SET @baseQuery = CONCAT(
            'SELECT COUNT(tck.ticket_id) AS tickets_count ',
            'FROM ', dbo.f_get_dbname(), 'tickets tck WITH (NOLOCK) ',
            'INNER JOIN ', dbo.f_get_dbname(), 'transaction_activities ta WITH (NOLOCK) ',
            '   ON ta.ticket_id = tck.ticket_id 
                AND ta.transaction_type_id = ''edf85abc-754b-11e6-9924-64006a4ba62f'' ',
            'LEFT JOIN ', dbo.f_get_dbname(), 'transaction_statuses ts WITH (NOLOCK) ',
            '   ON ta.transaction_status_id = ts.transaction_status_id ',
            'LEFT JOIN ', dbo.f_get_dbname(), 'error_status es WITH (NOLOCK) ',
            '   ON ta.error_status_id = es.error_status_id ',
            'LEFT JOIN ', dbo.f_get_dbname(), 'games g WITH (NOLOCK)
                ON tck.game_id = g.game_id ',
            @whereClause
        );
    END

    -- Execute the query using sp_executesql
    BEGIN TRY
        EXEC sp_executesql @baseQuery, N'@search NVARCHAR(MAX)', @search;
    END TRY
    BEGIN CATCH
        -- Error handling
        SELECT 
            ERROR_NUMBER() AS ErrorNumber,
            ERROR_MESSAGE() AS ErrorMessage;
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_trans_history_srch_count') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_trans_history_srch_count >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_trans_history_srch_count >>>'
GO


IF OBJECT_ID('dbo.p_winners_list_srch') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_winners_list_srch
    IF OBJECT_ID('dbo.p_winners_list_srch') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_winners_list_srch >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_winners_list_srch >>>'
END
GO
/******************************************************************************
* Object: p_winners_list_srch.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: Get Winning tickets on AMA and for export excel.
* Impacted View(s): v_winners_list_with_panel_data.
*                   v_winners_list.
* AMA Component: Winning Tickets.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2355: DB optimization: Minimize deadlocks and time outs (part_I)
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
* PTR 2237: AMA Export Excel: Exporting 10,000 or More Records Fail and Displays Error Message
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_winners_list_srch]
    -- Add the parameters for the stored procedure here
    @startDate	DATETIME =NULL,	--optional
    @endDate	DATETIME =NULL,	--optional
    @search	NVARCHAR(MAX) =NULL,	--optional
    @page	INT = 1,			    --optional
    @pageSize	INT = 20,			--optional
    @returnPanelData	INT=0	--optional
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @viewName NVARCHAR(100);
    DECLARE @offset INT = @pageSize * (@page - 1);
    DECLARE @whereClause NVARCHAR(MAX) = '';
    DECLARE @finalQuery NVARCHAR(MAX);
    DECLARE @countQuery NVARCHAR(MAX);

    -- Determine the view name based on @returnPanelData
    SET @viewName = 
        CASE 
            WHEN @returnPanelData = 1 
            THEN 'v_winners_list_with_panel_data'
            ELSE 'v_winners_list'
        END;

    -- Build WHERE clause dynamically
    IF @startDate IS NOT NULL AND @endDate IS NOT NULL
        SET @whereClause = CONCAT(@whereClause, 
            CASE WHEN LEN(@whereClause) > 0 THEN ' AND ' ELSE '' END,
            'w.draw_date BETWEEN @startDate AND @endDate'
        );
 
    -- Add search condition if provided
    IF @search IS NOT NULL
        SET @whereClause = CONCAT(
            CASE WHEN LEN(@whereClause) > 0 THEN @whereClause + ' AND ' ELSE '' END,
            @search
        );
    
    -- Finalize WHERE clause
    IF LEN(@whereClause) > 0
        SET @whereClause = CONCAT('WHERE ', @whereClause);

    -- Construct the main query
    SET @finalQuery = CONCAT(
        'SELECT w.* ',
        'FROM ', dbo.f_get_dbname(), @viewName, ' w WITH (NOLOCK) ',
        @whereClause, 
        ' ORDER BY w.created_date DESC OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY;'
    );

    -- Construct the count query
    SET @countQuery = CONCAT(
        'SELECT COUNT(*) FROM ', dbo.f_get_dbname(), @viewName, ' w WITH (NOLOCK) ',
        @whereClause
    );

    BEGIN TRY    
		EXEC sp_executesql @finalQuery, 
            N'@startDate DATETIME, @endDate DATETIME, @offset INT, @pageSize INT', 
            @startDate, @endDate, @offset, @pageSize;

        IF @page = 1
        BEGIN
            EXEC sp_executesql @countQuery, 
                N'@startDate DATETIME, @endDate DATETIME', 
                @startDate, @endDate;
        END
    END TRY
    BEGIN CATCH
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_winners_list_srch') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_winners_list_srch >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_winners_list_srch >>>'
GO


IF OBJECT_ID('dbo.p_winners_processing_details') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_winners_processing_details
    IF OBJECT_ID('dbo.p_winners_processing_details') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_winners_processing_details >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_winners_processing_details >>>'
END
GO
/******************************************************************************
* Object: p_winners_processing_details.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: list for records from winning_upload_status table.
* Impacted View(s): winning_upload_status.
* AMA Component: Winner Processing -> View Details.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_winners_processing_details]
    @gameId  INT = 0, 
    @drawId  INT = 0		
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Validate input parameters
    IF @gameId = 0 OR @drawId = 0
    BEGIN
        SELECT '-1', 'Both GameId and DrawId are required.';
        RETURN;
    END

    -- Declare variables
    DECLARE @sqlQuery NVARCHAR(MAX);
    DECLARE @whereClause NVARCHAR(MAX);

    -- Build the WHERE clause
    SET @whereClause = ' WHERE game_id = @gameId AND draw_id = @drawId ';

    -- Construct the main query
    SET @sqlQuery = CONCAT(
        'SELECT * FROM ', 
        dbo.f_get_dbname(), 'winning_upload_status WITH (NOLOCK) ', 
        @whereClause
    );

    -- Execute the query with parameterization
    BEGIN TRY
        EXEC sp_executesql @sqlQuery, 
            N'@gameId INT, @drawId INT', 
            @gameId, @drawId;
    END TRY
    BEGIN CATCH
        -- Error handling
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH
END
GO
IF OBJECT_ID('dbo.p_winners_processing_details') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_winners_processing_details >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_winners_processing_details >>>'
GO


IF OBJECT_ID('dbo.p_winners_processing_list') IS NOT NULL
BEGIN 
    DROP PROCEDURE dbo.p_winners_processing_list;
    IF OBJECT_ID('dbo.p_winners_processing_list') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.p_winners_processing_list >>>';
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.p_winners_processing_list >>>';
END;
GO
/******************************************************************************
* Object: p_winners_processing_list.
* Type: Stored Procedure.
* Caller(s): AMA.
* Description: gets the list of draws from winning_header_data.
* Impacted View(s): winning_header_data.
* AMA Component: Winner Processing.
*
* Update(s) History: 
* PTR 2383: DB: New Game Lotto 5/35 Development 
* PTR 2410: AMA Search Optimizations
* PTR 2353: DB optimization: Set XACT_ABORT/NOCOUNT ON
* PTR 2358: Header Text Update.	
* PTR 1690: Winner Processing - search does not have transfer status or date created
* PTR 1730: AMA Winner Processing Table - should show the draw date
* PTR 2174: AMA Winner Processing: Missing Date Field in Search Screen
*****************************************************************************/
CREATE PROCEDURE [dbo].[p_winners_processing_list]
    @gameId        INT = 0, 
    @drawId        INT = 0,
    @startDate     DATETIME2=NULL,
    @endDate       DATETIME2=NULL,
    @process_status INT = -1,
    @page          INT = 1,			
    @pageSize      INT = 20			
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Declare variables
    DECLARE @sqlQuery NVARCHAR(MAX);
    DECLARE @countQuery NVARCHAR(MAX);
    DECLARE @whereClause NVARCHAR(MAX) = N'';

    -- Build WHERE clause dynamically
    IF @startDate IS NOT NULL AND @endDate IS NOT NULL
        SET @whereClause = CONCAT(@whereClause, 'date_modified BETWEEN @startDate AND @endDate');

    IF @gameId <> 0
        SET @whereClause = CONCAT(
            CASE WHEN LEN(@whereClause) > 0 THEN @whereClause + ' AND ' ELSE '' END,
                'game_id = @gameId'
    );
    
    IF @drawId <> 0
        SET @whereClause = CONCAT(
        CASE WHEN LEN(@whereClause) > 0 THEN @whereClause + ' AND ' ELSE '' END,
            'draw_id = @drawId'
    );

    IF @process_status <> -1
    SET @whereClause = CONCAT(
        CASE WHEN LEN(@whereClause) > 0 THEN @whereClause + ' AND ' ELSE '' END,
        'process_status = @process_status'
    );

    -- Finalize WHERE clause
    IF LEN(@whereClause) > 0
        SET @whereClause = CONCAT('WHERE ', @whereClause);

    -- Build main query
    SET @sqlQuery = CONCAT(
        'SELECT game_id, draw_id, date_modified, process_status, draw_date ',
        'FROM ', dbo.f_get_dbname(), 'winning_header_data WITH (NOLOCK) ',
        @whereClause,
        ' ORDER BY date_modified DESC ',
        'OFFSET ', @pageSize, ' * (', @page, ' - 1) ROWS FETCH NEXT ', @pageSize, ' ROWS ONLY'
    );

    -- Build count query
    SET @countQuery = CONCAT(
        'SELECT COUNT(draw_id) ',
        'FROM ', dbo.f_get_dbname(), 'winning_header_data WITH (NOLOCK) ',
        @whereClause
    );

    -- Execute queries with parameters
    BEGIN TRY
        EXEC sp_executesql @sqlQuery,
            N'@startDate DATETIME2, @endDate DATETIME2, @gameId INT, @drawId INT, @process_status INT',
            @startDate, @endDate, @gameId, @drawId, @process_status;

        EXEC sp_executesql @countQuery,
            N'@startDate DATETIME2, @endDate DATETIME2, @gameId INT, @drawId INT, @process_status INT',
            @startDate, @endDate, @gameId, @drawId, @process_status;
    END TRY
    BEGIN CATCH
        -- Error handling
        SELECT '-1', CONCAT(ERROR_NUMBER(), '=>',ERROR_MESSAGE());
    END CATCH;
END;
GO
IF OBJECT_ID('dbo.p_winners_processing_list') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.p_winners_processing_list >>>';
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.p_winners_processing_list >>>';
GO


