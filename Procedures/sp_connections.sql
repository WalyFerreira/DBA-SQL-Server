-- ESTE SCRIPT É UTILIZADO PPARA REALIZAR UMA VALIDAÇÃO DAS CONEXÕES EM TEMPO REAL SEMPRE QUE EXECUTADA. SENDO ASSIM, O RESULT NOS TRÁS UMA RELAÇÃO DE UTILIZAÇÃO DE CPU, 
-- MEMÓRIA, QUANTIDADE DE LOCKS, SESSÕES ATIVAS, SQL TEXT, SHOW PLAN, ETC..

-- SENDO ASSIM, PARA FACILITAR A EXECUÇÃO E A ANÁLISE NO MOMENTO NECESSÁRIO, FOI CRIADO A PROC COM O NOME "SP_CONNECTIONS", SEM PRECISAR PASSAR NENHUM PARÂMETRO!

USE master
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROC IF EXISTS [dbo].[sp_connections]
GO

CREATE PROC [dbo].[sp_connections]
AS
SELECT
    RIGHT('00' + CAST(DATEDIFF(SECOND, COALESCE(B.start_time, A.login_time), GETDATE()) / 86400 AS VARCHAR), 2) + ' ' + 
    RIGHT('00' + CAST((DATEDIFF(SECOND, COALESCE(B.start_time, A.login_time), GETDATE()) / 3600) % 24 AS VARCHAR), 2) + ':' + 
    RIGHT('00' + CAST((DATEDIFF(SECOND, COALESCE(B.start_time, A.login_time), GETDATE()) / 60) % 60 AS VARCHAR), 2) + ':' + 
    RIGHT('00' + CAST(DATEDIFF(SECOND, COALESCE(B.start_time, A.login_time), GETDATE()) % 60 AS VARCHAR), 2) + '.' + 
    RIGHT('000' + CAST(DATEDIFF(SECOND, COALESCE(B.start_time, A.login_time), GETDATE()) AS VARCHAR), 3) 
    AS Duration,
    A.session_id AS session_id,
    B.command,
    TRY_CAST('<?query --' + CHAR(10) + (
        SELECT TOP 1 SUBSTRING(X.[text], B.statement_start_offset / 2 + 1, ((CASE
                                                                          WHEN B.statement_end_offset = -1 THEN (LEN(CONVERT(NVARCHAR(MAX), X.[text])) * 2)
                                                                          ELSE B.statement_end_offset
                                                                      END
                                                                     ) - B.statement_start_offset
                                                                    ) / 2 + 1
                     )
    ) + CHAR(10) + '--?>' AS XML) AS sql_text,
    TRY_CAST('<?query --' + CHAR(10) + X.[text] + CHAR(10) + '--?>' AS XML) AS sql_command,
    A.login_name,
    '(' + CAST(COALESCE(E.wait_duration_ms, B.wait_time) AS VARCHAR(20)) + 'ms)' + COALESCE(E.wait_type, B.wait_type) + COALESCE((CASE 
        WHEN COALESCE(E.wait_type, B.wait_type) LIKE 'PAGE%LATCH%' THEN ':' + DB_NAME(LEFT(E.resource_description, CHARINDEX(':', E.resource_description) - 1)) + ':' + SUBSTRING(E.resource_description, CHARINDEX(':', E.resource_description) + 1, 999)
        WHEN COALESCE(E.wait_type, B.wait_type) = 'OLEDB' THEN '[' + REPLACE(REPLACE(E.resource_description, ' (SPID=', ':'), ')', '') + ']'
        ELSE ''
    END), '') AS wait_info,
    FORMAT(COALESCE(B.cpu_time, 0), '###,###,###,###,###,###,###,##0') AS CPU,
    FORMAT(COALESCE(F.tempdb_allocations, 0), '###,###,###,###,###,###,###,##0') AS tempdb_allocations,
    FORMAT(COALESCE((CASE WHEN F.tempdb_allocations > F.tempdb_current THEN F.tempdb_allocations - F.tempdb_current ELSE 0 END), 0), '###,###,###,###,###,###,###,##0') AS tempdb_current,
    FORMAT(COALESCE(B.logical_reads, 0), '###,###,###,###,###,###,###,##0') AS reads,
    FORMAT(COALESCE(B.writes, 0), '###,###,###,###,###,###,###,##0') AS writes,
    FORMAT(COALESCE(B.reads, 0), '###,###,###,###,###,###,###,##0') AS physical_reads,
    FORMAT(COALESCE(B.granted_query_memory, 0), '###,###,###,###,###,###,###,##0') AS used_memory,
    NULLIF(B.blocking_session_id, 0) AS blocking_session_id,
    COALESCE(G.blocked_session_count, 0) AS blocked_session_count,
    'KILL ' + CAST(A.session_id AS VARCHAR(10)) AS kill_command,
    (CASE 
        WHEN B.[deadlock_priority] <= -5 THEN 'Low'
        WHEN B.[deadlock_priority] > -5 AND B.[deadlock_priority] < 5 AND B.[deadlock_priority] < 5 THEN 'Normal'
        WHEN B.[deadlock_priority] >= 5 THEN 'High'
    END) + ' (' + CAST(B.[deadlock_priority] AS VARCHAR(3)) + ')' AS [deadlock_priority],
    B.row_count,
    COALESCE(A.open_transaction_count, 0) AS open_tran_count,
    (CASE B.transaction_isolation_level
        WHEN 0 THEN 'Unspecified' 
        WHEN 1 THEN 'ReadUncommitted' 
        WHEN 2 THEN 'ReadCommitted' 
        WHEN 3 THEN 'Repeatable' 
        WHEN 4 THEN 'Serializable' 
        WHEN 5 THEN 'Snapshot'
    END) AS transaction_isolation_level,
    A.[status],
    NULLIF(B.percent_complete, 0) AS percent_complete,
    A.[host_name],
    COALESCE(DB_NAME(CAST(B.database_id AS VARCHAR)), 'master') AS [database_name],
    (CASE WHEN D.name IS NOT NULL THEN 'SQLAgent - TSQL Job (' + D.[name] + ' - ' + SUBSTRING(A.[program_name], 67, LEN(A.[program_name]) - 67) +  ')' ELSE A.[program_name] END) AS [program_name],
    H.[name] AS resource_governor_group,
    COALESCE(B.start_time, A.last_request_end_time) AS start_time,
    A.login_time,
    COALESCE(B.request_id, 0) AS request_id,
    W.query_plan
FROM
    sys.dm_exec_sessions AS A WITH (NOLOCK)
    LEFT JOIN sys.dm_exec_requests AS B WITH (NOLOCK) ON A.session_id = B.session_id
    JOIN sys.dm_exec_connections AS C WITH (NOLOCK) ON A.session_id = C.session_id AND A.endpoint_id = C.endpoint_id
    LEFT JOIN msdb.dbo.sysjobs AS D ON RIGHT(D.job_id, 10) = RIGHT(SUBSTRING(A.[program_name], 30, 34), 10)
    LEFT JOIN (
        SELECT
            session_id, 
            wait_type,
            wait_duration_ms,
            resource_description,
            ROW_NUMBER() OVER(PARTITION BY session_id ORDER BY (CASE WHEN wait_type LIKE 'PAGE%LATCH%' THEN 0 ELSE 1 END), wait_duration_ms) AS Ranking
        FROM 
            sys.dm_os_waiting_tasks
    ) E ON A.session_id = E.session_id AND E.Ranking = 1
    LEFT JOIN (
        SELECT
            session_id,
            request_id,
            SUM(internal_objects_alloc_page_count + user_objects_alloc_page_count) AS tempdb_allocations,
            SUM(internal_objects_dealloc_page_count + user_objects_dealloc_page_count) AS tempdb_current
        FROM
            sys.dm_db_task_space_usage
        GROUP BY
            session_id,
            request_id
    ) F ON B.session_id = F.session_id AND B.request_id = F.request_id
    LEFT JOIN (
        SELECT 
            blocking_session_id,
            COUNT(*) AS blocked_session_count
        FROM 
            sys.dm_exec_requests
        WHERE 
            blocking_session_id != 0
        GROUP BY
            blocking_session_id
    ) G ON A.session_id = G.blocking_session_id
    OUTER APPLY sys.dm_exec_sql_text(COALESCE(B.[sql_handle], C.most_recent_sql_handle)) AS X
    OUTER APPLY sys.dm_exec_query_plan(B.plan_handle) AS W
    LEFT JOIN sys.dm_resource_governor_workload_groups H ON A.group_id = H.group_id
WHERE
    A.session_id > 50
    AND A.session_id <> @@SPID
    AND (A.[status] != 'sleeping' OR (A.[status] = 'sleeping' AND A.open_transaction_count > 0))


------------------------------------------------------------------------------------------------------------

validar proc

DECLARE @NRPROP VARCHAR(9) = '520883855'              
              
DECLARE @CPF VARCHAR(15) 

SELECT @CPF = (
	SELECT REPLACE(REPLACE(PPCGC,'-',''),'.','')
	FROM PROPOSTAPANCP..CPROP WITH (NOLOCK) 
	WHERE PPNRPROP = @NRPROP)  

IF (
	SELECT COUNT(*) QNTD 
	FROM CDCPANCP..COPER (NOLOCK) O 
	WHERE O.OPCGCBNF = @CPF AND 
		  O.OPDTLIQ IS NULL AND 
		  O.OPCODPROD = '000001'
) >= 5   

	PRINT 0 
	
IF EXISTS (
	SELECT 1 
	FROM PROPOSTAPANCP..CPROP (NOLOCK) P 
	INNER JOIN PROPOSTAPANCP..CMOVP (NOLOCK) M 
		ON P.PPNRPROP = M.MPNRPROP   
	WHERE REPLACE(REPLACE(PPCGC,'-',''),'.','') = @CPF AND 
		  M.MPSIT NOT IN ('REP', 'INT', 'CAN') AND 
		  P.PPNRPROP <> @NRPROP AND 
		  P.PPCODPRD = '000001'

		 
)   

	PRINT 0   
 

IF EXISTS (
	SELECT 1 
	FROM CDCPANCP..COPER (NOLOCK) O 
	WHERE O.OPCGCBNF = @CPF AND 
		  O.OPDTLIQ IS NULL AND 
		  O.OPCODPROD = '000001' AND 
		  OPNROPER <> @NRPROP AND 
		  OPDTCAD BETWEEN DATEADD(MINUTE,-2,CONVERT(SMALLDATETIME,GETDATE())) AND CONVERT(SMALLDATETIME,GETDATE())
)
		 
	PRINT 0
	
PRINT 1

----------------------------------------------------------------------------------------------------------------------------------

Para melhorar a performance da sua procedure, há algumas mudanças que você pode considerar:

Evitar funções em colunas de filtro ou join: Funções como REPLACE podem tornar os índices ineficazes. Tente armazenar o valor sem formatação na tabela ou use uma coluna calculada indexada.

Evitar subconsultas no SELECT: Subconsultas no SELECT podem ser custosas. Se possível, mova a lógica da subconsulta para um JOIN ou uma CTE (Common Table Expression).

Evitar NOLOCK: O uso de NOLOCK pode resultar em leituras sujas (read uncommitted). Considere se isso é realmente necessário para sua lógica de negócios e, se possível, use isolamento de transação adequado.

Rever índices: Verifique se os índices existentes estão sendo usados efetivamente pelas consultas. Às vezes, a criação de índices compostos ou a adição de índices incluídos pode melhorar a performance.

Evitar operadores de função na cláusula WHERE: Evite usar funções em colunas da cláusula WHERE, pois isso pode impedir o uso de índices. Tente armazenar valores formatados e usá-los diretamente nas consultas.

Rever a necessidade de PRINT: Se a finalidade dos PRINT é apenas para fins de debug ou monitoramento, considere remover ou comentar essas instruções em produção para evitar a sobrecarga desnecessária.

Aqui está uma versão modificada da sua procedure com algumas dessas sugestões:

sql
Copy code
DECLARE @NRPROP VARCHAR(9) = '520883855'              
DECLARE @CPF VARCHAR(15)

SELECT @CPF = REPLACE(REPLACE(PPCGC,'-',''),'.','')
FROM PROPOSTAPANCP..CPROP WITH (NOLOCK) 
WHERE PPNRPROP = @NRPROP

IF (
    SELECT COUNT(*) 
    FROM CDCPANCP..COPER O WITH (NOLOCK)
    WHERE O.OPCGCBNF = @CPF AND 
          O.OPDTLIQ IS NULL AND 
          O.OPCODPROD = '000001'
) >= 5   
    PRINT 0 
ELSE IF EXISTS (
    SELECT 1 
    FROM PROPOSTAPANCP..CPROP P WITH (NOLOCK)
    INNER JOIN PROPOSTAPANCP..CMOVP M WITH (NOLOCK) ON P.PPNRPROP = M.MPNRPROP   
    WHERE REPLACE(REPLACE(PPCGC,'-',''),'.','') = @CPF AND 
          M.MPSIT NOT IN ('REP', 'INT', 'CAN') AND 
          P.PPNRPROP <> @NRPROP AND 
          P.PPCODPRD = '000001'
)
    PRINT 0   
ELSE IF EXISTS (
    SELECT 1 
    FROM CDCPANCP..COPER O WITH (NOLOCK)
    WHERE O.OPCGCBNF = @CPF AND 
          O.OPDTLIQ IS NULL AND 
          O.OPCODPROD = '000001' AND 
          OPNROPER <> @NRPROP AND 
          OPDTCAD BETWEEN DATEADD(MINUTE,-2,CONVERT(SMALLDATETIME,GETDATE())) AND CONVERT(SMALLDATETIME,GETDATE())
)
    PRINT 0
ELSE
    PRINT 1

Tenha em mente que a melhoria real na performance pode variar dependendo do volume de dados e da estrutura do seu banco de dados. Recomenda-se testar as alterações em um ambiente de desenvolvimento antes de implementá-las em produção.
