SELECT 
B.BOOKINGID AS BookingID,
PD.PACKAGEDEPARTURENAME AS DepartureName,	
--Optionname
--ExtraName	
BCR.BOOKEDCHILDRATEID AS BOOKEDCHILDRATEID,
BCR.BOOKEDCHILDRATECOSTAMOUNT AS COSTAMOUNT, 
BCR.BOOKEDCHILDRATESELLAMOUNT AS SELLAMOUNT, 
BCR.BOOKEDCHILDRATEQUANTITY AS QUANTITY, 
BCR.BOOKEDCHILDRATEAGE AS AGE, 
BCR.BOOKEDCHILDRATEORIGINALSELLAMOUNT AS ORIGINALSELLAMOUNT,
BCR.BOOKEDCHILDRATEORIGINALCOSTAMOUNT AS ORIGINALCOSTAMOUNT,
BO.BOOKEDOPTIONID AS BOOKEDOPTIONID,
BCR.BOOKEDCHILDRATETOTALCOSTAMOUNT AS TOTALCOSTAMOUNT,
BCR.BOOKEDCHILDRATETOTALSELLAMOUNT AS TOTALSELLAMOUNT, 
BCR.BOOKEDCHILDRATEORIGSELLINSRVCURR AS ORIGSELLINSRVCURR,
BCR.BOOKEDCHILDRATETOTALORIGINALCOSTAMOUNT AS TOTALORIGINALCOSTAMOUNT ,
BCR.BOOKEDELEMENTID AS BOOKEDELEMENTID , 
BCR.BOOKEDCHILDRATECOSTTAX AS COSTTAX, 
BCR.BOOKEDCHILDRATESELLTAX AS SELLTAX

FROM BOOKING B
INNER JOIN BOOKED_PACKAGE BP ON BP.BOOKINGID = B.BOOKINGID
INNER JOIN BOOKED_SERVICE BS ON BS.BOOKINGID = B.BOOKINGID
INNER JOIN BOOKED_OPTION BO ON BO.BOOKEDSERVICEID = BS.BOOKEDSERVICEID
INNER JOIN PACKAGE_DEPARTURE PD ON PD.PACKAGEDEPARTUREID =BP.PACKAGEDEPARTUREID
LEFT JOIN BOOKED_CHILD_RATE BCR ON BCR.BOOKEDOPTIONID = BO.BOOKEDOPTIONID
