-- Migração

-- Este conteúdo aborda uma experiência de migração realizada em ambiente de trabalho;

-- A necessidade desta migração veio através da obsolecência do Windows Server, onde foi criada uma EC2 atualizada;

-- Desta forma, foi necessário uma migração do SQL Server e aproveitamos essa janela para atualização de versão do SQL Server 2014 para o SQL Server 2019, 
-- e para que isso pudesse ocorrer de maneira transparente e efetiva, utilizei do recurso backup/restore,
-- tendo em vista que esta migração serviria também para uma melhor organização dos datafiles em crescimento em discos organizados e nomeados;

-- Tendo em vista que toda migração envolverá diversas questões de Infraestrutura, será abordado somente os scripts que foram utilizado a nível de banco de dados.

-- Passo 01
-- Neste passo acessamos o ambiente "antigo" (nomearemos aqui como EC2_antigo) e para que fosse feito o backup full de todas as databases, utilizaremos o seguinte script dinâmico:
  
    DECLARE @BackupPath NVARCHAR(255)
    SET @BackupPath = 'V:\BKP\SQLWV\FULL\' -- Substitua pelo caminho desejado para realização do bkp;
    
    DECLARE @CurrentDate NVARCHAR(20)
    SET @CurrentDate = CONVERT(NVARCHAR(20), GETDATE(), 112)
    
    DECLARE @DatabaseName NVARCHAR(255)
    DECLARE DatabaseCursor CURSOR FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4 and database_state = 'ONLINE' -- Exclui bases de sistema e bases que possívelmente estão OFFLINE
    ORDER BY name
    
    OPEN DatabaseCursor
    
    FETCH NEXT FROM DatabaseCursor INTO @DatabaseName
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @BackupName NVARCHAR(255)
        SET @BackupName = @BackupPath + @DatabaseName + '_' + @CurrentDate + '_Full.bak'
    
        BACKUP DATABASE @DatabaseName TO DISK = @BackupName WITH FORMAT, INIT, COMPRESSION, STATS = 10
    
        FETCH NEXT FROM DatabaseCursor INTO @DatabaseName
    END
    
    CLOSE DatabaseCursor
    DEALLOCATE DatabaseCursor

-- Passo 02 (PARTE 1)
-- Após o backup finalizado com sucesso, acessaremos o ambiente "novo" (nomearemos aqui como EC2_novo) e iniciamos o processo de restore.
-- OBSERVAÇÃO: como haverá um tempo até que o novo ambiente esteja pronto, colocaremos o restore full em modo NORECOVERY, para que no futuro seja restaurado um backup diff em modo RECOVERY:
  
    -- Defina as variáveis
    DECLARE @DatabaseName NVARCHAR(100) = 'NOME_DATABASE' -- Nome da base de dados a ser restaurada;
    DECLARE @BackupFilePath NVARCHAR(1000) = 'V:\BKP\SQLWV\FULL\NOME_DATABASE_Full.bak' -- Caminho e nome onde se encontra o bkp full;
    DECLARE @DataFileDest NVARCHAR(1000) = 'M:\DADOS01\' -- Caminho onde haverá o crescimento do datafile de dados;
    DECLARE @LogFileDest NVARCHAR(1000) = 'M:\LOGS01\' -- Caminho onde haverá o crescimento do datafile de log;
    DECLARE @MoveDataFiles NVARCHAR(MAX) = ''
    DECLARE @MoveLogFile NVARCHAR(MAX) = ''
    
    -- Obtenha a lista de arquivos do backup usando RESTORE FILELISTONLY
    DECLARE @FileListTable TABLE
    (
        LogicalName NVARCHAR(500),
        PhysicalName NVARCHAR(1000),
        Type CHAR(1),
        FileGroupName NVARCHAR(100),
        Size bigint,
        MaxSize bigint,
        FileID BIGINT,
        CreateLSN numeric(25,0),
        DropLSN numeric(25,0),
        UniqueID UNIQUEIDENTIFIER,
        ReadOnlyLSN numeric(25,0),
        ReadWriteLSN numeric(25,0),
        BackupSizeInBytes BIGINT,
        SourceBlockSize bigint,
        FileGroupID bigint,
        LogGroupGUID UNIQUEIDENTIFIER,
        DifferentialBaseLSN numeric(25,0),
        DifferentialBaseGUID UNIQUEIDENTIFIER,
        IsReadOnly BIT,
        IsPresent BIT,
        TDEThumbprint VARBINARY(32),
        SnapshotUrl nvarchar(360)
    )
    
    INSERT INTO @FileListTable
    EXEC('RESTORE FILELISTONLY FROM DISK = ''' + @BackupFilePath + '''')
    
    -- Construa a cláusula MOVE para os arquivos de dados
    SELECT @MoveDataFiles = @MoveDataFiles + 
        ',' + LogicalName + ''' TO ''' + @DataFileDest + SUBSTRING(PhysicalName, CHARINDEX('\', PhysicalName, 7), LEN(PhysicalName)) + ''''
    FROM @FileListTable
    WHERE Type = 'D'
    
    -- Construa a cláusula MOVE para os arquivos de log
    SELECT @MoveLogFile = @MoveLogFile + 
        ',' + LogicalName + ''' TO ''' + @LogFileDest + SUBSTRING(PhysicalName, CHARINDEX('\', PhysicalName, 7), LEN(PhysicalName)) + ''''
    FROM @FileListTable
    WHERE Type = 'L'
    
    -- Remova a vírgula inicial das cláusulas MOVE, se existirem
    SET @MoveDataFiles = CASE WHEN LEN(@MoveDataFiles) > 0 THEN RIGHT(@MoveDataFiles, LEN(@MoveDataFiles) - 1) ELSE '' END
    SET @MoveLogFile = CASE WHEN LEN(@MoveLogFile) > 0 THEN RIGHT(@MoveLogFile, LEN(@MoveLogFile) - 1) ELSE '' END
    
    -- Execute o comando de restauração
    DECLARE @RestoreCommand NVARCHAR(MAX)
    SET @RestoreCommand = 
        'USE master;' +
        'RESTORE DATABASE [' + @DatabaseName + '] FROM DISK = ''' + @BackupFilePath + '''' +
        ' WITH MOVE ''' + @MoveDataFiles +'' + ',' +
        ' MOVE '''+ @MoveLogFile +'' + ',' +
        ' NORECOVERY, REPLACE, STATS = 10;
        GO'
    
    -- Execute o comando de restauração
    SELECT(@RestoreCommand)

-- Passo 02 (PARTE 2)
-- Apesar do script acima ser dinâmino, trazendo para nós a estrutura praticamente pronta, ela se tornou inutilizavel após o desenvolvimento de um script mais dinâmico e pronto, 
-- onde não é necessário nenhum trabalho manual para colocar as databases e o caminho desejado nos dois primeiros DECLARE.
-- O script abaixo foi criado após "sentirmos a dor" do tempo de entrega, entendendo que uma instância com mais 200 databases levaria um tempo "desnecessário" até ter todo o script de retore:

            
      
-- Passo 03

  DECLARE @BackupPath NVARCHAR(255)
  SET @BackupPath = 'V:\BKP\SQLWV\DIFF\' -- Substitua pelo caminho desejado
  
  DECLARE @CurrentDate NVARCHAR(20)
  SET @CurrentDate = CONVERT(NVARCHAR(20), GETDATE(), 112)
  
  DECLARE @DatabaseName NVARCHAR(255)
  DECLARE DatabaseCursor CURSOR FOR
  SELECT name
  FROM sys.databases
  WHERE database_id > 4 -- Exclui bancos de sistema
  
  OPEN DatabaseCursor
  
  FETCH NEXT FROM DatabaseCursor INTO @DatabaseName
  WHILE @@FETCH_STATUS = 0
  BEGIN
      DECLARE @BackupName NVARCHAR(255)
      SET @BackupName = @BackupPath + @DatabaseName + '_' + @CurrentDate + '_Diff.bak'
  
      BACKUP DATABASE @DatabaseName TO DISK = @BackupName WITH DIFFERENTIAL, COMPRESSION, STATS = 10
  
      FETCH NEXT FROM DatabaseCursor INTO @DatabaseName
  END
  
  CLOSE DatabaseCursor
  DEALLOCATE DatabaseCursor
      
-- Após todo o restore full for executado, seguiremos com o restore diff e para isso foi desenvolvido um select simples (mas efetivo) onde nós precisamos saber apenas onde está o caminho dos backups diferenciais:

select 'RESTORE DATABASE [' + name + '] FROM DISK = ' + '''G:\diff\' + name + '_20240308_Diff.bak'' WITH RECOVERY, STATS = 10;'
from sys.databases
where database_id > 4
