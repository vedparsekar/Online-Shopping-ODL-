SELECT  S.SERVICEID,SERVICELONGNAME,AM.MASTERALLOCATIONID,SOIS.SERVICEOPTIONINSERVICEID,STO.SERVICETYPEOPTIONNAME
FROM [SERVICE] S
INNER JOIN SERVICE_OPTION_IN_SERVICE SOIS ON SOIS.SERVICEID = S.SERVICEID
INNER JOIN SERVICE_TYPE_OPTION STO ON STO.SERVICETYPEOPTIONID = SOIS.SERVICETYPEOPTIONID
INNER JOIN SERVICE_OPTION_STATUS SOS ON SOS.SERVICEOPTIONSTATUSID = SOIS.SERVICEOPTIONSTATUSID
INNER JOIN PRICE P ON P.SERVICEOPTIONINSERVICEID = SOIS.SERVICEOPTIONINSERVICEID
INNER JOIN ALLOCATION_MEMBERSHIP AM ON AM.SERVICEOPTIONINSERVICEID = SOIS.SERVICEOPTIONINSERVICEID
GROUP BY S.SERVICEID,SERVICELONGNAME,SOIS.SERVICEOPTIONINSERVICEID,AM.MASTERALLOCATIONID,
SOIS.SERVICETYPEOPTIONID, STO.SERVICETYPEOPTIONNAME, SOIS.SERVICEOPTIONSTATUSID,
SOS.SERVICEOPTIONSTATUSNAME