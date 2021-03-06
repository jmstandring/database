
CREATE OR REPLACE FUNCTION detag(TEXT) RETURNS TEXT IMMUTABLE AS $$
-- Copyright (c) 1999-2011 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pSource ALIAS FOR $1;
  _result TEXT := '';

BEGIN
  SELECT regexp_replace(pSource, E'<[^>]*>', '', 'g') INTO _result;
  RETURN _result;
END;
$$ LANGUAGE 'plpgsql';

