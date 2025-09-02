/*==============================================================*/
/* Deployment Database: datatrak_bgt_awb                        */
/*==============================================================*/

declare @version varchar(50),
        @oldversion varchar(50)
		
set @oldversion = 'v1.2.1-B00'
set @version = ( select rtrim(ltrim(dbversion_id)) from system_dbversion where dbversion_id like @oldversion + '%' )

if (@version is NULL)

raiserror('Deployment aborted due to incompatible datatrak_bgt_awb version!!!',20,-1) WITH LOG

else

print 'Proceed with the deployment as correct datatrak_bgt_awb version is being used...'

--
-- Rights allocation script for database
--
-- NB: This will allocate SELECT, DELETE, INSERT, UPDATE rights on tables to users
--     under group, central_system in the current database.
--

PRINT 'Granting user rights to tables for central_system group...'
GO

/*==================================================================================================================*/
/*                                                                                                                  */
/* Grant SELECT, DELETE, INSERT, UPDATE on all tables to users under central_system group in a Database             */
/* BUT grant SELECT, UPDATE on a specific table, system_dbversion to users under central_system group in a Database */
/*                                                                                                                  */
/*==================================================================================================================*/


if object_id('spDBAGrantLoginRights') is not null
  drop procedure spDBAGrantLoginRights
go

create procedure spDBAGrantLoginRights
@inLoginName varchar(20)
as
  set nocount on
  declare @txSQL varchar(255)

  declare csrTables cursor for
  select 
	  CASE
		WHEN SUSE.name + '.' + SOBJ.name = 'dbo.system_dbversion' 
		     THEN 'GRANT SELECT,UPDATE ON ' + SUSE.name + '.' + SOBJ.name + ' TO ' + @inLoginName
       		ELSE 'GRANT SELECT,DELETE,INSERT,UPDATE ON ' + SUSE.name + '.' + SOBJ.name + ' TO ' + @inLoginName
          END
	from sysobjects SOBJ,
         sysusers SUSE
   where SUSE.uid = SOBJ.uid
     and SOBJ.xtype = 'U'
   order by 1

  open csrTables
  fetch next from csrTables into @txSQL
  while @@fetch_status = 0
  begin
    PRINT @txSQL
    exec (@txSQL)
    fetch next from csrTables into @txSQL
  end
  close csrTables
  deallocate csrTables
  set nocount off
go


create procedure spDBAGrantRights
as
  set nocount on
  declare @txLogin varchar(20)
  declare csrLogins cursor for
    select name from sysusers where name = 'central_system'

  open csrLogins
  fetch next from csrLogins into @txLogin
  while @@fetch_status = 0
  begin
    exec spDBAGrantLoginRights @txLogin
    fetch next from csrLogins into @txLogin
  end
  close csrLogins
  deallocate csrLogins
  set nocount off
go


if object_id('spDBAGrantRights') is not null
  exec spDBAGrantRights
go


if object_id('spDBAGrantRights') is not null
  drop procedure spDBAGrantRights
go

if object_id('spDBAGrantLoginRights') is not null
  drop procedure spDBAGrantLoginRights
go


PRINT 'TABLE: Rights grant to central_system group completed...'
GO


--
-- Rights allocation script for database
--
-- NB: This will allocate SELECT, DELETE, INSERT, UPDATE rights on views to users
--     under group, central_system in the current database.
--

PRINT 'Granting user rights to views for central_system group...'
GO

/*==================================================================================================================*/
/*                                                                                                                  */
/* Grant SELECT, DELETE, INSERT, UPDATE on all views to users under central_system group in a Database              */
/*                                                                                                                  */
/*==================================================================================================================*/


if object_id('spDBAGrantLoginRights') is not null
  drop procedure spDBAGrantLoginRights
go

create procedure spDBAGrantLoginRights
@inLoginName varchar(20)
as
  set nocount on
  declare @txSQL varchar(255)

  declare csrTables cursor for
  select 'GRANT SELECT,DELETE,INSERT,UPDATE ON ' + SUSE.name + '.' + SOBJ.name + ' TO ' + @inLoginName
	from sysobjects SOBJ,
         sysusers SUSE
   where SUSE.uid = SOBJ.uid
     and SOBJ.xtype = 'V'
   order by 1

  open csrTables
  fetch next from csrTables into @txSQL
  while @@fetch_status = 0
  begin
    PRINT @txSQL
    exec (@txSQL)
    fetch next from csrTables into @txSQL
  end
  close csrTables
  deallocate csrTables
  set nocount off
go


create procedure spDBAGrantRights
as
  set nocount on
  declare @txLogin varchar(20)
  declare csrLogins cursor for
    select name from sysusers where name = 'central_system'

  open csrLogins
  fetch next from csrLogins into @txLogin
  while @@fetch_status = 0
  begin
    exec spDBAGrantLoginRights @txLogin
    fetch next from csrLogins into @txLogin
  end
  close csrLogins
  deallocate csrLogins
  set nocount off
go


if object_id('spDBAGrantRights') is not null
  exec spDBAGrantRights
go


if object_id('spDBAGrantRights') is not null
  drop procedure spDBAGrantRights
go

if object_id('spDBAGrantLoginRights') is not null
  drop procedure spDBAGrantLoginRights
go


PRINT 'VIEW: Rights grant to central_system group completed...'
GO


--
-- Rights allocation script for database
--

PRINT 'Granting user rights to affected Functions for central_system group...'
GO

/*===============================================================================*/
/*                                                                               */
/* Grant EXEC for Functions to users under central_system group in a Database    */
/*                                                                               */
/*===============================================================================*/


if object_id('spDBAGrantLoginRights') is not null
  drop procedure spDBAGrantLoginRights
go

create procedure spDBAGrantLoginRights
@inLoginName varchar(20)
as
  set nocount on
  declare @txSQL varchar(255)

  declare csrTables cursor for
  select 'GRANT EXEC ON ' + SUSE.name + '.' + SOBJ.name + ' TO ' + @inLoginName
    from sysobjects SOBJ,
         sysusers SUSE
   where SUSE.uid = SOBJ.uid
     and SOBJ.xtype = 'FN'
   order by 1

  open csrTables
  fetch next from csrTables into @txSQL
  while @@fetch_status = 0
  begin
    PRINT @txSQL
    exec (@txSQL)
    fetch next from csrTables into @txSQL
  end
  close csrTables
  deallocate csrTables
  set nocount off
go


create procedure spDBAGrantRights
as
  set nocount on
  declare @txLogin varchar(20)
  declare csrLogins cursor for
    select name from sysusers where name = 'central_system'

  open csrLogins
  fetch next from csrLogins into @txLogin
  while @@fetch_status = 0
  begin
    exec spDBAGrantLoginRights @txLogin
    fetch next from csrLogins into @txLogin
  end
  close csrLogins
  deallocate csrLogins
  set nocount off
go


if object_id('spDBAGrantRights') is not null
  exec spDBAGrantRights
go


if object_id('spDBAGrantRights') is not null
  drop procedure spDBAGrantRights
go

if object_id('spDBAGrantLoginRights') is not null
  drop procedure spDBAGrantLoginRights
go


PRINT 'Functions: Rights grant to central_system group completed...'
GO


--
-- Rights allocation script for database
--

PRINT 'Granting user rights to affected SPs for central_system group...'
GO

/*===============================================================================*/
/*                                                                               */
/* Grant EXEC for SPs to users under central_system group in a Database          */
/*                                                                               */
/*===============================================================================*/


if object_id('spDBAGrantLoginRights') is not null
  drop procedure spDBAGrantLoginRights
go

create procedure spDBAGrantLoginRights
@inLoginName varchar(20)
as
  set nocount on
  declare @txSQL varchar(255)

  declare csrTables cursor for
  select 'GRANT EXEC ON ' + SUSE.name + '.' + SOBJ.name + ' TO ' + @inLoginName
    from sysobjects SOBJ,
         sysusers SUSE
   where SUSE.uid = SOBJ.uid
     and SOBJ.xtype = 'P'
   order by 1

  open csrTables
  fetch next from csrTables into @txSQL
  while @@fetch_status = 0
  begin
    PRINT @txSQL
    exec (@txSQL)
    fetch next from csrTables into @txSQL
  end
  close csrTables
  deallocate csrTables
  set nocount off
go


create procedure spDBAGrantRights
as
  set nocount on
  declare @txLogin varchar(20)
  declare csrLogins cursor for
    select name from sysusers where name = 'central_system'

  open csrLogins
  fetch next from csrLogins into @txLogin
  while @@fetch_status = 0
  begin
    exec spDBAGrantLoginRights @txLogin
    fetch next from csrLogins into @txLogin
  end
  close csrLogins
  deallocate csrLogins
  set nocount off
go


if object_id('spDBAGrantRights') is not null
  exec spDBAGrantRights
go


if object_id('spDBAGrantRights') is not null
  drop procedure spDBAGrantRights
go

if object_id('spDBAGrantLoginRights') is not null
  drop procedure spDBAGrantLoginRights
go


PRINT 'SPs: Rights grant to central_system group completed...'
GO
