CREATE OR REPLACE FUNCTION currToBase(pCurrId INTEGER, pValue xmoney, pDate DATE) RETURNS xmoney AS $$
-- Copyright (c) 1999-2012 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
  SELECT currToCurr($1, baseCurrId(), $2, $3);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION currToBase(pCurrId INTEGER, pValue xcost, pDate DATE) RETURNS xcost AS $$
-- Copyright (c) 1999-2012 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
  SELECT currToCurr($1, baseCurrId(), $2, $3);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION currToBase(pCurrId INTEGER, pValue xpurchp, pDate DATE) RETURNS xpurchp AS $$
-- Copyright (c) 1999-2012 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
  SELECT currToCurr($1, baseCurrId(), $2, $3);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION currToBase(pCurrId INTEGER, pValue xsalep, pDate DATE) RETURNS xsalep AS $$
-- Copyright (c) 1999-2012 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
  SELECT currToCurr($1, baseCurrId(), $2, $3);
$$ LANGUAGE SQL STABLE;
