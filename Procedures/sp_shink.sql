USE master
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROC IF EXISTS [dbo].[sp_shink]
GO

CREATE PROC [dbo].[sp_shink]
AS

	DECLARE

	@SqlStatement nvarchar (MAX)
        ,@DatabaseName sysname
        ,@database_id INT
        ,@fileid int
        ,@shirink_folga int
        ,@shirink_filtro int;

	set @shirink_folga = 1000;
	set @shirink_filtro = (@shirink_folga + 100);

	IF OBJECT_ID (N'tempdb..#DatabaseSpace') IS NOT NULL
        DROP TABLE #DatabaseSpace;

	CREATE TABLE #DatabaseSpace(
       DATABASE_NAME  sysname
        ,LOGICAL_NAME sysname
        ,FILE_SIZE_MB decimal (12 , 2)
        ,FILE_USED_MB decimal (12 , 2)
        ,FILE_FREE_MB decimal (12 , 2)
        ,FILE_NAME            sysname
        ,GROWTH INT
        ,DRIVE VARCHAR (30 )
        ,DRIVE_LOGICAL_NAME VARCHAR (MAX )
        ,DRIVE_FREE_MB DECIMAL (10 , 1)
        ,DRIVE_TOTAL_MB DECIMAL (10 , 1)
        );
		
	DECLARE DatabaseList CURSOR LOCAL FAST_FORWARD FOR
        select
               db . name
               ,database_id
               ,fileid
        from
               sys.sysaltfiles
        inner join
                      sys.databases db
                            on
                                   dbid = db. database_id
                                                 and
                                                                     state_desc = 'ONLINE'
              where
                     1 = 1 -- and sysaltfiles.name = 'LogParametroXXXXXXXXX1'

	OPEN DatabaseList;

	WHILE 1 = 1
	BEGIN
        FETCH NEXT FROM DatabaseList  INTO @DatabaseName, @database_id, @fileid ;
        IF @@FETCH_STATUS = -1 BREAK ;
        SET @SqlStatement = N'USE '
               + QUOTENAME (@DatabaseName )
               + CHAR (13)+ CHAR( 10)
               + N'INSERT INTO #DatabaseSpace
       SELECT DISTINCT
              [DATABASE_NAME] = DB_NAME()
              ,[LOGICAL_NAME] = f.name
              ,[FILE_SIZE_MB] = CONVERT(decimal(12,2),round(f.size/128.000,2))
              ,[FILE_USED_MB] = CONVERT(decimal(12,2),round(fileproperty(f.name,''SpaceUsed'')/128.000,2))
              ,[FILE_FREE_MB] = CONVERT(decimal(12,2),round((f.size-fileproperty(f.name,''SpaceUsed''))/128.000,2))
              ,[FILENAME] = f.name
              ,[GROWTH] =  case when growth > 0 then 1 else  0  end
              ,[DRIVE]
              ,[DRIVE_LOGICAL_NAME]
        ,[DRIVE_FREE_MB]
        ,[DRIVE_TOTAL_MB]
       FROM sys.database_files f
              INNER JOIN
                      (
                           SELECT  DISTINCT
                                                 dovs .logical_volume_name AS DRIVE_LOGICAL_NAME,
                                                dovs .volume_mount_point AS DRIVE,
                                                cast(CONVERT (INT , dovs . available_bytes /1048576.0) as decimal(10 ,2)) AS DRIVE_FREE_MB ,
                                                cast(CONVERT (INT ,( dovs . total_bytes )/1048576.0) as decimal(10 ,2))      DRIVE_TOTAL_MB
                           FROM
                                         sys.master_files mf
                                                CROSS APPLY
                                                               sys.dm_os_volume_stats('+ cast (@database_id as varchar ( 10 )) + ', ' +    cast(@fileid as varchar (10 )) + ' ) dovs
             ) disco      
                on
                                  1 =1
       where file_id = ' + cast(@fileid as varchar (10 )) + ';'
        execute(@SqlStatement );
	END
	CLOSE DatabaseList ;
	DEALLOCATE DatabaseList ;
	SELECT
             DRIVE
        ,FILE_TOTAL_MB = sum ( FILE_SIZE_MB )
        ,FILE_USED_MB = sum ( FILE_USED_MB )
        ,FILE_FREE_MB = sum ( FILE_FREE_MB )
        ,[FILE % USED] = (( sum ( FILE_USED_MB ) + 1 ) / ( sum ( FILE_SIZE_MB ) + 1 )) * 100
        ,DRIVE_TOTAL_MB = MAX ( DRIVE_TOTAL_MB )
        ,DRIVE_USED_MB = MAX ( DRIVE_TOTAL_MB ) - MAX ( DRIVE_FREE_MB )
        ,[DRIVE % USED] = ((( MAX ( DRIVE_TOTAL_MB ) + 1 ) - MAX ( DRIVE_FREE_MB ))   / MAX ( DRIVE_TOTAL_MB )) * 100
             ,SHIRINK_FILES =      sum ( case when FILE_FREE_MB > @shirink_filtro then 1 else 0 end)     
        ,[SHIRINK_MB] =      SUM ( case when FILE_FREE_MB > @shirink_filtro then FILE_FREE_MB + @shirink_folga else 0 end )
              ,[DRIVE_FREE_MB] = MAX ( DRIVE_FREE_MB )
        ,[SHIRINK % USED] =
                      ((
                            MAX(DRIVE_TOTAL_MB ) - (
                                                                      MAX(DRIVE_FREE_MB ) +   
                                                                      sum(case when FILE_FREE_MB > @shirink_filtro then      FILE_FREE_MB -  @shirink_folga else 0 end )
                                                                      )
                      )  /        MAX( DRIVE_TOTAL_MB)) * 100
        ,GROWTH = SUM( GROWTH)
	FROM
       #DatabaseSpace
	group by
       DRIVE
	order by
       DRIVE_FREE_MB,[DRIVE % USED] 

	SELECT
       DRIVE ,
       DATABASE_NAME , 
       FILE_SIZE_MB  ,
       FILE_FREE_MB = FILE_FREE_MB + @shirink_folga ,
       [SHIRINK] = 'USE [' + DATABASE_NAME + ']' + '
                           ' + 'GO ' + '
                           ' + 'DBCC SHRINKFILE (' + '''' +  LOGICAL_NAME + '''' + ',' + CAST( cast ( FILE_USED_MB + @shirink_folga as int ) AS VARCHAR ( 99 )) + ')' ,
       [SHIRINK_WHILE] =
                            'USE [' + DATABASE_NAME + ']' + '
                           ' + 'GO ' + '
                           declare @LIMIT INT
                           declare @ATUAL INT
                           DECLARE @LIMPEZA INT
                           DECLARE @DATAFILE VARCHAR (255)
                           SET @ATUAL =' + cast(FILE_SIZE_MB as varchar (255)) + '
                           SET @LIMIT =  ' + CAST(cast (FILE_USED_MB + @shirink_folga as int ) AS VARCHAR (99)) + '
                           SET @LIMPEZA = 5000
                           SET @DATAFILE = ' + '''' +    LOGICAL_NAME + '''' +
                            '
                           while (@LIMIT + @LIMPEZA) < @ATUAL
                           BEGIN       
                           SET @ATUAL = (@ATUAL - @LIMPEZA)     
                           DBCC SHRINKFILE (@DATAFILE, @ATUAL)
                           END'
						   
	FROM
        #DatabaseSpace
	WHERE
      FILE_FREE_MB > @shirink_filtro
	ORDER BY DRIVE, FILE_FREE_MB desc
