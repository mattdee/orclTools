EXEC DBMS_STATS.gather_schema_stats('MATT');



CREATE OR REPLACE PROCEDURE gather_stats (
  p_owner            IN VARCHAR2  DEFAULT USER,
  p_options          IN VARCHAR2  DEFAULT 'GATHER',
  p_estimate_percent IN NUMBER    DEFAULT DBMS_STATS.AUTO_SAMPLE_SIZE,
  p_degree           IN NUMBER    DEFAULT NULL,                 -- NULL = AUTO_DEGREE
  p_cascade          IN BOOLEAN   DEFAULT TRUE,
  p_no_invalidate    IN BOOLEAN   DEFAULT DBMS_STATS.AUTO_INVALIDATE
) AUTHID DEFINER
IS
BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS(
    ownname          => p_owner,
    options          => p_options,
    estimate_percent => p_estimate_percent,
    degree           => p_degree,
    cascade          => p_cascade,
    no_invalidate    => p_no_invalidate
  );
END;
/




