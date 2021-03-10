
SELECT  S.SERVICEID,SERVICELONGNAME,SOIS.SERVICEOPTIONINSERVICEID,STO.SERVICETYPEOPTIONNAME, AT.ALLOCATIONTYPENAME,MA.MASTERALLOCATIONNAME,  MA.MASTERALLOCATIONFREESELLSALE,MA.MASTERALLOCATIONFREESELLSALEOVERRIDE,
MA.MASTERALLOCATIONSTARTDATE, MA.MASTERALLOCATIONENDDATE,
AM.MASTERALLOCATIONID,
MA.MASTERALLOCATIONOVERALLOCATABLE, MA.MASTERALLOCATIONOVERSOLD, MA.MASTERALLOCATIONDAYMONDAY AS MON, MA.MASTERALLOCATIONDAYTUESDAY AS TUE, 
MA.MASTERALLOCATIONDAYWEDNESDAY AS WED, MA.MASTERALLOCATIONDAYTHURSDAY AS THU, MA.MASTERALLOCATIONDAYFRIDAY AS FRI, MA.MASTERALLOCATIONDAYSATURDAY AS SAT,
MA.MASTERALLOCATIONDAYSUNDAY AS SUN, 
ALOC.ALLOCATIONDAYMONDAY AS UNITMON, ALOC.ALLOCATIONDAYTUESDAY AS UNITTUE, ALOC.ALLOCATIONDAYWEDNESDAY AS UNITWED, 
ALOC.ALLOCATIONDAYTHURSDAY as UNITTHU, ALOC.ALLOCATIONDAYFRIDAY AS UNITFRI, ALOC.ALLOCATIONDAYSATURDAY AS UNITSAT, 
ALOC.ALLOCATIONDAYSUNDAY AS UNITSUN, MA.MASTERALLOCATIONRELEASEPERIODMON AS RP_MON, MA.MASTERALLOCATIONRELEASEPERIODTUE AS RP_TUE, 
MA.MASTERALLOCATIONRELEASEPERIODWED AS RP_WED, MA.MASTERALLOCATIONRELEASEPERIODTHU AS RP_THU, MA.MASTERALLOCATIONRELEASEPERIODFRI AS RP_FRI, 
MA.MASTERALLOCATIONRELEASEPERIODSAT AS RP_SAT, MA.MASTERALLOCATIONRELEASEPERIODSUN AS RP_SUN, 
MA.FREESELLMAXLIMITMON AS MAXLIMITMON, MA.FREESELLMAXLIMITTUE AS MAXLIMITTUE,MA.FREESELLMAXLIMITWED AS MAXLIMITWED, 
MA.FREESELLMAXLIMITTHR AS MAXLIMITTHU, MA.FREESELLMAXLIMITFRI AS MAXLIMITFRI, MA.FREESELLMAXLIMITSAT AS MAXLIMITSAT
FROM [SERVICE] S
INNER JOIN SERVICE_OPTION_IN_SERVICE SOIS ON SOIS.SERVICEID = S.SERVICEID
INNER JOIN SERVICE_TYPE_OPTION STO ON STO.SERVICETYPEOPTIONID = SOIS.SERVICETYPEOPTIONID
INNER JOIN SERVICE_OPTION_STATUS SOS ON SOS.SERVICEOPTIONSTATUSID = SOIS.SERVICEOPTIONSTATUSID
INNER JOIN PRICE P ON P.SERVICEOPTIONINSERVICEID = SOIS.SERVICEOPTIONINSERVICEID
--GET THE ALLOCATION DETAILS
INNER JOIN ALLOCATION_MEMBERSHIP AM ON AM.SERVICEOPTIONINSERVICEID = SOIS.SERVICEOPTIONINSERVICEID
INNER JOIN MASTER_ALLOCATION MA ON MA.MASTERALLOCATIONID = AM.MASTERALLOCATIONID 
INNER JOIN ALLOCATION ALOC ON ALOC.MASTERALLOCATIONID = MA.MASTERALLOCATIONID
INNER JOIN ALLOCATION_TYPE AT ON AT.ALLOCATIONTYPEID = ALOC.ALLOCATIONTYPEID
--SELECT * FROM MASTER_ALLOCATION
WHERE MA.MASTERALLOCATIONQUANTITY > 0  AND MA.MASTERALLOCATIONFREESELLSALE = 1

GROUP BY S.SERVICEID,SERVICELONGNAME,SOIS.SERVICEOPTIONINSERVICEID,
AT.ALLOCATIONTYPENAME,AM.MASTERALLOCATIONID,SOIS.SERVICETYPEOPTIONID, STO.SERVICETYPEOPTIONNAME, SOIS.SERVICEOPTIONSTATUSID,
SOS.SERVICEOPTIONSTATUSNAME, MA.MASTERALLOCATIONOVERALLOCATABLE, MA.MASTERALLOCATIONOVERSOLD,
MA.MASTERALLOCATIONFREESELLSALE,MA.MASTERALLOCATIONFREESELLSALEOVERRIDE,MA.MASTERALLOCATIONSTARTDATE, 
MA.MASTERALLOCATIONENDDATE, MA.MASTERALLOCATIONDAYMONDAY , MA.MASTERALLOCATIONDAYTUESDAY , MA.MASTERALLOCATIONDAYWEDNESDAY ,
MA.MASTERALLOCATIONDAYTHURSDAY , MA.MASTERALLOCATIONDAYFRIDAY, MA.MASTERALLOCATIONDAYSATURDAY, MA.MASTERALLOCATIONDAYSUNDAY
,ALOC.ALLOCATIONDAYMONDAY , ALOC.ALLOCATIONDAYTUESDAY , ALOC.ALLOCATIONDAYWEDNESDAY , ALOC.ALLOCATIONDAYTHURSDAY , ALOC.ALLOCATIONDAYFRIDAY , ALOC.ALLOCATIONDAYSATURDAY , 
ALOC.ALLOCATIONDAYSUNDAY, MA.MASTERALLOCATIONRELEASEPERIODMON , MA.MASTERALLOCATIONRELEASEPERIODTUE , 
MA.MASTERALLOCATIONRELEASEPERIODWED , MA.MASTERALLOCATIONRELEASEPERIODTHU , MA.MASTERALLOCATIONRELEASEPERIODFRI , 
MA.MASTERALLOCATIONRELEASEPERIODSAT, MA.MASTERALLOCATIONRELEASEPERIODSUN, MA.FREESELLMAXLIMITMON , MA.FREESELLMAXLIMITTUE ,MA.FREESELLMAXLIMITWED , 
MA.FREESELLMAXLIMITTHR , MA.FREESELLMAXLIMITFRI , MA.FREESELLMAXLIMITSAT, MA.MASTERALLOCATIONNAME

