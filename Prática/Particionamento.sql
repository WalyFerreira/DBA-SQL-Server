use AdventureWorks2022
go

-- ADICIONANDO UM GRUPO DE ARQUIVOS PARA A MINHA DATABASE:
alter database AdventureWorks2022
add filegroup FG_01_AdventureWorks2022
go

-- ADICIONANDO UM DATAFILE .NDF AO MEU GRUPO DE ARQUIVO:
alter database AdventureWorks2022
add file
(
	name = Dat_01_AWorks,
	filename = 'V:\DADOS\SQLWV\AdventureWorks2022_01.ndf',
	size = 200MB,
	maxsize = unlimited, 
	filegrowth = 100MB
)
to filegroup FG_01_AdventureWorks2022

-- CRIANDO UMA FUN��O DE PARTI��O QUE I� CHAMAR UM RANGE DE PARTI��O ONDE SER� RESPONS�VEL POR DIVIR OS DADOS DENTRO DA TABELA:
create partition function PF_01_Range (int)
	as range left for values (200,500,1000);
go


-- OBSERVA��ES:
-- NESTE PARTICIONAMENTO EM PARTICULAR, SER� CRIADO UMA FUN��O CONTENDO APENAS UM CAMPO (PODE SER MAIS) DO TIPO INTEIRO (PODE SER DE OUTRO TIPO);
-- A DIVIS�O NESTE CASO SER� EM 3 RANGES, ONDE COME�AR� DA ESQUERDA PARA A DIREITA, OU SEJA, DO 0 EM DIANTE;
-- DESTA FORMA TEREMOS UM RANGE DE 0 � 200, OUTRO RANGE DE 201 � 500 E UM �LTIMO DE 501 � 1000. O QUE FOR ACRESCENTADO AP�S 1000, SER� LEVADO PARA UMA OUTRA PARTI��O (DEFAULT).

-- CRIANDO UM SCHEME ONDE IR� VINCULAR A MINHA FUN��O DE PARTI��O AO GRUPO DE ARQUIVOS CRIADO ANTERIORMENTE:
create partition scheme PS_01_Scheme
	as partition PF_01_Range
	to (FG_01_AdventureWorks2022,FG_01_AdventureWorks2022,FG_01_AdventureWorks2022,FG_01_AdventureWorks2022);
go

-- CRIANDO UMA TABELA PARTICIONADA QUE SER� ASSOCIADA A MINHA FUN��O DE PARTI��O, CONTENDO 2 COLUNAS SIMPLES:
create table PT_01_Table (col1 int primary key, col2 char(10))
	on PS_01_Scheme (col1);
go

-- INSERINDO DADOS NA TABELA PARTICIONADA PARA SIMULA��O DO PARTICIONAMENTO:
declare @count int
select @count = 0
while @count < 150000
	begin
		insert into PT_01_Table values (@count, cast(@count as varchar) + 'A')
		select @count = @count+1
	end

-- CONFIRMANDO A EXECU��O DE INSER��O DOS DADOS:
exec sp_spaceused PT_01_Table

-- CONFIIRMANDO SE A TABELA CRIADA EST� PARTICONADA:
select *
from sys.tables AS t
join sys.indexes AS i
	on t.[object_id] = i.[object_id]
	AND i.[type] IN (0,1)
join sys.partition_schemes ps
	on i.data_space_id = ps.data_space_id
--where t.name = 'PT_01_Table'
go

-- CONFIRMANDO OS VALORES DE LIMITE DETERMINADOS PARA A TABELA PARTICIONADA 
select	t.name AS Tablelane, 
		i.name AS IndexName, 
		p.partition_number, 
		p.partition_id, 
		i.data_space_id, 
		f.function_id, 
		f.type_desc, 
		r.boundary_id, 
		r.value
from sys.tables AS t
join sys.indexes AS i
	on t.object_id = i.object_id
join sys.partitions AS p
	on i.object_id = p.object_id and i.index_id = p. index_id 
join sys.partition_schemes AS s
	on i.data_space_id = s.data_space_id
join sys.partition_functions AS f 
	on s.function_id = f.function_id
left join sys.partition_range_values AS r
	on f.function_id = r.function_id and r.boundary_id = p.partition_number
where t.name = 'PT_01_Table' and i.type <= 1
order by p.partition_number;

-- VERIFICANDO A DISTRIBUI��O DOS DADOS DA TABELA
select	$partition.PF_01_Range(a.col1) as "N� da Parti��o",
		count(*) as "Total de Linhas"
from PT_01_Table a
group by $partition.PF_01_Range(a.col1)
order by 1
go

--drop table PT_01_Table
--drop partition scheme PS_01_Scheme
--drop partition function PF_01_Range

-- QUANDO PRECISAMOS REALIZAR ALGUM EXPURGO DE DADOS DAS PARTI��ES, N�S PODEMOS REALIZAR A CRIA��O DE UMA NOVA TABELA PARA RECEBER ESSES DADOS E EM SEGUIDA PROSSEGUIR COM O EXPURGO
-- CRIANDO UMA NOVA TABELA PARTICIONADA, COM AS MESMAS COLUNAS DA PRINCIPAL
create table PT_01_Table_Expurgo (col1 int primary key, col2 char(10))
	on PS_01_Scheme (col1);
go

-- MOVENDO A PARTI��O 4 DA TABELA PRINCIPAL PARA A TABELA DE EXPURGO
alter table PT_01_Table switch partition 4 to PT_01_Table_Expurgo partition 4

-- VERIFICANDO A DISTRIBUI��O DOS DADOS DA TABELA PRINCIPAL
select	$partition.PF_01_Range(a.col1) as "N� da Parti��o",
		count(*) as "Total de Linhas"
from PT_01_Table a
group by $partition.PF_01_Range(a.col1)
order by 1
go 

-- VERIFICANDO A DISTRIBUI��O DOS DADOS DA TABELA DE EXPURGO
select	$partition.PF_01_Range(a.col1) as "N� da Parti��o",
		count(*) as "Total de Linhas"
from PT_01_Table_Expurgo a
group by $partition.PF_01_Range(a.col1)
order by 1
go

-- REALIZANDO UM "ROLLBACK" DA PARTICI��O 4 DA TABELA DE EXPURGO PARA A TABELA PRINCIPAL
alter table PT_01_Table_Expurgo switch partition 4 to PT_01_Table partition 4

-- VERIFICANDO A DISTRIBUI��O DOS DADOS DA TABELA PRINCIPAL
select	$partition.PF_01_Range(a.col1) as "N� da Parti��o",
		count(*) as "Total de Linhas"
from PT_01_Table a
group by $partition.PF_01_Range(a.col1)
order by 1
go 

-- VERIFICANDO A DISTRIBUI��O DOS DADOS DA TABELA DE EXPURGO
select	$partition.PF_01_Range(a.col1) as "N� da Parti��o",
		count(*) as "Total de Linhas"
from PT_01_Table_Expurgo a
group by $partition.PF_01_Range(a.col1)
order by 1
go
