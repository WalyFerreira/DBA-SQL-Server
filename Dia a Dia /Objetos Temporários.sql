use tempdb
go

-- Get current temporary objects date of creation and size 
SELECT DISTINCT obj.name AS ObjectName
	,obj.type_desc AS ObjectType
	,obj.object_id AS ObjectId
	,obj.principal_id AS PrincipalId
	,obj.schema_id AS SchemaId
	,obj.parent_object_id AS ParentId
	,stat.row_count AS RowCountStat
	,stat.used_page_count * 8 AS UsedSizeKB
	,stat.reserved_page_count * 8 AS RevervedSizeKB
	,obj.create_date AS CreatedDate
	,obj.modify_date AS ModifiedDate
FROM tempdb.sys.partitions AS part WITH (NOLOCK)
INNER JOIN tempdb.sys.dm_db_partition_stats AS stat WITH (NOLOCK) ON part.partition_id = stat.partition_id
	AND part.partition_number = stat.partition_number
INNER JOIN tempdb.sys.tables AS tbl WITH (NOLOCK) ON stat.object_id = tbl.object_id
LEFT JOIN tempdb.sys.objects AS obj WITH (NOLOCK) ON tbl.name = obj.name
WHERE obj.name in ('##CCCRE_BTG', '##OPERS_BTG')
ORDER BY CreatedDate ASC;
