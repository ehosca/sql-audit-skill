/* =============================================================================
   Celko SQL Programming Style — Database Audit
   -----------------------------------------------------------------------------
   Read-only. Queries the system catalog and sys.sql_modules only.
   Emits ONE result set: (severity, rule_id, rule_name, schema_name,
                          object_name, detail)
   ordered by severity (ERROR > WARN > INFO), then rule_id.

   Run headless for clean parsing (trusted auth shown; for SQL auth use -U and pass the
   password via the SQLCMDPASSWORD env var, never -P on the command line):
     sqlcmd -S <srv> -d <db> -E -C -i audit.sql -s"|" -W -h-1

   Notes:
     * Requires VIEW DEFINITION on the target database (for sys.sql_modules).
     * Rules N06 and D07 use STRING_AGG (SQL Server 2017+). If targeting an
       older engine, comment those two blocks out.
     * Module-text rules (V01, C02, C03, C04) are heuristic and may match text
       inside comments or string literals — the skill reviews flagged modules.
   ============================================================================= */
SET NOCOUNT ON;

;WITH reserved(word) AS (
    /* Common SQL-92 / T-SQL reserved words that force quoting when used as identifiers. */
    SELECT word FROM (VALUES
        ('ALL'),('AND'),('ANY'),('AS'),('ASC'),('AUTHORIZATION'),('BACKUP'),('BEGIN'),
        ('BETWEEN'),('BREAK'),('BROWSE'),('BULK'),('BY'),('CASCADE'),('CASE'),('CHECK'),
        ('CHECKPOINT'),('CLOSE'),('CLUSTERED'),('COALESCE'),('COLLATE'),('COLUMN'),
        ('COMMIT'),('COMPUTE'),('CONSTRAINT'),('CONTAINS'),('CONTINUE'),('CONVERT'),
        ('CREATE'),('CROSS'),('CURRENT'),('CURSOR'),('DATABASE'),('DEFAULT'),('DELETE'),
        ('DENY'),('DESC'),('DISTINCT'),('DROP'),('ELSE'),('END'),('ERRLVL'),('ESCAPE'),
        ('EXCEPT'),('EXEC'),('EXECUTE'),('EXISTS'),('EXIT'),('EXTERNAL'),('FETCH'),
        ('FILE'),('FOR'),('FOREIGN'),('FREETEXT'),('FROM'),('FULL'),('FUNCTION'),
        ('GOTO'),('GRANT'),('GROUP'),('HAVING'),('IDENTITY'),('IF'),('IN'),('INDEX'),
        ('INNER'),('INSERT'),('INTERSECT'),('INTO'),('IS'),('JOIN'),('KEY'),('KILL'),
        ('LEFT'),('LIKE'),('LINENO'),('MERGE'),('NATIONAL'),('NOCHECK'),('NONCLUSTERED'),
        ('NOT'),('NULL'),('NULLIF'),('OF'),('OFF'),('ON'),('OPEN'),('OPTION'),('OR'),
        ('ORDER'),('OUTER'),('OVER'),('PERCENT'),('PIVOT'),('PLAN'),('PRIMARY'),
        ('PROCEDURE'),('PUBLIC'),('RAISERROR'),('READ'),('REFERENCES'),('REPLICATION'),
        ('RESTORE'),('RESTRICT'),('RETURN'),('REVOKE'),('RIGHT'),('ROLLBACK'),
        ('ROWCOUNT'),('RULE'),('SAVE'),('SCHEMA'),('SELECT'),('SESSION'),('SET'),
        ('SOME'),('STATISTICS'),('TABLE'),('THEN'),('TO'),('TOP'),('TRAN'),
        ('TRANSACTION'),('TRIGGER'),('TRUNCATE'),('UNION'),('UNIQUE'),('UPDATE'),
        ('USER'),('VALUES'),('VARYING'),('VIEW'),('WHEN'),('WHERE'),('WHILE'),('WITH')
    ) AS r(word)
),
findings AS (

/* ---------- N01: identifier length > 30 (SQL-92 §1.1.1) ---------- */
SELECT CAST('WARN' AS varchar(6))   AS severity,
       CAST('N01'  AS varchar(4))   AS rule_id,
       CAST('Identifier length > 30' AS varchar(60)) AS rule_name,
       s.name                       AS schema_name,
       CAST(o.name AS nvarchar(300)) AS object_name,
       CAST('object name is ' + CAST(LEN(o.name) AS varchar(5)) + ' chars' AS nvarchar(400)) AS detail
FROM sys.objects o
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND o.type IN ('U','V','P','FN','TF','IF','TR') AND LEN(o.name) > 30
UNION ALL
SELECT 'WARN','N01','Identifier length > 30', s.name,
       CAST(o.name + '.' + c.name AS nvarchar(300)),
       CAST('column name is ' + CAST(LEN(c.name) AS varchar(5)) + ' chars' AS nvarchar(400))
FROM sys.columns c
JOIN sys.objects o ON c.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND LEN(c.name) > 30

/* ---------- N02: non-standard identifier characters (§1.1.2) ---------- */
UNION ALL
SELECT 'ERROR','N02','Non-standard identifier chars', s.name,
       CAST(o.name + '.' + c.name AS nvarchar(300)),
       CAST('name has special char / leading non-letter / trailing or doubled underscore' AS nvarchar(400))
FROM sys.columns c
JOIN sys.objects o ON c.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0
  AND ( PATINDEX('%[^A-Za-z0-9_]%', c.name) > 0
     OR c.name LIKE '[^A-Za-z]%'
     OR c.name LIKE '%[_]'
     OR c.name LIKE '%[_][_]%' )
UNION ALL
SELECT 'ERROR','N02','Non-standard identifier chars', s.name,
       CAST(o.name AS nvarchar(300)),
       CAST('name has special char / leading non-letter / trailing or doubled underscore' AS nvarchar(400))
FROM sys.objects o
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND o.type IN ('U','V','P','FN','TF','IF','TR')
  AND ( PATINDEX('%[^A-Za-z0-9_]%', o.name) > 0
     OR o.name LIKE '[^A-Za-z]%'
     OR o.name LIKE '%[_]'
     OR o.name LIKE '%[_][_]%' )

/* ---------- N03: name requires quoting (reserved word / embedded space) (§1.1.3) ---------- */
UNION ALL
SELECT 'WARN','N03','Name requires quoting', s.name,
       CAST(o.name AS nvarchar(300)),
       CAST('object name is a reserved word or contains a space' AS nvarchar(400))
FROM sys.objects o
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND o.type IN ('U','V','P','FN','TF','IF','TR')
  AND ( o.name LIKE '% %' OR EXISTS (SELECT 1 FROM reserved r WHERE r.word = UPPER(o.name) COLLATE DATABASE_DEFAULT) )
UNION ALL
SELECT 'WARN','N03','Name requires quoting', s.name,
       CAST(o.name + '.' + c.name AS nvarchar(300)),
       CAST('column name is a reserved word or contains a space' AS nvarchar(400))
FROM sys.columns c
JOIN sys.objects o ON c.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0
  AND ( c.name LIKE '% %' OR EXISTS (SELECT 1 FROM reserved r WHERE r.word = UPPER(c.name) COLLATE DATABASE_DEFAULT) )

/* ---------- N04: Hungarian / descriptive prefix (§1.2.3) ---------- */
UNION ALL
SELECT 'INFO','N04','Descriptive/Hungarian prefix', s.name,
       CAST(o.name AS nvarchar(300)),
       CAST('object name uses a discouraged prefix (tbl_/vw_/sp_/usp_/fn_/udf_)' AS nvarchar(400))
FROM sys.objects o
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND o.type IN ('U','V','P','FN','TF','IF')
  AND ( o.name LIKE 'tbl[_]%' OR o.name LIKE 'tbl[A-Z]%'
     OR o.name LIKE 'vw[_]%'  OR o.name LIKE 'v[A-Z]%'
     OR o.name LIKE 'sp[_]%'  OR o.name LIKE 'usp[_]%'
     OR o.name LIKE 'fn[_]%'  OR o.name LIKE 'udf[_]%' )

/* ---------- N05: CamelCase column name (§2.1.2 / §2.1.5) ---------- */
UNION ALL
SELECT 'INFO','N05','CamelCase column name', s.name,
       CAST(o.name + '.' + c.name AS nvarchar(300)),
       CAST('column mixes case (prefer lowercase_with_underscores)' AS nvarchar(400))
FROM sys.columns c
JOIN sys.objects o ON c.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0
  AND PATINDEX('%[a-z][A-Z]%', c.name COLLATE Latin1_General_BIN) > 0

/* ---------- N06: attribute columns lacking ISO-11179 postfix (§1.2.4) ---------- */
UNION ALL
SELECT 'INFO','N06','Missing ISO-11179 postfix', s.name,
       CAST(o.name AS nvarchar(300)),
       CAST(CAST(COUNT(*) AS varchar(6)) + ' attribute column(s) without recognized postfix: '
            + LEFT(STRING_AGG(c.name COLLATE DATABASE_DEFAULT, ', '), 340) AS nvarchar(400))
FROM sys.columns c
JOIN sys.objects o ON c.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND o.type = 'U'
  AND NOT (
        c.name LIKE '%[_]id'    OR c.name LIKE '%[_]date' OR c.name LIKE '%[_]dt'
     OR c.name LIKE '%[_]nbr'   OR c.name LIKE '%[_]num'  OR c.name LIKE '%[_]name'
     OR c.name LIKE '%[_]nm'    OR c.name LIKE '%[_]code' OR c.name LIKE '%[_]cd'
     OR c.name LIKE '%[_]size'  OR c.name LIKE '%[_]tot'  OR c.name LIKE '%[_]seq'
     OR c.name LIKE '%[_]cat'   OR c.name LIKE '%[_]class' OR c.name LIKE '%[_]status' )
GROUP BY s.name, o.name

/* ---------- N07: generic 'id' primary key (§1.2.3) ---------- */
UNION ALL
SELECT 'INFO','N07','Generic ''id'' primary key', s.name,
       CAST(o.name + '.' + c.name AS nvarchar(300)),
       CAST('PK column named generically; prefer a business-meaningful key or <entity>_id' AS nvarchar(400))
FROM sys.indexes i
JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
JOIN sys.objects o ON i.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND i.is_primary_key = 1
  AND LOWER(c.name) IN ('id','pk','key')

/* ---------- D01: table has no PRIMARY KEY / heap (§3.4) ---------- */
UNION ALL
SELECT 'ERROR','D01','Table has no PRIMARY KEY', s.name,
       CAST(t.name AS nvarchar(300)),
       CAST('no primary key defined' AS nvarchar(400))
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.is_ms_shipped = 0
  AND NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = t.object_id AND i.is_primary_key = 1)

/* ---------- D02: IDENTITY used as key (§1.3.3) ---------- */
UNION ALL
SELECT 'INFO','D02','IDENTITY used as key', s.name,
       CAST(o.name + '.' + c.name AS nvarchar(300)),
       CAST('IDENTITY column is part of the PRIMARY KEY (exposed physical locator)' AS nvarchar(400))
FROM sys.identity_columns c
JOIN sys.index_columns ic ON c.object_id = ic.object_id AND c.column_id = ic.column_id
JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.objects o ON c.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND i.is_primary_key = 1

/* ---------- D03: uniqueidentifier / NEWID() primary key (§1.3.3) ---------- */
UNION ALL
SELECT 'INFO','D03','uniqueidentifier primary key', s.name,
       CAST(o.name + '.' + c.name AS nvarchar(300)),
       CAST('PK column is uniqueidentifier (exposed physical locator)' AS nvarchar(400))
FROM sys.indexes i
JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
JOIN sys.objects o ON i.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND i.is_primary_key = 1 AND ty.name = 'uniqueidentifier'

/* ---------- D04: FLOAT / REAL columns (§3.8.4) ---------- */
UNION ALL
SELECT 'ERROR','D04','FLOAT/REAL column', s.name,
       CAST(o.name + '.' + c.name AS nvarchar(300)),
       CAST('column type is ' + ty.name COLLATE DATABASE_DEFAULT + ' — prefer DECIMAL/NUMERIC to avoid rounding error' AS nvarchar(400))
FROM sys.columns c
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
JOIN sys.objects o ON c.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND ty.name IN ('float','real')

/* ---------- D05: deprecated / proprietary data types (§3.3) ---------- */
UNION ALL
SELECT 'WARN','D05','Deprecated/proprietary data type', s.name,
       CAST(o.name + '.' + c.name AS nvarchar(300)),
       CAST('column type is ' + ty.name COLLATE DATABASE_DEFAULT + ' — deprecated or proprietary' AS nvarchar(400))
FROM sys.columns c
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
JOIN sys.objects o ON c.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND ty.name IN ('text','ntext','image','money','smallmoney','sql_variant')

/* ---------- D06: system-generated (unnamed) constraints (§3.7) ---------- */
UNION ALL
SELECT 'WARN','D06','System-generated constraint name', s.name,
       CAST(OBJECT_NAME(dc.parent_object_id) + ' → ' + dc.name AS nvarchar(300)),
       CAST('DEFAULT constraint has an auto-generated name' AS nvarchar(400))
FROM sys.default_constraints dc
JOIN sys.objects o ON dc.parent_object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND dc.is_system_named = 1
UNION ALL
SELECT 'WARN','D06','System-generated constraint name', s.name,
       CAST(OBJECT_NAME(cc.parent_object_id) + ' → ' + cc.name AS nvarchar(300)),
       CAST('CHECK constraint has an auto-generated name' AS nvarchar(400))
FROM sys.check_constraints cc
JOIN sys.objects o ON cc.parent_object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND cc.is_system_named = 1
UNION ALL
SELECT 'WARN','D06','System-generated constraint name', s.name,
       CAST(OBJECT_NAME(kc.parent_object_id) + ' → ' + kc.name AS nvarchar(300)),
       CAST(kc.type_desc COLLATE DATABASE_DEFAULT + ' has an auto-generated name' AS nvarchar(400))
FROM sys.key_constraints kc
JOIN sys.objects o ON kc.parent_object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND kc.is_system_named = 1
UNION ALL
SELECT 'WARN','D06','System-generated constraint name', s.name,
       CAST(OBJECT_NAME(fk.parent_object_id) + ' → ' + fk.name AS nvarchar(300)),
       CAST('FOREIGN KEY has an auto-generated name' AS nvarchar(400))
FROM sys.foreign_keys fk
JOIN sys.objects o ON fk.parent_object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND fk.is_system_named = 1

/* ---------- D07: numeric columns without a range CHECK (§3.8.1) ---------- */
UNION ALL
SELECT 'INFO','D07','Numeric column without range CHECK', s.name,
       CAST(o.name AS nvarchar(300)),
       CAST(CAST(COUNT(*) AS varchar(6)) + ' numeric column(s) with no CHECK referencing them: '
            + LEFT(STRING_AGG(c.name COLLATE DATABASE_DEFAULT, ', '), 320) AS nvarchar(400))
FROM sys.columns c
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
JOIN sys.objects o ON c.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND o.type = 'U'
  AND ty.name IN ('int','bigint','smallint','tinyint','decimal','numeric')
  AND c.is_identity = 0
  AND NOT EXISTS (
        SELECT 1 FROM sys.check_constraints cc
        WHERE cc.parent_object_id = c.object_id
          AND cc.definition LIKE '%' + c.name COLLATE DATABASE_DEFAULT + '%')
GROUP BY s.name, o.name

/* ---------- V01: SELECT * in view definition (§7.1.1) ---------- */
UNION ALL
SELECT 'WARN','V01','SELECT * in view', s.name,
       CAST(o.name AS nvarchar(300)),
       CAST('view definition uses SELECT * — enumerate columns explicitly' AS nvarchar(400))
FROM sys.sql_modules m
JOIN sys.objects o ON m.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0 AND o.type = 'V'
  AND m.definition LIKE '%SELECT%*%FROM%'

/* ---------- C01: triggers exist — prefer DRI (§6.5) ---------- */
UNION ALL
SELECT 'INFO','C01','Trigger present', s.name,
       CAST(OBJECT_NAME(tr.parent_id) + ' → ' + tr.name AS nvarchar(300)),
       CAST('trigger defined — prefer declarative referential integrity where possible' AS nvarchar(400))
FROM sys.triggers tr
JOIN sys.objects o ON tr.parent_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE tr.is_ms_shipped = 0 AND tr.parent_class = 1

/* ---------- C02: optimizer hints in module text (§6.4) ---------- */
UNION ALL
SELECT 'WARN','C02','Optimizer hint in module', s.name,
       CAST(o.name AS nvarchar(300)),
       CAST('module text contains an optimizer hint (NOLOCK/FORCESEEK/INDEX/OPTION)' AS nvarchar(400))
FROM sys.sql_modules m
JOIN sys.objects o ON m.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0
  AND ( m.definition LIKE '%NOLOCK%'
     OR m.definition LIKE '%READUNCOMMITTED%'
     OR m.definition LIKE '%FORCESEEK%'
     OR m.definition LIKE '%WITH (INDEX%'
     OR m.definition LIKE '%OPTION (%' )

/* ---------- C03: legacy *= / =* outer join syntax (§6.1.1) ---------- */
UNION ALL
SELECT 'WARN','C03','Legacy outer-join syntax', s.name,
       CAST(o.name AS nvarchar(300)),
       CAST('module text contains *= or =* — use standard OUTER JOIN' AS nvarchar(400))
FROM sys.sql_modules m
JOIN sys.objects o ON m.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0
  AND ( m.definition LIKE '%*=%' OR m.definition LIKE '%=*%' )

/* ---------- C04: proprietary functions in module text (§6.1.4) ---------- */
UNION ALL
SELECT 'INFO','C04','Proprietary function in module', s.name,
       CAST(o.name AS nvarchar(300)),
       CAST('module uses GETDATE()/ISNULL() — prefer CURRENT_TIMESTAMP / COALESCE' AS nvarchar(400))
FROM sys.sql_modules m
JOIN sys.objects o ON m.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0
  AND ( m.definition LIKE '%GETDATE(%' OR m.definition LIKE '%ISNULL(%' )

)
SELECT severity, rule_id, rule_name, schema_name, object_name, detail
FROM findings
ORDER BY CASE severity WHEN 'ERROR' THEN 1 WHEN 'WARN' THEN 2 ELSE 3 END,
         rule_id, schema_name, object_name;
