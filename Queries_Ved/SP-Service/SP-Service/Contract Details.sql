SELECT 
S.SERVICELONGNAME,	
OSC.ORGANISATIONSUPPLIERCONTRACTID,
OSC.ORGANISATIONSUPPLIERCONTRACTNAME,	
CD.CONTRACTDURATIONID,	
CD.CONTRACTDURATIONSTARTDATE,
CD.CONTRACTDURATIONENDDATE,	
DR.DATERANGESTARTDATE,	
DR.DATERANGEENDDATE
FROM SERVICE S

INNER JOIN  SUPPLIER SU ON SU.SUPPLIERID = S.SUPPLIERID
INNER JOIN  ORGANISATION_SUPPLIER_CONTRACT OSC ON OSC.SUPPLIERID = SU.SUPPLIERID
INNER JOIN  CONTRACT_DURATION CD ON CD.CONTRACTDURATIONID = OSC.CONTRACTDURATIONID
INNER JOIN DATERANGE DR ON DR.CONTRACTDURATIONID = CD.CONTRACTDURATIONID
WHERE S.SERVICEID=1;


