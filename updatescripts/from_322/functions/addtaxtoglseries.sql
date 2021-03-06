-- add tax information to a GL Series
-- return the base currency value of the GL Series records inserted
--	  NULL if there has been an error

SELECT dropIfExists ('FUNCTION', 'addTaxToGLSeries(INTEGER, INTEGER, TEXT, TEXT, TEXT, DATE, DATE, INTEGER, NUMERIC, NUMERIC, NUMERIC)');
SELECT dropIfExists ('FUNCTION', 'addTaxToGLSeries(INTEGER, INTEGER, TEXT, TEXT, TEXT, DATE, DATE, INTEGER, NUMERIC, NUMERIC, NUMERIC, TEXT)');

CREATE OR REPLACE FUNCTION addTaxToGLSeries(INTEGER, TEXT, TEXT, TEXT, INTEGER, DATE, DATE, TEXT, INTEGER, TEXT) RETURNS NUMERIC AS $$
  DECLARE
    pSequence	ALIAS FOR $1;
    pSource	ALIAS FOR $2;
    pDocType	ALIAS FOR $3;
    pDocNumber	ALIAS FOR $4;
    pCurrId     ALIAS FOR $5;
    pExchDate	ALIAS FOR $6;
    pDistDate	ALIAS FOR $7;
    pTableName	ALIAS FOR $8;
    pParentId	ALIAS FOR $9;
    pNotes	ALIAS FOR $10;

    _count	INTEGER := 0;
    _baseTax	NUMERIC := 0;
    _returnVal	NUMERIC := 0;
    _t		RECORD;
    _test	INTEGER := 0;

  BEGIN

-- This is just a fancy select statement on taxhist.
-- Because all tax records tables inherit from taxhist,
-- we can use the same select statement for all.
-- https://www.postgresql.org/docs/8.1/static/ddl-inherit.html
-- pTableName in the where clause narrows down the selection
-- to the correct sub table.

    FOR _t IN SELECT *
              FROM taxhist JOIN tax ON (tax_id = taxhist_tax_id)
                           JOIN pg_class ON (pg_class.oid = taxhist.tableoid)
              WHERE ( (taxhist_parent_id = pParentId)
                AND   (relname = pTableName) ) LOOP

      _count := _count + 1;
      _baseTax := currToBase(pCurrId, _t.taxhist_tax, pExchDate);
      IF ( (pTableName = 'cmheadtax') OR (pTableName = 'cmitemtax') ) THEN
        _baseTax := _baseTax * -1;
      END IF;
      _returnVal := _returnVal + _baseTax;
      PERFORM insertIntoGLSeries( pSequence, pSource, pDocType, pDocNumber,
                                  _t.tax_sales_accnt_id, _baseTax,
                                  pDistDate, pNotes );

    END LOOP;

    RETURN _returnVal;
  END;
$$ LANGUAGE 'plpgsql';