CREATE OR REPLACE FUNCTION grantCmnttypeSource(INTEGER, INTEGER) RETURNS BOOL AS $$
DECLARE
  pCmnttypeid ALIAS FOR $1;
  pSourceid ALIAS FOR $2;
  _test INTEGER;

BEGIN

  SELECT cmnttypesource_id INTO _test
  FROM cmnttypesource
  WHERE ( (cmnttypesource_cmnttype_id=pCmnttypeid)
    AND (cmnttypesource_source_id=pSourceid) );

  IF (FOUND) THEN
    RETURN FALSE;
  END IF;

  INSERT INTO cmnttypesource
  ( cmnttypesource_cmnttype_id, cmnttypesource_source_id )
  VALUES
  ( pCmnttypeid, pSourceid );

  RETURN TRUE;

END;
$$ LANGUAGE 'plpgsql';

