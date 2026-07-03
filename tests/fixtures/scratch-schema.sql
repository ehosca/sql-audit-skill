/* =============================================================================
   sql-audit regression fixture
   -----------------------------------------------------------------------------
   Builds an isolated SqlAuditTest database whose objects deliberately trip a
   known set of Celko rules. Run queries/audit.sql against SqlAuditTest and
   compare to tests/README.md ("Expected findings").

   Setup:    sqlcmd -S <srv> -E -C -N -i tests/fixtures/scratch-schema.sql
   Audit:    sqlcmd -S <srv> -d SqlAuditTest -E -C -N \
                    -i skills/sql-audit/queries/audit.sql -s "|" -W -h -1 -w 65535
   Teardown: sqlcmd -S <srv> -E -C -N -Q "ALTER DATABASE SqlAuditTest SET SINGLE_USER
                    WITH ROLLBACK IMMEDIATE; DROP DATABASE SqlAuditTest;"
   ============================================================================= */
SET NOCOUNT ON;
IF DB_ID('SqlAuditTest') IS NOT NULL
BEGIN
    ALTER DATABASE SqlAuditTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SqlAuditTest;
END
GO
CREATE DATABASE SqlAuditTest;
GO
USE SqlAuditTest;
GO
-- D01: heap (no PRIMARY KEY)
CREATE TABLE dbo.bad_heap (some_col int NULL);
GO
-- D03: uniqueidentifier PRIMARY KEY (non-generic name, not identity)
CREATE TABLE dbo.guid_key (customer_ref uniqueidentifier NOT NULL PRIMARY KEY);
GO
-- D04: FLOAT column (row_id PK avoids D01; row_id not in id/pk/key so no N07)
CREATE TABLE dbo.float_col_tbl (row_id int NOT NULL PRIMARY KEY, measure_amt float NULL);
GO
-- N07: generic 'id' PRIMARY KEY
CREATE TABLE dbo.generic_id (id int NOT NULL PRIMARY KEY);
GO
-- V01: SELECT * in a view
CREATE VIEW dbo.v_select_star AS SELECT * FROM dbo.bad_heap;
GO
-- C03: legacy *= in module text. Real *= no longer compiles on modern engines, so it
--      lives in a comment - exactly the heuristic path C03 documents (review before reporting).
CREATE PROCEDURE dbo.legacy_join_proc AS
    SELECT some_col FROM dbo.bad_heap; /* old style: a.x *= b.y */
GO
