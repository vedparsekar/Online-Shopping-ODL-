SELECT *
--AllocationID	
--MasterAllocationID		
--AllocationTypeName
FROM PACKAGE P 

INNER JOIN PACKAGE_SERVICE PS ON PS.PACKAGEID = P.PACKAGEID
INNER JOIN PACKAGE_OPTION PO ON PO.PACKAGESERVICEID = PS.PACKAGESERVICEID
INNER JOIN PACKAGE_ALLOCATION_MEMBERSHIP PAM ON PAM.
