CREATE OR REPLACE FUNCTION explodeWo(INTEGER, BOOL) RETURNS INTEGER AS $$
DECLARE
  pWoid ALIAS FOR $1;
  pExplodeChildren ALIAS FOR $2;
  resultCode INTEGER;
  newWo RECORD;
  _newwoid INTEGER;
  _p RECORD;
  _r RECORD;
  _bbom BOOLEAN;

BEGIN
-- Find out if Breeder BOMs are enabled
  SELECT metric_value='t' INTO _bbom
         FROM metric
         WHERE (metric_name='BBOM');

--  Make sure that this W/O is Open
  SELECT wo_id INTO resultCode
  FROM wo
  WHERE ((wo_status='O')
   AND (wo_id=pWoid));
  IF (NOT FOUND) THEN
    RETURN -4;
  END IF;

--  Make sure that component all Component Item Sites exist
  SELECT bomitem_id INTO resultCode
  FROM wo, bomitem, itemsite
  WHERE ( (wo_itemsite_id=itemsite_id)
   AND (itemsite_item_id=bomitem_parent_item_id)
   AND (woEffectiveDate(wo_startdate) BETWEEN bomitem_effective AND (bomitem_expires - 1))
   AND (wo_id=pWoid)
   AND (bomitem_rev_id=wo_bom_rev_id)
   AND (bomitem_item_id NOT IN
        ( SELECT component.itemsite_item_id
          FROM itemsite AS component, itemsite AS parent
          WHERE ( (wo_itemsite_id=parent.itemsite_id)
           AND (parent.itemsite_item_id=bomitem_parent_item_id)
           AND (bomitem_item_id=component.itemsite_item_id)
           AND (woEffectiveDate(wo_startdate) BETWEEN bomitem_effective AND (bomitem_expires - 1))
           AND (component.itemsite_active)
           AND (component.itemsite_warehous_id=parent.itemsite_warehous_id) ) ) ) )
  LIMIT 1;
  IF (FOUND) THEN
    RETURN -2;
  END IF;

--  If the Parent Item is a Breeder, make sure that all the
--  Co-Product/By-Product Item Sites exist
  IF (_bbom) THEN

    IF ( ( SELECT (item_type='B')
           FROM wo, itemsite, item
           WHERE ( (wo_itemsite_id=itemsite_id)
            AND (itemsite_item_id=item_id)
            AND (wo_id=pWoid) ) ) ) THEN
      SELECT bbomitem_id INTO resultCode
      FROM wo, bbomitem, itemsite
      WHERE ( (wo_itemsite_id=itemsite_id)
       AND (itemsite_item_id=bbomitem_parent_item_id)
       AND (woEffectiveDate(wo_startdate) BETWEEN bbomitem_effective AND (bbomitem_expires - 1))
       AND (wo_id=pWoid)
       AND (bbomitem_item_id NOT IN
            ( SELECT component.itemsite_item_id
              FROM itemsite AS component, itemsite AS parent
              WHERE ( (wo_itemsite_id=parent.itemsite_id)
               AND (parent.itemsite_item_id=bbomitem_parent_item_id)
               AND (bbomitem_item_id=component.itemsite_item_id)
               AND (woEffectiveDate(wo_startdate) BETWEEN bbomitem_effective AND (bbomitem_expires - 1))
               AND (component.itemsite_active)
               AND (component.itemsite_warehous_id=parent.itemsite_warehous_id) ) ) ) )
      LIMIT 1;
      IF (FOUND) THEN
        RETURN -3;
      END IF;
    END IF;
  END IF;

--  Create the W/O Material Requirements
  INSERT INTO womatl
  ( womatl_wo_id, womatl_bomitem_id, womatl_wooper_id, womatl_schedatwooper,
    womatl_itemsite_id,
    womatl_duedate,
    womatl_uom_id, womatl_qtyper, womatl_scrap,
    womatl_qtyreq,
    womatl_qtyiss, womatl_qtywipscrap,
    womatl_lastissue, womatl_lastreturn, womatl_cost,
    womatl_picklist, womatl_createwo, womatl_issuemethod, womatl_notes, womatl_ref )
  SELECT wo_id, bomitem_id, bomitem_booitem_seq_id, bomitem_schedatwooper,
         cs.itemsite_id,
         CASE WHEN bomitem_schedatwooper THEN COALESCE(calcWooperStart(wo_id,bomitem_booitem_seq_id), wo_startdate)
              ELSE wo_startdate
         END,
         bomitem_uom_id, bomitem_qtyper, bomitem_scrap,
         roundQty(itemuomfractionalbyuom(bomitem_item_id, bomitem_uom_id), (bomitem_qtyper * wo_qtyord * (1 + bomitem_scrap))),
         0, 0,
         startOfTime(), startOfTime(), 0,
         item_picklist, ( (item_type='M') AND (bomitem_createwo) ), bomitem_issuemethod, bomitem_notes, bomitem_ref 
  FROM bomitem, wo, itemsite AS ps, itemsite AS cs, item
  WHERE ( (wo_itemsite_id=ps.itemsite_id)
   AND (bomitem_parent_item_id=ps.itemsite_item_id)
   AND (bomitem_item_id=cs.itemsite_item_id)
   AND (bomitem_rev_id=wo_bom_rev_id)
   AND (ps.itemsite_warehous_id=cs.itemsite_warehous_id)
   AND (cs.itemsite_item_id=item_id)
   AND (woEffectiveDate(wo_startdate) BETWEEN bomitem_effective AND (bomitem_expires - 1))
   AND (wo_id=pWoid)
       AND ((bomitem_char_id IS NULL)
       OR  EXISTS (
         SELECT charass_id
         FROM coitem,charass
         WHERE ((charass_target_type='SI')
          AND  (charass_target_id=coitem_id)
          AND  (charass_char_id=bomitem_char_id)
          AND  (charass_value=bomitem_value)
          AND  (wo_ordtype='S')
          AND  (coitem_id=wo_ordid)))) );

--  Create any required P/R's
  PERFORM createPr('W', womatl_id)
  FROM womatl, itemsite
  WHERE ((womatl_itemsite_id=itemsite_id)
   AND (itemsite_createpr)
   AND (womatl_wo_id=pWoid));

--  Update any created P/R's the have the project id as the parent WO.
  UPDATE pr SET pr_prj_id=wo_prj_id
    FROM womatl, wo
   WHERE ((wo_id=pWoid)
     AND  (womatl_wo_id=wo_id)
     AND  (pr_order_type='W')
     AND  (pr_order_id=womatl_id));

--  If the parent Item is a Breeder, create the brddist
--  records for the Co-Products and By-Products
  IF (_bbom) THEN

    INSERT INTO brddist
    ( brddist_wo_id, brddist_wo_qty, brddist_itemsite_id,
      brddist_stdqtyper, brddist_qty, brddist_posted )
    SELECT wo_id, 0, cs.itemsite_id,
           bbomitem_qtyper, 0, FALSE
    FROM wo, bbomitem,
         itemsite AS ps, itemsite AS cs, item
    WHERE ( (bbomitem_parent_item_id=ps.itemsite_item_id)
     AND (wo_itemsite_id=ps.itemsite_id)
     AND (ps.itemsite_item_id=item_id)
     AND (item_type='B')
     AND (bbomitem_item_id=cs.itemsite_item_id)
     AND (cs.itemsite_warehous_id=ps.itemsite_warehous_id)
     AND (wo_id=pWoid) );

  END IF;

--  Insert the W/O Operations if routings enabled
  IF ( ( SELECT (metric_value='t')
         FROM metric
         WHERE (metric_name='Routings') ) ) THEN

    INSERT INTO wooper
    ( wooper_wo_id, wooper_booitem_id, wooper_seqnumber,
      wooper_wrkcnt_id, wooper_stdopn_id,
      wooper_descrip1, wooper_descrip2, wooper_toolref,
      wooper_sutime, wooper_sucosttype, wooper_surpt,
      wooper_rntime, wooper_rncosttype, wooper_rnrpt,
      wooper_rnqtyper,
      wooper_produom, wooper_invproduomratio,
      wooper_issuecomp, wooper_rcvinv,
      wooper_suconsumed, wooper_sucomplete,
      wooper_rnconsumed, wooper_rncomplete,
      wooper_qtyrcv, wooper_instruc, wooper_scheduled,
      wooper_wip_location_id )
    SELECT wo_id, booitem_id, booitem_seqnumber,
           booitem_wrkcnt_id, booitem_stdopn_id,
           booitem_descrip1, booitem_descrip2, booitem_toolref,
           CASE WHEN (booitem_surpt) THEN booitem_sutime
                ELSE 0
           END, booitem_sucosttype, booitem_surpt,
           CASE WHEN ((booitem_rnqtyper = 0) OR (booitem_invproduomratio = 0)) THEN 0
                WHEN (NOT booitem_rnrpt) THEN 0
                ELSE ( ( booitem_rntime /
                         booitem_rnqtyper /
                         booitem_invproduomratio ) * wo_qtyord )
           END, booitem_rncosttype, booitem_rnrpt,
           CASE WHEN (booitem_rnqtyper = 0) THEN 0
                WHEN (NOT booitem_rnrpt) THEN 0
                ELSE (booitem_rntime / booitem_rnqtyper)
           END,
           booitem_produom, booitem_invproduomratio,
           booitem_issuecomp, booitem_rcvinv,
           0::NUMERIC, FALSE,
           0::NUMERIC, FALSE,
           0::NUMERIC, booitem_instruc,
           (wo_startdate + booitem_execday - 1),
           booitem_wip_location_id
    FROM booitem, wo, itemsite
    WHERE ((wo_itemsite_id=itemsite_id)
     AND (itemsite_item_id=booitem_item_id)
     AND (booitem_rev_id=wo_boo_rev_id)
     AND (woEffectiveDate(wo_startdate) BETWEEN booitem_effective AND (booitem_expires - 1))
     AND (wo_id=pWoid));

--  Update womatls item to link to wooper items when the respective
--  bomitem record indicates a booitem issue link.
    UPDATE womatl
    SET womatl_wooper_id=wooper_id
    FROM wo,wooper,booitem
    WHERE ((womatl_wooper_id=booitem_seq_id)
     AND (wooper_booitem_id=booitem_id)
     AND (womatl_wo_id=wo_id)
     AND (wooper_wo_id=wo_id)
     AND (wo_boo_rev_id=booitem_rev_id)
     AND (wo_id=pWoid));
    END IF;

-- Handle all of the Phantom material requirements
  WHILE ( ( SELECT COUNT(*)
            FROM womatl, itemsite, item
            WHERE ( (womatl_itemsite_id=itemsite_id)
             AND (itemsite_item_id=item_id)
             AND (womatl_wo_id=pWoid)
             AND (item_type='F') ) ) > 0 ) LOOP

    FOR _p IN SELECT wo_qtyord, wo_startdate, womatl_id, womatl_wooper_id
              FROM wo, womatl, itemsite, item
              WHERE ( (womatl_itemsite_id=itemsite_id)
               AND (itemsite_item_id=item_id)
               AND (item_type='F')
               AND (womatl_wo_id=wo_id)
               AND (wo_id=pWoid) ) LOOP

      INSERT INTO womatl
      ( womatl_wo_id, womatl_itemsite_id, womatl_wooper_id,
        womatl_schedatwooper, womatl_duedate,
        womatl_uom_id, womatl_qtyper, womatl_scrap,
        womatl_qtyreq,
        womatl_qtyiss, womatl_qtywipscrap,
        womatl_lastissue, womatl_lastreturn,
        womatl_cost, womatl_picklist, womatl_createwo,
        womatl_issuemethod, womatl_notes, womatl_ref )
      SELECT pWoid, cs.itemsite_id, _p.womatl_wooper_id,
             womatl_schedatwooper, womatl_duedate,
             bomitem_uom_id, (bomitem_qtyper * womatl_qtyper), bomitem_scrap,
             roundQty(itemuomfractionalbyuom(bomitem_item_id, bomitem_uom_id), (_p.wo_qtyord * bomitem_qtyper * womatl_qtyper * (1 + bomitem_scrap))),
             0, 0,
             startOfTime(), startOfTime(),
             0, ci.item_picklist, ( (ci.item_type='M') AND (bomitem_createwo) ),
             bomitem_issuemethod, bomitem_notes, bomitem_ref 
      FROM wo, womatl, bomitem, 
           itemsite AS cs, itemsite AS ps,
           item AS ci, item AS pi
      WHERE ( (womatl_itemsite_id=ps.itemsite_id)
       AND (womatl_wo_id=wo_id)
       AND (bomitem_parent_item_id=pi.item_id)
       AND (bomitem_item_id=ci.item_id)
       AND (ps.itemsite_warehous_id=cs.itemsite_warehous_id)
       AND (cs.itemsite_item_id=ci.item_id)
       AND (ps.itemsite_item_id=pi.item_id)
       AND (woEffectiveDate(_p.wo_startdate) BETWEEN bomitem_effective AND (bomitem_expires - 1))
       AND (womatl_id=_p.womatl_id));

      DELETE FROM womatl
      WHERE (womatl_id=_p.womatl_id);

    END LOOP;
  END LOOP;

--  Create W/Os for manufactured component items
  FOR newWo IN SELECT wo_number, nextWoSubnumber(wo_number) AS nextSubnumber,
                      itemsite_id, itemsite_leadtime, womatl_duedate,
                      womatl_wo_id, womatl_qtyreq, womatl_uom_id, wo_prj_id,
                      item_id, item_inv_uom_id, womatl_id
               FROM womatl, wo, itemsite, item
               WHERE ( (womatl_wo_id=wo_id)
                AND (womatl_itemsite_id=itemsite_id)
                AND (womatl_createwo)
                AND (itemsite_wosupply)
                AND (itemsite_item_id=item_id)
                AND (wo_id=pWoid) )
               ORDER BY womatl_id LOOP

    SELECT createWo( newWo.wo_number, newWo.itemsite_id, 1, 
                     itemuomtouom(newWo.item_id,newWo.womatl_uom_id,newWo.item_inv_uom_id,newWo.womatl_qtyreq),
                      newWo.itemsite_leadtime, newWo.womatl_duedate, '',
                      'W', newWo.womatl_wo_id, newWo.wo_prj_id ) INTO _newwoid;

    UPDATE wo SET wo_womatl_id = newWo.womatl_id WHERE wo_id=_newwoid;

  END LOOP;

  UPDATE wo
  SET wo_status='E', wo_adhoc=FALSE
  WHERE (wo_id=pWoid);

  IF (pExplodeChildren) THEN
    SELECT MAX(explodeWo(wo_id, TRUE)) INTO resultCode
    FROM wo
    WHERE ( (wo_ordtype='W')
     AND (wo_ordid=pWoid) );
  END IF;

  RETURN pWoid;
END;
$$ LANGUAGE 'plpgsql';
