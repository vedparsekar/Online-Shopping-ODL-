SELECT 
B.BOOKINGREFERENCENUMBER AS BOOKINGRef, 
BO.BOOKEDOPTIONID AS BOOKEDOPTIONID,
--ServiceName,
--OptionName, 
--ExtraName, 
BO.BOOKEDOPTIONID_1 AS BOOKEDOPTIONID_1,
BOS.BOOKEDOPTIONSTATUSNAME AS BOOKEDOPTIONSTATUSName,
BOS.BOOKEDOPTIONSTATUSDELETED AS ISDELETED, 
--BookedOptionClosed, 
--PASSENGERTYPEName,
--INDATE,
--OUTDATE,
--NUMBEROFNIGHTS,
--QUANTITY, 
--NUMBEROFPASSENGERS, 
--SplitPrice,
--MEALPLANName,
--DAYOVERLAP, 
--CHARGINGPOLICYName,
--COST_CURRENCYISOCode,
--BOOKEDOPTIONCOSTOVERRIDEN,
--BOOKEDOPTIONCOSTAMOUNT,
--BOOKEDOPTIONORIGCOSTAMOUNT, 
--BOOKEDOPTIONTOTALCOSTAMOUNT ,
--BOOKEDOPTIONTOTALORIGINALCOSTAMOUNT,
BO.ORIGINALCOST_PRICEID AS ORIGINALCOST_PRICEID,
BO.BOOKEDOPTIONCOSTROE AS BOOKEDOPTIONCOSTROE,
BO.BOOKEDOPTIONCOSTTAX AS BOOKEDOPTIONCOSTTAX,
BO.BOOKEDOPTIONORIGCOSTROE AS ORIGCOSTROE,                
-- SELL_CURRENCYISOCode,
BO.BOOKEDOPTIONSELLOVERRIDEN AS BOOKEDOPTIONSELLOVERRIDEN,
BO.BOOKEDOPTIONSELLINGAMOUNT AS BOOKEDOPTIONSELLINGAMOUNT, 
BO.BOOKEDOPTIONORIGSELLAMOUNT AS BOOKEDOPTIONORIGSELLAMOUNT, 
BO.ORIGINALSELL_PRICEID AS ORIGINALSELL_PRICEID,
BO.BOOKEDOPTIONTOTALSELLINGAMOUNT AS BOOKEDOPTIONTOTALSELLINGAMOUNT, 
BO.BOOKEDOPTIONORIGSELLAMOUNTINSRVCURR AS BOOKEDOPTIONORIGSELLAMOUNTINSRVCURR,
BO.BOOKEDOPTIONSELLTAX AS BOOKEDOPTIONSELLTAX ,
BO.BOOKEDOPTIONPREVIOUSTOTALSELLAMOUNT AS PREVIOUSTOTALSELLAMOUNT,  
BO.BOOKEDOPTIONROE AS BOOKEDOPTIONROE,
BO.BOOKEDOPTIONORIGROE AS ORIGROE, 
BO.BOOKEDOPTIONCOMMISSIONPERCENT AS COMMISSIONPERCENT,
BO.BOOKEDOPTIONCOMMISSIONAMOUNT AS COMMISSIONAMOUNT, 
BO.BOOKEDOPTIONCOMMISSIONTAXPERCENT AS COMMISSIONTAXPERCENT,
BO.BOOKEDOPTIONCOMMISSIONTAX AS COMMISSIONTAX 

FROM BOOKING B

INNER JOIN BOOKED_SERVICE BS ON BS.BOOKINGID = B.BOOKINGID
INNER JOIN SERVICE S ON S.SERVICEID = BS.SERVICEID
INNER JOIN BOOKED_OPTION BO ON BO.BOOKEDSERVICEID = BS.BOOKEDSERVICEID
INNER JOIN BOOKED_OPTION_STATUS BOS ON BOS.BOOKEDOPTIONSTATUSID = BO.BOOKEDOPTIONSTATUSID
INNER JOIN PASSENGER_TYPE PT ON PT.PASSENGERTYPEID = BO.PASSENGERTYPEID
INNER JOIN CURRENCY C ON C.CURRENCYID = B.CURRENCYID
INNER JOIN MEAL_PLAN MP ON MP.MEALPLANID = BO.MEALPLANID
INNER JOIN CHARGING_POLICY CP ON CP.CHARGINGPOLICYID = BO.CHARGINGPOLICYID