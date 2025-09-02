-- setup_memory_optimized.sql
USE [datatrak_bgt_agt]
GO

-- Variables
DECLARE @db_name SYSNAME = 'datatrak_bgt_agt';
DECLARE @min_version INT = 130;
DECLARE @current_version INT;
DECLARE @compat_level INT;
DECLARE @data_path NVARCHAR(500);

-- 1. Get SQL Server version
SELECT @current_version = PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR), 4);
PRINT 'Detected SQL Server major version: ' + CAST(@current_version AS VARCHAR);

IF @current_version < 13
BEGIN
    RAISERROR('SQL Server version is too old. Minimum required: SQL Server 2016 (version 13).', 16, 1);
    RETURN;
END

-- 2. Get current compatibility level
SELECT @compat_level = compatibility_level
FROM sys.databases
WHERE name = @db_name;

PRINT 'Current compatibility level: ' + CAST(@compat_level AS VARCHAR);

IF @compat_level < @min_version
BEGIN
    PRINT 'Compatibility level is below required minimum (130). Updating to 150.';
    EXEC('ALTER DATABASE [' + @db_name + '] SET COMPATIBILITY_LEVEL = 150;');
END
ELSE
BEGIN
    PRINT 'Compatibility level is sufficient (>= 130). No update required.';
END

-- 3. Get data file path
SELECT TOP 1 @data_path = LEFT(physical_name, LEN(physical_name) - CHARINDEX('/', REVERSE(physical_name)))
FROM sys.master_files
WHERE database_id = DB_ID(@db_name) AND type_desc = 'ROWS';

PRINT 'Resolved database file path: ' + @data_path;

-- 4. Create memory optimized filegroup and container
BEGIN TRY
    IF NOT EXISTS (
        SELECT 1
        FROM sys.filegroups
        WHERE name = 'MemOptFileGroup'
    )
    BEGIN
        EXEC('ALTER DATABASE [' + @db_name + '] ADD FILEGROUP [MemOptFileGroup] CONTAINS MEMORY_OPTIMIZED_DATA;');
        PRINT 'Memory optimized filegroup created.';
    END
    ELSE
    BEGIN
        PRINT 'Memory optimized filegroup already exists.';
    END

    IF NOT EXISTS (
        SELECT 1
        FROM sys.database_files
        WHERE name = 'MemOptContainer'
    )
    BEGIN
        EXEC('ALTER DATABASE [' + @db_name + '] ADD FILE (
            NAME = N''MemOptContainer'',
            FILENAME = N''' + @data_path + '/MemOptContainer''
        ) TO FILEGROUP [MemOptFileGroup];');
        PRINT 'Memory optimized file container created.';
    END
    ELSE
    BEGIN
        PRINT 'Memory optimized container already exists.';
    END

    -- 5. Final verification
    SELECT 
        name AS database_name,
        is_memory_optimized_enabled
    FROM sys.databases
    WHERE name = @db_name;

    PRINT 'Memory optimized setup completed successfully.';
END TRY
BEGIN CATCH
    PRINT 'Setup failed with error: ' + ERROR_MESSAGE();
    RETURN;
END CATCH;
