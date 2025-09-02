
/***************************************************/
/**          1_datatrak_create_new_table_scripts.sql             **/
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

set @oldversion = 'v1.2.1-B00'		
set @newversion = 'v1.3.0-B00'

IF NOT EXISTS (SELECT 'X' FROM system_dbversion)
BEGIN
INSERT INTO system_dbversion( dbversion_id )
  VALUES ( @newversion )
END
  
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
USE datatrak_bgt_agt
GO

/****************************************************************************** 
* Object:            dbo.coresys_panel_details_mem 
* Type:              IN Memory Table (Schema Only) 
* Description:       Core system update panel details for Lotto535 game 
* Impacted Procs:    
* 
* Update(s) History: 
*   PTR 2383: DB: New Game Lotto 5/35 Development 
*******************************************************************************/

IF OBJECT_ID('dbo.coresys_panel_details_mem', 'U') IS NOT NULL
BEGIN
    RAISERROR ('Table dbo.coresys_panel_details_mem already exists.', 16, 1);
    RETURN;
END
ELSE
BEGIN
    CREATE TABLE dbo.coresys_panel_details_mem (
        panel_id VARCHAR(36) NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 100000),
        game_id INT,
        ticket_id VARCHAR(36),
        selected_numbers VARCHAR(MAX),
        cost MONEY,
        quick_pick TINYINT,
        bonus_number INT,
        date_modified DATETIME2(7),
        summary VARCHAR(MAX),
        panel_number INT,
        sel_numbers_count INT,
        play_type INT,
        selcted_bonus VARCHAR(75),
        INDEX idx_ticket_id HASH (ticket_id) WITH (BUCKET_COUNT = 100000)
    )
    WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

    PRINT 'Table dbo.coresys_panel_details_mem has been created successfully.';
END
GO


USE datatrak_bgt_agt
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************** 
* Object:            dbo.coresys_update_panels_lotto535 
* Type:              Table 
* Description:       Core system update panel details for Lotto535 game 
* Impacted Procs:     
* 
* Update(s) History: 
*   PTR 2383: DB: New Game Lotto 5/35 Development  
*******************************************************************************/

-- Check if the table already exists
IF OBJECT_ID('dbo.coresys_update_panels_lotto535', 'U') IS NOT NULL
BEGIN
    RAISERROR ('Table dbo.coresys_update_panels_lotto535 already exists.', 16, 1);
    RETURN; -- Exit the script if the table exists
END
ELSE
BEGIN
    -- Create the table
    CREATE TABLE dbo.coresys_update_panels_lotto535 (
        panel_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(), -- Primary key with default sequential id
        ticket_id VARCHAR(36) NOT NULL,                     -- Foreign key to tickets table
        selected_numbers VARCHAR(100) NULL,               -- Selected numbers (e.g., <nums>)
        selected_bonus_numbers VARCHAR(100) NULL,         -- Selected bonus numbers (e.g., <bonus>:powerball)
        cost MONEY NOT NULL DEFAULT (0.00),               -- Optional. The EWS API specification does not require cost but still keeps it here to maintain the consistency with other lotto games.
        quick_pick TINYINT NOT NULL DEFAULT (0),           -- Default: Not a quick pick
        summary VARCHAR(500) NULL,                         -- Summary information
        panel_number INT,                 -- Panel number
        date_modified DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(), -- Last modification timestamp
    -- Primary Key Contraint
    CONSTRAINT [PK_coresys_update_panels_lotto535] PRIMARY KEY CLUSTERED (
            panel_id ASC
        ) WITH (
                PAD_INDEX = OFF, 
                STATISTICS_NORECOMPUTE = OFF, 
                IGNORE_DUP_KEY = OFF, 
                ALLOW_ROW_LOCKS = ON, 
                ALLOW_PAGE_LOCKS = ON, 
                OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
            ),
            -- Unique Constraint for ticket_id & panel_number
            CONSTRAINT [UQ_coresys_update_panels_lotto535_ticket_panel] UNIQUE (
                ticket_id,
                panel_number
            )
        )   

    -- Add Foreign Key Constraint
    ALTER TABLE dbo.coresys_update_panels_lotto535 
    ADD CONSTRAINT [FK_coresys_update_panels_lotto535_ticket_id] 
    FOREIGN KEY (ticket_id) 
    REFERENCES dbo.tickets (ticket_id)
    ON DELETE CASCADE;

    -- Success message
    PRINT 'Table dbo.coresys_update_panels_lotto535 has been created successfully.';
END
GO


USE datatrak_bgt_agt
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO

/****************************************************************************** 
* Object:            dbo.in_proc_coresys_update_panels_lotto535 
* Type:              Table 
* Description:       Core system update panel details for Lotto535 game 
* Impacted Procs:    
* 
* Update(s) History: 
*   PTR 2383: DB: New Game Lotto 5/35 Development 
*******************************************************************************/

-- Check if the table already exists
IF OBJECT_ID('dbo.in_proc_coresys_update_panels_lotto535', 'U') IS NOT NULL
BEGIN
    RAISERROR ('Table dbo.in_proc_coresys_update_panels_lotto535 already exists.', 16, 1);
    RETURN; -- Exit the script if the table exists
END
ELSE
BEGIN
    -- Create the table
    CREATE TABLE dbo.in_proc_coresys_update_panels_lotto535 (
        panel_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(), -- Primary key with default sequential id
        ticket_id VARCHAR(36) NOT NULL,                     -- Foreign key to in_proc_tickets table
        selected_numbers VARCHAR(100) NULL,               -- Selected numbers (e.g., <nums>)
        selected_bonus_numbers VARCHAR(100) NULL,         -- Selected bonus numbers (e.g., <bonus>:powerball)
        cost MONEY NOT NULL DEFAULT (0.00),               -- Optional. The EWS API specification does not require cost but still keeps it here to maintain the consistency with other lotto games.
        quick_pick TINYINT NOT NULL DEFAULT (0),           -- Default: Not a quick pick
        summary VARCHAR(500) NULL DEFAULT (NULL),          -- Summary information
        panel_number INT,                 -- Panel number
        date_modified DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(), -- Last modification timestamp
    -- Primary Key Contraint  
    CONSTRAINT [PK_in_proc_coresys_update_panels_lotto535] PRIMARY KEY CLUSTERED (
            panel_id ASC
        ) WITH (
                PAD_INDEX = OFF, 
                STATISTICS_NORECOMPUTE = OFF, 
                IGNORE_DUP_KEY = OFF, 
                ALLOW_ROW_LOCKS = ON, 
                ALLOW_PAGE_LOCKS = ON, 
                OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
            ),
            -- Unique Constraint for ticket_id & panel_number
            CONSTRAINT [UQ_in_proc_coresys_update_panels_lotto535_ticket_panel] UNIQUE (
                ticket_id,
                panel_number
            )
        )   

    -- Add Foreign Key Constraint
    ALTER TABLE dbo.in_proc_coresys_update_panels_lotto535 
    ADD CONSTRAINT [FK_in_proc_coresys_update_panels_lotto535_ticket_id] 
    FOREIGN KEY (ticket_id) 
    REFERENCES dbo.in_proc_tickets (ticket_id)
    ON DELETE CASCADE;

    -- Success message
    PRINT 'Table dbo.in_proc_coresys_update_panels_lotto535 has been created successfully.';
END
GO


USE datatrak_bgt_agt
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/******************************************************************************
* Object:            dbo.in_proc_panels_lotto535.
* Type:              Table.
* Description:       panel details for Lotto535 game
* Impacted procs:     
*
* Update(s) History: 
*   PTR 2383: DB: New Game Lotto 5/35 Development     
*******************************************************************************/
-- Check if the table already exists
IF OBJECT_ID('dbo.in_proc_panels_lotto535', 'U') IS NOT NULL
BEGIN
    RAISERROR ('Table dbo.in_proc_panels_lotto535 already exists.', 16, 1);
    RETURN; -- Exit the script if the table exists
END
ELSE
BEGIN
    -- Create the table
    CREATE TABLE dbo.in_proc_panels_lotto535(
        panel_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(), -- Primary key with default sequential id
        ticket_id VARCHAR(36) NOT NULL,                     -- Foreign key to in_proc_tickets table
        selected_numbers VARCHAR(100) NULL,                -- Selected numbers (e.g., <nums>)
        selected_bonus_numbers VARCHAR(100) NULL,          -- Selected bonus numbers (e.g., <bonus>:powerball)
        cost MONEY NOT NULL DEFAULT (0.00),                -- Optional. The EWS API specification does not require cost but still keeps it here to maintain the consistency with other lotto games.
        quick_pick TINYINT NOT NULL DEFAULT (0),            -- Quick pick flag (default: 0)
        panel_number INT,                              -- Panel number
        date_modified DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(), -- Last modification timestamp
    -- Primary Key Contraint  
    CONSTRAINT [PK_in_proc_panels_lotto535] PRIMARY KEY CLUSTERED (
            panel_id ASC
        ) WITH (
                PAD_INDEX = OFF, 
                STATISTICS_NORECOMPUTE = OFF, 
                IGNORE_DUP_KEY = OFF, 
                ALLOW_ROW_LOCKS = ON, 
                ALLOW_PAGE_LOCKS = ON, 
                OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
            ),
            -- Unique Constraint for ticket_id & panel_number
            CONSTRAINT [UQ_in_proc_panels_lotto535_ticket_panel] UNIQUE (
                ticket_id,
                panel_number
            )
        )   

     -- Foreign Key Constraint
    ALTER TABLE dbo.in_proc_panels_lotto535 WITH CHECK 
    ADD CONSTRAINT [FK_in_proc_panels_lotto535_ticket_id] 
    FOREIGN KEY (ticket_id) 
    REFERENCES dbo.in_proc_tickets (ticket_id)
    ON DELETE CASCADE;
    
    -- Success message
    PRINT 'Table dbo.in_proc_panels_lotto535 has been created successfully.';
END
GO


/****************************************************************************** 
* Object:            dbo.panel_details_mem 
* Type:              IN Memory Table (Schema Only) 
* Description:       Core system update panel details for Lotto535 game 
* Impacted Procs:    
* 
* Update(s) History: 
*   PTR 2383: DB: New Game Lotto 5/35 Development 
*******************************************************************************/
IF OBJECT_ID('dbo.panel_details_mem', 'U') IS NOT NULL
BEGIN
    RAISERROR ('Table dbo.panel_details_mem already exists.', 16, 1);
    RETURN;
END
ELSE
BEGIN
    CREATE TABLE dbo.panel_details_mem (
        panel_id VARCHAR(36) NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 100000),
        game_id INT,
        ticket_id VARCHAR(36),
        selected_numbers VARCHAR(MAX),
        cost MONEY,
        quick_pick TINYINT,
        bonus_number INT,
        date_modified DATETIME2(7),
        panel_number INT,
        sel_numbers_count INT,
        play_type INT,
        selcted_bonus VARCHAR(75),
        INDEX idx_ticket_id HASH (ticket_id) WITH (BUCKET_COUNT = 100000)
    )
    WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

    PRINT 'Table dbo.panel_details_mem has been created successfully.';
END
GO


USE datatrak_bgt_agt
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/******************************************************************************
* Object:            dbo.panels_lotto535.
* Type:              Table.
* Description:       panel details for Lotto535 game
* Impacted procs:     
*
* Update(s) History: 
*   PTR 2383: DB: New Game Lotto 5/35 Development     
*******************************************************************************/
-- Check if the table already exists
IF object_id('dbo.panels_lotto535','U') IS NOT NULL
BEGIN
    RAISERROR ('Table dbo.panels_lotto535 already exists.', 16, 1);
    RETURN; -- Exit the script if the table exists
END
ELSE
BEGIN
    -- Create the table
    CREATE TABLE dbo.panels_lotto535(
        panel_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(), -- Primary key with default sequential id
        ticket_id VARCHAR(36) NOT NULL,                     -- Foreign key to tickets table
        selected_numbers VARCHAR(100) NULL,                  -- Selected numbers (<nums>)
        selected_bonus_numbers VARCHAR(100) NULL,            -- Selected bonus numbers (<bonus>:powerball)
        cost MONEY NOT NULL DEFAULT (0.00),                 -- Optional. The EWS API specification does not require cost but still keeps it here to maintain the consistency with other lotto games.
        quick_pick TINYINT NOT NULL DEFAULT (0),            -- Default: Not a quick pick
        panel_number INT,                                   -- panel_number
        date_modified DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),  -- Last modification timestamp
    -- Primary Key Contraint    
    CONSTRAINT PK_panels_lotto535 PRIMARY KEY CLUSTERED 
    (
        panel_id ASC
    ) WITH (
            PAD_INDEX = OFF,
            STATISTICS_NORECOMPUTE = OFF,
            IGNORE_DUP_KEY = OFF,
            ALLOW_ROW_LOCKS = ON,
            ALLOW_PAGE_LOCKS = ON,
            OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF
        ),
        -- Unique Constraint for ticket_id & panel_number
        CONSTRAINT [UQ_panels_lotto535_ticket_panel] UNIQUE (
            ticket_id,
            panel_number
        )
    )   

    -- Foreign Key Constraint
    ALTER TABLE dbo.panels_lotto535
    ADD  CONSTRAINT FK_panels_lotto535_ticket_id 
    FOREIGN KEY(ticket_id)
    REFERENCES dbo.tickets (ticket_id)
    ON DELETE CASCADE; -- Cascade delete

    -- Success message
    PRINT 'Table dbo.panels_lotto535 has been created successfully.';
END
GO


/****************************************************************************** 
* Object:            dbo.staging_move_tickets 
* Type:              IN Memory Table (Schema Only) 
* Description:       Core system update panel details for Lotto535 game 
* Impacted Procs:    
* 
* Update(s) History: 
*   PTR 2383: DB: New Game Lotto 5/35 Development 
*******************************************************************************/
-- Check if the table already exists
/* The memory optimized tables needs to be setup DBADMIN help needed */
IF OBJECT_ID('dbo.staging_move_tickets', 'U') IS NOT NULL
BEGIN
    RAISERROR ('Table dbo.staging_move_tickets already exists.', 16, 1);
    RETURN;
END
ELSE
BEGIN
    CREATE TABLE dbo.staging_move_tickets (
        ticket_id VARCHAR(36) NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 10000),
        game_id INT NOT NULL,
        date_modified DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
        moved_to_mem BIT NOT NULL DEFAULT 0, -- 0: not moved ; 1: moved
    )
    WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

    PRINT 'Table dbo.staging_move_tickets has been created successfully.';
END
GO


/****************************************************************************** 
* Object:            dbo.tickets_details_mem 
* Type:              IN Memory Table (Schema Only) 
* Description:       Core system update panel details for Lotto535 game 
* Impacted Procs:    
* 
* Update(s) History: 
*   PTR 2383: DB: New Game Lotto 5/35 Development 
*******************************************************************************/
IF OBJECT_ID('dbo.tickets_details_mem', 'U') IS NOT NULL
BEGIN
    RAISERROR ('Table dbo.tickets_details_mem already exists.', 16, 1);
    RETURN;
END
ELSE
BEGIN
    CREATE TABLE dbo.tickets_details_mem (
        ticket_id VARCHAR(36) NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 100000),
        customer_id VARCHAR(9),
        draw_id INT,
        game_id INT,
        sub_game_id INT,
        system_number INT,
        draw_date DATETIME2(7),
        draw_offset INT,
        hwid VARCHAR(15),
        msn INT,
        vtid1 VARCHAR(16),
        vtid2 VARCHAR(40),
        vtid2_encrypted VARCHAR(40),
        tsn VARCHAR(50),
        cost MONEY,
        bet_result_type_id TINYINT,
        panel_count INT,
        purge_date DATETIME2(7),
        date_modified DATETIME2(7),
        date_created DATETIME2(7),
        header_summary NVARCHAR(MAX),
        footer_summary NVARCHAR(MAX),
        agnt_wnng_pymnt_status VARCHAR(36),
        agnt_wnng_upload_status VARCHAR(36)
    )
    WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

    PRINT 'Table dbo.tickets_details_mem has been created successfully.';
END
GO


/****************************************************************************** 
* Object:            dbo.transaction_details_mem 
* Type:              IN Memory Table (Schema Only) 
* Description:       Core system update panel details for Lotto535 game 
* Impacted Procs:    
* 
* Update(s) History: 
*   PTR 2383: DB: New Game Lotto 5/35 Development 
*******************************************************************************/
IF OBJECT_ID('dbo.transaction_details_mem', 'U') IS NOT NULL
BEGIN
    RAISERROR ('Table dbo.transaction_details_mem already exists.', 16, 1);
    RETURN;
END
ELSE
BEGIN
    CREATE TABLE dbo.transaction_details_mem (
        transaction_activity_id VARCHAR(36) NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 100000),
        ticket_id VARCHAR(36),
        transaction_date DATETIME2(7),
        transaction_type_id VARCHAR(36),
        oss_processed_date DATETIME2(7),
        error_status_id VARCHAR(36),
        oss_updated_cost MONEY,
        total_cost_alter MONEY,
        transaction_status_id VARCHAR(36),
        date_modified DATETIME2(7),
        agent_id VARCHAR(8),
        oss_agent_account_bal MONEY,
        agent_confirmed_receipt TINYINT,
        oss_tax_amount MONEY,
        INDEX idx_ticket_id HASH (ticket_id) WITH (BUCKET_COUNT = 100000)
    )
    WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

    PRINT 'Table dbo.transaction_details_mem has been created successfully.';
END
GO


