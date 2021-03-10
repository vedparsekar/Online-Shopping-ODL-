SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO

IF EXISTS (SELECT 1 FROM SYSOBJECTS WHERE ID=OBJECT_ID(N'[dbo].[usp_DEL_YIELD_CLIENT_BAND_FOR_BOOKED_SERVICE_B2CB2B]')
 AND OBJECTPROPERTY(ID,N'IsProcedure') =1 )
 DROP PROCEDURE [dbo].[usp_DEL_YIELD_CLIENT_BAND_FOR_BOOKED_SERVICE_B2CB2B]

GO

/************************************************************************************************************************
* Stored Proc:  usp_DEL_YIELD_CLIENT_BAND_FOR_BOOKED_SERVICE_B2CB2B
* Created by  : Nagesh Bhatkar
* Date	      : 06 May 2011
* Description : Deletes All yield and Client Band Rules Associated with the Booked Service
*		
*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* Modification History:
*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
* SNo	Who  	Date			Description
* -----------------------------------------------------------------------------------------------------------------------------------------------
************************************************************************************************************************/

CREATE PROCEDURE [dbo].[usp_DEL_YIELD_CLIENT_BAND_FOR_BOOKED_SERVICE_B2CB2B]
(
	@RI_BOOKEDSERVICEID INT
)
AS
BEGIN
	SET NOCOUNT ON
	
	DELETE BOYR  
	FROM BOOKED_OPTION_YIELD_RULE BOYR
	INNER JOIN BOOKED_OPTION BO ON BOYR.BOOKEDOPTIONID =BO.BOOKEDOPTIONID
	INNER JOIN BOOKED_SERVICE BS ON BS.BOOKEDSERVICEID = BO.BOOKEDSERVICEID
	WHERE BS.BOOKEDSERVICEID=@RI_BOOKEDSERVICEID
	
	DELETE BSCB
	FROM BOOKED_SERVICE_CLIENT_BAND BSCB
	INNER JOIN BOOKED_SERVICE BS ON BSCB.BOOKEDSERVICEID = BS.BOOKEDSERVICEID
    WHERE BS.BOOKEDSERVICEID=@RI_BOOKEDSERVICEID

	UPDATE BO
    SET BO.CLIENTBANDSELL = NULL
    FROM BOOKED_OPTION BO
    INNER JOIN BOOKED_SERVICE BS ON BS.BOOKEDSERVICEID = BO.BOOKEDSERVICEID
	WHERE BS.BOOKEDSERVICEID=@RI_BOOKEDSERVICEID

    
    SET NOCOUNT OFF
	RETURN @@ERROR       
    
END

GO

---
SET QUOTED_IDENTIFIER  OFF    SET ANSI_NULLS  ON 
GO

if exists (select * from sysobjects where id = object_id(N'[dbo].[usp_GET_ALL_VIOLATED_PACKAGE_RESTRICTION_RULES_B2CB2B]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
drop procedure [dbo].[usp_GET_ALL_VIOLATED_PACKAGE_RESTRICTION_RULES_B2CB2B]
GO

/*******************************************************************************************************************************************************************************
 Stored Proc		:	USP_GET_ALL_VIOLATED_PACKAGE_RESTRICTION_RULES_B2CB2B
 Created by			:	Jeogan Dias
 Date				:	20th May, 2014
 Description		:	Checks if any restriction rule is violated.
						Its a replica of USP_GET_ALL_VIOLATED_PACKAGE_RESTRICTION_RULES.

 Reference Document	:	ATOP-49
		
 Modification History:
------------------------------------------------------------------------------------------------------------------------
 SNo	Who			Date			Description
------------------------------------------------------------------------------------------------------------------------
 01		Jeogan		19 May 2014		Created
 02		Rupesh PK.  05 Sep 2014		Changes for ATOP-195; Extension to ATOP49 [Non Fixed some dates OffSale][Client: Abreu TOP]
 03		Rupesh PK.	29 Oct 2014		Changes for ATOP-290 [Restriction rule for only departure start date][Client: Abreu TOP]
 05		Neil S		13 Oct 2016		Fixed ticket#88344 - All - Can't Stop Sell on any period request
 04		Neil S		30 Mar 2017		Optimization
 ------------------------------------------------------------------------------------------------------------------------

******************************************************************************************************************************************************************************/
CREATE PROCEDURE dbo.usp_GET_ALL_VIOLATED_PACKAGE_RESTRICTION_RULES_B2CB2B
	@rdt_STARTDATE	DATETIME = NULL,
	@rdt_ENDDATE	DATETIME = NULL,
	@ri_PACKAGEID	INT = NULL,
	@rb_ShowDeparture BIT = 0 -- Rupesh PK.(02)
AS
BEGIN

 SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED --Neil(04)
	--DECLARATIONS
	DECLARE @iPrevDateFirst TINYINT, @i_OccupyWeeks BIGINT

	DECLARE @tbl_Departures TABLE
	(
		ID INT IDENTITY(1,1) PRIMARY KEY, --Neil(04)
		PACKAGEID INT,
		DEPARTURESTARTDATE DATETIME,
		DEPARTUREENDDATE DATETIME,
		OCCUPYWEEKS BIGINT
	)

	DECLARE @tbl_RestrictedDepartures TABLE
	(
		ID INT IDENTITY(1,1) PRIMARY KEY,--Neil(04)
		RULENAME CHAR(50),
		RULEENFORCED BIT,
		RULEMESSAGE CHAR(255),
		RULEFROMDATE DATETIME,
		RULETODATE DATETIME,
		RULETEXT VARCHAR(7000),
		PACKAGEID INT,
		DEPARTURESTARTDATE DATETIME
	)


	SELECT @iPrevDateFirst = @@DateFirst --Store previous DateFirst
	SET DATEFIRST 1	--Sets the first day to Monday (DatePart(dw,....) is effected)

	IF OBJECT_ID('tempdb..#TBL_NFD') IS NULL
	BEGIN
		SELECT @i_OccupyWeeks = SUM (DISTINCT PRICEDAYFLAG * POWER( 2.0 ,7 * (CEILING( CAST( DATEPART( DAY, PRICEDATE ) AS FLOAT)/7  ) -1)))
		FROM DATES
		WHERE PriceDate = @rdt_STARTDATE -- Only the Beginning Date of Package Departure needs to be considered

		INSERT INTO @tbl_Departures
		SELECT ISNULL(@ri_PACKAGEID,0),
			ISNULL(@rdt_STARTDATE,0),
			ISNULL(@rdt_ENDDATE,0),
			ISNULL(@i_OccupyWeeks,0)
	END
	ELSE
	BEGIN
		INSERT INTO @tbl_Departures
		SELECT tNFD.PACKAGEID,
			tNFD.DEPARTUREDATE,
			tNFD.DEPARTUREENDDATE,
			SUM (DISTINCT PRICEDAYFLAG * POWER ( 2.0, 7 * (CEILING( CAST( DATEPART( DAY, PRICEDATE ) AS FLOAT) / 7  ) -1)))
		FROM #TBL_NFD tNFD
		INNER JOIN DATES D ON tNFD.DEPARTUREDATE = D.PRICEDATE
		GROUP BY tNFD.PACKAGEID, tNFD.DEPARTUREDATE, tNFD.DEPARTUREENDDATE
	END

	--COLLECTING ALL RESTRICTED DEPARTURES AND RULES
	--Neil(04) rewrote the below query
	INSERT INTO @tbl_RestrictedDepartures
	SELECT  R.RULENAME,
			R.RULEENFORCED,
			R.RULEMESSAGE,
			AR.APPLIEDRULEFROMDATE RULEFROMDATE,
			AR.APPLIEDRULETODATE RULETODATE,
			ISNULL(RULETEXT, '') AS RULETEXT,
			tD.PACKAGEID,
			tD.DEPARTURESTARTDATE
	FROM @tbl_Departures tD
	INNER JOIN APPLIED_RULE AR ON AR.PACKAGEID = tD.PACKAGEID
	INNER JOIN Rule_1 R ON	R.RULEID = AR.RULEID
	INNER JOIN RESTRICTION_RULE RR ON R.RULEID = RR.RULEID
	WHERE R.RULEENFORCED = 1
	AND R.RULETYPEID = 3
	AND ((ISNULL(APPLYBASEDONDEPARTURESTARTDATE,0) = 0 AND ((AR.APPLIEDRULEFROMDATE BETWEEN tD.DEPARTURESTARTDATE AND tD.DEPARTUREENDDATE)
			OR (AR.APPLIEDRULETODATE BETWEEN tD.DEPARTURESTARTDATE AND tD.DEPARTUREENDDATE)
			OR (tD.DEPARTUREENDDATE BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE)
			OR (tD.DEPARTURESTARTDATE BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE)
			-- BOC Rupesh PK.(03)
			))
		OR
			((tD.DEPARTURESTARTDATE BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE) AND ISNULL(APPLYBASEDONDEPARTURESTARTDATE,0) = 1)
			-- EOC Rupesh PK.(03)
			)		
		AND
		(
			(
				ISNULL(RESTRICTIONRULEALLOWCHECKINON,0)=0
				AND
				((CAST
					((( RESTRICTIONRULENASUNDAY*1+
						RESTRICTIONRULENAMONDAY*2+
						RESTRICTIONRULENATUESDAY*4+
						RESTRICTIONRULENAWEDNESDAY*8+
						RESTRICTIONRULENATHURSDAY*16+
						RESTRICTIONRULENAFRIDAY*32+
						RESTRICTIONRULENASATURDAY*64) * RESTRICTIONRULENAWEEK1) 
					+
					(((	RESTRICTIONRULENASUNDAY*1+
						RESTRICTIONRULENAMONDAY*2+
						RESTRICTIONRULENATUESDAY*4+
						RESTRICTIONRULENAWEDNESDAY*8+
						RESTRICTIONRULENATHURSDAY*16+
						RESTRICTIONRULENAFRIDAY*32+
						RESTRICTIONRULENASATURDAY*64)*POWER(2.0,7)) * RESTRICTIONRULENAWEEK2) 
					+					
					(((	RESTRICTIONRULENASUNDAY*1+
						RESTRICTIONRULENAMONDAY*2+
						RESTRICTIONRULENATUESDAY*4+
						RESTRICTIONRULENAWEDNESDAY*8+
						RESTRICTIONRULENATHURSDAY*16+
						RESTRICTIONRULENAFRIDAY*32+
						RESTRICTIONRULENASATURDAY*64)*POWER(2.0,14)) * RESTRICTIONRULENAWEEK3) 
					+
					(((	RESTRICTIONRULENASUNDAY*1+
						RESTRICTIONRULENAMONDAY*2+
						RESTRICTIONRULENATUESDAY*4+
						RESTRICTIONRULENAWEDNESDAY*8+
						RESTRICTIONRULENATHURSDAY*16+
						RESTRICTIONRULENAFRIDAY*32+
						RESTRICTIONRULENASATURDAY*64)*POWER(2.0,21)) * RESTRICTIONRULENAWEEK4) 
					+
					(((	RESTRICTIONRULENASUNDAY*1+
						RESTRICTIONRULENAMONDAY*2+
						RESTRICTIONRULENATUESDAY*4+
						RESTRICTIONRULENAWEDNESDAY*8+
						RESTRICTIONRULENATHURSDAY*16+
						RESTRICTIONRULENAFRIDAY*32+
						RESTRICTIONRULENASATURDAY*64)*POWER(2.0,28)) * RESTRICTIONRULENAWEEK5) AS BIGINT)
				)  & tD.OCCUPYWEEKS > 0
			))
		--BOC Neil(05)
		OR
		(isnull(RESTRICTIONRULEALLOWCHECKINON,0)=0
		And
		( 	(cast(
			((
			RESTRICTIONRULENASUNDAY*1+
			RESTRICTIONRULENAMONDAY*2+
			RESTRICTIONRULENATUESDAY*4+
			RESTRICTIONRULENAWEDNESDAY*8+
			RESTRICTIONRULENATHURSDAY*16+
			RESTRICTIONRULENAFRIDAY*32+
			RESTRICTIONRULENASATURDAY*64) 
			) 
			+
			(((RESTRICTIONRULENASUNDAY*1+
			RESTRICTIONRULENAMONDAY*2+
			RESTRICTIONRULENATUESDAY*4+
			RESTRICTIONRULENAWEDNESDAY*8+
			RESTRICTIONRULENATHURSDAY*16+
			RESTRICTIONRULENAFRIDAY*32+
			RESTRICTIONRULENASATURDAY*64)*power(2.0,7)) 
			) 
			+					
			(((RESTRICTIONRULENASUNDAY*1+
			RESTRICTIONRULENAMONDAY*2+
			RESTRICTIONRULENATUESDAY*4+
			RESTRICTIONRULENAWEDNESDAY*8+
			RESTRICTIONRULENATHURSDAY*16+
			RESTRICTIONRULENAFRIDAY*32+
			RESTRICTIONRULENASATURDAY*64)*power(2.0,14)) 
			) 
			+
			(((RESTRICTIONRULENASUNDAY*1+
			RESTRICTIONRULENAMONDAY*2+
			RESTRICTIONRULENATUESDAY*4+
			RESTRICTIONRULENAWEDNESDAY*8+
			RESTRICTIONRULENATHURSDAY*16+
			RESTRICTIONRULENAFRIDAY*32+
			RESTRICTIONRULENASATURDAY*64)*power(2.0,21)) 
			) 
			+
			(((RESTRICTIONRULENASUNDAY*1+
			RESTRICTIONRULENAMONDAY*2+
			RESTRICTIONRULENATUESDAY*4+
			RESTRICTIONRULENAWEDNESDAY*8+
			RESTRICTIONRULENATHURSDAY*16+
			RESTRICTIONRULENAFRIDAY*32+
			RESTRICTIONRULENASATURDAY*64)*power(2.0,28)) 
			) as bigint)
			)  & @i_OccupyWeeks >0))
			--EOC NeiL(05)
			--code added to handle when Flag "Allow Check-In On" is Checked here no
			--significance of Week no only need to use weedkday but exactly in opposite logic
			OR
			(
				ISNULL(RESTRICTIONRULEALLOWCHECKINON,0) = 1   -- WHEN FLAG IS SET ON
				AND
				((CAST
					(((
						(CASE RESTRICTIONRULENASUNDAY WHEN 1 THEN 0 ELSE 1 END)*1+
						(CASE RESTRICTIONRULENAMONDAY WHEN 1 THEN 0 ELSE 1 END)*2+
						(CASE RESTRICTIONRULENATUESDAY WHEN 1 THEN 0 ELSE 1 END)*4+
						(CASE RESTRICTIONRULENAWEDNESDAY WHEN 1 THEN 0 ELSE 1 END)*8+
						(CASE RESTRICTIONRULENATHURSDAY WHEN 1 THEN 0 ELSE 1 END)*16+
						(CASE RESTRICTIONRULENAFRIDAY WHEN 1 THEN 0 ELSE 1 END)*32+
						(CASE RESTRICTIONRULENASATURDAY WHEN 1 THEN 0 ELSE 1 END)*64)
					)
					+
					(((
						(CASE RESTRICTIONRULENASUNDAY WHEN 1 THEN 0 ELSE 1 END)*1+
						(CASE RESTRICTIONRULENAMONDAY WHEN 1 THEN 0 ELSE 1 END)*2+
						(CASE RESTRICTIONRULENATUESDAY WHEN 1 THEN 0 ELSE 1 END)*4+
						(CASE RESTRICTIONRULENAWEDNESDAY WHEN 1 THEN 0 ELSE 1 END)*8+
						(CASE RESTRICTIONRULENATHURSDAY WHEN 1 THEN 0 ELSE 1 END)*16+
						(CASE RESTRICTIONRULENAFRIDAY WHEN 1 THEN 0 ELSE 1 END)*32+
						(CASE RESTRICTIONRULENASATURDAY WHEN 1 THEN 0 ELSE 1 END)*64)*POWER(2.0,7))
					)
					+
					(((
						(CASE RESTRICTIONRULENASUNDAY WHEN 1 THEN 0 ELSE 1 END)*1+
						(CASE RESTRICTIONRULENAMONDAY WHEN 1 THEN 0 ELSE 1 END)*2+
						(CASE RESTRICTIONRULENATUESDAY WHEN 1 THEN 0 ELSE 1 END)*4+
						(CASE RESTRICTIONRULENAWEDNESDAY WHEN 1 THEN 0 ELSE 1 END)*8+
						(CASE RESTRICTIONRULENATHURSDAY WHEN 1 THEN 0 ELSE 1 END)*16+
						(CASE RESTRICTIONRULENAFRIDAY WHEN 1 THEN 0 ELSE 1 END)*32+
						(CASE RESTRICTIONRULENASATURDAY WHEN 1 THEN 0 ELSE 1 END)*64)*POWER(2.0,14))
					)
					+
					(((
						(CASE RESTRICTIONRULENASUNDAY WHEN 1 THEN 0 ELSE 1 END)*1+
						(CASE RESTRICTIONRULENAMONDAY WHEN 1 THEN 0 ELSE 1 END)*2+
						(CASE RESTRICTIONRULENATUESDAY WHEN 1 THEN 0 ELSE 1 END)*4+
						(CASE RESTRICTIONRULENAWEDNESDAY WHEN 1 THEN 0 ELSE 1 END)*8+
						(CASE RESTRICTIONRULENATHURSDAY WHEN 1 THEN 0 ELSE 1 END)*16+
						(CASE RESTRICTIONRULENAFRIDAY WHEN 1 THEN 0 ELSE 1 END)*32+
						(CASE RESTRICTIONRULENASATURDAY WHEN 1 THEN 0 ELSE 1 END)*64)*POWER(2.0,21))
					)
					+
					(((
						(CASE RESTRICTIONRULENASUNDAY WHEN 1 THEN 0 ELSE 1 END)*1+
						(CASE RESTRICTIONRULENAMONDAY WHEN 1 THEN 0 ELSE 1 END)*2+
						(CASE RESTRICTIONRULENATUESDAY WHEN 1 THEN 0 ELSE 1 END)*4+
						(CASE RESTRICTIONRULENAWEDNESDAY WHEN 1 THEN 0 ELSE 1 END)*8+
						(CASE RESTRICTIONRULENATHURSDAY WHEN 1 THEN 0 ELSE 1 END)*16+
						(CASE RESTRICTIONRULENAFRIDAY WHEN 1 THEN 0 ELSE 1 END)*32+
						(CASE RESTRICTIONRULENASATURDAY WHEN 1 THEN 0 ELSE 1 END)*64)*POWER(2.0,28))
					) AS BIGINT)
				)  & tD.OCCUPYWEEKS > 0 )
			)
		)


	IF OBJECT_ID('tempdb..#TBL_NFD') IS NULL
	BEGIN
		SELECT RULENAME,
			RULEENFORCED,
			RULEMESSAGE,
			RULEFROMDATE,
			RULETODATE,
			RULETEXT,
			PACKAGEID,
			DEPARTURESTARTDATE
		FROM @tbl_RestrictedDepartures
	END
	ELSE
	BEGIN
		-- BOC Rupesh PK.(02)
		IF ISNULL(@rb_ShowDeparture,0) = 0
		BEGIN
		-- EOC Rupesh PK.(02)
			--DELETING THE RESTRICTED DEPARTURES FROM THE COLLECTION
			DELETE tNFD
			FROM #TBL_NFD tNFD
			INNER JOIN @tbl_RestrictedDepartures tRD ON tNFD.DEPARTUREDATE = tRD.DEPARTURESTARTDATE AND tNFD.PACKAGEID = tRD.PACKAGEID
		-- BOC Rupesh PK.(02)
		END
		ELSE
		BEGIN
			IF OBJECT_ID('tempdb..#TBL_RestrictedPackageDepartures') IS NOT NULL
			BEGIN
				INSERT INTO #TBL_RestrictedPackageDepartures
						(
							PACKAGEID,
							PackageDepartureDate
						)
				SELECT T.PACKAGEID,
					   T.DEPARTURESTARTDATE 
				FROM @tbl_RestrictedDepartures T
			END
		END
		-- EOC Rupesh PK.(02)
	END

	SET DATEFIRST @iPrevDateFirst --Restore previous DateFirst

	RETURN @@Error

END

GO
SET QUOTED_IDENTIFIER  OFF
SET ANSI_NULLS  ON 

GO

------------

if exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[USP_Insert_Receipts_B2CB2B]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
drop procedure [dbo].[USP_Insert_Receipts_B2CB2B]
SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


/***********************************************************************************************                            
* CREATED                            
* BY:  HARSHAD PAWAR                           
* ON:  05-09-2006                            
* DESCRIPTION: USP_Insert_Receipts_B2CB2B
*                               
* MODIFICATION HISTORY:                            
* WHO  WHEN  WHAT                            
* -------------   -------------   --------------------------------------------------------    
* Harshad(01) 03-March-2007  made union with credit note type transaction                          
* Vinod  (02) 10-July-2007   changed bug with bookingid hardcoded to 97
* Vinod  (03) 10-July-2007   uncommented code for adding credit card mask
* Vinod  (04) 10-July-2007   commented input parameter of exec insert_receipt_detail, it causes error because of 321 upgrade. 
							 Note: when upgrading to 321, the parameter should be uncommented to be safe.
* Lucio  (05) 24-July-2007   Modified query to deal with null
* Ravi        16-AUG-2007    Insert credit card commission amount changes
* Lucio	 (06) 23-Aug-2007    Called TS SP to insert Cedit card service if the credit card type used has the service attached	
* Lucio	 (07) 23-Aug-2007    If a credit card is associated with the booking then a receipt type having the credit card type flag is set otherwise default is assumed
* Harshad(08) 25-Aug-2007    Added new functionality to take care of only receipt		
* Vinod  (09) 22-Oct-2007    fixed issue with creditcard mask for length 15 (mask applied American Express (xxxx-xxxxxx-xxxxx)) ; fixed creditcard substring error
* Lucio	 (10) 02-Sep-2008    added parameter to accept receipt amount. if parameter not passed then original functionality is assumed
* Hrishikesh(11) 10-Oct-2008 Fixed a bug: Credit Card Service was not getting booked when receipts were raised from XMLAPI.
* Hrishikesh(12) 15-Dec-2008 As told by Erryl, made some changes.
* Lucio(13)	02 Jan 2009  Fixed the issue of saving the authorization number
* Pgaonkar(14) 05 Jan 2009  fixed bug Receipttypeid Value going as null
* Sajjan.H(15) 27 Jan 2009  modified to allow raising of invoice against a existing invoice
* Pgaonkar(16) 23 Feb 2009  Fixed issue #14356 
* Pgaonkar(17) 07 Mar 2009  Fixed issue #14356 replcated Vivek's changes 
* Pgaonkar (18) 18 Mar 2009 Issue 14612
* Lucio	   (19) 13 May 2009 Added code to save the last 4 digits of the CC number to the receipts table
* Parind   (20) 08 Jul 2009	Added Code to Save the SystemUserID in Receipt Table
* Lucio		(21) 24 Dec 2009	Added new parameters and code to save credit card data
* Raish	   (22) 05 Jan 2011	Issue 21555 , Multiple Receipt Detail entries due to NUll FinancialTransactionID
* Sanket	(23) 20 Jan 2012	ROE by booking and based on booking creation date functionality[Client:RMV,Spec:CR262 ]
* Shivanand (24)  20 Apr 2012  Changes to save instalment discount details [Client:ETS || CR:ETS-04]
* IRshad   (25) 27 mar 2012	Issue 31875 , 
* Jaymala(26)	17 May 2012	Added param @rstr_SELECTEDPASSENGERIDS [Client:A&K|5821 - API CreateFinancialTransaction]
* Kedar(27)		11 Jun 2012	Added parameters @RSTR_RECEIPTCREDITCARDTRANSACTIONID and @VC_GATEWAYSPECIFICDATA [Client : ETS | CR : ETS-51]
* SVarshney(28) 27 Jul 2012 Fixed issue 34622: Added a condition to check @rvcRECEIPTCREDITCARDNUMBER while inserting in CLient_Credit_card table
* Shivanand (29)  04 Dec 2012  Changes to save Campaign Code [Client:ETS || CR:ETS-70]
* Shivanand (30)  19 Mar 2013  Fixed issue#40937 
* Sandip(32)	12 July 2013 CR:TUIS-5 Changes to Accounting API's
* Azim(33)		24 Jan  2013 Fixed Issue 48595,CreateFinancialTransaction method creates receipt in Booking Currency even if requested in other currency
* Kalpi(36)     27 May 2014  Changes done for ETS-132 Additional details on TSV2 Receipts [Client : ETS]
* Satish(37)	17 Jun 2014 Ticket 45682:No receipt details are created for negative receipt amount.
* Geetesh(38)   08 May 2015 CR : DT-140 Receipting Voucher Type
* Mosam	(39)    19 May 2014	DT-29 7.14 API Changes : Create Finacial transaction
* Gayeetri(40)  05 Sep 2015 DT-29 : Fixed Issue - QAAPI-673
*Gautam(41      19 Aug 2017 Fixed Issue:VH-36 Agent Credit Receipt Allocation is not updating Utilised amount 
*Prita(43)		09 Jan 2018 DH-26[Globus integration fixed issue related to Globus B2C Booking]
*Archana(42)    31 Oct 2017 CR: DH-93 [Issue : DH-434 Receipts - GroupOn Voucher Number]
*Diptesh H(43)   16 Feb 2018 CR:PER-52 Select Organisation on login or pop-up
* Clerance(41)	13 Nov 2017	Added Changes for CR: ARC-80 
* Clerance(42)	27 Nov 2017	Fixed Issue found while developer testing CR: ARC-80 
* Clerance(43)	27 Nov 2017	Code review changes 
*Pradnya (44)    CR: PER-431 BCP Receipt, Invoice and Ticket Processing
*Diptesh H(45)   28 Mar 2018 CR:PER-431 BCP Receipt, Invoice and Ticket Processing
*Pradnya(47)	 08 Mar 2019	 CR: PER-434 Prepayment over BCP interface
*RahulH(48)		 11 Oct 2019	 UAT Issue : 103790
***********************************************************************************************/                  
create  PROCEDURE dbo.USP_Insert_Receipts_B2CB2B
@ri_Bookingid			INT,
 @rm_CommissionAmount	MONEY = 0,
 @rv_CurISOcode			VARCHAR(5) = '',
 @rb_OnlyReceipt		INT = null,
 @ri_InvoiceId			INT = null,
 @rm_ReceiptAmount		money=0,--Lucio(10),
 @riSystemUserID		Int=0,	--Parind(20)
 --BOC Lucio(21)
 @riReceiptTypeID int=0,
@rvRECEIPTCREDITCARDNAMEONCARD varchar(50)=null,
@rdtRECEIPTCREDITCARDSTARTDATE datetime=null,
@rdtRECEIPTCREDITCARDENDDATE datetime=null,
@rvcRECEIPTCREDITCARDNUMBER varchar(512)=null,
@rvcRECEIPTCREDITCARDAUTHORISATIONNUMBER varchar(25)=null,
@rvcRECEIPTCREDITCARDISSUENUMBER varchar(3)=null,
@rvcRECEIPTCREDITCARDVALIDATIONNUMBER varchar(150)=null,
@rvcRECEIPTDESCRIPTION varchar(100)=null,
@riRECEIPTCREDITCARDTYPEID INT=NULL,
@rvcRECEIPTCREDITCARDLASTFOURDIGITS VARCHAR(4)=null
--EOC Lucio(21)
	,@ri_INSTALMENTDISCOUNTID INT = NULL --Shivanand(24) 
	,@rm_INSTALMENTVALUE MONEY = NULL   --Shivanand(24) 
	,@dc_DISCOUNTPERCENT DECIMAL(10,2) = NULL --Shivanand(24) 
,@rstr_SELECTEDPASSENGERIDS CHAR(1024)= ''  --Jaymala(26)
--BOC Kedar(27)
,@RSTR_RECEIPTCREDITCARDTRANSACTIONID VARCHAR(25) = NULL
,@VC_GATEWAYSPECIFICDATA VARCHAR(1000) = NULL  
--EOC Kedar(27)
,@VC_CAMPAIGNCODE VARCHAR(5) = NULL --Shivanand(29)
,@VC_INVOICEIDS VARCHAR(1000)=NULL--Sandip(32)
--BOC Kalpi(36)
,@RM_ORIGINALAMOUNT MONEY = NULL
,@RI_ORIGINALCURRENCYID INT = NULL
,@RF_APPLIEDROE FLOAT = NULL
--EOC Kalpi(36)
--Boc Sundeep
,@RF_TAXPERCENT FLOAT = NULL 
,@RM_TAXVALUE MONEY = NULL
,@RM_NETVALUEEXCLUDINGTAX MONEY = NULL
--Eoc Sundeep
,@RI_VOUCHERTYPEID INT=NULL--Geetesh(38)
,@RVC_VOUCHERCODE VARCHAR(50)=NULL--Archana(42)
,@RVC_PAYMENTTOKEN VARCHAR(25)=NULL	--Clerance(41)
,@RI_POINTOFTRANSACTIONTYPEID INT = NULL --Diptesh(43)
,@RI_AGENTCREDITRECEIPTID INT = NULL --Pradnya(47)
,@rb_SKIPANTICIPOCONSUMPTION  BIT=0 --RahulH()
AS
BEGIN
/*                  
Get the details for receipts                  
*/ 
--BOC SANDIP(32)                
DECLARE @INVOICEIDS TABLE (ID INT, PRICE MONEY)
IF @VC_INVOICEIDS IS NOT NULL OR @VC_INVOICEIDS <>''
BEGIN
DECLARE @IDOCINV INT
DECLARE @ERROR INT
--CREATE AN INTERNAL REPRESENTATION OF THE XML DOCUMENT.
EXEC SP_XML_PREPAREDOCUMENT @IDOCINV OUTPUT, @VC_INVOICEIDS	
INSERT INTO @INVOICEIDS
SELECT  *
FROM       OPENXML (@IDOCINV, '//INVC')
WITH ( ID INT , PRICE MONEY)
EXEC SP_XML_REMOVEDOCUMENT @IDOCINV	
SET @ERROR= @@ERROR		
IF (@ERROR!=0)
RETURN @ERROR
END
--EOC SANDIP(32)
create table #tempReceiptData                  
(                  
pid int identity(1,1),                  
financialtransactionid int,              
financialtransactiondate datetime,                  
financialtransactionnumber int,                  
financialtransactiontypeid int,              
financialtransactiontypename varchar(90),                
currencyid int,                  
currencysysmbol varchar(50),                  
invoiceamount money,                  
paidamount money,                  
receiptvalue money
,RECEIPTDETAILROEFROMINVOICETORECEIPTCURRENCY   float    --Prita(43)               
)   

-- BOC Diptesh H(45)
DECLARE @tempReceiptData TABLE
(                  
pid int identity(1,1),                  
financialtransactionid int,              
financialtransactiondate datetime,                  
financialtransactionnumber int,                  
financialtransactiontypeid int,              
financialtransactiontypename varchar(90),                
currencyid int,                  
currencysysmbol varchar(50),                  
invoiceamount money,                  
paidamount money,                  
receiptvalue money
,RECEIPTDETAILROEFROMINVOICETORECEIPTCURRENCY   float
) 
-- EOC Diptesh H(45)

              
--declare the variables for reciept                  
declare @ri_receiptid  int,                     
 @ri_receiptnumber   int,                    
 @rdt_receiptdate   datetime,                    
 --@rstr_receiptdescription  varchar(100),                    
 @rm_receipttotal   money,                    
 @rstr_receiptcreditcardnameoncard  varchar(50),                    
 @rdt_receiptcreditcardstartdate  datetime,                    
 @rdt_receiptcreditcardenddate   datetime,                    
 @rstr_receiptcreditcardno  varchar(512),                    
 @rstr_receiptcreditcardauthorisationno varchar(25),                    
 @rstr_receiptcreditcardissueno  varchar(3),                    
 @rstr_receiptcreditcardvalidationno  varchar(3),                    
 @ri_receipttypeid   int,                    
 @ri_currencyid    int,                    
 @ri_creditcardtypeid   int,                    
 @ri_systemuserid   int,
 @rstr_CCLast4Digits varchar(4)--Lucio(19)   
     ,@dt_RECEIPTDATETIME datetime --Irshad(25)                  
                  
--declare the variables for reciept details                  
                  
 declare                   
 @rm_receiptvalue  money,                    
 @rm_receiptroefrominvoicetoreceiptcurrency float,                    
 @ri_financialtransactionid int
 --,@rstr_selectedpassengerids char(1024)  Jaymala(26) commented as it passed as an input param to SP               
              
--declare the variable for xml reading              
declare @rv_Notetext varchar(8000)              
declare @idoc int,@i_length int  

declare @Prevcurrencyid  int, @RI_FROMCURRENCY INT,  
	@RI_TOCURRENCY int,@CURRId int--Pgaonkar
--boc Sanket(23)
DECLARE @i_ROEBASEDONBOOKINGDATE AS INT,   
		@i_ROEVALUE AS FLOAT,
		@LROUNDINGVALUECOST FLOAT,
		@RV_LOGGEDINUSER VARCHAR(254) --Pradnya(47)
		
 SELECT @i_ROEBASEDONBOOKINGDATE = ISNULL(OS.ROEBASEDONBOOKINGDATE, 0)    
 FROM ORGANISATION_SETTINGS OS    
   INNER JOIN ORGANISATION O ON O.ORGANISATIONID = OS.ORGANISATIONID    
 WHERE O.PARENT_ORGANISATIONID IS NULL   
--eoc Sanket(23)

--Harshad(02)
if isnull(@rb_OnlyReceipt,0)=0 
begin
	insert into @tempReceiptData -- Diptesh H Changed the temp table                  
	exec usp_GET_ALL_DISPLAY_INVOICE_DETAILS_FOR_RECEIPTING @ri_Bookingid, 0, NULL                  

	-- BOC Diptesh H(45)
	INSERT INTO #TEMPRECEIPTDATA
		(
			FINANCIALTRANSACTIONID ,              
FINANCIALTRANSACTIONDATE ,                  
FINANCIALTRANSACTIONNUMBER ,                  
FINANCIALTRANSACTIONTYPEID ,              
FINANCIALTRANSACTIONTYPENAME ,                
CURRENCYID ,                  
CURRENCYSYSMBOL ,                  
INVOICEAMOUNT ,                  
PAIDAMOUNT ,                  
			RECEIPTVALUE
		)
		SELECT FINANCIALTRANSACTIONID ,              
FINANCIALTRANSACTIONDATE ,                  
FINANCIALTRANSACTIONNUMBER ,                  
FINANCIALTRANSACTIONTYPEID ,              
FINANCIALTRANSACTIONTYPENAME ,                
CURRENCYID ,                  
CURRENCYSYSMBOL ,                  
INVOICEAMOUNT ,                  
PAIDAMOUNT ,                  
			   RECEIPTVALUE 
FROM @tempReceiptData
	ORDER BY FINANCIALTRANSACTIONID
-- EOC Diptesh H(45)
end
else
begin
	truncate table #tempBookingInvoiceDet
	Insert into #tempBookingInvoiceDet                      
  	exec usp_GET_ALL_DETAILS_FOR_NEW_INVOICE @ri_BOOKINGID, ''                      
   

	insert into #tempReceiptData
	SELECT @ri_InvoiceId as  FINANCIALTRANSACTIONID,            
	getdate() as FINANCIALTRANSACTIONDATE,            
	null as FINANCIALTRANSACTIONNUMBER,            
	1 as FINANCIALTRANSACTIONTYPEID,            
	'Invoice' as FINANCIALTRANSACTIONTYPENAME,            
	(select INVOICE_CURRENCYID from FINANCIAL_TRANSACTION where financialtransactionid=@ri_Invoiceid),            
	(select CURRENCYSYMBOL From Currency where
	Currencyid in(select INVOICE_CURRENCYID from FINANCIAL_TRANSACTION where financialtransactionid=@ri_Invoiceid))
	as CURRENCYSYMBOL,            
	(Select Sum(Isnull(BOOKED_OPTION_TOTAL,0)+IsNull(BOOKED_OPTION_SELL_TAX,0))from #tempBookingInvoiceDet
	where BOOKEDOPTIONID in(select FINANCIALTRANSACTIONDETAILBOOKEDOPTIONID from Financial_Transaction_detail
	where Financialtransactionid=@ri_Invoiceid)) as InvoiceAmount,             
	-- 0  AS PAIDAMOUNT,  --Commented by Sajjan.H(15)           
	isnull((SELECT SUM(Isnull(ReceiptDetailValue,0)) FROM RECEIPT_DETAIL WHERE financialtransactionid=@ri_Invoiceid),0) AS PAIDAMOUNT,-- Sajjan.H(15)
	0 AS RECEIPTVALUE
	,null  --Prita(43)	
end
--Harshad(02)



--Boc Harshad(01)              
delete from #tempReceiptData     
where financialtransactionid in(                
(/*select financialtransactionid from Financial_transaction  
where financialtransactionid in(select financialtransactionid from                  
receipt_detail)  
and bookingid=@ri_Bookingid --and financialtransactiontypeid<>1
union*/ -- commented by Sajjan.H(15)
select financialtransactionid from Financial_transaction  
where bookingid=@ri_Bookingid  and financialtransactiontypeid=2))               



	if exists(select top 1 pid from #tempReceiptData)
	begin
	--Eoc Harshad(01) 
		select @ri_receiptid=null,@ri_receiptnumber=null,@rdt_receiptdate=getDate(),  @dt_RECEIPTDATETIME = GETDATE(), --Irshad(25)                         

		@rm_receipttotal=(select sum(isnull(invoiceamount,0)) from #tempReceiptData),                    
		@rstr_receiptcreditcardnameoncard=NULL,          
		@rdt_receiptcreditcardstartdate=NULL,                    
		@rdt_receiptcreditcardenddate=NULL,                    
		@rstr_receiptcreditcardno=NULL,                    
		@rstr_receiptcreditcardauthorisationno=0,                    
		@rstr_receiptcreditcardissueno=0,                    
		@rstr_receiptcreditcardvalidationno=0,    
		--@ri_receipttypeid=(select top 1 receipttypeid from receipt_type where receipttypedefault=1),  --Commented and took down, Hrishikesh(11)
		@ri_currencyid=(select currencyid from booking where bookingid=@ri_Bookingid),     
		@ri_creditcardtypeid=null,                --RahulH(48)    
		@ri_systemuserid= Case When IsNull(@riSystemUserID,0) = 0 Then 1 Else @riSystemUserID End,
		--@ri_systemuserid=1 ,--Parind(20) Commented checked below that if no value is passed then it will still hold
		-- previous default value 1 as above		
		@rstr_CCLast4Digits=null --Lucio(19)
		--Commented the block below, Hrishikesh(11)   
-- 		--BOC lucio(07)
-- 		if exists(select  1 from booking_credit_card where bookingid=@ri_Bookingid)
-- 		begin
-- 			if exists(select 1 from receipt_type where receipttypeid=@ri_receipttypeid and receipttypecreditcard<>1)
-- 			begin
-- 				select @ri_receipttypeid=receipttypeid from receipt_type where receipttypecreditcard=1
-- 			end
-- 		end				
-- 		--EOC Lucio(07)

		--BOC Hrishikesh(11)
		if exists(select  1 from booking_credit_card where bookingid = @ri_Bookingid)
		begin
			if exists (select 1 from receipt_type where isnull(receipttypecreditcard, 0) = 1 and receipttypename != 'Reallocation Credit')
				select top 1 @ri_receipttypeid = receipttypeid from receipt_type where isnull(receipttypecreditcard, 0) = 1 and receipttypename != 'Reallocation Credit'
			else
			begin
				if  exists (select 1 from receipt_type where isnull(receipttypedefault, 0) = 1) 
					select @ri_receipttypeid = receipttypeid from receipt_type where isnull(receipttypedefault, 0) = 1 
				else
	 				select top 1 @ri_receipttypeid = receipttypeid from receipt_type where receipttypename != 'Reallocation Credit'
			end
		end
		--Pgaonkar(14) boc
		if isnull(@ri_receipttypeid,0) = 0
			select @ri_receipttypeid = receipttypeid from receipt_type where isnull(receipttypedefault, 0) = 1
 
		if isnull(@ri_receipttypeid,0) = 0
			select top 1 @ri_receipttypeid = receipttypeid from receipt_type 
		--Pgaonkar(14) eoc
		--EOC Hrishikesh(11)

		--Boc Ravi insert credit card commision amount		
		declare @UICreditCardID int
		if(ltrim(rtrim(isnull(@rv_CurISOcode,''))) <> '' )
		Begin 
			select @UICreditCardID =CURRENCYID from currency where lower(CURRENCYISOCODE) = lower(@rv_CurISOcode) and CURRENCYID <> @ri_currencyid
			
			if(isnull(@UICreditCardID,0) >0)
				--boc Sanket(23)
				IF @i_ROEBASEDONBOOKINGDATE >0 
				BEGIN
					SELECT @rm_CommissionAmount =ISNULL(@rm_CommissionAmount ,0) * ISNULL(DBO.UDF_UTL_GET_BOOKING_ROE (@ri_Bookingid,NULL,@UICreditCardID,@ri_currencyid ),1)
				END
				ELSE
				BEGIN --eoc Sanket(23)
					select @rm_CommissionAmount = isnull(@rm_CommissionAmount,0) * isnull(EXCHANGERATEVALUE,0) from exchange_rate 
					where CURRENCYID=@UICreditCardID and TOCURRENCYID_CURRENCYID= @ri_currencyid and (getdate() between EXCHANGERATESTARTDATE and EXCHANGERATEENDDATE)
				END
		end
	
		--Boc Ravi insert credit card commision amount
		

		IF EXISTS(SELECT TOP 1 BOOKINGCREDITCARDID FROM BOOKING_CREDIT_CARD WHERE BOOKINGID=@RI_BOOKINGID AND isnull(PASSENGERCREDITCARDID,0)>0)  --Vinod (02) changed to ri_bookingid  --Lucio(05)
		 SELECT top 1 @rstr_receiptcreditcardno=PASSENGERCREDITCARDNUMBER,@rstr_receiptcreditcardnameoncard=PASSENGERCREDITCARDNAMEONCARD,  --Lucio(13)
		 @rdt_receiptcreditcardstartdate=PASSENGERCREDITCARDVALIDFROM,@rdt_receiptcreditcardenddate=PASSENGERCREDITCARDEXPIRYDATE,@ri_creditcardtypeid=CREDITCARDTYPEID,  
		 @rstr_receiptcreditcardvalidationno=PASSENGERCREDITCARDVALIDATIONNUMBER,@ri_currencyid=CURRENCYID,
		 @rstr_receiptcreditcardauthorisationno=BCC.AUTH#,  --Lucio(13)
		 @rstr_CCLast4Digits=CCDECRYPTIONLAST4 --Lucio(19)
		 FROM PASSENGER_CREDIT_CARD PC  
		 INNER JOIN PASSENGER_FINANCE PF ON(PC.PASSENGERFINANCEID=PF.PASSENGERFINANCEID)  
			--BOC Lucio(13)
		 INNER JOIN (SELECT TOP 100 PERCENT BOOKINGCREDITCARDID,BOOKINGID,CLIENTCREDITCARDID,PASSENGERCREDITCARDID,AUTH# FROM BOOKING_CREDIT_CARD WHERE AUTH# !='0' ORDER BY BOOKINGCREDITCARDID DESC) --Pgaonkar(17)
			BCC ON(PC.PASSENGERCREDITCARDID=BCC.PASSENGERCREDITCARDID AND BOOKINGID=@RI_BOOKINGID)  
			--EOC Lucio(13)
		ELSE  
		 SELECT @rstr_receiptcreditcardno=CLIENTCREDITCARDNUMBER,@rstr_receiptcreditcardnameoncard=CLIENTCREDITCARDNAME,  
		 @rdt_receiptcreditcardstartdate=CLIENTCREDITCARDDATEVALIDFROM,@rdt_receiptcreditcardenddate=CLIENTCREDITCARDDATEEXPIRY,  
		 @ri_creditcardtypeid=CREDITCARDTYPEID,@rstr_receiptcreditcardvalidationno=CLIENTCREDITCARDVALIDATIONNUMBER,  
		 @RI_CURRENCYID=CURRENCYID ,@rstr_receiptcreditcardauthorisationno = BCC.AUTH#, --pgaonkar(16)   
		@rstr_CCLast4Digits=CCDECRYPTIONLAST4 --Lucio(19)
		 FROM CLIENT_CREDIT_CARD CC   
		 INNER JOIN CLIENT C ON(CC.CLIENTID=C.CLIENTID)  
		 INNER JOIN CLIENT_FINANCE CF ON(CF.CLIENTID=C.CLIENTID)  
		 INNER JOIN BOOKING_CREDIT_CARD BCC ON(CC.CLIENTCREDITCARDID=BCC.CLIENTCREDITCARDID AND BOOKINGID=@RI_BOOKINGID and AUTH# !='0' )  --Pgaonkar(17)
		--BOC Lucio(13)
		--Pgaonkar boc
		
		select @Prevcurrencyid  = isnull(@RI_CURRENCYID,0)
		if exists (select * from booking_credit_card where bookingid = @ri_Bookingid and isnull(AUTH#,'0') <>'0')
			begin				
				select @CURRId = 0
				select @CURRId =CURRENCYID from currency where lower(CURRENCYISOCODE) = lower(@rv_CurISOcode)
				if isnull(@CURRId,0) <>0 
					select @RI_CURRENCYID = @CURRId
				
				if isnull(@CURRId,0) =0
					begin
						select @RI_CURRENCYID = isnull(@Prevcurrencyid,0)
						SELECT @RI_TOCURRENCY=@RI_CURRENCYID
						select @RI_FROMCURRENCY=CURRENCYID FROM BOOKING WHERE BOOKINGID=  @ri_BOOKINGID 
						if(@RI_TOCURRENCY<>@RI_FROMCURRENCY)
						begin
							declare @rd_TravelDate datetime
							SELECT TOP 1 @rd_TravelDate=BOOKEDOPTIONINDATE FROM BOOKED_OPTION BO
								INNER JOIN BOOKED_SERVICE BS ON (BS.BOOKEDSERVICEID=BO.BOOKEDSERVICEID AND BS.BOOKINGID=@ri_BOOKINGID)
								ORDER BY BOOKEDOPTIONINDATE  ASC
							--exec @rm_ReceiptAmount=dbo.udf_ROE_Conversion_B2CB2B @rm_ReceiptAmount,@RI_FROMCURRENCY,@RI_TOCURRENCY,@rd_TravelDate
							--boc Sanket(23)
							IF @i_ROEBASEDONBOOKINGDATE >0 
							BEGIN
								SELECT @LROUNDINGVALUECOST  =CURRENCYROUNDINGVALUE FROM CURRENCY WHERE CURRENCYID =@RI_TOCURRENCY 
								SELECT @i_ROEVALUE = DBO.UDF_UTL_GET_BOOKING_ROE (@ri_Bookingid, NULL, @RI_FROMCURRENCY, @RI_TOCURRENCY)
								SET @rm_ReceiptAmount =CEILING(ISNULL(((@RM_RECEIPTAMOUNT * ISNULL(@I_ROEVALUE,0)/@LROUNDINGVALUECOST)),0))*@LROUNDINGVALUECOST 
							END
							ELSE
							BEGIN									
							--eoc Sanket(23)
								exec @rm_ReceiptAmount=udf_ROE_Conversion_B2CB2B @rm_ReceiptAmount,@RI_FROMCURRENCY,@RI_TOCURRENCY,@rd_TravelDate
							END
						end
					end
			end
		--Pgaonkar eoc
		--The auth number should be reset so that other receipts do not pickup an existing auth number
		UPDATE BOOKING_CREDIT_CARD SET AUTH#=0 WHERE AUTH#=@rstr_receiptcreditcardauthorisationno
		--EOC Lucio(13)

		-- BOC Vinod(03)
		IF LEN(@rstr_receiptcreditcardno) < 16
		BEGIN        
			SET @i_length = 16 - LEN(@rstr_receiptcreditcardno)        
			SET @rstr_receiptcreditcardno = @rstr_receiptcreditcardno + SUBSTRING('00000000000000000', 1, @i_length)        
			SELECT @rstr_receiptcreditcardno = SUBSTRING(@rstr_receiptcreditcardno, 1, 4) + '-' + SUBSTRING(@rstr_receiptcreditcardno, 5, 6) + 
			   '-' + SUBSTRING(@rstr_receiptcreditcardno, 11, 5) -- Vinod(09)
		END         
		ELSE
		BEGIN
			IF SUBSTRING(@rstr_receiptcreditcardno, 1, 9) <> '<Encrypt>'  --Hrishikesh(11)
				SELECT @rstr_receiptcreditcardno = SUBSTRING(@rstr_receiptcreditcardno, 1, 4) + '-' + 
				SUBSTRING(@rstr_receiptcreditcardno, 5, 4) + '-' + SUBSTRING(@rstr_receiptcreditcardno, 9, 4) + 
				'-' + SUBSTRING(@rstr_receiptcreditcardno, 13, 4)  -- Vinod(09)
		END
		-- EOC Vinod(03)
		
		-- EOC Vinod(03)
		--BOC Lucio(10)
	 	if @rm_ReceiptAmount>0
	 	begin
			select @rm_receipttotal=0
	 		select @rm_receipttotal=@rm_ReceiptAmount
			--print '@rm_receipttotal=' + cast( @rm_receipttotal as varchar(50))
	 	end
		--EOC Lucio(10)
		--BOC Lucio(21)
		-- Insert the details into receipt table using usp_ins_receipt
		if(isnull(@riReceiptTypeID,0)>0)
		begin
			if exists (select 1 from receipt_type where receipttypeid=@riReceiptTypeID)
			begin
				select @ri_receipttypeid=ISNULL(@riReceiptTypeID,0)
			end
		end
		
		if (rtrim(Ltrim(ISNULL(@rvRECEIPTCREDITCARDNAMEONCARD,'')))<>'')
		begin
			select @rstr_receiptcreditcardnameoncard=rtrim(Ltrim(ISNULL(@rvRECEIPTCREDITCARDNAMEONCARD,'')))
			--this is put within this if condition because the dates passed from .net are always a value and can never be null
			select @rdt_receiptcreditcardstartdate=@rdtRECEIPTCREDITCARDSTARTDATE,@rdt_receiptcreditcardenddate=@rdtRECEIPTCREDITCARDENDDATE
		end
		
		if (rtrim(Ltrim(ISNULL(@rvcRECEIPTCREDITCARDNUMBER,'')))<>'')
		begin
			select @rstr_receiptcreditcardno=rtrim(Ltrim(ISNULL(@rvcRECEIPTCREDITCARDNUMBER,'')))
		end
		
		if (rtrim(Ltrim(ISNULL(@rvcRECEIPTCREDITCARDAUTHORISATIONNUMBER,'')))<>'')
		begin
			select @rstr_receiptcreditcardauthorisationno=rtrim(Ltrim(ISNULL(@rvcRECEIPTCREDITCARDAUTHORISATIONNUMBER,'')))
		end
		
		if (rtrim(Ltrim(ISNULL(@rvcRECEIPTCREDITCARDISSUENUMBER,'')))<>'')
		begin
			select @rstr_receiptcreditcardissueno=rtrim(Ltrim(ISNULL(@rvcRECEIPTCREDITCARDISSUENUMBER,'')))
		end
		
		if (rtrim(Ltrim(ISNULL(@rvcRECEIPTCREDITCARDVALIDATIONNUMBER,'')))<>'')
		begin
			select @rstr_receiptcreditcardvalidationno=rtrim(Ltrim(ISNULL(@rvcRECEIPTCREDITCARDVALIDATIONNUMBER,'')))
		end
		
		--Boc Shivanand(30)
		if exists (select 1 from CREDIT_CARD_TYPE where CREDITCARDTYPEID=@riRECEIPTCREDITCARDTYPEID)
		begin
			select @ri_creditcardtypeid=@riRECEIPTCREDITCARDTYPEID
		end
		--Eoc Shivanand(30)
		
		declare @ri_ClientID int,
		@ri_SMCPassengerID int

		if(isnull(@riRECEIPTCREDITCARDTYPEID,0)>0 and isnull(@rvcRECEIPTCREDITCARDNUMBER,'')<>'')--SVarshney(28)
		begin
			
			if exists (select 1 from CREDIT_CARD_TYPE where CREDITCARDTYPEID=@riRECEIPTCREDITCARDTYPEID)
			begin
				select @ri_creditcardtypeid=ISNULL(@riRECEIPTCREDITCARDTYPEID,0)
				if exists (select 1 from BOOKING where BOOKINGID=@ri_Bookingid and isnull(CLIENTID,0) >0)
					begin
						--declare @ri_ClientID int	--Clerance(41)
						select @ri_ClientID=clientid from BOOKING where BOOKINGID=@ri_Bookingid
						if not exists(select 1 from CLIENT_CREDIT_CARD where ltrim(rtrim(CLIENTCREDITCARDNUMBER))= ltrim(RTRIM(@rstr_receiptcreditcardno)))
							begin
								insert into CLIENT_CREDIT_CARD 
									(CCDECRYPTIONLAST4,
									CLIENTCREDITCARDDATEEXPIRY,
									CLIENTCREDITCARDDATEVALIDFROM,
									CLIENTCREDITCARDISSUENUMBER,
									CLIENTCREDITCARDNAME,
									CLIENTCREDITCARDNUMBER,
									CLIENTCREDITCARDVALIDATIONNUMBER,
									CLIENTID,
									CREDITCARDTYPEID)
								values
									(
									@rvcRECEIPTCREDITCARDLASTFOURDIGITS,
									@rdt_receiptcreditcardenddate,
									@rdt_receiptcreditcardstartdate,
									@rvcRECEIPTCREDITCARDISSUENUMBER,
									@rvRECEIPTCREDITCARDNAMEONCARD,
									@rvcRECEIPTCREDITCARDNUMBER,
									@rvcRECEIPTCREDITCARDVALIDATIONNUMBER,
									@ri_ClientID,
									@ri_creditcardtypeid
									)
										
							end
					end
				
				if exists (select 1 from PASSENGER p where p.BOOKINGID=@ri_Bookingid and ISNULL(p.SMCPASSENGERID,0)>0 and isnull(p.PASSENGERISLEADPASSENGER,0)=1	)
					begin
					
					--declare @ri_SMCPassengerID int	--Clerance(41)
					declare @ri_PassengerFinanceID int 
					select  top 1  @ri_SMCPassengerID=smcpassengerid from passenger p where isnull(smcpassengerid,0)>0 and isnull(p.PASSENGERISLEADPASSENGER,0)=1 and p.BOOKINGID=@ri_Bookingid
					--print 'herte'+ cast (isnull(@ri_SMCPassengerID,0) as varchar(10)) 
					if not exists (select 1 from PASSENGER_FINANCE pf,PASSENGER_CREDIT_CARD pcc where SMCPASSENGERID=@ri_SMCPassengerID and pf.SMCPASSENGERID=@ri_SMCPassengerID and  pcc.PASSENGERFINANCEID=pf.PASSENGERFINANCEID and ltrim(rtrim(pcc.PASSENGERCREDITCARDNUMBER))=LTRIM(RTRIM(@rvcRECEIPTCREDITCARDNUMBER)))
					begin
						select top 1 @ri_PassengerFinanceID=passengerfinanceid from PASSENGER_FINANCE where SMCPASSENGERID=@ri_SMCPassengerID
						if(ISNULL(@ri_PassengerFinanceID,0)>0)
							begin
								insert into PASSENGER_CREDIT_CARD(
									AUTH#,
									CCDECRYPTIONLAST4,
									CREDITCARDTYPEID,
									PASSENGERCREDITCARDEXPIRYDATE,
									PASSENGERCREDITCARDISSUENUMBER,
									PASSENGERCREDITCARDNAMEONCARD,
									PASSENGERCREDITCARDNUMBER,
									PASSENGERCREDITCARDVALIDATIONNUMBER,
									PASSENGERCREDITCARDVALIDFROM,
									PASSENGERFINANCEID
								)
								values
								(
									@rvcRECEIPTCREDITCARDAUTHORISATIONNUMBER,
									@rvcRECEIPTCREDITCARDLASTFOURDIGITS,
									@ri_creditcardtypeid,
									@rdt_receiptcreditcardenddate,
									@rvcRECEIPTCREDITCARDISSUENUMBER,
									@rvRECEIPTCREDITCARDNAMEONCARD,
									@rvcRECEIPTCREDITCARDNUMBER,
									@rvcRECEIPTCREDITCARDVALIDATIONNUMBER,
									@rdt_receiptcreditcardstartdate,
									@ri_PassengerFinanceID
								)
							end
						end
					end
			end
		end
		--EOC Lucio(21)
		
		
			--BOC Azim(33)
		if exists (select currencyid from CURRENCY where CURRENCYISOCODE =@rv_CurISOcode) 
		begin
			select @ri_currencyid =(select currencyid from CURRENCY where CURRENCYISOCODE =@rv_CurISOcode)
			
		end 
		--EOC Azim(33)


		--BOC Clerance(41)
		IF ISNULL(@RVC_PAYMENTTOKEN,'') <> '' --Clerance(43)
		BEGIN
		DECLARE @I_PAYMENTTOKENID INT,
		@I_ORGANISATIONID INT,
		@I_CREDITCARDAUTHORITYID INT

		DECLARE @TBL_CCA TABLE
		(
			ORGANISATIONSETTINGSID INT,
			CREDITCARDAUTHORITYID INT,
			ORGANISATIONID INT
		)
		
		INSERT INTO @TBL_CCA
		(
			ORGANISATIONSETTINGSID,
			CREDITCARDAUTHORITYID,
			ORGANISATIONID
		)
		EXEC DBO.USP_GET_DEFAULT_CREDIT_CARD_AUTHORITY NULL,@RI_BOOKINGID 

		SELECT TOP 1 
		@I_CREDITCARDAUTHORITYID = CREDITCARDAUTHORITYID,
		@I_ORGANISATIONID = ORGANISATIONID  
		FROM @TBL_CCA		

		IF EXISTS(SELECT 1 FROM DBO.ORGANISATION_SETTINGS OS WITH(NOLOCK) 
						WHERE OS.ORGANISATIONID = @I_ORGANISATIONID AND ISNULL(TOKENIZATION,0) = 1 )
		BEGIN			

			SELECT @I_PAYMENTTOKENID = PAYMENTTOKENID 
			FROM DBO.PAYMENT_TOKEN WITH(NOLOCK) 
			WHERE PAYMENTTOKEN = @RVC_PAYMENTTOKEN AND (CLIENTID = @RI_CLIENTID OR SMCPASSENGERID = @RI_SMCPASSENGERID)	

			IF @I_PAYMENTTOKENID IS NULL
			BEGIN
				EXEC DBO.USP_INS_PAYMENT_TOKEN @I_PAYMENTTOKENID OUTPUT,@RI_SMCPASSENGERID,@RI_CLIENTID,@RVC_PAYMENTTOKEN,@RVCRECEIPTCREDITCARDLASTFOURDIGITS, --Clerance(42)
											@RVRECEIPTCREDITCARDNAMEONCARD,@RDTRECEIPTCREDITCARDSTARTDATE ,@RDTRECEIPTCREDITCARDENDDATE,@RIRECEIPTCREDITCARDTYPEID,
											@I_ORGANISATIONID,@I_CREDITCARDAUTHORITYID

			END
		END
		END
		--EOC Clerance(41)
		
		 exec usp_ins_receipt  @ri_receiptid out,null,@rdt_receiptdate,                    
		 @rvcRECEIPTDESCRIPTION,              
		 @rm_receipttotal,                    
		 @rstr_receiptcreditcardnameoncard,                 
		 @rdt_receiptcreditcardstartdate,                   
		 @rdt_receiptcreditcardenddate,                    
		 @rstr_receiptcreditcardno,
		 @rstr_receiptcreditcardauthorisationno,                  
		 @rstr_receiptcreditcardissueno,                   
		 @rstr_receiptcreditcardvalidationno,                  
		 @ri_receipttypeid,                    
		 @ri_currencyid,@ri_bookingid,                    
		 @ri_creditcardtypeid,                    
		 @ri_systemuserid   ,
		 @rm_CREDITCARDCHARGEAMOUNT=@rm_CommissionAmount ,
		@rstr_RECEIPTCREDITCARDNODECRYPTED=@rstr_CCLast4Digits--Lucio(19)
		  ,@rdt_RECEIPTDATETIME = @dt_RECEIPTDATETIME --Irshad(25)
        ,@ri_INSTALMENTDISCOUNTID = @ri_INSTALMENTDISCOUNTID --Shivanand(24)
		,@rm_INSTALMENTVALUE = @rm_INSTALMENTVALUE --Shivanand(24)
		,@dc_DISCOUNTPERCENT = @dc_DISCOUNTPERCENT --Shivanand(24)
		--BOC Kedar(27)
		,@RSTR_RECEIPTCREDITCARDTRANSACTIONID = @RSTR_RECEIPTCREDITCARDTRANSACTIONID
		,@VC_GATEWAYSPECIFICDATA = @VC_GATEWAYSPECIFICDATA 
		--EOC Kedar(27)
		--Boc Shivanand(29)
		,@RD_CREDITEDACDATE = NULL
		,@RD_BANKCODETYPEID = NULL
		,@VC_CAMPAIGNCODE = @VC_CAMPAIGNCODE
		--Eoc Shivanand(29)
		--BOC Kalpi(36)
		,@RM_ORIGINALAMOUNT = @RM_ORIGINALAMOUNT
		,@RI_ORIGINALCURRENCYID = @RI_ORIGINALCURRENCYID
		,@RF_APPLIEDROE = @RF_APPLIEDROE
		--EOC Kalpi(36)
		--Boc Sundeep
		,@RF_TAXPERCENT=@RF_TAXPERCENT
		,@RM_TAXVALUE =@RM_TAXVALUE
		,@RM_NETVALUEEXCLUDINGTAX =@RM_NETVALUEEXCLUDINGTAX
		--Eoc Sundeep
		,@RI_VOUCHERTYPEID=@RI_VOUCHERTYPEID --Geetesh(38)
		,@RVC_VOUCHERCODE=@RVC_VOUCHERCODE--Archana(42)
		,@RI_PAYMENTTOKENID = @I_PAYMENTTOKENID --Clerance(41)
		,@RI_POINTOFTRANSACTIONTYPEID =@RI_POINTOFTRANSACTIONTYPEID  --Diptesh H(43)
		if isnull(@ri_receiptid,0)>0		
		 begin              
			--select @rstr_selectedpassengerids='' Jaymala(26) commented
			select @ri_financialtransactionid=null
			 
			select @ri_receiptnumber=receiptnumber from receipt where receiptid=@ri_receiptid              
			
			SELECT @rv_LoggedInUser =ISNULL(SYSTEMUSERNAME,'') FROM SYSTEMUSER WHERE SYSTEMUSERID=  @ri_systemuserid  --Pradnya(47)        
			  	while exists(select top 1 pid from #tempReceiptData)
				  begin
				     select top 1 @ri_financialtransactionid=financialtransactionid,
				     --@rm_receiptvalue=invoiceamount from #tempReceiptData --Commented by Sajjan.H(15)
					 --BOC Sajjan.H(15)
						@rm_receiptvalue=invoiceamount-paidamount FROM #tempReceiptData
						IF(@rm_receiptvalue>@rm_receipttotal)
						BEGIN
							SET @rm_receiptvalue=@rm_receipttotal
							SET @rm_receipttotal = @rm_receipttotal-@rm_receiptvalue
						END
						ELSE
						IF (SELECT COUNT(*) FROM #tempReceiptData)>1
							SET @rm_receipttotal = @rm_receipttotal-@rm_receiptvalue
						ELSE
							SET @rm_receiptvalue = @rm_receipttotal
						IF(@rm_receiptvalue<>0)--Satish(37)--negative receipts details are not inserted due to > 0 condition.
						BEGIN
					 --EOC Sajjan.H(15)
					 --BOC Sandip(32)
						IF EXISTS(SELECT ID FROM @INVOICEIDS)
						BEGIN
						 DECLARE @INVOICEID INT
						 DECLARE @PRICE MONEY
						 WHILE EXISTS(SELECT TOP 1 ID FROM @INVOICEIDS)
						 BEGIN
						 SELECT TOP 1 @INVOICEID= ID,@PRICE=PRICE FROM @INVOICEIDS
						 EXEC USP_INS_RECEIPT_DETAIL NULL, @PRICE, 1, @RI_RECEIPTID, @INVOICEID, @RSTR_SELECTEDPASSENGERIDS,@rv_LoggedInUser,0,@RI_AGENTCREDITRECEIPTID --Pradnya(47)
						 DELETE FROM @INVOICEIDS WHERE ID=@INVOICEID
						 END
						END
						ELSE--EOC Sandip(32)
						exec usp_INS_RECEIPT_DETAIL null, @rm_receiptvalue, 1, @ri_receiptid, @ri_financialtransactionid, @rstr_selectedpassengerids,@rv_LoggedInUser,@rb_SKIPANTICIPOCONSUMPTION,@RI_AGENTCREDITRECEIPTID--, null Vinod (04) Commented --Pradnya(47) --RahulH(49)
						END
						delete from #tempReceiptData where financialtransactionid=@ri_financialtransactionid                    
						
						--Raish BOC(22)
						IF @ri_financialtransactionid IS NULL
						BEGIN
							Delete from #tempReceiptData Where financialtransactionid IS NULL
						END
						--Raish EOC(22)						

				
				  end
				--BOC Lucio(06)
			  	exec usp_INSERT_CREDIT_CARD_CHARGE_SERVICE @ri_BOOKINGID,@ri_receiptid,0
		        --EOC Lucio(06)
				--BOC Mosam(39)
				IF EXISTS (SELECT 1  FROM SYSTEM_SETTINGS_FIELD WHERE SYSTEMSETTINGSFIELDNAME = 'EVALUATIONCREDITLIMITBASEDONBRORBSR' AND SYSTEMSETTINGSFIELDVALUE = '1') --CHECKS FOR FLAG
				BEGIN
						IF EXISTS (SELECT 1 from BOOKING where BOOKINGID=@ri_Bookingid and isnull(CLIENTID,0) >0) --CHECKS IF BOOKING IS DONE BY CLIENT
						BEGIN
						DECLARE @i_BookingClientID int 
						     SELECT @i_BookingClientID=CLIENTID from BOOKING where BOOKINGID=@ri_Bookingid
						     IF EXISTS (SELECT 1 FROM RECEIPT_TYPE WHERE RECEIPTTYPEID = @ri_receipttypeid AND ISNULL(RECEIPTTYPEAGENTCREDITREDEMPTION , 0) = 1) --CHECKS FOR 'CREDIT RECEIPTS'   
								     BEGIN
									   DECLARE @m_AvailableAmount MONEY,  @i_BookingCurrencyID INT
									    SELECT @I_BOOKINGCURRENCYID = CURRENCYID FROM BOOKING WHERE BOOKINGID=@ri_BookingID

												DECLARE @tblAGENTCREDITRECEIPTSWITHROE TABLE
														(				
															BalanceLimitAmount MONEY,
															LimitAmount MONEY,
															UTILISEDAMOUNT MONEY,
															EXCHANGERATE MONEY			
														)
	
												INSERT INTO @tblAGENTCREDITRECEIPTSWITHROE
													EXEC USP_GET_CLIENT_CREDIT_RECEIPTS_WITH_EXCHANGERATE @ri_ClientID,@i_BookingCurrencyID 

												SELECT @m_AvailableAmount = (SUM(ISNULL(BalanceLimitAmount,0.00))) FROM @tblAGENTCREDITRECEIPTSWITHROE 
												
												IF (@m_AvailableAmount > 0)
												BEGIN
													 --BOC Gayeetri(40) : Commented and rewritten
												     --EXEC USP_UPD_CLIENT_CREDIT_REDEMPTION @ri_Bookingid ,@ri_receiptid , @m_AvailableAmount , @ri_receipttypeid,@riSystemUserID   --DEDUCT THE VALUE OF THE RECEIPT FROM AGENCY LEVEL
													   DECLARE @I_RECEIPTCURRENCYID INT --Gautami(41)
	                                                   SELECT @I_RECEIPTCURRENCYID = CURRENCYID FROM RECEIPT WHERE RECEIPTID=@ri_receiptid  --Gautami(41)
													   EXEC USP_UPD_CLIENT_CREDIT_REDEMPTION @ri_Bookingid ,@ri_receiptid,@rm_receipttotal,@riSystemUserID,@I_RECEIPTCURRENCYID,0,@RI_AGENTCREDITRECEIPTID  --Gautami(41) --Pradnya(47)
													 --EOC Gayeetri(40)
												END
							  END
						END
				END
				--EOC Mosam(39)
		end		
	end 
drop table #tempBookingInvoiceDet
drop table #tempReceiptData
end






GO
SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


---------------

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
if exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[USP_CALCULATE_MULTIPLE_TAX_FOR_BOOKED_OPTION_B2CB2B]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
drop procedure [dbo].[USP_CALCULATE_MULTIPLE_TAX_FOR_BOOKED_OPTION_B2CB2B]
GO
/************************************************************************************************************************  
* Stored Proc  : USP_TSHOTELAPI_CALCULATE_MULTIPLE_TAX_FOR_BOOKED_OPTION
* Created by   : Abhijit Karpe  
* Date         : 6th Aug, 2008  
* Description   : Recalculates Tax based on the Net Value for Multiple Taxes
*    
* Modification History:  
*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  
* SNo Who   Date  Description            Client   Specification  
* -----------------------------------------------------------------------------------------------------------------------  
*  
************************************************************************************************************************/  
/************************************************************************************************************************  
             CALLED FROM
1) HAPI - BookingImport.cpp: InsertBookedOptions,AmendBookedOptions
*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  
* SNo 	Who   		Date   		 Description           							   		        Client   Specification  
* 1     Sarika      8 Mar 2012   Originally created SP 
                                 USP_TSHOTELAPI_CALCULATE_MULTIPLE_TAX_FOR_BOOKED_OPTION
                                 is renamed USP_CALCULATE_MULTIPLE_TAX_FOR_BOOKED_OPTION_B2CB2B
                                 and moved from Hotel API to B2C
************************************************************************************************************************/  
CREATE PROCEDURE [dbo].[USP_CALCULATE_MULTIPLE_TAX_FOR_BOOKED_OPTION_B2CB2B]
   @ri_BOOKEDOPTIONID   INT                            
AS      
BEGIN      
 DECLARE @dt_INDATE DATETIME,@dt_OUTDATE DATETIME,     
 @i_COSTCURRENCYID INT,@i_SELLCURRENCYID INT,                    
 @d_COSTROE    DECIMAL(28,14),@d_SELLROE    DECIMAL(28,14),    
 @i_COSTPRICEID INT ,@i_SELLPRICEID INT,@i_PACKAGEPRICEID INT,                   
 @i_PACKAGEOPTIONCOSTID INT,                    
 @d_TOTALCOST    DECIMAL(28,14),@d_TOTALSELL    DECIMAL(28,14),                    
 @d_COSTTAX    DECIMAL(28,14), @d_SELLTAX     DECIMAL(28,14), @d_TOTALSELLTAX DECIMAL(28,14),
 @d_COMMISSIONAMOUNT DECIMAL(28,14),       
 @i_PassengerCount INT,                    
 @i_NightsCount INT,                    
 @i_ChildAge INT,                    
 @i_ChildRecCount INT, -- Number of child records     
 @i_NumberOfChild INT,    
 @i_Cnt INT,    
 @d_BCRV   DECIMAL(10,5),    
 @d_CCRV DECIMAL(28,14),
    @i_BookingID INT,    
    @i_BOOKINGCURRENCYID INT,    
    @i_BOOKEDSERVICEID INT,    
    @b_IsInsuranceService bit, @i_BOOKEDCHILDRATEID INT,    
 @b_BOOKINGCLIENTISNETRATED bit
 DECLARE @I_ERRORNUM INT       
 DECLARE @tblChildDetails TABLE 
 (     
  CID int identity,    
  BOOKEDCHILDRATEID INT,
  TOTALSELL DECIMAL(28,14),    
  NUMBEROFCHILD INT,    
  CHILDAGE INT    
 )    
    -- TOTAL TAX =  Total ADULT TAX + Total Child Tax + AddOn Tax    
 set @d_TOTALSELLTAX = 0      
 set @i_COSTPRICEID = NULL      
 set @i_SELLPRICEID = NULL      
 set @i_PACKAGEPRICEID = NULL      
    set @d_COSTTAX = NULL    
 set @d_SELLTAX = NULL    
 set @i_BOOKEDSERVICEID = NULL    
 SELECT @dt_INDATE = BOOKEDOPTIONINDATE,@dt_OUTDATE = BOOKEDOPTIONOUTDATE,      
 @i_COSTCURRENCYID = COST_CURRENCYID,@i_SELLCURRENCYID= SELL_CURRENCYID,      
 @d_COSTROE = BOOKEDOPTIONCOSTROE,      
 @d_SELLROE = BOOKEDOPTIONROE,      
 @i_COSTPRICEID = ORIGINALCOST_PRICEID,@i_SELLPRICEID = ORIGINALSELL_PRICEID,@i_PACKAGEPRICEID=PACKAGEPRICEID,      
 @d_TOTALSELL = BOOKEDOPTIONTOTALSELLINGAMOUNT,      
 @i_PassengerCount = BOOKEDOPTIONNUMBEROFPASSENGERS,      
 @i_NightsCount = BOOKEDOPTIONNUMBEROFNIGHTS,    
 @i_BOOKEDSERVICEID = BO.BOOKEDSERVICEID,    
 @i_BookingID =     
 case when ISNULL(BOOKEDPACKAGEID,0)>0 then    
  (Select BookingID from Booked_package where BookedPackageID = BO.BOOKEDPACKAGEID)      
 else    
  (Select BookingID from Booked_Service where BookedServiceID = BO.BOOKEDSERVICEID)      
 end ,  
 @d_COMMISSIONAMOUNT = ISNULL(BOOKEDOPTIONCOMMISSIONAMOUNT,0)  
from BOOKED_OPTION BO where BOOKEDOPTIONID = @ri_BOOKEDOPTIONID      
--Tax Should not be calculated on Insurance Services    
 IF ISNULL(@i_BOOKEDSERVICEID,0) > 0    
 BEGIN    
  SELECT @b_IsInsuranceService = ISNULL(SERVICETYPETRAVELINSURANCE,0) FROM BOOKED_OPTION BO    
  INNER JOIN BOOKED_SERVICE BS ON BS.BOOKEDSERVICEID= BO.BOOKEDSERVICEID    
  INNER JOIN SERVICE S ON S.SERVICEID = BS.SERVICEID    
  INNER JOIN SERVICE_TYPE ST ON  ST.SERVICETYPEID = S.SERVICETYPEID    
  where BOOKEDOPTIONID = @ri_BOOKEDOPTIONID    
  if @b_IsInsuranceService = 1    
   return    
 END    
 select @b_BOOKINGCLIENTISNETRATED = ISNULL(BOOKINGCLIENTISNETRATED,0) from Booking where BookingID = @i_BookingID 
 if @b_BOOKINGCLIENTISNETRATED = 1
 	set @d_TOTALSELL = @d_TOTALSELL - @d_COMMISSIONAMOUNT       
--Calculate Adult Tax    
 EXEC @I_ERRORNUM = dbo.usp_CALCULATE_COST_AND_SELL_TAX @dt_INDATE,@dt_OUTDATE,@i_COSTCURRENCYID,@i_SELLCURRENCYID      
                   ,@d_COSTROE,@d_SELLROE,@i_COSTPRICEID,@i_SELLPRICEID,@i_PACKAGEPRICEID,NULL,NULL,@d_TOTALSELL,@d_COSTTAX output,@d_SELLTAX output,      
                   @i_PassengerCount,@i_NightsCount,NULL,@ri_BOOKEDOPTIONID         
 if @I_ERRORNUM > 0      
  return @I_ERRORNUM      
 set @d_TOTALSELLTAX = @d_TOTALSELLTAX + ISNULL(@d_SELLTAX,0)
--Calculate Add - on Tax    
 set @d_SELLTAX = 0    
 EXEC @I_ERRORNUM = dbo.usp_CALCULATE_AGENT_PASSENGER_ADDON_TAX  @ri_BOOKEDOPTIONID,@d_TOTALSELL,@d_SELLTAX output,@dt_INDATE,@dt_OUTDATE      
 if @I_ERRORNUM > 0      
  return @I_ERRORNUM      
 set @d_TOTALSELLTAX = @d_TOTALSELLTAX + ISNULL(@d_SELLTAX,0)
 -- Rounding the tax value    
 SELECT @i_BOOKINGCURRENCYID = CURRENCYID FROM dbo.BOOKING WHERE BOOKINGID = @i_BOOKINGID     
 SELECT @d_BCRV = CURRENCYROUNDINGVALUE FROM CURRENCY WHERE CURRENCYID = @i_BOOKINGCURRENCYID      
 SELECT @d_CCRV = CURRENCYROUNDINGVALUE FROM dbo.CURRENCY WHERE CURRENCYID = @i_COSTCURRENCYID  
 SELECT @d_TOTALSELLTAX = (ROUND(CEILING(@d_TOTALSELLTAX / @d_BCRV),4) * @d_BCRV), 
	@d_SELLTAX = (ROUND(CEILING(@d_SELLTAX / @d_BCRV),4) * @d_BCRV),    
        @d_COSTTAX = ROUND(CEILING(@d_COSTTAX / @d_CCRV),4) * (@d_CCRV)
 -- Set the Total Tax    
update 	BOOKED_OPTION 
SET 	BOOKEDOPTIONSELLTAX =  @d_TOTALSELLTAX + ISNULL(ADDONTAX,0),
	GSTTaxCodeValue = IsNull(@d_SELLTAX, 0), 
        BOOKEDOPTIONCOSTTAX = IsNULL(@d_COSTTAX,0)
where BOOKEDOPTIONID = @ri_BOOKEDOPTIONID      
--Calculate child tax      
 insert into @tblChildDetails    
  select BOOKEDCHILDRATEID,BOOKEDCHILDRATESELLAMOUNT,BOOKEDCHILDRATEQUANTITY,BOOKEDCHILDRATEAGE from BOOKED_CHILD_RATE where BOOKEDOPTIONID = @ri_BOOKEDOPTIONID    
 set @i_Cnt = 1    
 select @i_ChildRecCount = count(*) from @tblChildDetails    
 WHILE @i_Cnt<=@i_ChildRecCount    
 BEGIN     
  set @d_TOTALSELLTAX = 0      
  set @i_COSTPRICEID = NULL      
  set @i_SELLPRICEID = NULL      
  set @i_PACKAGEPRICEID = NULL      
  set @d_COSTTAX = NULL    
  set @d_SELLTAX = NULL    
  SET @i_BOOKEDCHILDRATEID = NULL    
  select @i_BOOKEDCHILDRATEID = BOOKEDCHILDRATEID ,@d_TOTALSELL = TOTALSELL,@i_NumberOfChild = NUMBEROFCHILD , @i_ChildAge = CHILDAGE 
	from  @tblChildDetails   where CID = @i_Cnt      
  EXEC @I_ERRORNUM = dbo.usp_CALCULATE_COST_AND_SELL_TAX @dt_INDATE,@dt_OUTDATE,@i_COSTCURRENCYID,@i_SELLCURRENCYID      
                   ,@d_COSTROE,@d_SELLROE,@i_COSTPRICEID,@i_SELLPRICEID,@i_PACKAGEPRICEID,NULL,NULL,@d_TOTALSELL,@d_COSTTAX output,@d_SELLTAX output,      
                   @i_NumberOfChild,@i_NightsCount,@i_ChildAge,@ri_BOOKEDOPTIONID         
  if @I_ERRORNUM > 0  
   return @I_ERRORNUM      
  set @d_TOTALSELLTAX = @d_TOTALSELLTAX + ISNULL(@d_SELLTAX,0)
  set @d_SELLTAX = NULL
	EXEC @I_ERRORNUM = dbo.usp_CALCULATE_AGENT_PASSENGER_ADDON_TAX  @ri_BOOKEDOPTIONID,@d_TOTALSELL,@d_SELLTAX output,
				@dt_INDATE,@dt_OUTDATE, @i_BOOKEDCHILDRATEID      
	if @I_ERRORNUM > 0      
		return @I_ERRORNUM      
	set @d_TOTALSELLTAX = @d_TOTALSELLTAX + ISNULL(@d_SELLTAX,0)
 SELECT @d_TOTALSELLTAX = (ROUND(CEILING(@d_TOTALSELLTAX / @d_BCRV),4) * @d_BCRV), 
	@d_SELLTAX = (ROUND(CEILING(@d_SELLTAX / @d_BCRV),4) * @d_BCRV),    
	@d_COSTTAX = ROUND(CEILING(@d_COSTTAX / @d_CCRV),4) * (@d_CCRV)
	Update Booked_Child_rate
	Set BookedChildRateSellTax = @d_TOTALSELLTAX + ISNULL(BOOKEDCHILDRATEADDONTAX,0)
	, GSTTaxCodeValue = IsNull(@d_SELLTAX, 0)
        ,BookedChildRateCostTax = IsNull(@d_COSTTAX, 0)
	Where BookedChildRateID = @i_BOOKEDCHILDRATEID      
  set @i_Cnt = @i_Cnt +1    
 END    
 return @@ERROR      
END 
GO

-----------

set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go
if exists (select top 1 1 from sysobjects where id = object_id(N'[dbo].[usp_Get_TSHotel_GetServicesForTSHotel_B2C]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
drop procedure [dbo].[usp_Get_TSHotel_GetServicesForTSHotel_B2C]
GO
/**************************************************************************
* Created by  : Vernal D'costa
* On	      : 31st Aug, 2010
* Description : Altered existing hapi sp according to the required  hapi.net processing.
* Modification History :
* 	Who		When		What
* 	---   		----    	----
* 1   GGOSAVI     28-05-07        Changes to include recommended product search.This is for TS WEB.NET.
* 2   VIVEK       04-08-07        Changes made to fetch INCREMENTAL STAR SERVICE
* 3   GGOSAVI     22-08-07        Fixed issue 8236-The problem was that if there two region with same name
                                 It takes top 1. 
* 4   VIVEK       25-Aug-2007     Changes made to fetch Transfer Arrival/Departure SERVICEs     
* 5   Sweta	 22 Feb 2008	 Added ISDAYWISERELEASEPERIOD  
* 6   Ravi	 25-Feb-2008	Temporaryli commented  this chages  
* 7   GGosavi     23-Dec-2008     Issue 13712
* 8   Vernal 31 aug 2010    Altered existing hapi sp according to the required  hapi.net processing.
* 9   Vernal 1 sep 2010     ServiceInfoRequired,Imagerequired,Matchcodedetailsrequired
* 10  Vernal 2 sep 2010     Service search based on regionid 
* 11  Vernal 15 sep 2010    Source name and id
* 12  Vernal 21 sep 2010    Removed image processing
  13  Julia  20 Oct 2010    Added Extra Tags for TS.NET
  14  Derik  16 Nov 2010	Added extra request fields  
  15  Harshad Teli	21 Feb 2011	Added ISNULL check addresspostcode for TS.NET
  16  Melvita 27 Apr 2011   Added @ri_CalledFrom
  17  Abhijit L. 29 Sept 2011 Added ServiceStatusName
  18  Savira  1 Feb 2012   Issue fix 30763 for TSV2 
  19  Vanessa 17 Feb 2012  Considered Booking Search and No Bookings flag of Service status and supplier status in case of TSV2
  20 Shivanand  27 Feb 2012 Added @ServiceTypeIDs varchar(200) [Client:ETS || CR:ETS40]
  21  Leroy		15 Nov 2012		Changes to return End Point Name.
  22  Sriker	25 Jan 2012		Added @rb_IsFastBuildService
  23  Savira    27 Mar 2012     Added @STARTDATE and @ENDDATE and returned SPECIALOFFERSCOUNT
  24  Harshad   18 Jun 2013     Issue fix 43580
  25  Deval     25 Jun 2013     Fixed issue 43844
  26 Sarika     16 Jul 2013     Fixed TCA Issue - 44103 - Search Priority Issues
  27  SVarshney 03 Sep 2013		Fixed Ticket 45303: Increased the size of @SQLtoRun to Varchar(max) [Client: Cullinan]
  28 Salim Mandrekar 04 Nov 2013	Fixed issue 46607-GetServicesPricesAndAvailability - rating (CEREXT)
  29 Mahadev     11 Feb 2014         Fixed TCA Issue 41134- Available for nights not applied when making booking
  30 Nagendra	 15 Sep 2014	GAR-190 Multi geo-location search using Enhanced Service Search		
  31  Amogh     3 April 2014  Ticket 50479 : Added Distinct to Query returning Same ServiceID twice causing Primary Key Violation.
  32  Swapnil	11 Jun 2014	   Optimization - Suppressed fetching of services which are inactive for service search
  33  Amey.R	03 Jul 2014		Fixed issue QATSVTWO-688, Added BETWEEN condition for startdate and enddate for showing special offer in service search
  34  Leslie     4 sep 2014 Fixed Issue 52535
  35  Yuvraj    16 Sep 2014 Optmization Fixes.
  35 Vimlesh	10 Sep 2014		CR Changes DT-15 Get Services prices avaliability
  36 Vimlesh	24 Dec 2014		Issue# 58385 Best Seller Request Fixed
  37 Ankita N   21 MAr 2015     Replicated Kavita's changes for ew-46 (multilingual enhancement)
  38 kartheek   13 Nov 2014     Added CancellationPolicyID and SupplierCancellationPolicyID - CR:TUIIN-4 - Cancellation Policies [Client : TUI]
  38 Gautami    16 Oct 2015		CR:DT-302 67448 Special Offer Display
  39 Jeogan		21 May 2015		Added tag ReturnOnlyFastBuildServices in ServiceSearch [ATOP-284 | Abreu TOP]
  40 Neil S     16 Jun 2015     Fixed Ticket#65176-Special Offers not appearing when selected
  30 Gayeetri   12 Mar 2015     ETUR-164 - ETS-143b Special Offer Start Date validation & fixed rates
  30 Saroj       03 Feb 2014       Changed the functionality to return star ratings instead of default ratings
  31 Vanessa    08 Oct 2015     ETUR-271 - ETS-180 Special Offer - Apply Within Rule Dates
  33 Swapnil	21 Aug 2014		Optimization Changes [Creative] + Optimization - Suppressed fetching of services which are inactive for service search [Creative]
  41 Gitesh Naik 13 Nov 2015	Optimization 69870
  42 Nagesh      22 Jan 2016    Fixed Issue# QATSVTWO-3752
  32 Arun		02 Mar 2015		61443-Travalco Issue Fix - Changed the datatype to Varchar(MAX).
  33 Arun		 24 May 2016	CR TRAV-159 Secondary Region Assignment for Services Client - Travalco
  34 Arun		 16 Jun 2016	Fixed issue QATSVTWO-4902
  35 Shivanand   15 Sep 2016    Fixed issue QATSVTWO-5732
  35 Prita		17 Aug 2016		Fixed Issue:78073 Client:Cullinan[Booking PP issue] 
  34 Ganapatrao 17 Sep 2014     Added changes for TCA137 Client:TCASIA 		
  42 Lorraine   07 Apr 2016     QADNN-517 “TravelStudio_Tansfer” endpoint service when imported, It requires the ‘region’ for the service to be imported as “Country” (Level 3 in Geo tree) for service to be searchable in DNN. Currently Region is not taken as Country.
  43 Shivanand  02 Nov 2016     Fixed Issue QAAPI-1049
  44 VishalNaik 16 Dec 2016		Fixed Issue QAAPI-1071 Services of the 'InActive' supplier are returned in the response of method GetServicesPricesAndAvailability. 
  35 Arun	     08 Aug 2016	CR: TRAV-142 Enhanced Flexible Packages
  36 Shamil		 09 Mar 2017	Optimisation #QAAPI-1150
  37 Arun		 17 Apr 2017	Fixed issue QAAPI-1185
  45 Lorraine	09 Feb 2017		DA-183 Cancellation Policies in GSPAA search request 
  46 Tanmay		10 Feb 2017		fixed issue QATSVTWO-6833 rewrote the pick up drop off filter to handle pick up location type and drop off location type.
  47 Rohitk		25 Mar 2016		Fixed:84214
  45 Shakeel    14 Sep 2017     DSO -Performance optimization
  46 Suraj      18 Sep 2017     DSO -Performance optimization
  36 Sandip P.   09 Aug 2017    Fixed issue 86270 (Optimization)
  37 Azim		10 Sep 2017     Fixed issue QATSVTWO-8683,Special offer icon is not shown and Service Prices are shown zero in Booking>Service Search results if Apply Early Booking offer is checked while applying special offer rule to the Service.
  38 RAMA       28 DEC 2017	    Fixed issue 90189:Geo Tree not right - Service Search (Same parent and child region name)
  39 Shantaram	01 Mar 2018		Fixed ticket 89154 
  40 Gitesh Naik 12 Aprl 2018	Fixed Issue : QATSVTWO-9163 -> May Release 2018-Unable to create a fast build service
  40 Abhijit L. 11 Apr 2018		Issue Fix: QATSVTWO-9283
  41 Suchina    30 Apr 2018     Fixed Issue : ticket No. 93157 : Simple non-Accommodation service with Per Person charging policy. No specials or limitations. - Estimated rates
  41 Pratham     27 Apr 2018    QATSVTWO-9304
  42 Suraj		11 May 2018		Changes for QATSVTWO-9304 May Release 2018 - ANK - High response time observed in Enhanced Service Search [Client:A&K]
  43 Suraj		18 May 2018		Changes for QATSVTWO-9304 May Release 2018 - ANK - High response time observed in Enhanced Service Search [Client:A&K]
  44 Neil S		14 Feb 2017		Fixed Ticket#83007-API - Bug - Star-rating in GSPA - Malaysia doesn't show
  48 Xenio		13 June 2018	Fixed:94417 DNN not showing all product
  47 Poorva N   18 Jul 2018		Fixed Ticket#94413-FIT Product Search section
  47 Wayne		25 Oct 2018		95364 - Performance: Service Search. 
  48 Suraj		11 April 2018	CR:Intrepid group: IG-167: Introduce Short Name in Service Search
  49 Apeksha	24 Nov 2018		Fixed Issue 97849 : Service Search - Results - Special Offers
  50 Prudhvi	14 Dec 2018     Fixed Issue 98185 :  Service shows twice in search results
  51 Aman		01 Mar 2019		Fixed Issue 98769 : Service shows twice in search results
  51 Najeeb		12 Mar 2019		ICR DA-614 : Only flag property functionality for Operations Module - 100018
  52 Anuja		29 Mar 2019		Fixed issue QATSVTWO-10965
  53 Bharat     06 June 2019    Fixed Issue 98284 - Problems booking Transfer services
  54 Poonam     26 Sep 2019     Fixed issue 100403 : DA Test Environment (419.1.3) - Incorrect Services showing on transfer search

  54 ManojG     03 Oct 2019     CR:TSVTWO-5419 Booking Migration - Service
  55 ManojG     28 Nov 2019     CR:AKBVTWO-477 Circuit Special Offers
  56 Gitesh Naik	07 Jan 2020 Issue : QATSVTWO-13140 Circuit Special Offers
**************************************************************************/



Create procedure [dbo].[usp_Get_TSHotel_GetServicesForTSHotel_B2C]
@ServiceIDs varchar(max) =NULL,  -- Provide comma formatted ServiceIDs or LocationName  --leslie(34) changed from 8000 to max
@locationName  varchar(2048) =NULL,
@ServiceTypeRatingName  varchar(2048) =NULL,
@ServiceTypeID int =0,
@ISRECOMMENDEDPRODUCT int =0 ,              --ggosavi(01)
@INCSTARSERVICES int =0,                     --VIVEK(02)
@ServiceTypeCategoryArrDep int =NULL ,           --VIVEK(04)
@ServiceInfoRequired int=1, --Vernal(9)
--@Imagerequired int=1 ,--vernal(9)--vernal(12)
@Matchcodedetailsrequired int=0, --vernal(9)
@locationID int = 0,          --vernal(10)
--BOC-Derik(14)   
@SupplierName varchar(100) =NULL,  
 @ServiceTypeRatingTypeID int = 0,   
 @ServiceTypeRatingID int = 0,         
 @PostCode varchar(100) =NULL,  
 @ServiceTypeOptionIds varchar(max) =NULL    
--EOC-Derik(14)
 ,@ri_CalledFrom INT =0 --Melvita(16)
 ,@ServiceStatusRequired Int = NULL --Abhijit L.(17)
 ,@ServiceTypeIDs varchar(2048) =NULL --Shivanand(20) Comma seperated Service Type IDs
 ,@RB_ISFASTBUILDSERVICE bit = 0 --Sriker(22) 
 ,@STARTDATE DateTime = NULL --Savira(23)
 ,@ENDDATE DateTime= NULL --Savira(23)
 ,@RVC_GEOLOCATIONIDS varchar(8000)=NULL	--Nagendra(30)
 --BOC Vimlesh(35)
	,@RI_SERVICESOURCE VARCHAR(20)=NULL,--This will "LOCAL", "HotelBeds" etc.
 --EOC Vimlesh(35)
  @rv_language varchar(50)= Null  -- Ankita N (37)
 ,@ITINERYTYPENAME VARCHAR(2048) = NULL  -- Ankita N (37)
	,@RB_RETURNONLYFASTBUILDSERVICES BIT = 0	--Jeogan(39)
	--BOC Lorraine(42)
	,@RI_PickUpLocationID INT = Null
	,@RI_DropOffLocationID INT = Null
	,@RD_PickUpLocationType VarChar(2000) = Null
	,@RD_DropOffLocationType VarChar(2000) = Null
	--EOC Lorraine(42)
	,@RI_BOOKING_TYPE INT =NULL --Apeksha(49)
	,@RI_PRICE_TYPE INT =NULL --Apeksha(49)
AS
DECLARE @I_LANGUAGEID INT =0
DECLARE @ITINERYTYPEID INT = 0
	SELECT @I_LANGUAGEID = LANGUAGEID FROM LANGUAGE WHERE LANGUAGENAME = @rv_language  --Kavita(32)
	SELECT @ITINERYTYPEID =  ITINERARYTYPEID from ITINERARY_TYPE where ITINERARYTYPENAME = @ITINERYTYPENAME  --Ankita N (37)
BEGIN
SET NOCOUNT ON --Anish(31)
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED --Anish(31)
	Declare @dtStartDate DATETIME = @STARTDATE	--Gautami(38)
	DECLARE @dtToday DATETIME = convert(varchar(8),GetDate(),112 )       --Gautami(38) --Shantaram(39) added convert
	--Declare @LocalServiceIDs varchar(8000)
	Declare @LocalServiceIDs varchar(MAX) --Arun(32)
	set @LocalServiceIDs = isnull(@ServiceIDs, '')
	Declare @SQLtoRun varchar(max) --SVarshney(27)
	set @SQLtoRun = ''		--Swapnil(33)
	set @SQLtoRun='declare @I_RegionID INT declare @i_RegionCount Int ' --Arun(35)
	declare @runQuery bit
	DECLARE @listStr VARCHAR(MAX)--Ganapatrao(34)
	set @runQuery=1
	--	Swapnil(33)()(BOC)
	declare @tbl_Region table (RegionID int primary key) --Suraj(43)
	declare @i_RegionCount Int,@PICKUPLOCATIONTYPELEN INT,@DROPOFFLOCATIONTYPELEN INT--TANMAY(46)
	--BOC Lorraine(42)
	declare @IsServiceTypeTransfer bit
	DECLARE @NO_NIGHTS INT --Abhijit L.(40)
	select @IsServiceTypeTransfer= isnull(SERVICETYPETRANSFERS,0) from SERVICE_TYPE where SERVICETYPEID=@ServiceTypeID 
	--EOC Lorraine(42)
	SELECT @PICKUPLOCATIONTYPELEN = LEN(RTRIM(LTRIM(REPLACE(UPPER(ISNULL(@RD_PICKUPLOCATIONTYPE, '')), 'ANY', ''))))--TANMAY(46)
	SELECT @DROPOFFLOCATIONTYPELEN = LEN(RTRIM(LTRIM(REPLACE(UPPER(ISNULL(@RD_DROPOFFLOCATIONTYPE, '')), 'ANY', ''))))--TANMAY(46)

	--Pratham(41)
	Create table #tblServiceRatings 
	(
	Serviceid int,
	SERVICETYPERATINGNAME varchar(52)
	)
	  CREATE TABLE #Region (
			  REGIONID int,
			  REGIONNAME varchar(50),
			  LEVEL1_REGIONID int,
			  LEVEL2_REGIONID int,
			  LEVEL3_REGIONID int,
			  LEVEL4_REGIONID int,
			  LEVEL5_REGIONID int,
			  LEVEL6_REGIONID int,
			  LEVEL7_REGIONID int,
			  LEVEL8_REGIONID int,
			  LEVEL9_REGIONID int,
			  SERVICEID int
			)


			CREATE TABLE #RegionwithService (
			  REGIONID int,
			  REGIONNAME varchar(50),
			  LEVEL1_REGIONID int,
			  LEVEL2_REGIONID int,
			  LEVEL3_REGIONID int,
			  LEVEL4_REGIONID int,
			  LEVEL5_REGIONID int,
			  LEVEL6_REGIONID int,
			  LEVEL7_REGIONID int,
			  LEVEL8_REGIONID int,
			  LEVEL9_REGIONID int,
			  SERVICEID int
			)
			CREATE INDEX NDX#REGIONWITHSERVICE ON #REGIONWITHSERVICE  (SERVICEID) --Suraj(46)
	--Pratham(41)

	if isnull(@locationName,'') <> '' AND @locationID =0 
	begin
        -- set @locationName =replace(@locationName , '''','''''') --comm By Prita(35) as it was giving error for locationname with '(single quote)
		insert into @tbl_Region 
		select regionid from Region WITH (NOLOCK) where RegionName = @locationName and regionTypeId between 1 and 9 
	end 
	else if isnull(@locationName,'') = '' AND @locationID <> 0 
	begin
		insert into @tbl_Region select regionid from Region WITH (NOLOCK) where RegionID = cast (@locationId  as varchar) and regionTypeId between 1 and 9  
	end
	else if isnull(@locationName,'') <> '' AND @locationID <> 0 
	begin
		-- set @locationName = replace(@locationName , '''','''''') --comm By Prita(35) 
		insert into @tbl_Region select regionid from Region WITH (NOLOCK) where RegionName = @locationName and RegionID =  cast (@locationId  as varchar) and regionTypeId between 1 and 9  
	end
	select @i_RegionCount =count(1) from @tbl_Region 

	if isnull(@i_RegionCount,0)>0
	begin
		declare @I_RegionID int
		select @I_RegionID=regionid from @tbl_Region
		--set @SQLtoRun='declare @I_RegionID INT declare @i_RegionCount Int '
		set @SQLtoRun= @SQLtoRun + 'select @I_RegionID=' + cast(@I_RegionID as varchar) + '  '
		set @SQLtoRun= @SQLtoRun + 'select @i_RegionCount=' + cast(@i_RegionCount as varchar) + '  '
	end
	--BOC Lorraine(42)
	SET @SQLtoRun= @SQLtoRun + ' declare @IgnoreRegionId bit '

		if isnull(@IsServiceTypeTransfer,0)=1 
	begin
	--BOC TANMAY(46)
	SET @SQLTORUN = @SQLTORUN + ' DECLARE @TEMPTRANSFERSERVICE TABLE (SERVICEID INT,REGIONID INT,REGIONNAME VARCHAR(8000)) '
	SET @SQLTORUN = @SQLTORUN + ' INSERT INTO @TEMPTRANSFERSERVICE' + 
	' SELECT DISTINCT S.SERVICEID,' + CAST(ISNULL(@LOCATIONID, 0) AS VARCHAR) + ',' + '''' + CAST(ISNULL(@LOCATIONNAME, '') AS VARCHAR) + '''' + 
	' FROM SERVICE S ' + ' INNER JOIN SERVICE_TYPE ST ON S.SERVICETYPEID=ST.SERVICETYPEID AND ISNULL(ST.SERVICETYPETRANSFERS,0)=1 '
	
	--BOC Poonam(54)
	IF(@I_REGIONID>0)
	BEGIN
	SET @SQLTORUN = @SQLTORUN +'INNER JOIN ASSIGNED_REGION  TSAR  
	ON S.SERVICEID = TSAR.SERVICEID  
	INNER JOIN UDF_GETSUBREGIONS(' + CAST(@I_REGIONID AS VARCHAR) + ') REG 
	ON  TSAR.REGIONID = REG.REGID '
	END
	--EOC Poonam(54)
	
	SET @SQLTORUN = @SQLTORUN + (
			CASE 
				WHEN (ISNULL(@RI_PICKUPLOCATIONID, 0) <> 0 AND RTRIM(LTRIM(UPPER(@RD_PICKUPLOCATIONTYPE))) <>'HOTEL' )--Xenio(48)
					THEN ' INNER JOIN PACKAGE_TERMS PTP ON PTP.SERVICEID = S.SERVICEID AND PTP.REGIONLOCATIONID = ' + CAST(@RI_PICKUPLOCATIONID AS VARCHAR) + 
					' AND PTP.PACKAGETERMSPICKUPDESCRIPTION IS NOT NULL ' + 
					' INNER JOIN REGION_LOCATION RLP ON PTP.REGIONLOCATIONID = RLP.REGIONLOCATIONID ' + 
					' AND RTRIM(LTRIM((RLP.REGIONLOCATIONTYPE))) =' + '''' + CAST(RTRIM(LTRIM((@RD_PICKUPLOCATIONTYPE))) AS VARCHAR) + ''''
				WHEN @PICKUPLOCATIONTYPELEN > 0
					THEN ' INNER JOIN PACKAGE_TERMS PTP ON PTP.SERVICEID = S.SERVICEID ' + 
					' AND PTP.PACKAGETERMSPICKUPDESCRIPTION IS NOT NULL ' + 
					' INNER JOIN REGION_LOCATION RLP ON PTP.REGIONLOCATIONID = RLP.REGIONLOCATIONID ' + 
					' AND RTRIM(LTRIM(UPPER(RLP.REGIONLOCATIONTYPE))) =' + '''' + RTRIM(LTRIM(UPPER(@RD_PICKUPLOCATIONTYPE))) + ''''
				ELSE ''
				END
			)
	SET @SQLTORUN = @SQLTORUN + (
			CASE 
				WHEN (ISNULL(@RI_DROPOFFLOCATIONID, 0) <> 0 AND RTRIM(LTRIM(UPPER(@RD_DROPOFFLOCATIONTYPE))) <>'HOTEL')--Xenio(48)
					THEN ' INNER JOIN PACKAGE_TERMS PTD  WITH(nolock) ON PTD.SERVICEID = S.SERVICEID AND PTD.REGIONLOCATIONID =' + CAST(@RI_DROPOFFLOCATIONID AS VARCHAR) + 
					' AND PTD.PACKAGETERMSDROPOFFDESCRIPTION IS NOT NULL ' + 
					' INNER JOIN REGION_LOCATION RLD  WITH(nolock) ON PTD.REGIONLOCATIONID = RLD.REGIONLOCATIONID ' + 
					' AND RTRIM(LTRIM(UPPER(RLD.REGIONLOCATIONTYPE))) =' + '''' + RTRIM(LTRIM(UPPER(@RD_DROPOFFLOCATIONTYPE))) + ''''
				WHEN @DROPOFFLOCATIONTYPELEN > 0
					THEN ' INNER JOIN PACKAGE_TERMS PTD  WITH(nolock) ON PTD.SERVICEID = S.SERVICEID ' + 
					' AND PTD.PACKAGETERMSDROPOFFDESCRIPTION IS NOT NULL ' + 
					' INNER JOIN REGION_LOCATION RLD  WITH(nolock) ON PTD.REGIONLOCATIONID = RLD.REGIONLOCATIONID ' + 
					' AND RTRIM(LTRIM(UPPER(RLD.REGIONLOCATIONTYPE))) =' + '''' + RTRIM(LTRIM(UPPER(@RD_DROPOFFLOCATIONTYPE))) + ''''
				ELSE ''
				END
			)
			
	-- BOC Bharat(53)
	SET @SQLTORUN = @SQLTORUN + (
			CASE
				WHEN ((@PICKUPLOCATIONTYPELEN > 0 and @RI_PICKUPLOCATIONID=0)  OR (@DROPOFFLOCATIONTYPELEN > 0 and @RI_DROPOFFLOCATIONID=0)) AND @LOCATIONID > 0  
					THEN
					'INNER JOIN ASSIGNED_REGION AR ON AR.SERVICEID=S.SERVICEID AND ISNULL(S.ENDPOINTID,0)=0 ' +
					'INNER JOIN REGION R ON R.REGIONID=AR.REGIONID ' +
					' AND (R.REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL1_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL2_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '  
									OR R.LEVEL3_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL4_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL5_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL6_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL7_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL8_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL9_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									) '
				
				    ELSE ''
				    END
	)
	-- EOC Bharat(53)
	
	SET @SQLTORUN = @SQLTORUN + (
			CASE 
				WHEN (
						ISNULL(@RI_DROPOFFLOCATIONID, 0) = 0
						AND ISNULL(@RI_PICKUPLOCATIONID, 0) = 0
						AND @PICKUPLOCATIONTYPELEN = 0
						AND @DROPOFFLOCATIONTYPELEN = 0
						)
					THEN 
				 ' INNER JOIN PACKAGE_TERMS PTD  WITH(nolock) ON PTD.SERVICEID = S.SERVICEID ' + 
				' INNER JOIN ASSIGNED_REGION AR  WITH(nolock) ON AR.SERVICEID=S.SERVICEID AND ISNULL(S.ENDPOINTID,0)=0 ' +
				' INNER JOIN REGION R  WITH(nolock) ON R.REGIONID=AR.REGIONID ' + --Rohitk(47) added inner join
					--BOC TANMAY(44)
					(
						CASE 
							WHEN @LOCATIONID > 0
								THEN --WHEN CALLED FROM USP_GET_TSHOTEL_BASICSERVICESEARCHDETAILS_B2C
									--('AND AR.REGIONID=' + CAST(@LOCATIONID AS VARCHAR) + '') --Rohitk(47) commented and rewrote below
									(
								' AND (R.REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL1_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL2_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '  
									OR R.LEVEL3_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL4_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL5_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL6_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL7_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL8_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL9_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									) '
								)
							WHEN @RVC_GEOLOCATIONIDS IS NOT NULL
								AND LEN(@RVC_GEOLOCATIONIDS) > 0 --WHEN CALLED FROM USP_GET_TSHOTEL_SERVICESOPTIONSANDPRICESFORCLIENT_B2C
								THEN --'AND AR.REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')' --Rohitk(47) commented and rewrote below
								' AND (R.REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + '
									OR R.LEVEL1_REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + '
									OR R.LEVEL2_REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + '  
									OR R.LEVEL3_REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + '
									OR R.LEVEL4_REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ' 
									OR R.LEVEL5_REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ' 
									OR R.LEVEL6_REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ' 
									OR R.LEVEL7_REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + '
									OR R.LEVEL8_REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ' 
									OR R.LEVEL9_REGIONID =' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + '
									) '
							ELSE ''
							END
						)
					 ELSE ' WHERE ISNULL(S.ENDPOINTID,0) = 0 '
				END
			)
		--EOC TANMAY(46)

		
		
			set @SQLtoRun= @SQLtoRun+ ' insert into @TempTransferService 
			select distinct S.SERVICEID,R.REGIONID,R.REGIONNAME from service  S  WITH(nolock) 
			INNER JOIN SERVICE_TYPE ST  WITH(nolock) ON S.SERVICETYPEID=ST.SERVICETYPEID AND isnull(ST.SERVICETYPETRANSFERS,0)=1
			INNER JOIN ASSIGNED_REGION AR  WITH(nolock) ON AR.SERVICEID=S.SERVICEID AND ISNULL(S.ENDPOINTID,0)=0
			INNER JOIN REGION R  WITH(nolock) ON R.REGIONID=AR.REGIONID
			LEFT JOIN PACKAGE_TERMS PT  WITH(nolock) ON S.SERVICEID= PT.SERVICEID ' +
			'WHERE ' +
			'ISNULL(S.ENDPOINTID,0)=0  '+
				--BOC Tanmay(44)
				CASE 
					WHEN @LOCATIONID > 0
						THEN --when called from USP_GET_TSHOTEL_BASICSERVICESEARCHDETAILS_B2C
							(
								' AND (R.REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL1_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL2_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '  
									OR R.LEVEL3_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL4_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL5_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL6_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL7_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									OR R.LEVEL8_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + ' 
									OR R.LEVEL9_REGIONID =' + CAST(@LOCATIONID AS VARCHAR) + '
									) '
								)
					WHEN @RVC_GEOLOCATIONIDS IS NOT NULL
							AND LEN(@RVC_GEOLOCATIONIDS) > 0 --when called from USP_GET_TSHOTEL_SERVICESOPTIONSANDPRICESFORCLIENT_B2C
							THEN  --when called from USP_GET_TSHOTEL_SERVICESOPTIONSANDPRICESFORCLIENT_B2C
						(
							' AND (R.REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')
									OR R.LEVEL1_REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')
									OR R.LEVEL2_REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ') 
									OR R.LEVEL3_REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')
									OR R.LEVEL4_REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')
									OR R.LEVEL5_REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')
									OR R.LEVEL6_REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')
									OR R.LEVEL7_REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')
									OR R.LEVEL8_REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')
									OR R.LEVEL9_REGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')
									) '
							)
							ELSE ''
					END
					--EOC Tanmay(44)
			+ 'AND ISNULL(REGIONLOCATIONID,0)=0 AND PT.PACKAGETERMSPICKUPDESCRIPTION IS NULL '+
			'AND PT.PACKAGETERMSDROPOFFDESCRIPTION IS NULL ' 
			--AND S.SERVICEID NOT IN (SELECT SERVICEID FROM PACKAGE_TERMS) '
			
	      set @SQLtoRun= @SQLtoRun+ + ' insert into @TempTransferService 
		                SELECT DISTINCT SERVICEID ,'+ cast(@locationID as varchar)+','+ ''''+ cast(ISNULL(@locationName,'') as varchar)+''''+ 
						' FROM SERVICE S  WITH(nolock) INNER JOIN SERVICE_TYPE ST  WITH(nolock) ON S.SERVICETYPEID = ST.SERVICETYPEID AND ISNULL(SERVICETYPETRANSFERS,0) = 1
						INNER JOIN REGION_MAPPING RM  WITH(nolock) ON S.ENDPOINTID= RM.ENDPOINTID '+
						--BOC Tanmay(44)
						CASE 
								WHEN @LOCATIONID > 0
									THEN --WHEN CALLED FROM USP_GET_TSHOTEL_BASICSERVICESEARCHDETAILS_B2C
										('WHERE RM.TSREGIONID = ' + CAST(@LOCATIONID AS VARCHAR))
								WHEN @RVC_GEOLOCATIONIDS IS NOT NULL
										AND LEN(@RVC_GEOLOCATIONIDS) > 0 --when called from USP_GET_TSHOTEL_SERVICESOPTIONSANDPRICESFORCLIENT_B2C
									THEN 
									'WHERE RM.TSREGIONID IN (' + CAST(@RVC_GEOLOCATIONIDS AS VARCHAR) + ')'
									ELSE ''
								END	
						--EOC Tanmay(44)


			
end		  
	--EOC Lorraine(42)

	--Swapnil(33)(EOC)
	--BOC Neil(40)
	DECLARE @dt_BOOKINGBOOKINGDATE AS DATETIME
	set @dt_BOOKINGBOOKINGDATE = CONVERT(VARCHAR(8), Getdate(), 112)
	--BOC Neil(40)
	--set @locationName =replace(@locationName , '''','''''')
	set @ServiceTypeRatingName =replace(@ServiceTypeRatingName , '''','''''')
	--set @SQLtoRun = '  SELECT distinct S.SERVICEID , rtrim( SERVICELongName ) SERVICELongName , ISNULL(ISDAYWISERELEASEPERIOD,0 ) as ISDAYWISERELEASEPERIOD,  rtrim(R.RegionName) RegionName, S.ServiceTypeId, ' +--vernal(8) commented
	--BOC Abhijit L.(17)
	
	
	--BOC Arun(33) One Service can be assigned to multiple region. So, Selecting the Top Region Name if multiple regionid's are there
	DECLARE @tmpServiceIDs TABLE
	(RowID INT,
	SERVICEID INT)

	INSERT INTO @tmpServiceIDs(RowID,SERVICEID)
	SELECT TABLEID,VALUEID FROM dbo.udf_LIST_TO_TABLE(@ServiceIDs) 

	CREATE TABLE #tmpRegion
	(REGIONID INT,
	REGIONNAME VARCHAR(300),
	SERVICEID INT
	,ASSIGNEDREGION BIT) --Aman(51) added ,ASSIGNEDREGION BIT

	IF EXISTS (SELECT TOP 1 1 FROM LINKED_ASSIGNED_REGION) --WAYNE(47)
	BEGIN
	INSERT INTO #tmpRegion
	SELECT DISTINCT R.REGIONID, R.REGIONNAME, S.SERVICEID,case WHEN AR.REGIONID = R.REGIONID then 1 else 0 END --Aman(51)
	From Service S with(nolock) --shamil(36)
	LEFT OUTER JOIN Assigned_Region AR with(nolock) on AR.ServiceId = S.ServiceId  
	LEFT OUTER JOIN LINKED_ASSIGNED_REGION AMSR with(nolock) ON AMSR.SERVICEID = AR.ServiceId
		INNER JOIN REGION R with(nolock) ON (AR.RegionId = r.RegionId OR AMSR.REGIONID = r.RegionId) --INDEX SCAN
	INNER JOIN @tmpServiceIDs tmpS ON tmpS.SERVICEID = S.SERVICEID
	
	AND ( R.RegionID =@I_RegionID
        OR R.LEVEL1_REGIONID =@I_RegionID
        OR R.LEVEL2_REGIONID =@I_RegionID   
        OR R.LEVEL3_REGIONID =@I_RegionID 
        OR R.LEVEL4_REGIONID =@I_RegionID 
        OR R.LEVEL5_REGIONID =@I_RegionID 
        OR R.LEVEL6_REGIONID =@I_RegionID 
        OR R.LEVEL7_REGIONID =@I_RegionID 
        OR R.LEVEL8_REGIONID =@I_RegionID 
        OR R.LEVEL9_REGIONID =@I_RegionID  )
	END
	ELSE
	BEGIN --BOC WAYNE(47)
		INSERT INTO #tmpRegion
		SELECT DISTINCT R.REGIONID, R.REGIONNAME, S.SERVICEID,0 --Aman(51)
		From Service S with(nolock) --shamil(36)
		LEFT OUTER JOIN Assigned_Region AR with(nolock) on AR.ServiceId = S.ServiceId  
		INNER JOIN REGION R with(nolock) ON AR.RegionId = r.RegionId
		INNER JOIN @tmpServiceIDs tmpS ON tmpS.SERVICEID = S.SERVICEID
		--WHERE S.SERVICEID IN (@ServiceIDs)
		AND ( R.RegionID =@I_RegionID
			OR R.LEVEL1_REGIONID =@I_RegionID
			OR R.LEVEL2_REGIONID =@I_RegionID   
			OR R.LEVEL3_REGIONID =@I_RegionID 
			OR R.LEVEL4_REGIONID =@I_RegionID 
			OR R.LEVEL5_REGIONID =@I_RegionID 
			OR R.LEVEL6_REGIONID =@I_RegionID 
			OR R.LEVEL7_REGIONID =@I_RegionID 
			OR R.LEVEL8_REGIONID =@I_RegionID 
			OR R.LEVEL9_REGIONID =@I_RegionID  )
	END
	--EOC WAYNE(47)
	--EOC Arun(33)


	--IF (@ServiceStatusRequired = 1)
	-- BEGIN
	--   if isnull(@ServiceTypeOptionIds,'') <> ''  -- Derik(14) - Required distinct services when ServiceTypeOptionIDs are selected
	  -- BOC Ankita N(37)
	    
	  --set @SQLtoRun = @SQLtoRun + '  SELECT distinct S.SERVICEID , --Suraj(46) commented and rewritten below
		 --   ISNULL((SELECT TOP 1 LTRIM(RTRIM(CAST(SIS.SERVICEITINERARYSEGMENTNAME AS VARCHAR(8000)))) FROM SERVICE_ITINERARY_SEGMENT SIS WHERE  
   --                      SIS.SERVICEID = s.SERVICEID AND SIS.LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' AND 
			--			 (SIS.ITINERARYTYPEID = ' +  cast( @ITINERYTYPEID as varchar)  +'  OR ' + 
			--			  cast( @ITINERYTYPEID as varchar) + ' NOT IN (select ITINERARYTYPEID from SERVICE_ITINERARY_SEGMENT WHERE LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' AND SERVICEID=S.SERVICEID  )) ),s.SERVICELONGNAME)  SERVICELONGNAME, 
	  --  ISNULL(ISDAYWISERELEASEPERIOD,0 ) as ISDAYWISERELEASEPERIOD, '
	  
	    set @SQLtoRun = @SQLtoRun + '  SELECT distinct S.SERVICEID ,'
		IF (@I_LANGUAGEID>0)--BOC Suraj(46)devided the above statement in the following
		BEGIN
			set @SQLtoRun = @SQLtoRun + ' ISNULL((SELECT TOP 1 LTRIM(RTRIM(CAST(SIS.SERVICEITINERARYSEGMENTNAME AS VARCHAR(8000)))) FROM SERVICE_ITINERARY_SEGMENT SIS  WITH(nolock) WHERE  
                         SIS.SERVICEID = s.SERVICEID AND SIS.LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' AND 
						 (SIS.ITINERARYTYPEID = ' +  cast( @ITINERYTYPEID as varchar) 
						--  cast( @ITINERYTYPEID as varchar) + ' NOT IN (select ITINERARYTYPEID from SERVICE_ITINERARY_SEGMENT WHERE LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' AND SERVICEID=S.SERVICEID  )) ),s.SERVICELONGNAME)  SERVICELONGNAME,   --shakeel(45) commented and rewrittend below
					+' OR  NOT EXISTS (select TOP 1 1   from SERVICE_ITINERARY_SEGMENT WITH(nolock)  WHERE ITINERARYTYPEID =' + cast( @ITINERYTYPEID as varchar) +' AND  LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' AND SERVICEID=S.SERVICEID  )) ),s.SERVICELONGNAME)  SERVICELONGNAME,'
		END
		ELSE
		BEGIN
			set @SQLtoRun = @SQLtoRun + 's.SERVICELONGNAME AS SERVICELONGNAME,'
		END 
	    set @SQLtoRun = @SQLtoRun +' ISNULL(ISDAYWISERELEASEPERIOD,0 ) as ISDAYWISERELEASEPERIOD, '
		--EOC Suraj(46)
		IF(@I_LANGUAGEID>0) --Suraj(46)
		BEGIN
		   set @SQLtoRun = @SQLtoRun +  
		   case when isnull(@IsServiceTypeTransfer,0)=1 
		   then
				'  ISNULL((SELECT TOP 1 LTRIM(RTRIM(CAST(MD.ENTITYDESCRIPTION AS VARCHAR(8000)))) FROM MULTILINGUAL_DESCRIPTION  MD WHERE  
				MD.ENTITYID = '+ cast(ISNULL(@I_RegionID,0) as varchar)+' AND ENTITYTYPEID = 21  AND MD.LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +'), TTS.regionname) as regionname, ' 
		   else 
			   '  ISNULL((SELECT TOP 1 LTRIM(RTRIM(CAST(MD.ENTITYDESCRIPTION AS VARCHAR(8000)))) FROM MULTILINGUAL_DESCRIPTION MD WHERE  
				MD.ENTITYID = r.REGIONID AND ENTITYTYPEID = 21  AND MD.LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' ),r.regionname)
				 as	regionname, ' 
		   end 
		 --BOC Suraj(46)
		END
		ELSE
		BEGIN
		   set @SQLtoRun = @SQLtoRun +  
		   case when isnull(@IsServiceTypeTransfer,0)=1 
		   then
				' TTS.regionname as regionname, ' 
		   else 
			   ' ISNULL((SELECT TOP 1 regionname FROM #tmpRegion WHERE  (SERVICEID = s.SERVICEID) ORDER BY ASSIGNEDREGION desc,REGIONID),r.regionname) as regionname, ' --Aman(51) 
		   end 
		END
		--EOC Suraj(46)

		    set @SQLtoRun = @SQLtoRun + ' S.ServiceTypeId, LTRIM(RTRIM(ST.ServiceStatusName)) As ServiceStatusName, ' 
	   -- EOC Ankita N(37)

	--EOC Lorraine(42)
   if @ServiceInfoRequired =1
    begin
	--BOC Lorraine(42)
	 set @SQLtoRun= @SQLtoRun +case when isnull(@IsServiceTypeTransfer,0)=1 
	 then ' TTS.regionid as regionid ,'
	 else  ' ISNULL((SELECT TOP 1 REGIONID FROM #tmpRegion WHERE  (SERVICEID = s.SERVICEID) ORDER BY ASSIGNEDREGION desc,REGIONID),r.regionid) AS regionid, ' --Aman(51) 
	 end 
	 --EOC Lorraine(42)
     --BOC Suraj(46) commented and rewritten
    --set @SQLtoRun= @SQLtoRun + ' ISNULL((SELECT TOP 1 LTRIM(RTRIM(CAST(SIS.SERVICEITINERARYSEGMENTTEXT AS VARCHAR(8000)))) FROM SERVICE_ITINERARY_SEGMENT SIS WHERE  
    --                      SIS.SERVICEID = s.SERVICEID AND SIS.LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' AND 
				--		 (SIS.ITINERARYTYPEID = ' +  cast( @ITINERYTYPEID as varchar) 
				--		  +'  OR NOT EXISTS (select TOP 1 1   from SERVICE_ITINERARY_SEGMENT WHERE ITINERARYTYPEID =' + cast( @ITINERYTYPEID as varchar) +' AND  LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' AND SERVICEID=S.SERVICEID  )) ),s.servicedescription)  servicedescription, 
		IF(@I_LANGUAGEID>0 )
		BEGIN
		set @SQLtoRun= @SQLtoRun + ' ISNULL((SELECT TOP 1 LTRIM(RTRIM(CAST(SIS.SERVICEITINERARYSEGMENTTEXT AS VARCHAR(8000)))) FROM SERVICE_ITINERARY_SEGMENT SIS  WITH(nolock)  WHERE  
                          SIS.SERVICEID = s.SERVICEID AND SIS.LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' AND 
						 (SIS.ITINERARYTYPEID = ' +  cast( @ITINERYTYPEID as varchar) 
						  +'  OR NOT EXISTS (select TOP 1 1   from SERVICE_ITINERARY_SEGMENT WHERE ITINERARYTYPEID =' + cast( @ITINERYTYPEID as varchar) +' AND  LANGUAGEID = ' + cast( @I_LANGUAGEID as varchar) +' AND SERVICEID=S.SERVICEID  )) ),s.servicedescription)  servicedescription, 					    
					d.addressline1,d.addressline2,d.addressline3,d.addressline4,d.addresscity,e.statename,f.countryname,Isnull(sup.supplierpreferencevalue, 0) supplierpreferencevalue , sup.SUPPLIERNAME,d.ADDRESSTELEPHONENUMBER,d.ADDRESSFAXNUMBER, ' --Julia (13) Added Extra TAgs for TS.net  --shakeel(45)
					
		END
		ELSE
		BEGIN
			set @SQLtoRun= @SQLtoRun + ' s.servicedescription as servicedescription, 
									d.addressline1,d.addressline2,d.addressline3,d.addressline4,d.addresscity,e.statename,f.countryname,Isnull(sup.supplierpreferencevalue, 0) supplierpreferencevalue , sup.SUPPLIERNAME,d.ADDRESSTELEPHONENUMBER,d.ADDRESSFAXNUMBER, ' 
		END
		--EOC Suraj(46)
    end
    else 
    begin
     set @SQLtoRun= @SQLtoRun + ' null as regionid,null as servicedescription,null as addressline1,null as addressline2,null as addressline3,null as addressline4,null as addresscity,null as statename,null as countryname,null as supplierpreferencevalue, null as SUPPLIERNAME,null as ADDRESSTELEPHONENUMBER,null as ADDRESSFAXNUMBER,  '
    end

    if @Matchcodedetailsrequired =1 and @ServiceInfoRequired =1
    begin
    set @SQLtoRun= @SQLtoRun + ' sm.servicematchcode,ismaster as ismain,sm.serviceinternalcode, '
    end
    else
    begin
    set @SQLtoRun= @SQLtoRun + ' null as servicematchcode,null as ismain,null as serviceinternalcode, '
    end 
    --boc vernal
    set @SQLtoRun=@SQLtoRun+ ' isnull(endpointtypename,''Local'')  SourceName,isnull(s.endpointid,0)  SourceId ,'
    --eoc vernal  
    --eoc vernal(9)
	--set @SQLtoRun= @SQLtoRun +' (Select top 1 rtrim(SERVICETYPERATINGNAME) from ASSIGNED_SERVICE_RATING ASR inner join SERVICE_TYPE_RATING STRA on (ASR.SERVICETYPERATINGID = STRA.SERVICETYPERATINGID and ASR.ASSIGNEDSERVICERATINGDEFAULT=1) where ASR.ServiceID = S.ServiceID) as Rating, S.ISRECOMMENDEDPRODUCT as ISRECOMMENDEDPRODUCT' +--Saroj(30)
	set @SQLtoRun= @SQLtoRun +' case when (Select top 1 1 from ASSIGNED_SERVICE_RATING ASR inner join SERVICE_TYPE_RATING STRA on (ASR.SERVICETYPERATINGID = STRA.SERVICETYPERATINGID ) INNER JOIN SERVICE_TYPE_RATING_TYPE STRT ON (STRT.SERVICETYPERATINGTYPEID=STRA.SERVICETYPERATINGTYPEID AND STRT.ISSTARRATING=1) where ASR.ServiceID = S.ServiceID and ASR.ASSIGNEDSERVICERATINGDEFAULT=1)=1 
			then (Select rtrim(SERVICETYPERATINGNAME)  from ASSIGNED_SERVICE_RATING ASR inner join SERVICE_TYPE_RATING STRA on (ASR.SERVICETYPERATINGID = STRA.SERVICETYPERATINGID ) INNER JOIN SERVICE_TYPE_RATING_TYPE STRT ON (STRT.SERVICETYPERATINGTYPEID=STRA.SERVICETYPERATINGTYPEID AND STRT.ISSTARRATING=1) where ASR.ServiceID = S.ServiceID and ASR.ASSIGNEDSERVICERATINGDEFAULT=1)
			else (Select top 1 rtrim(SERVICETYPERATINGNAME) from ASSIGNED_SERVICE_RATING ASR inner join SERVICE_TYPE_RATING STRA on (ASR.SERVICETYPERATINGID = STRA.SERVICETYPERATINGID ) INNER JOIN SERVICE_TYPE_RATING_TYPE STRT ON (STRT.SERVICETYPERATINGTYPEID=STRA.SERVICETYPERATINGTYPEID AND STRT.ISSTARRATING=1) where ASR.ServiceID = S.ServiceID ORDER BY SERVICETYPERATINGSEQUENCE ASC) end as Rating, S.ISRECOMMENDEDPRODUCT as ISRECOMMENDEDPRODUCT' +--Saroj(30) --Neil(40)
	
				' ,isnull(ep.EndPointName, ''Local'') as ServiceSourceName ' --Leroy(21)
    --BOC Savira(23)		
	IF @ServiceInfoRequired <> 0 
    BEGIN
        IF ISNULL(@ri_CalledFrom, 0) = 0 
            BEGIN
                SET @SQLtoRun = @SQLtoRun + ',NULL as SpecialOffersCount';
            END
        ELSE
            --boc Harshad(24)
            BEGIN				
				IF ISNULL(@STARTDATE, '') = '' OR ISNULL(@ENDDATE, '') = ''
					BEGIN
						SET @SQLtoRun = @SQLtoRun + ',NULL as SpecialOffersCount';
					END
                ELSE
                BEGIN
				--BOC Yuvraj(35)
                        --BOC Gautami(38)
						SELECT @NO_NIGHTS = DATEDIFF(D, @STARTDATE, @ENDDATE)+1 --Abhijit L.(40)
						--BOC  Apeksha(49)
						DECLARE @APPLIED_RULE_LINKED_PRICEDETAILS_JOIN AS VARCHAR(300)= '',@CHECKBTPT AS VARCHAR(300) =''
						IF(@RI_BOOKING_TYPE IS NOT NULL AND @RI_PRICE_TYPE IS NOT NULL)
						BEGIN
							SET @APPLIED_RULE_LINKED_PRICEDETAILS_join=' Inner join DBO.APPLIED_RULE_LINKED_PRICEDETAILS ARLP WITH (NOLOCK) ON AR.ORGANISATIONSUPPLIERCONTRACTID = ARLP.ORGANISATIONSUPPLIERCONTRACTID '
							SET @CHECKBTPT=' AND ARLP.SELLBOOKINGTYPEID ='+CAST (@RI_BOOKING_TYPE AS VARCHAR (30))+' AND ARLP.SELLPRICETYPEID ='+CAST (@RI_PRICE_TYPE AS VARCHAR (30))
						END
						--BOC  Apeksha(49) 



                        SET @SQLtoRun = @SQLtoRun + ',(SELECT 
						(SELECT COUNT(DISTINCT AR.APPLIEDRULEID)  FROM APPLIED_RULE AR WITH (NOLOCK)  INNER JOIN RULE_1 R1 WITH (NOLOCK) ON AR.RULEID = R1.RULEID'
						+@APPLIED_RULE_LINKED_PRICEDETAILS_join+ 
						' INNER JOIN APPLIED_SUPPLEMENT_RULE ASR WITH (NOLOCK) ON ASR.APPLIEDRULEID = AR.APPLIEDRULEID 
						INNER JOIN SUPPLEMENT_RULE SR WITH (NOLOCK) ON AR.RULEID = SR.RULEID    --Abhijit L.(40) 
						WHERE AR.SERVICEID = S.SERVICEID'
						+@CHECKBTPT+ 
						' AND ( AR.APPLIEDRULEFROMDATE <=' + '''' + CAST (@STARTDATE AS VARCHAR (30)) + '''' + ' AND AR.APPLIEDRULETODATE >= ' + '''' + CAST (@ENDDATE AS VARCHAR (30)) + '''' 
						--BOC Amey.R(33) - added BETWEEN condition for startdate and enddate
						+ ' OR ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE '
						+ ' OR ''' + CAST (@ENDDATE AS VARCHAR (30))   + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE '
						--BOC Gayeetri(30)
						+ ' OR AR.APPLIEDRULEFROMDATE BETWEEN ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' AND ''' + CAST (@ENDDATE AS VARCHAR (30)) + ''''
						+ ' OR AR.APPLIEDRULETODATE BETWEEN ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' AND ''' + CAST (@ENDDATE AS VARCHAR (30)) + ''' )'
						--EOC Gayeetri(30)
						--EOC Amey.R(33)
						--BOC Gayeetri(30)
						+ ' AND ((ISNULL((SELECT ARRIVEWITHINRULEDATES FROM SUPPLEMENT_RULE  WITH(nolock) WHERE RULEID = AR.RULEID ),0) = 1 '
					    + ' AND ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE)'
						+ ' OR (ISNULL((SELECT ARRIVEWITHINRULEDATES FROM SUPPLEMENT_RULE WITH(nolock)  WHERE RULEID = AR.RULEID),0) = 0)) '
						--EOC Gayeetri(30)
						--BOC Vanessa (31)
						+ ' AND ((CASE WHEN ISNULL(AR.BOOKINGWITHINRULEDATES,0) = 1 THEN (CASE WHEN (''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE) '
						+ ' AND (''' + CAST (@ENDDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE) THEN 1 '
						+ '	ELSE 0 END) ELSE 1 END) = 1) '
						--EOC Vanessa (31)
						--BOC Gautami(38)
						+ ' AND R1.RULETYPEID = 5 AND (isnull(ASR.ApplyEBO,0)= 0)' --)' --Abhijit L.(40) closing bracket moved down
						
						--BOC Abhijit L.(40) --added condition from USP_GET_ALL_APPLICABLE_SPECIAL_OFFERS
						+ ' AND ( (ISNULL(SUPPLEMENTRULEAPPLIEDTOFLEXIBLERIGID, 0) = 0 AND ( ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' = 0 OR SR.SUPPLEMENTRULEMINIMUMSTAY <=  ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' )) '
						+ '       OR '
						+ '		  (ISNULL(SUPPLEMENTRULEAPPLIEDTOFLEXIBLERIGID, 0) = 1 AND ( ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' = 0 OR SR.SUPPLEMENTRULEMINIMUMSTAY =  ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' OR SR.SUPPLEMENTRULEMINIMUMSTAY = 0)) '
						+ '		)  '
						+ ' AND ( (((ISNULL(SR.SUPPLEMENTRULEMAXIMUMSTAY, 0) > 0) '
						+ '			 AND ((ISNULL(SUPPLEMENTRULEAPPLIEDTOFLEXIBLERIGID, 0) = 0  AND ( ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' = 0 OR SR.SUPPLEMENTRULEMAXIMUMSTAY >=  ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' )) '
						+ '				  OR '
						+ '				  (ISNULL(SUPPLEMENTRULEAPPLIEDTOFLEXIBLERIGID, 0) = 1 AND ( ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' = 0 OR SR.SUPPLEMENTRULEMAXIMUMSTAY =  ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' OR SR.SUPPLEMENTRULEMAXIMUMSTAY = 0)) '
						+ '				 ) '
						+ '			) '
						+ '		   ) '
						+ '		  OR (ISNULL(SR.SUPPLEMENTRULEMAXIMUMSTAY, 0)) = 0 '
						+ '		) '
						+ ' ) '
						--EOC Abhijit L.(40) 'Apeksha(49) added @APPLIED_RULE_LINKED_PRICEDETAILS_join and @CHECKBTPT


						if exists (select Top 1 1 from APPLIED_SUPPLEMENT_RULE where isnull(ApplyEBO,0) > 0)--shakeel(45)
						Begin
							SET @SQLtoRun = @SQLtoRun + 
							' +	
							(SELECT COUNT(1) FROM 					
							(SELECT TOP 1 AR.APPLIEDRULEID  FROM APPLIED_RULE AR WITH(nolock) INNER JOIN RULE_1 R1  WITH(nolock) ON AR.RULEID = R1.RULEID																		
							INNER JOIN APPLIED_SUPPLEMENT_RULE ASR  WITH(nolock) ON ASR.APPLIEDRULEID = AR.APPLIEDRULEID 
							INNER JOIN SUPPLEMENT_RULE SR WITH (NOLOCK) ON AR.RULEID = SR.RULEID   --Abhijit L.(40)
							WHERE AR.SERVICEID = S.SERVICEID 
							AND ( AR.APPLIEDRULEFROMDATE <=' + '''' + CAST (@STARTDATE AS VARCHAR (30)) + '''' + ' AND AR.APPLIEDRULETODATE >= ' + '''' + CAST (@ENDDATE AS VARCHAR (30)) + '''' 
							+ ' OR ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE '
							+ ' OR ''' + CAST (@ENDDATE AS VARCHAR (30))   + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE '
							+ ' OR AR.APPLIEDRULEFROMDATE BETWEEN ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' AND ''' + CAST (@ENDDATE AS VARCHAR (30)) + ''''
							+ ' OR AR.APPLIEDRULETODATE BETWEEN ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' AND ''' + CAST (@ENDDATE AS VARCHAR (30)) + ''' )'
							+ ' AND ((ISNULL((SELECT ARRIVEWITHINRULEDATES FROM SUPPLEMENT_RULE WHERE RULEID = AR.RULEID ),0) = 1 '
							+ ' AND ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE)'
							+ ' OR (ISNULL((SELECT ARRIVEWITHINRULEDATES FROM SUPPLEMENT_RULE WHERE RULEID = AR.RULEID),0) = 0)) '
							+ ' AND ((CASE WHEN ISNULL(AR.BOOKINGWITHINRULEDATES,0) = 1 THEN (CASE WHEN (''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE) '
							+ ' AND (''' + CAST (@ENDDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE) THEN 1 '
							+ '	ELSE 0 END) ELSE 1 END) = 1) '
							+ ' AND RULETYPEID = 5 AND (ISNULL(ASR.ApplyEBO,0)=1 )'
							+ ' AND (( ISNULL(ASR.APPLIEDEBOMINDAYSPRIOR,0)=0 AND ASR.DAYSPRIORBOOKING IS  NULL AND ''' + CAST (@dtToday AS VARCHAR (30)) + ''' BETWEEN ASR.BookingFromDate AND ASR.BookingToDate )' --Azim(37) Added condition to check Booking date between ASR.BookingFromDate AND ASR.BookingToDate						
							
							+ ' OR  (ISNULL(ASR.DAYSPRIORBOOKING, -1) = -1  AND ISNULL(ASR.APPLIEDEBOMINDAYSPRIOR,0)>0 AND ASR.APPLIEDEBOMINDAYSPRIOR<'+ CAST(Datediff(d, @dtToday, @dtStartDate)as varchar(30)) +' ) ' --Shivanand(35) --Azim(37) Added ISNULL(ASR.APPLIEDEBOMINDAYSPRIOR,0)>0 
							--Boc Shivanand(35)
							+ ' OR  (ASR.APPLIEDEBOMINDAYSPRIOR IS NULL AND ''' +  
							CAST(CONVERT(DATE,GETDATE()) AS VARCHAR(30))  + ''' <= ''' + CAST(CONVERT(DATE, @STARTDATE)AS VARCHAR (30)) 
							+ ''' AND DATEADD(DAY,-ISNULL(ASR.DAYSPRIORBOOKING,0), ''' +   CAST(CONVERT(DATE, @STARTDATE)AS VARCHAR (30)) + ''') <= ''' 
							+ CAST(CONVERT(DATE,GETDATE()) AS VARCHAR(30)) 	+ '''))'
							--Eoc Shivanand(35)
							--BOC Abhijit L.(40) --added condition from USP_GET_ALL_APPLICABLE_SPECIAL_OFFERS
							+ ' AND ( (ISNULL(SUPPLEMENTRULEAPPLIEDTOFLEXIBLERIGID, 0) = 0 AND ( ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' = 0 OR SR.SUPPLEMENTRULEMINIMUMSTAY <=  ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' )) '
							+ '       OR '
							+ '		  (ISNULL(SUPPLEMENTRULEAPPLIEDTOFLEXIBLERIGID, 0) = 1 AND ( ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' = 0 OR SR.SUPPLEMENTRULEMINIMUMSTAY =  ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' OR SR.SUPPLEMENTRULEMINIMUMSTAY = 0)) '
							+ '		)  '
							+ ' AND ( (((ISNULL(SR.SUPPLEMENTRULEMAXIMUMSTAY, 0) > 0) '
							+ '			 AND ((ISNULL(SUPPLEMENTRULEAPPLIEDTOFLEXIBLERIGID, 0) = 0  AND ( ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' = 0 OR SR.SUPPLEMENTRULEMAXIMUMSTAY >=  ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' )) '
							+ '				  OR '
							+ '				  (ISNULL(SUPPLEMENTRULEAPPLIEDTOFLEXIBLERIGID, 0) = 1 AND ( ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' = 0 OR SR.SUPPLEMENTRULEMAXIMUMSTAY =  ' + CAST(@NO_NIGHTS AS CHAR(4)) + ' OR SR.SUPPLEMENTRULEMAXIMUMSTAY = 0)) '
							+ '				 ) '
							+ '			) '
							+ '		   ) '
							+ '		  OR (ISNULL(SR.SUPPLEMENTRULEMAXIMUMSTAY, 0)) = 0 '
							+ '		) '
							--EOC Abhijit L.(40)
							+ ' ORDER BY ASR.APPLIEDEBOMINDAYSPRIOR DESC ) EARLYBIRDOFFERCOUNT) '

						END

						SET @SQLtoRun = @SQLtoRun + 
						')					
						AS SPECIALOFFERSCOUNT ';
						--EOC Gautami(38)
                   END

    
			END
			--eoc Harshad(24)
    END
    ELSE --SRIKER(XXX) ADDED ELSE PART
    BEGIN
        SET @SQLtoRun = @SQLtoRun + ',NULL as SpecialOffersCount';
    END    
    --EOC Savira(23)
     --BOC Sarika(26)
    IF @ServiceInfoRequired <> 0 
    BEGIN
    IF ISNULL(@ri_CalledFrom, 0) = 1
     BEGIN
        SET @SQLtoRun = @SQLtoRun + ',SEARCHPRIORITY'
     END           
     ELSE
     
            BEGIN
                SET @SQLtoRun = @SQLtoRun + ',NULL as SEARCHPRIORITY';
            END
    END
    else
    BEGIN
       SET @SQLtoRun = @SQLtoRun + ',NULL as SEARCHPRIORITY';
    END
    
    --EOC Sarika(26)
    --BOC mahadev(29)
    IF @ServiceInfoRequired <> 0 
    BEGIN
    IF ISNULL(@ri_CalledFrom, 0) = 1
     BEGIN
        SET @SQLtoRun = @SQLtoRun + ',SERVICEMUSTSTAY'
     END           
     ELSE
            BEGIN
                SET @SQLtoRun = @SQLtoRun + ',NULL as SERVICEMUSTSTAY';
            END
    END
    else
    BEGIN
       SET @SQLtoRun = @SQLtoRun + ',NULL as SERVICEMUSTSTAY';
    END
    --EOC mahadev(29)
    --BOC Vimlesh(36)
	SET  @SQLtoRun = @SQLtoRun + ',ISBESTSELLER';
	--EOC Vimlesh(36)
	    --BOC kartheek(38)
  
        SET @SQLtoRun = @SQLtoRun + ',S.CANCELLATIONPOLICYID,S.SUPPLIER_CANCELLATIONPOLICYID'
    --EOC kartheek(38)
       SET @SQLtoRun = @SQLtoRun + ',NULL as SERVICRATING, LTRIM(RTRIM(S.SERVICESHORTNAME)) AS SERVICESHORTNAME,ST.SERVICESTATUSNOBOOKINGS,SUPS.SUPPLIERSTATUSNOBOOKINGS ';--Ganapatrao(34) --Suraj(48)--ManojG(54)
		 --BOC ManojG(55)
	   IF ISNULL(@ri_CalledFrom, 0) = 0  OR ISNULL(@ri_CalledFrom, 0) = 1
            BEGIN
           
			  IF ISNULL(@STARTDATE, '') = '' OR ISNULL(@ENDDATE, '') = ''
					BEGIN
						SET @SQLtoRun = @SQLtoRun + ',0 as HASCIRCUITOFFER';
					END
              ELSE
			       BEGIN
				    SELECT @NO_NIGHTS = CASE WHEN @NO_NIGHTS IS NULL THEN DATEDIFF(D, @STARTDATE, @ENDDATE)+1 ELSE @NO_NIGHTS END
				     SET @SQLTORUN = @SQLTORUN + ',(CASE WHEN EXISTS
					(SELECT TOP 1 1  FROM APPLIED_RULE AR WITH (NOLOCK)  INNER JOIN RULE_1 R1 WITH (NOLOCK) ON AR.RULEID = R1.RULEID'
						+' INNER JOIN APPLIED_CIRCUIT_RULE ACR WITH (NOLOCK) ON ACR.APPLIEDRULEID = AR.APPLIEDRULEID' 
						+' INNER JOIN APPLIED_RULE_OPTION_EXTRA AROE WITH (NOLOCK) ON AROE.APPLIEDRULEID = AR.APPLIEDRULEID'
						+' INNER JOIN SERVICE_OPTION_IN_SERVICE SOIS WITH (NOLOCK) ON SOIS.SERVICEOPTIONINSERVICEID = AROE.SERVICEOPTIONINSERVICEID
						   WHERE SOIS.SERVICEID = S.SERVICEID '
						+' AND ( AR.APPLIEDRULEFROMDATE <=' + '''' + CAST (@STARTDATE AS VARCHAR (30)) + '''' + ' AND AR.APPLIEDRULETODATE >= ' + '''' + CAST (@ENDDATE AS VARCHAR (30)) + '''' 
						--ADDED BETWEEN CONDITION FOR STARTDATE AND ENDDATE
						+ ' OR ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE '
						+ ' OR ''' + CAST (@ENDDATE AS VARCHAR (30))   + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE '
						+ ' OR AR.APPLIEDRULEFROMDATE BETWEEN ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' AND ''' + CAST (@ENDDATE AS VARCHAR (30)) + ''''
						+ ' OR AR.APPLIEDRULETODATE BETWEEN ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' AND ''' + CAST (@ENDDATE AS VARCHAR (30)) + ''' )'						
					    + ' AND (''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE)'					 
						+ ' AND (''' + CAST (@dtToday AS VARCHAR (30)) + ''' BETWEEN ACR.BOOKINGFROMDATE AND ACR.BOOKINGTODATE)'
						+ ' AND ((''' + CAST (@NO_NIGHTS AS CHAR(4)) + ''' BETWEEN ACR.MINDAYSORNIGHTS AND ACR.MAXDAYSORNIGHTS) OR (ISNULL(ACR.MINDAYSORNIGHTS,0) =0 OR ISNULL(ACR.MAXDAYSORNIGHTS,0)=0))' --Gitesh Naik(56)
						+ ' AND R1.RULETYPEID = 17'
						+ ' UNION'
						+' SELECT TOP 1 1  FROM APPLIED_RULE AR WITH (NOLOCK)  INNER JOIN RULE_1 R1 WITH (NOLOCK) ON AR.RULEID = R1.RULEID'
						+' INNER JOIN APPLIED_CIRCUIT_RULE ACR WITH (NOLOCK) ON ACR.APPLIEDRULEID = AR.APPLIEDRULEID' 
						+' INNER JOIN APPLIED_RULE_OPTION_EXTRA AROE WITH (NOLOCK) ON AROE.APPLIEDRULEID = AR.APPLIEDRULEID'
						+' INNER JOIN SERVICE_EXTRA SE ON SE.SERVICEEXTRAID = AROE.SERVICEEXTRAID
						   WHERE SE.SERVICEID = S.SERVICEID'
						+' AND ( AR.APPLIEDRULEFROMDATE <=' + '''' + CAST (@STARTDATE AS VARCHAR (30)) + '''' + ' AND AR.APPLIEDRULETODATE >= ' + '''' + CAST (@ENDDATE AS VARCHAR (30)) + '''' 
						+ ' OR ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE '
						+ ' OR ''' + CAST (@ENDDATE AS VARCHAR (30))   + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE '
						+ ' OR AR.APPLIEDRULEFROMDATE BETWEEN ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' AND ''' + CAST (@ENDDATE AS VARCHAR (30)) + ''''
						+ ' OR AR.APPLIEDRULETODATE BETWEEN ''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' AND ''' + CAST (@ENDDATE AS VARCHAR (30)) + ''' )'						
					    + ' AND (''' + CAST (@STARTDATE AS VARCHAR (30)) + ''' BETWEEN AR.APPLIEDRULEFROMDATE AND AR.APPLIEDRULETODATE)'					 
						+ ' AND (''' + CAST (@dtToday AS VARCHAR (30)) + ''' BETWEEN ACR.BOOKINGFROMDATE AND ACR.BOOKINGTODATE)'
						+ ' AND ((''' + CAST (@NO_NIGHTS AS CHAR(4)) + ''' BETWEEN ACR.MINDAYSORNIGHTS AND ACR.MAXDAYSORNIGHTS)  OR (ISNULL(ACR.MINDAYSORNIGHTS,0) =0 OR ISNULL(ACR.MAXDAYSORNIGHTS,0)=0))'  --Gitesh Naik(56)
						+ ' AND R1.RULETYPEID = 17'
						+ ' ) '
						+ 'THEN 1
						ELSE 0
						END ) 
						AS HASCIRCUITOFFER ';
				END
			END
	 
       --EOC ManojG(55)
		set @SQLtoRun= @SQLtoRun +' From Service S with(nolock)' --shamil(36)
	 --BOC Arun(33)
	IF(ISNULL(@locationID,0) = 0 AND ISNULL(@locationName,'') = '')
	  BEGIN
		 SET @SQLtoRun = @SQLtoRun +
		        case 		--BOC Lorraine(42)
				when  ISNULL(@IsServiceTypeTransfer,0)=0 --Arun(35)
				then
				' Inner join Assigned_Region AR on ( AR.ServiceId = S.ServiceId)  ' +
				' Inner join Region R on (AR.RegionId = r.RegionId)  ' 
				else
				' inner join @TempTransferService TTS on TTS.ServiceId =S.ServiceId '
				end			--EOC Lorraine(42)
	 END
	ELSE
	  BEGIN
	  --BOC SHAMIL(36)--Suraj(43) shifted below
		--IF ISNULL(@IsServiceTypeTransfer,0) = 0 --Arun(37)
		--BEGIN
		--	CREATE TABLE #tmpAllRegions
		--	(
		--		SERVICEID INT,
		--		REGIONID INT
		--	)
			
		--	CREATE INDEX NDX1 ON #tmpAllRegions(SERVICEID) INCLUDE ([REGIONID]) --Suraj(42)

		--	INSERT INTO #tmpAllRegions (SERVICEID,REGIONID)
		--		SELECT SERVICEID, REGIONID FROM Assigned_Region WITH(NOLOCK) WHERE ISNULL(SERVICEID,0) > 0
		--		UNION
		--		SELECT SERVICEID, REGIONID FROM LINKED_ASSIGNED_REGION WITH(NOLOCK) WHERE ISNULL(SERVICEID,0) > 0

		--END
		--EOC SHAMIL(36)
		
			  	---BOC Sandip P.(36) Changes suggested by Shani.

			--BOC RAMA(38)
		if isnull(@locationName,'') <> '' AND @locationID =0 
			  INSERT INTO #region (Regionid, REGIONNAME, LEVEL1_REGIONID, LEVEL2_REGIONID, LEVEL3_REGIONID, LEVEL4_REGIONID, LEVEL5_REGIONID, LEVEL6_REGIONID,
			  LEVEL7_REGIONID, LEVEL8_REGIONID, LEVEL9_REGIONID)
			   SELECT 
			    Regionid,
				R.REGIONNAME,
				R.LEVEL1_REGIONID,
				R.LEVEL2_REGIONID,
				R.LEVEL3_REGIONID,
				R.LEVEL4_REGIONID,
				R.LEVEL5_REGIONID,
				R.LEVEL6_REGIONID,
				R.LEVEL7_REGIONID,
				R.LEVEL8_REGIONID,
				R.LEVEL9_REGIONID
			  FROM REGION R WITH (NOLOCK)
			  WHERE RegionName = @locationName AND regionTypeId BETWEEN 1 AND 9 
			  OR R.LEVEL1_REGIONID IN (SELECT regionid FROM @TBL_region)--Suraj(43)
		      OR R.LEVEL2_REGIONID IN (SELECT regionid FROM @TBL_region)--Suraj(43)
		      OR R.LEVEL3_REGIONID IN (SELECT regionid FROM @TBL_region)--Suraj(43)
		      OR R.LEVEL4_REGIONID IN (SELECT regionid FROM @TBL_region)--Suraj(43)
		      OR R.LEVEL5_REGIONID IN (SELECT regionid FROM @TBL_region)--Suraj(43)
		      OR R.LEVEL6_REGIONID IN (SELECT regionid FROM @TBL_region)--Suraj(43)
		      OR R.LEVEL7_REGIONID IN (SELECT regionid FROM @TBL_region)--Suraj(43)
		      OR R.LEVEL8_REGIONID IN (SELECT regionid FROM @TBL_region)--Suraj(43)
		      OR R.LEVEL9_REGIONID IN (SELECT regionid FROM @TBL_region)--Suraj(43)
	     else
		 --EOC RAMA(38)
			INSERT INTO #region (Regionid, REGIONNAME, LEVEL1_REGIONID, LEVEL2_REGIONID, LEVEL3_REGIONID, LEVEL4_REGIONID, LEVEL5_REGIONID, LEVEL6_REGIONID,
			LEVEL7_REGIONID, LEVEL8_REGIONID, LEVEL9_REGIONID)
			  SELECT
				Regionid,
				R.REGIONNAME,
				R.LEVEL1_REGIONID,
				R.LEVEL2_REGIONID,
				R.LEVEL3_REGIONID,
				R.LEVEL4_REGIONID,
				R.LEVEL5_REGIONID,
				R.LEVEL6_REGIONID,
				R.LEVEL7_REGIONID,
				R.LEVEL8_REGIONID,
				R.LEVEL9_REGIONID
			  FROM REGION R WITH (NOLOCK)
			  WHERE (CASE
				WHEN R.RegionID = @I_RegionID THEN 1
				WHEN R.LEVEL1_REGIONID = @I_RegionID THEN 1
				WHEN R.LEVEL2_REGIONID = @I_RegionID THEN 1
				WHEN R.LEVEL3_REGIONID = @I_RegionID THEN 1
				WHEN R.LEVEL4_REGIONID = @I_RegionID THEN 1
				WHEN R.LEVEL5_REGIONID = @I_RegionID THEN 1
				WHEN R.LEVEL6_REGIONID = @I_RegionID THEN 1
				WHEN R.LEVEL7_REGIONID = @I_RegionID THEN 1
				WHEN R.LEVEL8_REGIONID = @I_RegionID THEN 1
				WHEN R.LEVEL9_REGIONID = @I_RegionID THEN 1
				ELSE 0
			  END
			  ) > 0
			  --BOC Suchina(41)
			IF EXISTS (SELECT TOP 1 1 FROM @tmpServiceIDs ) 
			BEGIN
			INSERT INTO #RegionwithService
			  SELECT
				R.Regionid,
				R.REGIONNAME,
				R.LEVEL1_REGIONID,
				R.LEVEL2_REGIONID,
				R.LEVEL3_REGIONID,
				R.LEVEL4_REGIONID,
				R.LEVEL5_REGIONID,
				R.LEVEL6_REGIONID,
				R.LEVEL7_REGIONID,
				R.LEVEL8_REGIONID,
				R.LEVEL9_REGIONID,
				S.SERVICEID
			  FROM Service S WITH (NOLOCK)
			  LEFT OUTER JOIN Assigned_Region AR WITH (NOLOCK)
				ON AR.ServiceId = S.ServiceId
			 LEFT OUTER JOIN LINKED_ASSIGNED_REGION AMSR WITH (NOLOCK) --Poorva N(47)
			ON AMSR.SERVICEID = AR.ServiceId
			  INNER JOIN #region R
				ON (AR.RegionId = r.RegionId
				OR AMSR.REGIONID = r.RegionId)
				INNER JOIN @tmpServiceIDs tmpS ON tmpS.SERVICEID = S.SERVICEID
			END
			ELSE
			BEGIN
			--EOC Suchina(41)
			INSERT INTO #RegionwithService
			--BOC Suraj(42) commented and rewritten with union
			 -- SELECT
				--R.Regionid,
				--R.REGIONNAME,
				--R.LEVEL1_REGIONID,
				--R.LEVEL2_REGIONID,
				--R.LEVEL3_REGIONID,
				--R.LEVEL4_REGIONID,
				--R.LEVEL5_REGIONID,
				--R.LEVEL6_REGIONID,
				--R.LEVEL7_REGIONID,
				--R.LEVEL8_REGIONID,
				--R.LEVEL9_REGIONID,
				--S.SERVICEID
			 -- FROM Service S WITH (NOLOCK)
			 -- LEFT OUTER JOIN Assigned_Region AR WITH (NOLOCK)
				--ON AR.ServiceId = S.ServiceId
			 -- LEFT OUTER JOIN LINKED_ASSIGNED_REGION AMSR WITH (NOLOCK)
				--ON AMSR.SERVICEID = AR.ServiceId
			 -- INNER JOIN #region R
				--ON (AR.RegionId = r.RegionId
				--OR AMSR.REGIONID = r.RegionId)
			SELECT
				R.Regionid,
				R.REGIONNAME,
				R.LEVEL1_REGIONID,
				R.LEVEL2_REGIONID,
				R.LEVEL3_REGIONID,
				R.LEVEL4_REGIONID,
				R.LEVEL5_REGIONID,
				R.LEVEL6_REGIONID,
				R.LEVEL7_REGIONID,
				R.LEVEL8_REGIONID,
				R.LEVEL9_REGIONID,
				S.SERVICEID
			  FROM Service S WITH (NOLOCK)
			  LEFT OUTER JOIN Assigned_Region AR WITH (NOLOCK)
				ON AR.ServiceId = S.ServiceId
			  LEFT OUTER JOIN LINKED_ASSIGNED_REGION AMSR WITH (NOLOCK)
				ON AMSR.SERVICEID = AR.ServiceId
			  INNER JOIN #region R
				ON AR.RegionId = r.RegionId
			UNION 
				SELECT
				R.Regionid,
				R.REGIONNAME,
				R.LEVEL1_REGIONID,
				R.LEVEL2_REGIONID,
				R.LEVEL3_REGIONID,
				R.LEVEL4_REGIONID,
				R.LEVEL5_REGIONID,
				R.LEVEL6_REGIONID,
				R.LEVEL7_REGIONID,
				R.LEVEL8_REGIONID,
				R.LEVEL9_REGIONID,
				S.SERVICEID
			  FROM Service S WITH (NOLOCK)
			  LEFT OUTER JOIN Assigned_Region AR WITH (NOLOCK)
				ON AR.ServiceId = S.ServiceId
			  LEFT OUTER JOIN LINKED_ASSIGNED_REGION AMSR WITH (NOLOCK)
				ON AMSR.SERVICEID = AR.ServiceId
			  INNER JOIN #region R
				ON AMSR.REGIONID = r.RegionId
			--EOC Suraj(42)
		     END
			--SET @SQLtoRun = @SQLtoRun + ' inner join #RegionwithService R on R.SERVICEID = S.SERVICEID'  ---Sandip P.(SSS) --Suraj(46) commented and used below
			---EOC Sandip P.(36)
		--BOC Suraj(43)
		IF ISNULL(@IsServiceTypeTransfer,0) = 0 
		BEGIN
			CREATE TABLE #tmpAllRegions
			(
				SERVICEID INT,
				REGIONID INT
			)
			

			INSERT INTO #tmpAllRegions (SERVICEID,REGIONID)
				SELECT AR.SERVICEID, AR.REGIONID FROM Assigned_Region AR WITH(NOLOCK) 
				inner join #RegionwithService RS on RS.SERVICEID = AR.SERVICEID
				WHERE ISNULL(AR.SERVICEID,0) > 0
				UNION
				SELECT LAR.SERVICEID, LAR.REGIONID FROM LINKED_ASSIGNED_REGION LAR WITH(NOLOCK) 
				inner join #RegionwithService RS on RS.SERVICEID = LAR.SERVICEID
				WHERE ISNULL(LAR.SERVICEID,0) > 0
		END
		--EOC Suraj(43)
		 SET @SQLtoRun = @SQLtoRun + 
		  		case 		--BOC Lorraine(42)
		  		when  ISNULL(@IsServiceTypeTransfer,0)=0 --Arun(35)
		  		then
				--boc shamil(36)
		 		--' Left Outer join Assigned_Region AR with(nolock) on AR.ServiceId = S.ServiceId '
		 		--+'LEFT OUTER JOIN LINKED_ASSIGNED_REGION AMSR ON AMSR.SERVICEID = AR.SERVICEID  '
				 'INNER JOIN #tmpAllRegions AR with(nolock) on AR.ServiceId = S.ServiceId '
				 --eoc shamil(36)
		 		+ 'Inner join Region R with(nolock)  on (AR.RegionId = r.RegionId)' -- OR AMSR.REGIONID = r.RegionId)  ' --shamil(36)
				+ ' inner join #RegionwithService RS on RS.SERVICEID = S.SERVICEID AND RS.RegionId = AR.RegionId ' --Suraj(46) added sandip's changes here--Prudhvi(50) join RegionId also
				 else
				' inner join @TempTransferService TTS on TTS.ServiceId =S.ServiceId '
			    end			--EOC Lorraine(42)
	  END
	--EOC Arun(33)
	insert into #tblServiceRatings
	Select S.SERVICEID, rtrim(SERVICETYPERATINGNAME)SERVICETYPERATINGNAME
									  from Service S inner join
									  #RegionwithService RWS on RWS.serviceid = S.SERVICEID
									  INNER JOIN ASSIGNED_SERVICE_RATING ASR  WITH(nolock) ON ASR.ServiceID = S.ServiceID
									  INNER JOIN SERVICE_TYPE_RATING STRA  WITH(nolock) on (ASR.SERVICETYPERATINGID = STRA.SERVICETYPERATINGID ) 
									  INNER JOIN SERVICE_TYPE_RATING_TYPE STRT  WITH(nolock) ON (STRT.SERVICETYPERATINGTYPEID=STRA.SERVICETYPERATINGTYPEID AND STRT.ISSTARRATING=1
									  ) 
									  ORDER BY SERVICETYPERATINGSEQUENCE ASC
	


	SET @SQLtoRun= @SQLtoRun + ' INNER JOIN SERVICE_STATUS ST with(nolock) ON (S.SERVICESTATUSID = ST.SERVICESTATUSID AND SERVICESTATUSBOOKINGSEARCH = 1' --shamil(36)

	IF ISNULL(@ri_CalledFrom,0) = 0 
	BEGIN 
		SET @SQLtoRun = @SQLtoRun + ' AND ST.SERVICESTATUSAPIAVAILABLE = 1'
	END

	IF @RB_RETURNONLYFASTBUILDSERVICES = 1
	BEGIN
		SET @SQLtoRun = @SQLtoRun + ' AND ST.SERVICESTATUSFASTBUILD = 1'
	END			

	SET @SQLtoRun = @SQLtoRun + ') '
	--EOC Jeogan(39)

	if(ISNULL(@ServiceTypeIDs, '') = '')--Shivanand(20)
	BEGIN
		if @ServiceTypeID = 0 --if value 0 then take servicetypeid from TSHotelAPIB2C_settings
		Begin
			set @SQLtoRun= @SQLtoRun + ' inner join TSHotelAPIB2C_settings STH with(nolock) on ' +--vernal(8) --Gitesh Naik(41)
					' (s.ServiceTypeID = STH.ServiceTypeID and STH.ServiceSearchMaxCount>0)  ' 
		End
		if @ServiceTypeID = -1 --if servicetpe = 0 then return services of all service types
		Begin
			set @SQLtoRun= @SQLtoRun + ' inner join TSHotelAPIB2C_settings STH on ' +--vernal(8)
				' (STH.ServiceSearchMaxCount>0)  ' 
		End
		if @ServiceTypeID >0  --if value 0 then take servicetypeid from TSHotelAPIB2C_settings
		Begin -- if @ServiceTypeID > 0 then return service only with servicetypeid = @ServiceTypeID
				set @SQLtoRun= @SQLtoRun + ' inner join TSHotelAPIB2C_settings STH with(nolock) on ' +--vernal(8) --Gitesh Naik(41)
					' (s.ServiceTypeID = '+ cast (@ServiceTypeID  as varchar)   +' and STH.ServiceSearchMaxCount>0)  ' 
		End
	END
	ELSE
	BEGIN--Boc Shivanand(20)
		set @SQLtoRun= @SQLtoRun + ' inner join TSHotelAPIB2C_settings STH with(nolock) on ' +--vernal(8) --Gitesh Naik(41)
		' (s.ServiceTypeID in ('+  LTRIM(RTRIM(@ServiceTypeIDs))   +') and STH.ServiceSearchMaxCount>0)  ' 
	END--Eoc Shivanand(20)
	--BOC VIVEK 04
	IF @ServiceTypeCategoryArrDep =1
	BEGIN
		set @SQLtoRun= @SQLtoRun + ' inner join service_type STYP with(nolock) on ' + --Gitesh Naik(41)
				--' (S.ServiceTypeID = STYP.ServiceTypeID AND STYP.ServiceTypeCategory = 1)  '
                ' (S.ServiceTypeID = STYP.ServiceTypeID )  ' --vernal(8) 
	END
	ELSE IF @ServiceTypeCategoryArrDep =0	
	BEGIN
		set @SQLtoRun= @SQLtoRun + ' inner join service_type STYP with(nolock) on ' + --Gitesh Naik(41)
				--' (S.ServiceTypeID = STYP.ServiceTypeID AND STYP.ServiceTypeCategory = 0)  ' 
                ' (S.ServiceTypeID = STYP.ServiceTypeID )  '
	END
	--EOC VIVEK 04
	 --BOC-Derik(14)
	 if @ServiceTypeRatingTypeID >0  
	 Begin  
		set @SQLtoRun= @SQLtoRun + ' inner join ASSIGNED_SERVICE_TYPE_RATING_TYPE ASTR with(nolock) on ' +  --Gitesh Naik(41)
		' (ASTR.SERVICETYPEID = S.SERVICETYPEID and ASTR.SERVICETYPERATINGTYPEID = '+ cast (@ServiceTypeRatingTypeID  as varchar)   +')  '  
	 End  
	 if @ServiceTypeRatingID >0  
	 Begin  
		set @SQLtoRun= @SQLtoRun + ' inner join ASSIGNED_SERVICE_RATING ASR with(nolock) on ' +  --Gitesh Naik(41)
		' (ASR.SERVICEID = S.SERVICEID and ASR.SERVICETYPERATINGID = '+ cast (@ServiceTypeRatingID  as varchar(max))   +')  '  
	 End   
	 if isnull(@ServiceTypeOptionIds,'') <> ''  
	 Begin  
		set @SQLtoRun= @SQLtoRun + ' inner join service_option_in_service sois with(nolock) on ' +  --Gitesh Naik(41) 
		' (sois.serviceid = s.serviceid and sois.servicetypeoptionid IN ('+ cast (@ServiceTypeOptionIds  as varchar (max))   +'))  '  
		
	 End  
	 --EOC-Derik(14)
	if isnull(@ServiceTypeRatingName,'') <> '' and @ServiceTypeRatingID <=0 --Added @ServiceTypeRatingID <=0 condition //Salim Mandrekar(28)
	Begin
		--BOC VIVEK 02
		IF @INCSTARSERVICES=0
		BEGIN
		set @SQLtoRun= @SQLtoRun + ' inner join ASSIGNED_SERVICE_RATING ASR on ( ASR.ServiceId = S.ServiceId) ' +
				' inner join SERVICE_TYPE_RATING STRA on (ASR.SERVICETYPERATINGID = STRA.SERVICETYPERATINGID AND STRA.SERVICETYPERATINGNAME like ''' + @ServiceTypeRatingName +''' ) '
		END
		ELSE
		BEGIN
			set @SQLtoRun= @SQLtoRun + ' inner join ASSIGNED_SERVICE_RATING ASR with(nolock)on ( ASR.ServiceId = S.ServiceId) ' + --Gitesh Naik(41)
					' inner join SERVICE_TYPE_RATING STRA with(nolock) on (ASR.SERVICETYPERATINGID = STRA.SERVICETYPERATINGID)' + --Gitesh Naik(41)
					' INNER JOIN SERVICE_TYPE_RATING STRA2 ON (STRA.SERVICETYPERATINGTYPEID = STRA2.SERVICETYPERATINGTYPEID AND STRA.SERVICETYPERATINGSEQUENCE >= STRA2.SERVICETYPERATINGSEQUENCE AND STRA2.SERVICETYPERATINGNAME like ''' + @ServiceTypeRatingName +''' ) '
		END
		--EOC VIVEK 02
	End
    --boc(8) vernal
   if @ServiceInfoRequired <> 0
    begin
    if @ri_CalledFrom = 1   --Savira(18)
    begin
    set @SQLtoRun= @SQLtoRun + ' LEFT OUTER JOIN address d WITH (NOLOCK) ON s.serviceid = d.serviceid '+		--Anish(31) --VishalNaik (44)
    'LEFT OUTER JOIN state e WITH (NOLOCK) ON d.stateid = e.stateid '+				--Anish(31)
    'LEFT OUTER JOIN country f WITH (NOLOCK) ON d.countryid = f.countryid '--+		--Anish(31)
   
    end
    else
    begin
    set @SQLtoRun= @SQLtoRun + ' LEFT OUTER JOIN address d WITH (NOLOCK) ON s.serviceid = d.serviceid AND addresstypeid = 2'+ --Anish(31) --VishalNaik (44)
    'LEFT OUTER JOIN state e WITH (NOLOCK) ON d.stateid = e.stateid '+							  --Anish(31)
    'LEFT OUTER JOIN country f WITH (NOLOCK) ON d.countryid = f.countryid '						--Anish(31)
    end
    end


	 set @SQLtoRun= @SQLtoRun + ' INNER JOIN supplier sup WITH (NOLOCK) ON ( s.supplierid = sup.supplierid AND sup.suppliername LIKE ''%'+isnull(@SupplierName,'')+'%'') '+
	   'LEFT OUTER JOIN  SUPPLIER_STATUS SUPS ON sup.SUPPLIERSTATUSID = SUPS.SUPPLIERSTATUSID'     --Vanessa (19) --VishalNaik (44)
--vernal(12) commented
--    if @Imagerequired <> 0 and @ServiceInfoRequired =1
--    begin 
--    set @SQLtoRun= @SQLtoRun + ' inner join assigned_image aim on aim.serviceid=s.serviceid '+
--    'inner join image a on a.IMAGEID=aim.IMAGEID '+
--    'INNER JOIN (SELECT serviceid,MIN(assignedimageid) assignedimageid FROM   assigned_image ai '+
--    'WHERE  serviceoptioninserviceid IS NULL AND serviceextraid IS NULL '+
--    'GROUP  BY serviceid) tmp ON ( aim.assignedimageid = tmp.assignedimageid AND aim.serviceid = tmp.serviceid ) '
--    end
    if @Matchcodedetailsrequired <> 0 and @ServiceInfoRequired =1
    begin
    set @SQLtoRun= @SQLtoRun +  ' LEFT OUTER JOIN service_matching sm ON s.serviceid = sm.serviceid '
    end
    --boc(11) vernal
    set @SQLtoRun= @SQLtoRun + ' left outer join End_point ep WITH (NOLOCK) on ep.endpointid = s.endpointid left   outer join end_point_type et WITH (NOLOCK) on et.endpointtypeid=ep.endpointtypeid '			--Anish(31)
    --eoc(11) vernal 
	set @SQLtoRun= @SQLtoRun + ' Left outer join #tblServiceRatings tblSTR ON tblSTR.SERVICEID = S.SERVICEID '
    --eoc(8) vernal
	if @LocalServiceIDs <> '' 
		Set @SQLtoRun =@SQLtoRun +	' where s.ServiceID in (' + @ServiceIDs + ')'
	else 
		Set @SQLtoRun =@SQLtoRun +	' where 1=1 '  -- Just a place holder
	--Ravi (6) BOC 25Feb08
	--Set @SQLtoRun =@SQLtoRun +	' and isnull(s.endpointid,0) in (select endpointid from end_point where isenable=1) '
	--Ravi (6) EOC
	
	if ISNULL(@IsServiceTypeTransfer,0)=0 -- Lorraine(42) --Arun(35)
	begin-- Lorraine(42)
	if isnull(@locationName,'') <> '' OR  @locationID <> 0 OR CHARINDEX(',',@RVC_GEOLOCATIONIDS) > 0  --vernal(10) --Arun(35)
	Begin
		declare @RegionTypeID int
		declare @RegionID int
		-- until the new region degpth is defined , we are putting check of
		--regionTypeId between 1 and 9
	        --boc ggosavi(03)
                declare @str_RegionId varchar(8000)	--Nagendra(30) increased the size to 8000
                --queries which will get all region id
                --set @str_RegionId='select  regionid from Region where RegionName = '''+ @locationName + ''' and regionTypeId between 1 and 9  '--ggosavi(7)
         	--Check if the region is there for The location
                --Top 1 can be used
                --eoc ggosavi(03)
              
               --BOC Vernal
				if isnull(@locationName,'') <> '' AND @locationID =0 
				begin
                	select top 1 @RegionTypeID  = regionTypeId , @RegionID = RegionID from Region  WITH (NOLOCK) where RegionName = @locationName and regionTypeId between 1 and 9		--Anish(31)
               		--boc ggosavi(7)
                	set @locationName =replace(@locationName , '''','''''') 
	                set @str_RegionId='select  regionid from Region WITH (NOLOCK) where RegionName = '''+ @locationName + ''' and regionTypeId between 1 and 9  '			--Anish(31)
	                --eoc ggosavi(7)  
					end 
				else if isnull(@locationName,'') = '' AND @locationID <> 0 
				begin
					select @RegionTypeID  = regionTypeId , @RegionID = RegionID from Region where RegionID = @locationId and regionTypeId between 1 and 9
					set @str_RegionId='select  regionid from Region WITH (NOLOCK) where RegionID = '+ cast (@locationId  as varchar) + ' and regionTypeId between 1 and 9  '		--Anish(31)
				end
				else if isnull(@locationName,'') <> '' AND @locationID <> 0 
				begin
					select @RegionTypeID  = regionTypeId , @RegionID = RegionID from Region where RegionID = @locationId AND RegionName = @locationName and regionTypeId between 1 and 9
					set @locationName = replace(@locationName , '''','''''') 
					--set @str_RegionId='select  regionid from Region WITH (NOLOCK) where RegionName = '''+ @locationName + ''' and RegionID = '+ cast (@locationId  as varchar) + ' and regionTypeId between 1 and 9  ' --Anish(31)
				end
				--EOC Vernal(9)
				--BOC Nagendra(30)
				IF CHARINDEX(',',@RVC_GEOLOCATIONIDS) > 0
					SET @str_RegionId = @RVC_GEOLOCATIONIDS
				--EOC Nagendra(30)	
				
                if @RegionID is not null OR CHARINDEX(',',@RVC_GEOLOCATIONIDS) > 0	--Nagendra(30)
				begin --Swapnil(33)
		         --boc ggosavi(03)	
                         --set @SQLtoRun= @SQLtoRun + ' and (R.RegionID = ' + cast (@RegionID  as varchar)   + ' or R.LEVEL' + CAST( @RegionTypeID AS VARCHAR) + '_REGIONID  = ' + cast (@RegionID  as varchar) + ' ) '
		         --set @SQLtoRun= @SQLtoRun + ' and (R.RegionID in ('+ @str_RegionId + ' ))'
                         IF @i_RegionCount <> 1
						BEGIN
                         set @SQLtoRun= @SQLtoRun + ' and ( R.RegionID in ('+ @str_RegionId + ' ) 
                                                           OR R.LEVEL1_REGIONID in ('+ @str_RegionId + ' )
                                                           OR R.LEVEL2_REGIONID in ('+ @str_RegionId + ' )   
                                                           OR R.LEVEL3_REGIONID in ('+ @str_RegionId + ' )
                                                           OR R.LEVEL4_REGIONID in ('+ @str_RegionId + ' )
                                                           OR R.LEVEL5_REGIONID in ('+ @str_RegionId + ' )
                                                           OR R.LEVEL6_REGIONID in ('+ @str_RegionId + ' )
                                                           OR R.LEVEL7_REGIONID in ('+ @str_RegionId + ' )
                                                           OR R.LEVEL8_REGIONID in ('+ @str_RegionId + ' )
                                                           OR R.LEVEL9_REGIONID in ('+ @str_RegionId + ' ) ) and ISNULL(@i_RegionCount,0)<>1 ' --Swapnil(33)--Nagesh(42)   --Arun(35)
														   END
						 ELSE
						 BEGIN
								--Swapnil(33)(BOC) ---Sandip P.(36)  --Changes Suggestd by Shani
								----set @SQLtoRun= @SQLtoRun + ' and ( R.RegionID =@I_RegionID
								----                                   OR R.LEVEL1_REGIONID =@I_RegionID
								----                                   OR R.LEVEL2_REGIONID =@I_RegionID   
								----                                   OR R.LEVEL3_REGIONID =@I_RegionID 
								----                                   OR R.LEVEL4_REGIONID =@I_RegionID 
								----                                   OR R.LEVEL5_REGIONID =@I_RegionID 
								----                                   OR R.LEVEL6_REGIONID =@I_RegionID 
								----                                   OR R.LEVEL7_REGIONID =@I_RegionID 
								----                                   OR R.LEVEL8_REGIONID =@I_RegionID 
								----                                   OR R.LEVEL9_REGIONID =@I_RegionID  ) and @i_RegionCount=1'
								set @SQLtoRun= @SQLtoRun + ' and @i_RegionCount=1 '  ---Sandip P.(36)
								
							END
						--Swapnil(33)(EOC)
                         --eoc ggosavi(03) 
						 end --Swapnil(33)
                else
			set @runQuery=0
	End
     end -- Lorraine(42) 
	
        --boc ggosavi(01)
        if @ISRECOMMENDEDPRODUCT<>0 
         begin
           set @SQLtoRun = @SQLtoRun + ' and ISRECOMMENDEDPRODUCT =' + cast(@ISRECOMMENDEDPRODUCT as varchar) 
         end  	
        --eoc ggosavi(01)
        --BOC-Derik(14)
		 -- if @ServiceInfoRequired <> 0  --Savira(18)    
			--begin 
			--IF ISNULL(@ri_CalledFrom,0) = 0  --Vanessa (19)
			--begin	
			----BOC Harshad Teli(15)
			--	set @SQLtoRun= @SQLtoRun + 'AND (ISNULL(addresspostcode,'''') LIKE ''%' + isnull(@PostCode,'') +'%'')and (('+ cast(IsNull(@ri_CalledFrom,0) as varchar) +' != 1) or d.SERVICEID is null or d.ADDRESSID = ( select  min( ADDRESSID )  from ADDRESS WITH (NOLOCK) where  SERVICEID = S.SERVICEID ) )'		--Anish(31)
			----EOC Harshad Teli(15)
			--end
			----BOC Vanessa (19)
			--else
			--begin			
			--	--BOC SRIKER(22)
			--	IF (ISNULL(@RB_ISFASTBUILDSERVICE, 0) = 1)
			--	BEGIN
			--		set @SQLtoRun= @SQLtoRun + 'AND (ISNULL(addresspostcode,'''') LIKE ''%' + isnull(@PostCode,'') +'%'')and (('+ cast(IsNull(@ri_CalledFrom,0) as varchar) +' != 1) or d.SERVICEID is null or d.ADDRESSID = ( select  min( ADDRESSID )  from ADDRESS WITH (NOLOCK) where  SERVICEID = S.SERVICEID ) ) AND (ST.SERVICESTATUSFASTBUILD=1)'		--Anish(31)
			--	END
			--	--EOC SRIKER(22)
			--	ELSE
			--	BEGIN
			--		set @SQLtoRun= @SQLtoRun + 'AND (ISNULL(addresspostcode,'''') LIKE ''%' + isnull(@PostCode,'') +'%'')and (('+ cast(IsNull(@ri_CalledFrom,0) as varchar) +' != 1) or d.SERVICEID is null or d.ADDRESSID = ( select  min( ADDRESSID )  from ADDRESS WITH (NOLOCK) where  SERVICEID = S.SERVICEID ) ) AND (ST.SERVICESTATUSBOOKINGSEARCH=1) AND (SUPS.SUPPLIERSTATUSBOOKINGSEARCH = 1)AND (SUPS.SUPPLIERSTATUSNOBOOKINGS = 0) AND (ST.SERVICESTATUSNOBOOKINGS =0)'			--Anish(31)
			--	END
			--end
			----EOC Vanessa (19)
			--end
			
		   if @ServiceInfoRequired <> 0  --Savira(18)    
			begin			
				--BOC SRIKER(22)
				IF (ISNULL(@RB_ISFASTBUILDSERVICE, 0) = 1)
				BEGIN
					set @SQLtoRun= @SQLtoRun + ' AND (ISNULL(addresspostcode,'''') LIKE ''%' + isnull(@PostCode,'') +'%'')and (('+ cast(IsNull(@ri_CalledFrom,0) as varchar) +' != 1) or d.SERVICEID is null or d.ADDRESSID = ( select  min( ADDRESSID )  from ADDRESS WITH (NOLOCK) where  SERVICEID = S.SERVICEID ) ) AND (ST.SERVICESTATUSFASTBUILD=1)'		--Anish(31)
				END
				--EOC SRIKER(22)
				ELSE
				BEGIN
					set @SQLtoRun= @SQLtoRun + ' AND (ISNULL(addresspostcode,'''') LIKE ''%' + isnull(@PostCode,'') +'%'')and (('+ cast(IsNull(@ri_CalledFrom,0) as varchar) +' != 1) or d.SERVICEID is null or d.ADDRESSID = ( select  min( ADDRESSID )  from ADDRESS WITH (NOLOCK) where  SERVICEID = S.SERVICEID ) )'			--Anish(31)
				END
			end
		set @SQLtoRun= @SQLtoRun + ' AND (ST.SERVICESTATUSBOOKINGSEARCH=1) AND (SUPS.SUPPLIERSTATUSBOOKINGSEARCH = 1)'-- AND (SUPS.SUPPLIERSTATUSNOBOOKINGS = 0) AND (case when '+cast(ISNULL(@RB_ISFASTBUILDSERVICE, 0) as varchar)+'=1 then 0 else ST.SERVICESTATUSNOBOOKINGS end) = 0' --Vanessa (19)	--VishalNaik (44) --Gitesh Naik(39) --ManojG(54)
		--EOC-Derik(14)
	--BOC VIMLESH(35)
	IF (ISNULL(@RI_SERVICESOURCE,'')<>'')
	BEGIN
		IF (@RI_SERVICESOURCE = 'LOCAL')
		BEGIN
			SET @SQLtoRun=@SQLtoRun + ' AND (endpointtypename = ''' + @RI_SERVICESOURCE + '''' +' OR endpointtypename IS NULL)'
		END
		ELSE
		BEGIN
			SET @SQLtoRun=@SQLtoRun + ' AND endpointtypename = ''' + @RI_SERVICESOURCE + ''''
		END
	END

		SET @SQLtoRun=@SQLtoRun + ' AND ISNULL(STYP.OPERATIONALSERVICEONLY, 0) = 0 ' -- Najeeb(51)	--Anuja(52)	-- Added Null Check.

	set @SQLtoRun= @SQLtoRun +' OPTION (KEEPFIXED PLAN) ' --Suraj(47)
		--EOC VIMLESH(35)
		if @runQuery=1 and OBJECT_ID('tempdb..#temp') IS NOT NULL
	begin
		insert into #temp 
		exec (@SQLtoRun)
	end
	--BOC SHAMIL(36)
	IF OBJECT_ID('tempdb..#tmpAllRegions') IS NOT NULL
		DROP TABLE #tmpAllRegions
	--EOC SHAMIL(36)
	DROP TABLE #tmpRegion --Arun(33)
		--BOC Suraj(46)
	IF(ISNULL(@locationID,0) > 0 AND ISNULL(@locationName,'') != '')
	BEGIN
		DROP TABLE #Region
		DROP TABLE #RegionwithService
	END
	--EOC Suraj(46)
END

GO

--------------

SET QUOTED_IDENTIFIER  OFF    SET ANSI_NULLS  ON 
GO

IF EXISTS (SELECT 1 FROM SYSOBJECTS WHERE ID = OBJECT_ID(N'[dbo].[usp_Get_NFD_Package_Service_Allocation_Availibility]') AND OBJECTPROPERTY(ID, N'ISPROCEDURE') = 1)
DROP PROCEDURE dbo.usp_Get_NFD_Package_Service_Allocation_Availibility
GO 

/******************************************************************************************************************
Created By:- Rupesh P. Korgaukar
Date      :- 31 Aug 2013
Logic     :- Logic taken from usp_Get_Package_Service_Allocation_Availibility
Modification History
------------------------------------------------------------------------------------------------------------------
Snela(01)       25 Nov 2013	      Fixed Issue #47415,Service in STOP SALES appears available in API 
Deval(02)       29 Jan 2014       Fixed Issue 48112, Added @rvc_FirstDeparture
Shakeel(03)     25 Jun 2014       Fixed Issue 51317-TOP - API - Package Search - Timeout (LIVE) -(Replicated Fix by Shani)
Shakeel(04)     14 Aug 2014       Replicated Shani's change for 55642
Mahendra(05)	10 Jun 2016		  Fixed QAAPI-955
Arun(06)		18 Jul 2016		  Fixed issue QAAPI-976
Meena(07)       28 Jul 2016       Fixed issue:69758:Changed the logic to handled scenarios related to split
Rohitk(08)      10 Nov 2016       Fixed:80636 
Rohitk(09)		06 Jan 2016		  Fixed: Issue : 82078 
Yogesh(09)		24 Nov 2018		  Fixed issue: 93595
******************************************************************************************************************/

CREATE PROCEDURE dbo.usp_Get_NFD_Package_Service_Allocation_Availibility
	@rvc_ServiceType VARCHAR(8000) = '',
	@rvc_ElementIDs VARCHAR(1000) = '',
	@rvc_NFDXML TEXT = '',
	@rb_FirstDeparture BIT = 0 --DEVAL(02)
AS
BEGIN
	SET NOCOUNT ON
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED--Snela(01)
	
		DECLARE @tblNOFIXEDDEPARTURE TABLE
				(
					Packageid INT,
					TMPDEPARTUREDATE DATETIME
				)  
		
		--BOC Deval(32)
		DECLARE @tblFIRSTDEPARTURE TABLE
				(
					Packageid INT,
					TMPDEPARTUREDATE DATETIME
				)  
		--EOC Deval(32)		 
				
		DECLARE @NFDDoc INT, @vcServiceType VARCHAR(50), @I_SYSTEMSETTINGSFIELDVALUE BIT, @dt_BookingDate DATETIME

		IF CONVERT (VARCHAR(8000),@rvc_NFDXML) = ''
			RETURN--SET @rvc_NFDXML = NULL 

		IF @rvc_NFDXML IS NOT NULL 
		BEGIN 
			EXEC sp_xml_preparedocument @NFDDoc OUTPUT, @rvc_NFDXML

			INSERT INTO @tblNOFIXEDDEPARTURE (Packageid, TMPDEPARTUREDATE)    
			SELECT PID,DD    
			FROM OPENXML(@NFDDoc, N'/NFDDETAILS/NFD',1)     
			WITH (PID INT '@PID', DD DATETIME '@DD')   --Mahendra(05) converted PId to upper case     

			EXEC sp_xml_removedocument @NFDDoc 
			
			--BOC DEVAL(02)
			IF @RB_FIRSTDEPARTURE = 1
			BEGIN
			  INSERT INTO @tblFIRSTDEPARTURE (PACKAGEID, TMPDEPARTUREDATE) 
			  SELECT PACKAGEID, MIN(TMPDEPARTUREDATE)
			  FROM @tblNOFIXEDDEPARTURE
			  GROUP BY PACKAGEID
			 			
			  DELETE FROM @tblNOFIXEDDEPARTURE
			
			  INSERT INTO @tblNOFIXEDDEPARTURE (Packageid, TMPDEPARTUREDATE)
			  SELECT PACKAGEID, TMPDEPARTUREDATE
			   FROM @tblFIRSTDEPARTURE     
		    END
			--EOC DEVAL(02) 
		END

--BOC MEENA(07) --Declare table to store allocation for each day
		DECLARE @tblPackageServiceAllocationsInfo TABLE(
		ID INT IDENTITY(1,1) PRIMARY KEY,
		PackageDepartureID INT,
		PackageElementID INT,
		PackageServiceID INT,
		Availibility INT
		,AllocationId INT --
		,ReleasePeriod INT 
		,InDate DATETIME
		,ALLOCATIONTYPEID	INT
		,OutDate DATETIME 
		,SERVICEOPTIONINSERVICEID int
		,Serviceid int 
		,ALLOCATIONUSAGEDATE DATETIME
		,PackageDepartureDate DATETIME
		,PackageID INT
		)
		--EOC MEENA(07)
		DECLARE @tblPackageServiceAllocations TABLE
				(
					ID INT IDENTITY(1,1) PRIMARY KEY,
					PackageDepartureID INT,
					PackageElementID INT,
					PackageServiceID INT,
					ServiceOptionID INT,
					Availibility INT,
					AllocationId INT,
					ReleasePeriod INT,
					InDate DATETIME,
					PackageID INT,
					PackageDepartureDate DATETIME
					,OutDate DATETIME --Snela(01)
                    ,PACKAGEOPTIONID INT --MEENA(07)
				)
		--BOC Snela(01)
		--DECLARE @tblResult TABLE(
		create table #tblResult( --Rohitk(08) Replaced #tblResult to #tblResult
			PACKAGEDEPARTUREID	INT ,
			PACKAGEELEMENTID	INT ,
			PackageServiceID INT ,
			AVAILABILITY INT,
			ALLOCATIONid INT ,
			SERVICEOPTIONINSERVICEID INT ,
			ServiceID INT,
			PackageID INT,					
			PackageDepartureDate DATETIME,	
			ISNFD BIT
			,InDate DATETIME 
			,OutDate DATETIME 	
			,PACKAGEOPTIONID INT --MEENA(07)
			)					
		IF OBJECT_ID('tempdb..#tblServiceStopSales') IS NOT NULL DROP TABLE #tblServiceStopSales --Rohitk(09)
								
		CREATE table #tblServiceStopSales --Rohitk(09) Replaced @tblServiceStopSales with #tblServiceStopSales	
		--DECLARE @tblServiceStopSales TABLE
		(	
			SERVICEOPTIONINSERVICEID INT NULL,	
			ALLOCATIONID	INT NULL,
			STOPSALESSTARTDATE	DATETIME NULL,
			STOPSALESENDDATE	DATETIME NULL)
	--EOC Snela(01)
	
		DECLARE @tblPackageDepartureIDs TABLE
				(
					ID INT IDENTITY(1,1) PRIMARY KEY,
					PackageDepartureID INT
				)

		DECLARE @tblServiceType TABLE
				(
					ID INT IDENTITY(1,1) PRIMARY KEY,
					ServiceTypeID INT,
					ServiceTypeName VARCHAR(50)
				)

		DECLARE @tblPackageElementIDs TABLE
				(
					ID INT IDENTITY(1,1) PRIMARY KEY,
					PackageElementID INT
				)



		DECLARE @tblPackageOptions TABLE
				(
					ServiceOptionID INT,
					PackageElementID INT,
					PackageDepartureID INT,
					PackageServiceID INT,
					DepartureStartDate DATETIME,
					DepartureEndDate DATETIME,
					PackageOptionID INT,
					DayOverLap INT,
					PackageOptionSplitPrice INT,
					PackageOptionStartDate DATETIME,
					PackageOptionEndDate DATETIME,
					PackageID INT,
					ServiceID INT --Deval(02) 
                   ,PACKAGEOPTIONNUMBEROFNIGHTS INT --MEENA(07)
				)
         
         --BOC Deval(02)
		DECLARE @TBLPACKAGEDAYSEQ TABLE
				(
					ID INT IDENTITY(1,1) PRIMARY KEY,
					PACKAGEID INT,
					LASTPACKAGEITENARYDAYSEQ INT
				)
		
		INSERT INTO @TBLPACKAGEDAYSEQ
				SELECT NFD.PACKAGEID, MAX(PACKAGEITINERARYDAYSEQ)
				FROM @TBLNOFIXEDDEPARTURE NFD 
				INNER JOIN PACKAGE_ITINERARY_DAY PID ON NFD.PACKAGEID = PID.PACKAGEID 
				GROUP BY NFD.PACKAGEID 		
		--EOC Deval(02)	


		SELECT @I_SYSTEMSETTINGSFIELDVALUE = SYSTEMSETTINGSFIELDVALUE 
		FROM SYSTEM_SETTINGS_FIELD 
		WHERE SYSTEMSETTINGSFIELDNAME like 'USEGENERALALLOCATIONFORAPI'

	
		SET @dt_BookingDate = CAST((CONVERT(CHAR(8), GETDATE(), 112)) AS DATETIME)

		SELECT  @rvc_ServiceType = ISNULL(@rvc_ServiceType,''),
				@rvc_ElementIDs = ISNULL(@rvc_ElementIDs,'')


		-- Get ServiceType into a table
		IF isnull(LEN(@rvc_ServiceType),0) > 12 and @rvc_ServiceType like 'SERVICETYPE%'
		BEGIN
			SET @vcServiceType = LTRIM(RTRIM(SUBSTRING(@rvc_ServiceType,1,CHARINDEX(':',@rvc_ServiceType)-1)))
			
			IF(@vcServiceType = 'ServiceTypeID')
			BEGIN
				SET @rvc_ServiceType =  REPLACE(LTRIM(RTRIM(SUBSTRING(@rvc_ServiceType,CHARINDEX(':', @rvc_ServiceType) + 1, 999))),'~',',')

				INSERT INTO @tblServiceType(ServiceTypeID,ServiceTypeName) 
				SELECT VALUEID,NULL FROM DBO.UDF_LIST_TO_TABLE(@rvc_ServiceType)
			END
			ELSE IF(@vcServiceType = 'ServiceTypeName')
			BEGIN 
				SET @rvc_ServiceType = REPLACE(LTRIM(RTRIM(SUBSTRING(@rvc_ServiceType,CHARINDEX(':', @rvc_ServiceType) + 1, 999))),'~',',')

				INSERT INTO @tblServiceType(ServiceTypeID,ServiceTypeName)
				SELECT NULL,VALUENAME FROM dbo.UDF_STR_LIST_TO_TABLE(@rvc_ServiceType)

				UPDATE tST SET
					tST.ServiceTypeID = ST.SERVICETYPEID
				FROM @tblServiceType tST
				INNER JOIN SERVICE_TYPE ST ON ST.SERVICETYPENAME = tST.ServiceTypeName
			END
		END
		
		-- Get PackageElement into a table.
		INSERT INTO @tblPackageElementIDs(PackageElementID)
		SELECT DISTINCT VALUEID FROM dbo.udf_LIST_TO_TABLE(@rvc_ElementIDs)

		/*IF NOT EXISTS(SELECT TOP 1 1 FROM @tblPackageElementIDs)
			RETURN*/ --DEVAL(02), COMMENTED FOR OPTIONAL OPTIONS


		IF NOT EXISTS(SELECT TOP 1 1 FROM @tblPackageElementIDs)
			INSERT INTO @tblPackageElementIDs(PackageElementID)
			SELECT DISTINCT PE.PackageElementID  --Shakeel(04) added distinct
			--SELECT PE.PackageElementID
			FROM PACKAGE_ELEMENT PE
			INNER JOIN @tblNOFIXEDDEPARTURE FD ON  FD.Packageid = PE.PACKAGEID 
			INNER JOIN PACKAGE P ON P.PACKAGEID = FD.Packageid


		--IF NOT EXISTS(SELECT TOP 1 1 FROM @tblServiceType)
		--	INSERT INTO @tblServiceType(ServiceTypeID)
		--	SELECT ST.SERVICETYPEID
		--	FROM SERVICE_TYPE ST
		--	INNER JOIN SERVICE S ON S.SERVICETYPEID = ST.SERVICETYPEID
		--	INNER JOIN PACKAGE_SERVICE PS ON PS.SERVICEID = S.SERVICEID
		--	INNER JOIN @tblNOFIXEDDEPARTURE FD ON FD.Packageid = PS.PACKAGEID
		--	WHERE ISNULL(PS.PACKAGESERVICEISDELETED,0) = 0 
		
		 --BOC Deval(02), above commented
        IF NOT EXISTS(SELECT TOP 1 1 FROM @tblServiceType)
			INSERT INTO @tblServiceType(ServiceTypeID)
			SELECT SERVICETYPEID
			FROM SERVICE_TYPE
        --EOC Deval(02)


		INSERT INTO @tblPackageOptions
				(
					ServiceOptionID,
					PackageElementID,
					PackageDepartureID,
					PackageServiceID,
					DepartureStartDate,
					DepartureEndDate,
					PackageOptionID,
					DayOverLap,
					PackageOptionStartDate,
					PackageOptionEndDate,
					PackageID,
					ServiceID --Deval(02) 
                   ,PACKAGEOPTIONNUMBEROFNIGHTS --MEENA(07)
				)
				
		SELECT PO.SERVICEOPTIONINSERVICEID, 
			   pe.PACKAGEELEMENTID, 
			   0, 
			   ps.PACKAGESERVICEID,
			   NFD.TMPDEPARTUREDATE, 
			   NFD.TMPDEPARTUREDATE + PID.LASTPACKAGEITENARYDAYSEQ, --Deval(02)--MAX(PID.PACKAGEITINERARYDAYSEQ),
			   PO.PackageOptionID,
			   ISNULL((SELECT CHARGINGPOLICYDAYOVERLAP 
				       FROM CHARGING_POLICY	  WHERE CHARGINGPOLICYID  = (SELECT TOP 1 CHARGINGPOLICYID 
					 FROM ASSIGNED_CHARGING_POLICY WHERE SERVICEoptioninserviceid = po.SERVICEOPTIONINSERVICEID)),0) AS CHARGINGPOLICYDAYOVERLAP,
			   DATEADD(DD,PO.PACKAGEOPTIONFROMDAYSEQ - 1,NFD.TMPDEPARTUREDATE),
			   DATEADD(DD,PO.PACKAGEOPTIONTODAYSEQ - 1,NFD.TMPDEPARTUREDATE),
			   NFD.Packageid,
			   PS.SERVICEID --Deval(02) 
              ,PO.PACKAGEOPTIONNUMBEROFNIGHTS --MEENA()
		FROM PACKAGE_SERVICE PS
		INNER JOIN @tblNOFIXEDDEPARTURE NFD ON NFD.Packageid = PS.PACKAGEID 
		--INNER JOIN SERVICE S ON PS.SERVICEID = S.SERVICEID --Deval(02), Commented
		--INNER JOIN @tblServiceType TST ON TST.ServiceTypeID = S.SERVICETYPEID --Deval(02) commented
		INNER JOIN PACKAGE_ELEMENT PE ON NFD.PACKAGEID = PE.PACKAGEID
		INNER JOIN @tblPackageElementIDs TPE ON TPE.PackageElementID = PE.PACKAGEELEMENTID
		INNER JOIN PACKAGE_OPTION PO ON (PO.PACKAGEELEMENTID = PE.PACKAGEELEMENTID OR PO.PACKAGEELEMENTID IS NULL) AND PO.PACKAGESERVICEID = PS.PACKAGESERVICEID
		--INNER JOIN PACKAGE_ITINERARY_DAY PID ON	NFD.PACKAGEID = PID.PACKAGEID --Deval(02), commented
		INNER JOIN @TBLPACKAGEDAYSEQ PID ON	NFD.PACKAGEID = PID.PACKAGEID  --Deval(02)
		WHERE ISNULL(PS.PACKAGESERVICECLOSED,0) = 0 AND
			  ISNULL(PS.PACKAGESERVICEISDELETED,0) = 0
		--GROUP BY PO.SERVICEOPTIONINSERVICEID, --Deval(02), commented groupby
		--		 PE.PACKAGEELEMENTID,
		--		 PS.PACKAGESERVICEID,
		--		 NFD.TMPDEPARTUREDATE,
		--		 PO.PackageOptionID,
		--		 PO.PACKAGEOPTIONFROMDAYSEQ,
		--		 PO.PACKAGEOPTIONTODAYSEQ,
		--		 NFD.Packageid 
		
		
		INSERT INTO @tblPackageOptions
				(
					ServiceOptionID,
					PackageElementID,
					PackageDepartureID,
					PackageServiceID,
					DepartureStartDate,
					DepartureEndDate,
					PackageOptionID,
					DayOverLap,
					PackageOptionStartDate,
					PackageOptionEndDate,
					PackageID,
					ServiceID --Deval(02)   
                   ,PACKAGEOPTIONNUMBEROFNIGHTS --MEENA(07)
				)
		SELECT PO.SERVICEOPTIONINSERVICEID, 
			   PO.PACKAGEELEMENTID, 
			   0, 
			   PS.PACKAGESERVICEID,
			   NFD.TMPDEPARTUREDATE, 
			   NFD.TMPDEPARTUREDATE + PID.LASTPACKAGEITENARYDAYSEQ, --Deval(02)+ MAX(PID.PACKAGEITINERARYDAYSEQ),
			   PO.PackageOptionID, 
			   ISNULL((SELECT CHARGINGPOLICYDAYOVERLAP  FROM CHARGING_POLICY
						 WHERE CHARGINGPOLICYID  = (SELECT TOP 1 CHARGINGPOLICYID  FROM ASSIGNED_CHARGING_POLICY 
													 WHERE SERVICEoptioninserviceid = po.SERVICEOPTIONINSERVICEID)),0) AS CHARGINGPOLICYDAYOVERLAP,
			   DATEADD(DD,PO.PACKAGEOPTIONFROMDAYSEQ - 1,NFD.TMPDEPARTUREDATE),
			   DATEADD(DD,PO.PACKAGEOPTIONTODAYSEQ - 1,NFD.TMPDEPARTUREDATE),
			   NFD.Packageid,
			   PS.SERVICEID --Deval(02)  
              ,PO.PACKAGEOPTIONNUMBEROFNIGHTS --MEENA(07)
		FROM PACKAGE_SERVICE PS
		INNER JOIN @tblNOFIXEDDEPARTURE NFD ON NFD.Packageid = PS.PACKAGEID 
		--INNER JOIN SERVICE S ON PS.SERVICEID = S.SERVICEID --Deval(02), Commented
		--INNER JOIN @tblServiceType TST ON TST.ServiceTypeID = S.SERVICETYPEID --Deval(02), Commented
		INNER JOIN PACKAGE_OPTION PO ON (PO.PACKAGEELEMENTID IS NULL AND PO.PACKAGEOPTIONOPTIONAL =1)
		AND PO.PACKAGESERVICEID = PS.PACKAGESERVICEID 
		--INNER JOIN PACKAGE_ITINERARY_DAY PID ON NFD.Packageid = PID.PACKAGEID --Deval(02), commented
		INNER JOIN @TBLPACKAGEDAYSEQ PID ON	NFD.PACKAGEID = PID.PACKAGEID --Deval(02), commented
		WHERE ISNULL(PS.PACKAGESERVICECLOSED,0) = 0 AND
			  ISNULL(PS.PACKAGESERVICEISDELETED,0) = 0
		--GROUP BY PO.SERVICEOPTIONINSERVICEID, --Deval(02), commented groupby
		--		 PO.PACKAGEELEMENTID, 
		--		 PS.PACKAGESERVICEID,
		--		 NFD.TMPDEPARTUREDATE,
		--		 PO.PackageOptionID,
		--		 PO.PACKAGEOPTIONFROMDAYSEQ,
		--		 PO.PACKAGEOPTIONTODAYSEQ,
		--		 NFD.Packageid 
		
        DELETE PO
		FROM  @tblPackageOptions PO
		INNER JOIN SERVICE S on PO.ServiceID = S.SERVICEID
		WHERE s.SERVICETYPEID not in (select SERVICETYPEID from @tblServiceType)
		


		/*
		INSERT INTO @tblPackageOptions
				(
					ServiceOptionID,
					PackageElementID,
					PackageDepartureID,
					PackageServiceID,
					DepartureStartDate,
					DepartureEndDate,
					PackageOptionID,
					DayOverLap,
					PackageOptionStartDate,
					PackageOptionEndDate,
					PackageID 
				)
		SELECT PO.SERVICEOPTIONINSERVICEID, 
			   PO.PACKAGEELEMENTID, 
			   0, 
			   PS.PACKAGESERVICEID_1,
			   NFD.TMPDEPARTUREDATE, 
			   NFD.TMPDEPARTUREDATE + MAX(PID.PACKAGEITINERARYDAYSEQ),
			   PO.PackageOptionID,
			   ISNULL((SELECT CHARGINGPOLICYDAYOVERLAP FROM CHARGING_POLICY  WHERE CHARGINGPOLICYID  = (SELECT TOP 1 CHARGINGPOLICYID 
												FROM ASSIGNED_CHARGING_POLICY WHERE SERVICEoptioninserviceid = po.SERVICEOPTIONINSERVICEID)),0) AS CHARGINGPOLICYDAYOVERLAP,
			   DATEADD(DD,PO.PACKAGEOPTIONFROMDAYSEQ - 1,NFD.TMPDEPARTUREDATE),
			   DATEADD(DD,PO.PACKAGEOPTIONTODAYSEQ - 1,NFD.TMPDEPARTUREDATE),
			   NFD.Packageid 
		FROM PACKAGE_SERVICE PS
		INNER JOIN @tblNOFIXEDDEPARTURE NFD ON NFD.Packageid = PS.PACKAGEID 
		INNER JOIN SERVICE S ON PS.SERVICEID = S.SERVICEID
		INNER JOIN @tblServiceType TST ON TST.ServiceTypeID = S.SERVICETYPEID
		INNER JOIN PACKAGE_OPTION PO ON (PO.PACKAGEELEMENTID IS NULL AND PO.PACKAGEOPTIONOPTIONAL =1)AND PO.PACKAGESERVICEID = PS.PACKAGESERVICEID 
		INNER JOIN PACKAGE_ITINERARY_DAY PID ON PID.PACKAGEID = NFD.Packageid
		WHERE ISNULL(PS.PACKAGESERVICECLOSED,0) = 0 AND
			  ISNULL(PS.PACKAGESERVICEISDELETED,0) = 0
		GROUP BY PO.SERVICEOPTIONINSERVICEID, 
				 PO.PACKAGEELEMENTID, 
				 PS.PACKAGESERVICEID_1,
				 NFD.TMPDEPARTUREDATE,
				 PO.PACKAGEOPTIONID,
				 PO.PACKAGEOPTIONFROMDAYSEQ,
				 PO.PACKAGEOPTIONTODAYSEQ,
				 NFD.Packageid 
		*/
		
		
		-- Get INTERNET allocations --Deval(02), Also check for General allocations
--BOC MEENA(07)
-- Fetched allocation for each day

		INSERT INTO @tblPackageServiceAllocationsInfo (
		PackageDepartureID,
		PackageElementID,
		PackageServiceID,
		Availibility
		,AllocationId 
		,ReleasePeriod 
		,InDate 
		,ALLOCATIONTYPEID
		,OutDate 
		,SERVICEOPTIONINSERVICEID 
		,Serviceid 
		,ALLOCATIONUSAGEDATE 
		,PackageDepartureDate 
		,PackageID
		)
		SELECT  TPO.PackageDepartureID,
				TPO.PackageElementID,
				TPO.PackageServiceID,
				AU.ALLOCATIONUSAGEAVAILABLEQUANTITY,
				AU.ALLOCATIONID,
				AU.ALLOCATIONUSAGERELEASEPERIOD,
				TPO.PackageOptionStartDate,
				A.ALLOCATIONTYPEID,
				TPO.PackageOptionEndDate,
				TPO.ServiceOptionID,
				TPO.Serviceid,
				AU.ALLOCATIONUSAGEDATE,
				TPO.DepartureStartDate ,
				TPO.PackageID
				 
		FROM ALLOCATION_USAGE AU
		INNER JOIN ALLOCATION A ON A.ALLOCATIONID = AU.ALLOCATIONID
		INNER JOIN ALLOCATION_MEMBERSHIP AM ON AM.ALLOCATIONID = A.ALLOCATIONID
		--INNER JOIN ALLOCATION_TYPE AT ON AT.ALLOCATIONTYPEID = A.ALLOCATIONTYPEID AND AT.ALLOCATIONTYPEID = 4 --Deval(02), commented
		INNER JOIN ALLOCATION_TYPE AT ON AT.ALLOCATIONTYPEID = A.ALLOCATIONTYPEID 
		INNER JOIN @tblPackageOptions TPO ON TPO.ServiceOptionID = AM.SERVICEOPTIONINSERVICEID 
		WHERE  (AU.ALLOCATIONUSAGEDATE BETWEEN TPO.PackageOptionStartDate  AND TPO.PackageOptionEndDate - TPO.DayOverLap)

		--EOC MEENA(07)
		

--BOC MEENA(07)--CODE TO CHECK STOP SALES
        insert into	#tblServiceStopSales
				SELECT	distinct SSS.SERVICEOPTIONINSERVICEID, 
					SSS.ALLOCATIONID,   
 					DateFrom,  
					DateTo
				FROM @tblPackageServiceAllocationsInfo TR
				 INNER JOIN SERVICE_STOP_SALE SSS ON SSS.SERVICEOPTIONINSERVICEID=TR.SERVICEOPTIONINSERVICEID 

				UPDATE R
				SET R.Availibility=0
				FROM @tblPackageServiceAllocationsInfo R 
				INNER JOIN #tblServiceStopSales SSS ON R.SERVICEOPTIONINSERVICEID =SSS.SERVICEOPTIONINSERVICEID AND R.AllocationId =SSS.ALLOCATIONID 
				WHERE (R.InDate BETWEEN SSS.STOPSALESSTARTDATE AND SSS.STOPSALESENDDATE) 
				--Yogesh(09) Commented and rewritten below as per discussion by FL with Deval/Charlotte "The 'To Date' in the package service is the check-out date and not an overnight date, therefore the restriction rule / stop sale should not be applied"
				--OR (R.OutDate BETWEEN SSS.STOPSALESSTARTDATE AND SSS.STOPSALESENDDATE) 
				--OR (SSS.STOPSALESSTARTDATE BETWEEN R.InDate AND R.OutDate) 
				--OR (SSS.STOPSALESENDDATE BETWEEN R.InDate AND R.OutDate)
				OR (CASE WHEN DATEADD(dd,-1,R.OutDate) <= R.InDate THEN R.InDate ELSE DATEADD(dd,-1,R.OutDate) END  BETWEEN SSS.STOPSALESSTARTDATE AND SSS.STOPSALESENDDATE)
				OR (SSS.STOPSALESSTARTDATE BETWEEN R.InDate AND CASE WHEN DATEADD(dd,-1,R.OutDate) <= R.InDate THEN R.InDate ELSE DATEADD(dd,-1,R.OutDate) END) 
				OR (SSS.STOPSALESENDDATE BETWEEN R.InDate AND CASE WHEN DATEADD(dd,-1,R.OutDate) <= R.InDate THEN R.InDate ELSE DATEADD(dd,-1,R.OutDate) END)

--EOC MEENA(07)
		INSERT INTO @tblPackageServiceAllocations
				(
					PackageDepartureID,
					PackageElementID,
					PackageServiceID,
                    ServiceOptionID,--MEENA(07) added
					Availibility,
					AllocationId,
					ReleasePeriod,
					InDate,
					PackageID,
					PackageDepartureDate 
					,OutDate --Snela(01)  
                    ,PACKAGEOPTIONID--MEENA(07) added
				)
		SELECT  TPO.PackageDepartureID,
				TPO.PackageElementID,
				TPO.PackageServiceID,
				TPO .ServiceOptionID ,--MEENA(07) ADDED
				--MIN(AU.ALLOCATIONUSAGEAVAILABLEQUANTITY),--MEENA(07) COMMENTED AND REWRITTEN BELOW

                MIN(PSAI.Availibility),
				--AU.ALLOCATIONID,--MEENA(07) COMMENTED
				'',
				--MAX(AU.ALLOCATIONUSAGERELEASEPERIOD),--MEENA(07) COMMENTED 

                MAX(PSAI.ReleasePeriod),
                TPO.PackageOptionStartDate,
				TPO.PackageID,
				TPO.DepartureStartDate  
			    ,TPO.PackageOptionEndDate --Snela(01)

               ,TPO.Packageoptionid --MEENA(07) ADDED
		--BOC MEENA(07)
	FROM @tblPackageOptions TPO inner join @tblPackageServiceAllocationsInfo PSAI  ON  PSAI.SERVICEOPTIONINSERVICEID=TPO.ServiceOptionID
				where   PSAI.ALLOCATIONTYPEID = CASE WHEN @I_SYSTEMSETTINGSFIELDVALUE = 1 THEN 1 ELSE 4 END --Deval(02)
				AND (PSAI.ALLOCATIONUSAGEDATE BETWEEN TPO.PackageOptionStartDate  AND TPO.PackageOptionEndDate - TPO.DayOverLap)
	             group by  ServiceOptionID,
				           TPO.PackageDepartureID,
                           TPO.PackageElementID,
	                       TPO.PackageServiceID,
                           PACKAGEOPTIONID,
						   TPO.PackageOptionStartDate,
						   TPO.PackageOptionEndDate,
   						   TPO.DepartureStartDate,PACKAGEOPTIONNUMBEROFNIGHTS,
						   TPO.PackageID
	              Having Count(Distinct PSAI.ALLOCATIONUSAGEDATE)>=PACKAGEOPTIONNUMBEROFNIGHTS

--MEENA(07) commented below code as the required data is already fetched above
     /*
		INNER JOIN ALLOCATION A ON A.ALLOCATIONID = AU.ALLOCATIONID
		INNER JOIN ALLOCATION_MEMBERSHIP AM ON AM.ALLOCATIONID = A.ALLOCATIONID
		--INNER JOIN ALLOCATION_TYPE AT ON AT.ALLOCATIONTYPEID = A.ALLOCATIONTYPEID AND AT.ALLOCATIONTYPEID = 4 --Deval(02), commented
		INNER JOIN ALLOCATION_TYPE AT ON AT.ALLOCATIONTYPEID = A.ALLOCATIONTYPEID 
		           AND AT.ALLOCATIONTYPEID = CASE WHEN @I_SYSTEMSETTINGSFIELDVALUE = 1 THEN 1 ELSE 4 END --Deval(02)
		INNER JOIN @tblPackageOptions TPO ON TPO.ServiceOptionID = AM.SERVICEOPTIONINSERVICEID 
		WHERE  (AU.ALLOCATIONUSAGEDATE BETWEEN TPO.PackageOptionStartDate  AND TPO.PackageOptionEndDate - TPO.DayOverLap)
		GROUP BY TPO.PackageDepartureID,
				 TPO.PackageElementID,
				 TPO.PackageServiceID,
				 AU.ALLOCATIONID,
				 TPO.PackageOptionStartDate,
				 TPO.PackageID,
				 TPO.DepartureStartDate
				 ,TPO.PackageOptionEndDate --Snela(01)

   */

--EOC MEENA(07)
        --Deval(02), commented
		---- Get GENERAL allocations
		--INSERT INTO @tblPackageServiceAllocations
		--		(
		--			PackageDepartureID,
		--			PackageElementID,
		--			PackageServiceID,
		--			Availibility,
		--			AllocationId,
		--			ReleasePeriod,
		--			InDate,
		--			PackageID,
		--			PackageDepartureDate  
		--			,OutDate --Snela(01) 
		--		)
		--SELECT  TPO.PackageDepartureID,
		--		TPO.PackageElementID,
		--		TPO.PackageServiceID,
		--		MIN(AU.ALLOCATIONUSAGEAVAILABLEQUANTITY),
		--		AU.ALLOCATIONID,
		--		MAX(AU.ALLOCATIONUSAGERELEASEPERIOD),
		--		TPO.PackageOptionStartDate,
		--		TPO.PackageID,
		--		TPO.DepartureStartDate  
		--		,TPO.PackageOptionEndDate --Snela(01)
		--FROM ALLOCATION_USAGE AU
		--INNER JOIN ALLOCATION A ON A.ALLOCATIONID = AU.ALLOCATIONID
		--INNER JOIN ALLOCATION_MEMBERSHIP AM ON AM.ALLOCATIONID = A.ALLOCATIONID
		--INNER JOIN ALLOCATION_TYPE AT ON AT.ALLOCATIONTYPEID = A.ALLOCATIONTYPEID AND @I_SYSTEMSETTINGSFIELDVALUE = 1 AND AT.ALLOCATIONTYPEID = 1 
		--INNER JOIN @tblPackageOptions TPO ON TPO.ServiceOptionID = AM.SERVICEOPTIONINSERVICEID 
		--WHERE  (AU.ALLOCATIONUSAGEDATE BETWEEN TPO.PackageOptionStartDate  AND TPO.PackageOptionEndDate - TPO.DayOverLap)
		--GROUP BY TPO.PackageDepartureID,
		--		 TPO.PackageElementID,
		--		 TPO.PackageServiceID,
		--		 AU.ALLOCATIONID,
		--		 TPO.PackageOptionStartDate,
		--		 TPO.PackageID,
		--		 TPO.DepartureStartDate
		--		 ,TPO.PackageOptionEndDate --Snela(01)
		

	
		UPDATE T
			SET T.Availibility = 0
		FROM @tblPackageServiceAllocations T
				WHERE T.ReleasePeriod > (DATEDIFF(DD,@dt_BookingDate, T.InDate))

		
		IF OBJECT_ID('tempdb..#tbl_PackageServiceOptionAvailability') IS NOT NULL--This Table Is Created in USP_GET_PACKAGE_LIST_INFO_B2CB2B sp for CalculateBookingPrice Method
		BEGIN
		
		--BOC Snela(01)
		INSERT INTO #tblResult
		  SELECT distinct PSA.PackageDepartureID,
					isnull(PSA.PackageElementID,0) AS PackageElementID,
					PSA.PackageServiceID,
					PSA.Availibility,
					PSA.ALLOCATIONid,
					PSA.ServiceOptionID,-- MEENA(07) changed AM.SERVICEOPTIONINSERVICEID to PSA.ServiceOptionID
					PS.SERVICEID 
                   ,PSA.PackageID
					,PSA.PackageDepartureDate
					,1,PSA.InDate ,PSA.OutDate 
                    ,PSA.PACKAGEOPTIONID --MEENA(07) added
			FROM @tblPackageServiceAllocations PSA
			INNER JOIN PACKAGE_SERVICE PS ON PS.PACKAGESERVICEID =PSA.PackageServiceID
		--	INNER JOIN ALLOCATION_MEMBERSHIP AM ON PSA.AllocationId =AM.ALLOCATIONID  --MEENA(07) COMMENTED AS ITS NOT REQUIRED
			
--BOC MEENA(07) COMMENTED CODE AND REWRITTEN ABOVE
          /*
			insert into	#tblServiceStopSales
				SELECT	distinct SSS.SERVICEOPTIONINSERVICEID, --Shakeel(03)
					SSS.ALLOCATIONID,   
 					DateFrom,  
					DateTo
				FROM #tblResult TR
				 --INNER JOIN SERVICE_OPTION_IN_SERVICE SOIS ON TR.ServiceId=SOIS.SERVICEID --Arun(06)
				 INNER JOIN SERVICE_STOP_SALE SSS ON SSS.SERVICEOPTIONINSERVICEID=TR.SERVICEOPTIONINSERVICEID --Arun(06)
				
				UPDATE R
				SET R.AVAILABILITY=0
				FROM #tblResult R 
				INNER JOIN #tblServiceStopSales SSS ON R.SERVICEOPTIONINSERVICEID =SSS.SERVICEOPTIONINSERVICEID AND R.AllocationId =SSS.ALLOCATIONID 
				WHERE (R.InDate BETWEEN SSS.STOPSALESSTARTDATE AND SSS.STOPSALESENDDATE) 
				OR (R.OutDate BETWEEN SSS.STOPSALESSTARTDATE AND SSS.STOPSALESENDDATE) 
				OR (SSS.STOPSALESSTARTDATE BETWEEN R.InDate AND R.OutDate) 
				OR (SSS.STOPSALESENDDATE BETWEEN R.InDate AND R.OutDate)
	  --EOC Snela(01)
		

 */
	  --EOC MEENA(07)
			INSERT INTO  #tbl_PackageServiceOptionAvailability
					(
						PACKAGEDEPARTUREID,
						PackageDepartureDate,
						PACKAGEID,
						PACKAGEELEMENTID,
						PackageServiceID,
						AVAILABILITY,
                        ALLOCATIONid,
                        OPTIONID,
                        ServiceID,
                        ISNFD
                       ,PACKAGEOPTIONID--MEENA(07) added
                    )
			SELECT 
				R.PackageDepartureID,
				R.PackageDepartureDate,
				R.PackageID, 
				R.PackageElementID,
				R.PackageServiceID,
				R.AVAILABILITY, 
				R.AllocationId,
				R.SERVICEOPTIONINSERVICEID, 
				R.SERVICEID,
				R.ISNFD 
                ,R.PACKAGEOPTIONID --MEENA(07) ADDED
			FROM #tblResult R--@tblPackageServiceAllocations PSA--Snela(01)
			/*Snela(01) Commented 
			INNER JOIN PACKAGE_SERVICE PS ON PS.PACKAGESERVICEID =PSA.PackageServiceID
			INNER JOIN ALLOCATION_MEMBERSHIP AM ON PSA.AllocationId =AM.ALLOCATIONID */
		END
		ELSE
		BEGIN
		  IF EXISTS (SELECT TOP 1 1 FROM @tblPackageServiceAllocations)--Deval(02)
		   BEGIN
			SELECT 
				PSA.PackageDepartureID,
				PSA.PackageDepartureDate,
				PSA.PackageID, 
				PackageElementID,
				PSA.PackageServiceID,
				(CASE WHEN MIN(Availibility) = 0 
					THEN
						'No' 
					ELSE 
						'Yes' 
				END) AS Availibility
			FROM @tblPackageServiceAllocations PSA
			GROUP BY PackageDepartureID, PSA.PackageDepartureDate, PSA.PackageID,PackageElementID, PackageServiceID
		   END
		    ELSE --Deval(2), to return No, if allocations are empty
		     BEGIN
		     	SELECT 
				PackageDepartureID,
				DepartureStartDate,
				PackageID, 
				PackageElementID,
				PackageServiceID,
				'No' AS Availibility
			  FROM @tblPackageOptions
		     END
		END


END
Go

SET QUOTED_IDENTIFIER  OFF    SET ANSI_NULLS  ON 
GO


------------

SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

IF EXISTS (SELECT TOP 1 1 FROM DBO.SYSOBJECTS WHERE ID = OBJECT_ID(N'[dbo].[Usp_Get_Search_Additional_Child_Amount]') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
	DROP PROCEDURE [dbo].[Usp_Get_Search_Additional_Child_Amount]
GO
/********************************************************************************************************************
* Created by	: Snela Naik
* On			: 28 Jan 2014
* Description	: This SP is used in CalculateBookingPrices API method to determing the Additional Child and fetch its pricing
				  
* Modification History :      
*		Who			     When											What   
* -----------------  -----------     ----------------------------------------------------------------------------  
* 01 Pradnya		 04 Feb 2014	Fixed Issue QAAPI-147 Incorrect FinalBookingPrice  is returned in the response of method CalculateBookingPrice 
* 02 Rupesh PK.		 27 Mar 2014	Fixed Issue#50245 & 51299 [Client: Abreu TOP]
* 03 Rupesh PK.		 01 Apr 2014	Fixed Issue#51299 [Client: Abreu TOP]
* 04 Rupesh PK.          29 Apr 2014	Changes for ATOP64-Apply Additional Child Amounts for Packages - Phase II [Client: Abreu TOP]
* 05 Rupesh PK.		 17 May 2014	Changes for ATOP-53 [Client: Abreu TOP]
* 07 Snela      	 04 Jun 2014	Fixed Issue#53153 API - CalculateBookingPrice - Duplicated information and wrong prices (LIVE/DEV)
* 06 Rupesh PK.		 23 May 2014	Changes for ATOP-49 [Client: Abreu TOP]
* 08 Ankita S		 08 July 2014	CR# ATOP-173 : Extn to ATOP62 Internet Available Dates
* 09 Myrtle	         24 Aug 2015	Added changes for STRAT-72 XML Memory Leaks -Added SP_XML_REMOVEDOCUMENT for SP_XML_PREPAREDOCUMENT 
* 10 Shani			 13 Apr 2016	Fixed XML Memory Leaks -Added SP_XML_REMOVEDOCUMENT for SP_XML_PREPAREDOCUMENT [Client: Abreu TOP]
********************************************************************************************************************/ 

CREATE PROCEDURE dbo.Usp_Get_Search_Additional_Child_Amount
	@rtxt_PackageListXML TEXT = NULL,
	@rvc_BookingTypeID varchar(10),
	@rvc_PriceTypeID varchar(10),
	@ri_CurrencyID int,
	@rtxt_PassengerInfoXML TEXT = NULL, -- Rupesh PK.(05)
	@rb_SearchbyBookDate bit=0  --Ankita S(08)
AS
BEGIN
	
	DECLARE @tblMainElements TABLE 
				(
					MainElementIdentity int identity(1,1),
					PACKAGEID INT,
					DEPARTUREID INT,
					DEPARTUREDATE DATETIME,
					ELEMENTID INT,
					QUANTITY INT,
					NOOFADULTS INT,
					NOOFCHILDREN INT
				)

		DECLARE @tblElementChildDetails TABLE 
				(
					ChildIdentity int identity(1,1),
					MainElementIdentity int,
					PACKAGEID INT,
					PACKAGEDEPARTUREID INT,
					DEPARTUREDATE DATETIME,
					ELEMENTID INT,
					EAge INT,
					ECnt INT
				)
		
			
		DECLARE @tblOptionalElements TABLE 
				( 
					PACKAGEDEPARTUREIDentity int identity(1,1),
					PACKAGEID INT, 
					PACKAGEDEPARTUREID INT,
					DEPARTUREDATE DATETIME, 
					PackageOptionID INT,
					OptionDATE DATETIME,
					OptionQUANTITY INT,
					OptionNOOFADULTS INT,
					OptionNOOFCHILDREN INT
				)

		DECLARE @tblOptionalChildDetails TABLE 
				(
					OptionalChildIdentity int identity(1,1),
					PACKAGEDEPARTUREIDentity int,
					PACKAGEDEPARTUREID INT,
					PackageOptionID INT,
					OAge INT,
					OCnt INT,
					PACKAGEID INT,
					DEPARTUREDATE DATETIME
				)	
				
		DECLARE @tblElementOccupanyId TABLE
		(			
					ID int identity(1,1),
					OccupancyTypeID INT,
					ElementID INT
				)
		
			DECLARE @tblOptionalOccupanyId TABLE
		(			
					ID int identity(1,1),
					OccupancyTypeID INT,
					OptionalOptionID INT
				)
		--Main Element
		DECLARE @tblDataTable TABLE
			(
				ID INT IDENTITY(1,1),
				ElementID INT,
				OccupancyID INT,
				AdultCapacity INT,
				ChildCapacity INT,
				NoOfAdults INT,
				NoOfChild INT,
				PACKAGEID INT, 
				DEPARTUREDATE DATETIME,
				PACKAGEDEPARTUREID INT
			)
			
		--Optional Element	
		DECLARE @tblOptionalDataTable TABLE
			(
				ID INT IDENTITY(1,1),
				PackageOptionID INT,
				OccupancyID INT,
				AdultCapacity INT,
				ChildCapacity INT,
				NoOfAdults INT,
				NoOfChild INT,
				PACKAGEID INT, 
				DEPARTUREDATE DATETIME,
				OptionDATE DATETIME ,
				PACKAGEDEPARTUREID INT
			)
		
		--Main Element
		DECLARE @tblSplitElementChildDetails TABLE 
					(
						ID int identity(1,1),
						PACKAGEID INT, 
						OccupancyID INT,
						ChildCapacity INT,
						NoOfChild INT,
						PACKAGEDEPARTUREID INT,
						DEPARTUREDATE DATETIME, 
						ELEMENTID INT,
						ChildAge INT
					)
		--Optional Element	
		DECLARE @tblSplitOptionalChildDetails TABLE 
					(
						ID int identity(1,1),
						PACKAGEID INT, 
						OccupancyID INT,
						ChildCapacity INT,
						NoOfChild INT,
						PACKAGEDEPARTUREID INT,
						DEPARTUREDATE DATETIME, 
						PackageOptionId INT,
						ChildAge INT,
						OptionDATE DATETIME 
					)			
		
		--Main Element	
		DECLARE @tblFinalChildDetails TABLE 
					(
						ID int identity(1,1),
						PACKAGEID INT, 
						OccupancyID INT,
						ChildCapacity INT,
						NoOfChild INT,
						PACKAGEDEPARTUREID INT,
						DEPARTUREDATE DATETIME, 
						ELEMENTID INT,
						ChildAge INT,
						LogicalRoomID INT
					)
		--Optional Element	
		DECLARE @tblFinalOptionalChildDetails TABLE 
					(
						ID int identity(1,1),
						PACKAGEID INT, 
						OccupancyID INT,
						ChildCapacity INT,
						NoOfChild INT,
						PACKAGEDEPARTUREID INT,
						DEPARTUREDATE DATETIME, 
						PackageOptionID INT,
						ChildAge INT,
						LogicalRoomID INT,
						OptionDATE DATETIME 
					)
					
		

	--Main Element
	DECLARE @tbl_FirstChildInfo TABLE
			(
				ID INT IDENTITY(1,1),
				Age INT,
				RoomNO INT,
				PACKAGEID INT , 
				PACKAGEDEPARTUREID INT ,
				ELEMENTID INT ,
				PaxID INT,
				DEPARTUREDATE DATETIME
			)
	--Main Element		
	DECLARE @tbl_ChildInfo TABLE
			(
				ID INT IDENTITY(1,1),
				PaxID INT,
				RoomNO INT,
				Age INT,
				IsAdditionalChild BIT
				,AdditionalChildAmount decimal,
				PACKAGEID INT , 
				PACKAGEDEPARTUREID INT ,
				ELEMENTID INT ,
				PackagePriceID int,
				DEPARTUREDATE DATETIME,
				PRICEAMT DECIMAL(28,14), 
				ROE DECIMAL(28,14),
				ISCHILDSHARING BIT,
				IsUpdated BIT
			)
	
	--Optional Element
	DECLARE @tbl_FirstOptionalChildInfo TABLE
			(
				ID INT IDENTITY(1,1),
				Age INT,
				RoomNO INT,
				PACKAGEID INT , 
				PACKAGEDEPARTUREID INT ,
				PackageOptionID INT ,
				PaxID INT,
				DEPARTUREDATE DATETIME,
				OptionDATE DATETIME 
			)
	--Optional Element		
	--BOC Rupesh PK.(04)
	DECLARE @tbl_tmpOptionalChildInfo TABLE
			(
				ID INT IDENTITY(1,1),
				PaxID INT,
				RoomNO INT,
				Age INT,
				IsAdditionalChild BIT
				,AdditionalChildAmount decimal,
				PACKAGEID INT , 
				PACKAGEDEPARTUREID INT ,
				PackageOptionId INT ,
				PackagePriceID int,
				DEPARTUREDATE DATETIME,
				PRICEAMT DECIMAL(28,14), 
				ROE DECIMAL(28,14),
				ISCHILDSHARING BIT,
				IsUpdated BIT
				,PackageElementID INT -- Rupesh PK.(02)
				,AdditionalUpdated BIT DEFAULT 0 -- Rupesh PK.(02)
				,SEQ INT 
			)	
	--EOC Rupesh PK.(04)

	DECLARE @tbl_OptionalChildInfo TABLE
			(
				ID INT IDENTITY(1,1),
				PaxID INT,
				RoomNO INT,
				Age INT,
				IsAdditionalChild BIT
				,AdditionalChildAmount decimal,
				PACKAGEID INT , 
				PACKAGEDEPARTUREID INT ,
				PackageOptionId INT ,
				PackagePriceID int,
				DEPARTUREDATE DATETIME,
				PRICEAMT DECIMAL(28,14), 
				ROE DECIMAL(28,14),
				ISCHILDSHARING BIT,
				IsUpdated BIT
				,PackageElementID INT -- Rupesh PK.(02)
				,AdditionalUpdated BIT DEFAULT 0 -- Rupesh PK.(02)
				,SEQ INT--Rupesh PK.(04)
			)	

	declare @TMPBTPT table 
	(
		BOOKINGTYPEID int,
		PRICETYPEID int
	)			
		declare @tblnum table (id int identity(1,1), value int)
	
	-- BOC Rupesh PK.(02)
	DECLARE @tbl_ElementInfo TABLE
			(
				ID INT IDENTITY(1,1),
				Age INT,
				ElementID INT,
				DepartureDate DATETIME,
				IsAdditionalChild INT
				,SEQ INT --Rupesh PK.(04)
			)
	-- EOC Rupesh PK.(02)	
	
	-- BOC Rupesh PK.(05)
		DECLARE @tblTmpElementChild TABLE 
				(
					ChildIdentity int identity(1,1),
					MainElementIdentity int,
					PackageID INT, 
					PackageDepartureID INT,
					DepartureDate DATETIME,
					ElementID INT,
					Age INT,
					Cnt INT,
					ChildID INT,
					ChildIDs VARCHAR(50),
					ProcessDuplicate BIT DEFAULT  0
				)
		
		DECLARE @tblTmpOptionalChild TABLE
				(
					OptionalChildIdentity int IDENTITY(1,1),
					PackageDepartureIdentity int,
					PackageDepartureID INT,
					PackageOptionID INT,
					PackageID INT,
					Age INT,
					Cnt INT,
					DepartureDate DATETIME,
					ChildID INT,
					ChildIDs VARCHAR(50),
					SeqNo INT,
					ProcessDuplicate BIT DEFAULT  0
				)
		
		DECLARE @tbl_Optional TABLE
				(
					OptionalChildIdentity int IDENTITY(1,1),
					PackageDepartureIdentity int,
					PackageDepartureID INT,
					PackageOptionID INT,
					PackageID INT,
					Age INT,
					Cnt INT,
					DepartureDate DATETIME,
					ChildID INT,
					ChildIDs VARCHAR(50),
					ProcessDuplicate BIT DEFAULT  0
				)
		
		DECLARE @tbl_Element TABLE 
				(
					ChildIdentity int identity(1,1),
					MainElementIdentity int,
					PackageID INT, 
					PackageDepartureID INT,
					DepartureDate DATETIME,
					ElementID INT,
					Age INT,
					Cnt INT,
					ChildID INT,
					ChildIDs VARCHAR(50),
					ProcessDuplicate BIT DEFAULT  0
				)

			DECLARE @tblChildInfo TABLE
					(
						ID INT IDENTITY(1,1),
						ChildID INT,
						DOB DATETIME,
						Age INT,
						RoomID INT,
						Gender INT
					)
		-- EOC Rupesh PK.(05)
		--BOC Ankita S(08)
		DECLARE @rb_SearchbyBookDateAndOrgFlag bit 
		 DECLARE @rd_BOOKINGDATE datetime 
	    	    
		 select @rb_SearchbyBookDateAndOrgFlag=SYSTEMSETTINGSFIELDVALUE from SYSTEM_SETTINGS_FIELD  where SYSTEMSETTINGSFIELDNAME like 'SetBookingDateDefault' 
	     
		 if @rb_SearchbyBookDateAndOrgFlag=1 and @rb_SearchbyBookDate=1
			select @rb_SearchbyBookDateAndOrgFlag=1
		 else
			select @rb_SearchbyBookDateAndOrgFlag=0
			
		 SET @rd_BOOKINGDATE =   CONVERT(VARCHAR(8), Getdate(), 112)
		--EOC Ankita S(08)

		DECLARE @max int, @ri_BOOKEDOPTIONID int,@ri_Age int,@rb_ISCHILDSHARING bit, @i_PaxID INT, @i_RoomNO INT, @i_ROEBASEDONBOOKINGDATE2 AS INT,
			    @minid int ,@maxID int,@PackageElementId int ,@ChildCapacity int,@RoomId int,@DepartureDate DATETIME,@PreviousDepartureDate DATETIME,
			    @PreviousPackageElementId int, @idoc INT,@rvc_BookingID varchar(8000), @rvc_Age varchar(8000) = NULL, @rvc_BOOKEDOPTIONID varchar(8000),
			    @rvc_ISCHILDSHARING varchar(8000)=0, @DoNotConsiderAgeBandForAdditionalChild BIT,
			    @i_MaxCount INT, @i_CommaPos INT, @v_ChildIDs VARCHAR(50), @v_ChildIDsSubString VARCHAR(50), @i_ChildID INT, @iDocPax INT -- Rupesh PK.(05)
	
	
	-->> Fetch data from XML so that we can process this data according to our need.
	IF DATALENGTH(@rtxt_PackageListXML) > 0	
		BEGIN 
			exec sp_xml_preparedocument @idoc OUTPUT, @rtxt_PackageListXML   
			
			INSERT INTO @tblMainElements(PACKAGEID,DEPARTUREID,DEPARTUREDATE, ELEMENTID, QUANTITY,NOOFADULTS, NOOFCHILDREN)
				SELECT  PACKAGEID, DEPARTUREID ,DEPARTUREDATE, ElementID,SUM(Quantity) AS Quantity,SUM(NoOfAdults) AS NoOfAdults,SUM(NoOfChildren) AS NoOfChildren -- Snela(16)
					FROM  OPENXML (@idoc, '//Pkgs//Departure/MainOptionalElements//Main/Element')  
					WITH (
					    	PACKAGEID INT '../../../@PkgID',
						DEPARTUREID int '../../../@DepID',
						DEPARTUREDATE DATETIME '../../../@DepDate',
						ELEMENTID INT '@ID',
						QUANTITY INT '@Qty' ,
						NOOFADULTS INT '@Adults' ,
						NOOFCHILDREN INT '@Children') 
						GROUP BY PACKAGEID, DEPARTUREID ,DEPARTUREDATE, ElementID 

			-- Rupesh PK.(05) commented and rewritten below				
			/*INSERT INTO @tblElementChildDetails(PACKAGEID,PACKAGEDEPARTUREID,DEPARTUREDATE,ELEMENTID,EAge,ECnt)
				SELECT PACKAGEID, PACKAGEDEPARTUREID,DEPARTUREDATE, ELEMENTID,EAge, ECnt 
					FROM  OPENXML (@idoc, '//Pkgs//Departure/MainOptionalElements//Main/Element/Child')  
					WITH (
						PACKAGEID INT '../../../../@PkgID',
						PACKAGEDEPARTUREID int '../../../../@DepID',
						DEPARTUREDATE DATETIME '../../../../@DepDate',
						ELEMENTID INT '@ElementID',
						EAge INT '@Age' ,
						ECnt INT '@Cnt')
			*/
			-->> Fetch records from the XML
			INSERT INTO @tbl_Element (PackageID, PackageDepartureID, DepartureDate, ElementID, Age, Cnt, ChildIDs, ProcessDuplicate, ChildID)
				SELECT PACKAGEID, PACKAGEDEPARTUREID, DEPARTUREDATE, ELEMENTID, Age, Cnt, ChildIDs, 0, 0
					FROM  OPENXML (@idoc, '//Pkgs//Departure/MainOptionalElements//Main/Element/Child')  
					WITH (
						PACKAGEID INT '../../../../@PkgID',
						PACKAGEDEPARTUREID int '../../../../@DepID',
						DEPARTUREDATE DATETIME '../../../../@DepDate',
						ELEMENTID INT '@ElementID',
						Age INT '@Age' ,
						Cnt INT '@Cnt',
						ChildIDs VARCHAR(50) '@ChildIDs'
						)
			-- EOC Rupesh PK.(05)
			
			INSERT INTO @tblOptionalElements(PACKAGEID,PACKAGEDEPARTUREID,DEPARTUREDATE,PackageOptionID, OptionDATE, OptionQUANTITY, OptionNOOFADULTS, OptionNOOFCHILDREN) 
				SELECT PACKAGEID,PACKAGEDEPARTUREID,DEPARTUREDATE,PackageOptionID,Optiondate,SUM(Quantity) AS Quantity,SUM(NoOfAdults) AS NoOfAdults,SUM(NoOfChildren) AS NoOfChildren 
					FROM OPENXML (@idoc, '//Pkgs//Departure/MainOptionalElements//Optional/Option')    
					WITH (
						PACKAGEID INT '../../../@PkgID', 
						PACKAGEDEPARTUREID Int '../../../@DepID', 
						DEPARTUREDATE DATETIME '../../../@DepDate', 
						PackageOptionID INT '@ID', 
						OptionDATE DATETIME '@Date', 
						QUANTITY INT '@Qty' ,
						NOOFADULTS INT '@Adults' ,
						NOOFCHILDREN INT '@Children'
						)
						GROUP BY PACKAGEID,PACKAGEDEPARTUREID,DEPARTUREDATE,PackageOptionID,Optiondate 
			-- Rupesh PK.(05) commented and rewritten below				
			/*			
			INSERT INTO @tblOptionalChildDetails(PACKAGEDEPARTUREID,PackageOptionID,OAge,OCnt,PACKAGEID,DEPARTUREDATE )
				SELECT   PACKAGEDEPARTUREID,PackageOptionID,Age,Cnt,PACKAGEID,DEPARTUREDATE  
					FROM  OPENXML (@idoc, '//Pkgs//Departure/MainOptionalElements//Optional/Option/Child')  
					WITH (
						PACKAGEDEPARTUREID int '../../../../@DepID',
						PackageOptionID INT '@OptionID',
						Age INT '@Age' ,
						Cnt INT '@Cnt',
						PACKAGEID INT '../../../../@PkgID',
						DEPARTUREDATE DATETIME '../../../../@DepDate'
						)			
			*/
			INSERT INTO @tbl_Optional (PackageDepartureID, PackageOptionID, PackageID, Age, Cnt, DepartureDate, ChildIDs, ProcessDuplicate, ChildID)
				SELECT   PackageDepartureID, PackageOptionID, PackageID, Age, Cnt , DepartureDate, ChildIDs, 0, 0
					FROM  OPENXML (@idoc, '//Pkgs//Departure/MainOptionalElements//Optional/Option/Child')  
					WITH (
						PackageDepartureID int '../../../../@DepID',
						PackageOptionID INT '@OptionID',
						PackageID INT '../../../../@PkgID',
						Age INT '@Age' ,
						Cnt INT '@Cnt',
						DepartureDate DATETIME '../../../../@DepDate',
						ChildIDs VARCHAR(50) '@ChildIDs'
						)
						
			-- EOC Rupesh PK.(05)		
			exec sp_xml_removedocument @idoc  -- Shani(10)
						
	   END
		-- BOC Rupesh PK.(06)
		IF OBJECT_ID('tempdb..#TBL_NFD') IS NOT NULL
		AND (SELECT TOP 1 ISNULL(SYSTEMSETTINGSFIELDVALUE,0) FROM SYSTEM_SETTINGS_FIELD WHERE SYSTEMSETTINGSFIELDNAME = 'HidePackageSearchResultsWithEnforcedRestrictionRules') = 1
		BEGIN
			DELETE TMP FROM @tblMainElements TMP 
			LEFT OUTER JOIN #TBL_NFD tNFD ON TMP.DEPARTUREDATE = tNFD.DEPARTUREDATE AND TMP.PACKAGEID = tNFD.PACKAGEID
			WHERE tNFD.PACKAGEID IS NULL AND ISNULL(TMP.DEPARTUREID,0) = 0

			DELETE TMP FROM @tbl_Element TMP 
			LEFT OUTER JOIN #TBL_NFD tNFD ON TMP.DEPARTUREDATE = tNFD.DEPARTUREDATE AND TMP.PACKAGEID = tNFD.PACKAGEID
			WHERE tNFD.PACKAGEID IS NULL AND ISNULL(TMP.PackageDepartureID,0) = 0

			DELETE TMP FROM @tblOptionalElements TMP 
			LEFT OUTER JOIN #TBL_NFD tNFD ON TMP.DEPARTUREDATE = tNFD.DEPARTUREDATE AND TMP.PACKAGEID = tNFD.PACKAGEID
			WHERE tNFD.PACKAGEID IS NULL AND ISNULL(TMP.PACKAGEDEPARTUREID,0) = 0

			DELETE TMP FROM @tbl_Optional TMP 
			LEFT OUTER JOIN #TBL_NFD tNFD ON TMP.DEPARTUREDATE = tNFD.DEPARTUREDATE AND TMP.PACKAGEID = tNFD.PACKAGEID
			WHERE tNFD.PACKAGEID IS NULL  AND ISNULL(TMP.PackageDepartureID,0) = 0

		END
		-- EOC Rupesh PK.(06)

		-- BOC Rupesh PK.(05)
		IF DATALENGTH(@rtxt_PassengerInfoXML) > 0	
		BEGIN
			

			EXEC SP_XML_PREPAREDOCUMENT @iDocPax OUTPUT, @rtxt_PassengerInfoXML

			INSERT INTO @tblChildInfo
					(
						ChildID,
						DOB,
						Age,
						RoomID,
						Gender
					)
			SELECT CHILDID, BIRTHDATE, AGE, ROOMID, GENDER
			FROM OPENXML (@iDocPax, '//PASSENGERS//CHILDREN/CHILD')
			WITH (
					CHILDID int '@CHILDID',
					BIRTHDATE DATETIME '@BIRTHDATE',
					AGE INT '@AGE',
					ROOMID INT '@ROOMID',
					GENDER INT '@GENDER'
				 )
			EXEC SP_XML_REMOVEDOCUMENT @iDocPax --Myrtle(09)
			
			
			

		
		END

		-->>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Operation on Element Child Date <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
		/*-->> Fetch the count of child associated with that Age
		UPDATE T
		SET T.Cnt = (SELECT COUNT(1) FROM DBO.udf_LIST_TO_TABLE(T.ChildIDs))
		FROM @tblTmpElementChild T
		WHERE LEN(T.ChildIDs) > 0 AND T.ChildIDs <>'0'*/
			

		-->> Append a ',' at the end of the string if the comma is not present. This will help us furthere when String functions will be used.
		UPDATE T
		SET T.ChildIDs = LTRIM(RTRIM(T.ChildIDs)) + ','
		FROM @tbl_Element T
		WHERE SUBSTRING(T.ChildIDs, LEN(T.ChildIDs), LEN(T.ChildIDs) + 1) <> ','

		-->> Fetch the count of child associated with that Age
		UPDATE T
		SET T.Cnt = LEN(T.ChildIDs) - LEN(REPLACE(T.ChildIDs, ',', ''))
		FROM @tbl_Element T
		WHERE LEN(T.ChildIDs) > 0 AND T.ChildIDs <>'0'
			  AND CHARINDEX(',', T.ChildIDs) > 1

		-->> Fetch the Max Count of the Child
		SELECT @i_MaxCount = MAX(Cnt) FROM @tbl_Element

		-->> Get the Number sequence
		INSERT INTO @tblNum
		SELECT NUMBER   
		FROM dbo.udf_NumberToTable(@i_MaxCount, 1, NULL)  

		-->> Do a self insert here for those record which has Count > 1 (Duplicate records are generated in this case which is needed)
		INSERT INTO @tbl_Element
		(PackageID,PackageDepartureID,DepartureDate,ElementID,Age,Cnt, ChildIDs, ProcessDuplicate, ChildID)
		SELECT T.PackageID, T.PackageDepartureID, T.DepartureDate, T.ElementID, T.Age, 1, T.ChildIDs, 1,0
		FROM @tbl_Element T
		INNER JOIN @tblnum B ON B.value BETWEEN 1 AND T.Cnt
		WHERE T.Cnt > 1

		-->> After Splitting the records deleting the record which was used in splitting so that there is no extra records.
		DELETE T FROM @tbl_Element T WHERE T.Cnt > 1 AND T.ProcessDuplicate = 0

		-->> Use ordered data 
		INSERT INTO @tblTmpElementChild (PackageID,PackageDepartureID,DepartureDate,ElementID,Age,Cnt, ChildIDs, ProcessDuplicate, ChildID)
		SELECT T.PackageID, T.PackageDepartureID, T.DepartureDate, T.ElementID, T.Age, 1, T.ChildIDs, 1,0
		FROM @tbl_Element T
		ORDER BY T.PackageDepartureID, T.ChildIdentity

		-->> Initialise the variables so that the initial condition can be met and we can process the records
		SELECT @v_ChildIDs = '', @v_ChildIDsSubString = '', @i_CommaPos = 0

		-->> This is a self update which is coded to avoid loops. UPDATE itself is a loop within
		UPDATE T
			-->> Get the String
		SET @v_ChildIDs = CASE WHEN @v_ChildIDs = '' OR @v_ChildIDsSubString = ''
							THEN T.ChildIDs 
							ELSE @v_ChildIDsSubString
							END ,
			-->> Find the position of comma(',')
			@i_CommaPos = CHARINDEX(',', @v_ChildIDs),
			-->> Get the String till the Comma from the left; this is done using the LEFT function (this will fetch us the ID which we are wants)
			@i_ChildID =  CONVERT(INT, LTRIM(RTRIM(LEFT(@v_ChildIDs, @i_CommaPos - 1)))) ,
			-->> Delete the values that are fetched in the above statement so that we can process the remaining string
			@v_ChildIDsSubString = SUBSTRING(@v_ChildIDs, @i_CommaPos + 1, LEN(@v_ChildIDs)),
			-->> Update the ID that is fetched 
			T.ChildID = @i_ChildID
		FROM @tblTmpElementChild T 

		
		-->> Calculate the Age based on the DOB
		UPDATE T
		SET T.Age = (CASE WHEN ISNULL(CF.DOB,'') = '' OR CF.DOB = '17530101'
					THEN T.Age -->> If DOB is not passsed then no need to recalculate the age
					ELSE 
						DATEDIFF(YEAR, CF.DOB, T.DepartureDate) -
						CASE WHEN DATEPART(MM, CF.DOB) > DATEPART(MM, T.DepartureDate) OR 
								  (DATEPART(MM, CF.DOB) = DATEPART(MM, T.DepartureDate) AND DATEPART(DD, CF.DOB) > DATEPART(DD, T.DepartureDate))
						THEN 1
						ELSE 0 
						END 
					END)
		FROM @tblTmpElementChild T
		INNER JOIN @tblChildInfo CF ON CF.ChildID = T.ChildID 
		WHERE T.ChildID > 0 
		

		-->> Populate the main Element child table
		INSERT INTO @tblElementChildDetails(PACKAGEID,PACKAGEDEPARTUREID,DEPARTUREDATE,ELEMENTID,EAge,ECnt)
		SELECT PACKAGEID, PACKAGEDEPARTUREID,DEPARTUREDATE, ELEMENTID, Age, Cnt
		FROM @tblTmpElementChild

		-->>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Operation on Optional Option Child Date <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
		/*-->> Fetch the count of child associated with that Age
		UPDATE T
		SET T.Cnt = (SELECT COUNT(1) FROM DBO.udf_LIST_TO_TABLE(T.ChildIDs))
		FROM @tbl_Optional T
		WHERE LEN(T.ChildIDs) > 0 AND T.ChildIDs <>'0'*/
			

		-->> Append a ',' at the end of the string if the comma is not present. This will help us furthere when String functions will be used.
		UPDATE T
		SET T.ChildIDs = LTRIM(RTRIM(T.ChildIDs)) + ','
		FROM @tbl_Optional T
		WHERE SUBSTRING(T.ChildIDs, LEN(T.ChildIDs), LEN(T.ChildIDs) + 1) <> ','

		-->> Fetch the count of child associated with that Age
		UPDATE T
		SET T.Cnt = LEN(T.ChildIDs) - LEN(REPLACE(T.ChildIDs, ',', ''))
		FROM @tbl_Optional T
		WHERE LEN(T.ChildIDs) > 0 AND T.ChildIDs <>'0'
			  AND CHARINDEX(',', T.ChildIDs) > 1
		
		-->> Only if the Maximum Count of Optional child is more then that of the Elemnt Child record
		IF @i_MaxCount < (SELECT MAX(Cnt) FROM @tbl_Optional)
		BEGIN 
			-->> Flush the temp table
			DELETE FROM @tblNum

			-->> Fetch the Max Count of the Child
			SELECT @i_MaxCount = MAX(Cnt) FROM @tbl_Optional
			
			-->> Get the Number sequence
			INSERT INTO @tblNum
			SELECT NUMBER   
			FROM dbo.udf_NumberToTable(@i_MaxCount, 1, NULL)		
		END
		

		-->> Do a self insert here for those record which has Count > 1 (Duplicate records are generated in this case which is needed)
		INSERT INTO @tbl_Optional
		(PackageDepartureID, PackageOptionID, Age, Cnt, DepartureDate, ChildIDs, ProcessDuplicate, ChildID, PACKAGEID)
		SELECT T.PackageDepartureID, T.PackageOptionID, T.Age, 1, T.DepartureDate, T.ChildIDs, 1,0, T.PackageID
		FROM @tbl_Optional T
		INNER JOIN @tblnum B ON B.value BETWEEN 1 AND T.Cnt
		WHERE T.Cnt > 1

		-->> After Splitting the records deleting the record which was used in splitting so that there is no extra records.
		DELETE T FROM @tbl_Optional T WHERE T.Cnt > 1 AND T.ProcessDuplicate = 0
		
		INSERT INTO @tblTmpOptionalChild
		(PackageDepartureID, PackageOptionID, Age, Cnt, DepartureDate, ChildIDs, ProcessDuplicate, ChildID, PACKAGEID)
		SELECT T.PackageDepartureID, T.PackageOptionID, T.Age, 1, T.DepartureDate, T.ChildIDs, 1,0, T.PackageID
		FROM @tbl_Optional T
		ORDER BY T.PackageOptionID, T.PackageDepartureID, T.OptionalChildIdentity 
 

		-->> Initialise the variables so that the initial condition can be met and we can process the records
		SELECT @v_ChildIDs = '', @v_ChildIDsSubString = '', @i_CommaPos = 0, @i_ChildID = 0

		-->> This is a self update which is coded to avoid loops. UPDATE itself is a loop within
		UPDATE T
			-->> Get the String
		SET @v_ChildIDs = CASE WHEN @v_ChildIDs = '' OR @v_ChildIDsSubString = ''
							THEN T.ChildIDs 
							ELSE @v_ChildIDsSubString
							END ,
			-->> Find the position of comma(',')
			@i_CommaPos = CHARINDEX(',', @v_ChildIDs),
			-->> Get the String till the Comma from the left; this is done using the LEFT function (this will fetch us the ID which we are wants)
			@i_ChildID =  CONVERT(INT, LTRIM(RTRIM(LEFT(@v_ChildIDs, @i_CommaPos - 1)))) ,
			-->> Delete the values that are fetched in the above statement so that we can process the remaining string
			@v_ChildIDsSubString = SUBSTRING(@v_ChildIDs, @i_CommaPos + 1, LEN(@v_ChildIDs)),
			-->> Update the ID that is fetched 
			T.ChildID = @i_ChildID
		FROM @tblTmpOptionalChild T 
		

		
		-->> Calculate the Age based on the DOB
		UPDATE T
		SET T.Age = (CASE WHEN ISNULL(CF.DOB,'') = '' OR CF.DOB = '17530101'
					THEN T.Age -->> If DOB is not passsed then no need to recalculate the age
					ELSE 
						DATEDIFF(YEAR, CF.DOB, T.DepartureDate) -
						CASE WHEN DATEPART(MM, CF.DOB) > DATEPART(MM, T.DepartureDate) OR 
								  (DATEPART(MM, CF.DOB) = DATEPART(MM, T.DepartureDate) AND DATEPART(DD, CF.DOB) > DATEPART(DD, T.DepartureDate))
						THEN 1
						ELSE 0 
						END 
					END)
		FROM @tblTmpOptionalChild T
		INNER JOIN @tblChildInfo CF ON CF.ChildID = T.ChildID 
		WHERE T.ChildID > 0 
		
		-->> Since we have distributed all child recrds, the count will be 1 for all the records.
		UPDATE T SET T.Cnt = 1 FROM @tblTmpOptionalChild T 
		
		-->> Populate the main Optional option child table
		INSERT INTO @tblOptionalChildDetails(PACKAGEDEPARTUREID, PackageOptionID, OAge, OCnt, DEPARTUREDATE, PACKAGEID)
		SELECT   PackageDepartureID, PackageOptionID, Age, Cnt, DepartureDate, PackageID
		FROM  @tblTmpOptionalChild	
		ORDER BY PackageOptionID

		-- EOC Rupesh PK.(05)		

		
		-->> Fetch the Flag which is set in Additional Flag tab of Organisation
		SELECT @DoNotConsiderAgeBandForAdditionalChild = SYSTEMSETTINGSFIELDVALUE 
				FROM dbo.SYSTEM_SETTINGS_FIELD WITH(NOLOCK)	WHERE SYSTEMSETTINGSFIELDNAME='Age Band Not To Be Considered For Determining Additional Child'
	
		--Main Element
		insert into @tblElementOccupanyId(ElementID)
			select distinct ElementID from @tblMainElements
		
		--Optional Element	
		insert into @tblOptionalOccupanyId(OptionalOptionID)
			select distinct PackageOptionID from @tblOptionalElements		
		
		--Main Element
		update EOI
		set EOI.OccupancyTypeID=AO.OCCUPANCYTYPEID 
		from @tblElementOccupanyId EOI inner join PACKAGE_ELEMENT PE on EOI.ElementID =PE.PACKAGEELEMENTID 
		INNER JOIN ASSIGNED_OCCUPANCY AO ON PE.SERVICETYPEOPTIONID = AO.SERVICETYPEOPTIONID
		
		--Optional Element
		update OOI
		set OOI.OccupancyTypeID=AO.OCCUPANCYTYPEID 
		from @tblOptionalOccupanyId OOI inner join PACKAGE_OPTION PO on OOI.OptionalOptionID =PO.PACKAGEOPTIONID 
		inner join SERVICE_OPTION_IN_SERVICE SOIS on PO.SERVICEOPTIONINSERVICEID=PO.SERVICEOPTIONINSERVICEID  
		INNER JOIN ASSIGNED_OCCUPANCY AO ON SOIS.SERVICETYPEOPTIONID = AO.SERVICETYPEOPTIONID

		
		--Main Element
		INSERT INTO @tblDataTable
			select ME.ELEMENTID,
					OT.OCCUPANCYTYPEID ,
					OT.OCCUPANCYTYPECAPACITY ,
					OT.CHILDCAPAICITY ,
					ME.NOOFADULTS,
					ME.NOOFCHILDREN,
					ME.PACKAGEID , 
					ME.DEPARTUREDATE ,
					ME.DEPARTUREID 
			from @tblMainElements ME 
			inner join @tblElementOccupanyId EOI on ME.ELEMENTID =EOI.ElementID 
			inner join OCCUPANCY_TYPE OT on EOI.OccupancyTypeID =OT.OCCUPANCYTYPEID


		--Optional Element
		-- Rupesh PK.(02) commented as Occupancy details are not needed for Optional	
		--BOC Pradnya(1)
		/*IF ISNULL(@DoNotConsiderAgeBandForAdditionalChild,0) = 0
		BEGIN
		INSERT INTO @tblOptionalDataTable
			select OE.PackageOptionID,
					OT.OCCUPANCYTYPEID ,
					OT.OCCUPANCYTYPECAPACITY ,
					OT.CHILDCAPAICITY ,
					OE.OptionNOOFADULTS,
					OE.OptionNOOFCHILDREN,
					OE.PACKAGEID, 
					OE.DEPARTUREDATE,
					OE.OptionDATE,
					OE.PACKAGEDEPARTUREID  
			from @tblOptionalElements OE 
			inner join @tblOptionalOccupanyId OOI on OE.PackageOptionID =OOI.OptionalOptionID  
			inner join OCCUPANCY_TYPE OT on OOI.OccupancyTypeID =OT.OCCUPANCYTYPEID
		END
		ELSE
		BEGIN*/
		INSERT INTO @tblOptionalDataTable
		select OE.PackageOptionID,
					0,
					0,
					0,
					OE.OptionNOOFADULTS,
					OE.OptionNOOFCHILDREN,
					OE.PACKAGEID, 
					OE.DEPARTUREDATE,
					OE.OptionDATE,
					OE.PACKAGEDEPARTUREID  
			from @tblOptionalElements OE 
			inner join @tblOptionalOccupanyId OOI on OE.PackageOptionID =OOI.OptionalOptionID  	
		--END -- Rupesh PK.(02) commented the END stmt.
		--EOC Pradnya(1)
		
		-- Rupesh PK.(05) commented as this is handled on top
		/*select @max = MAX(Ecnt) from @tblElementChildDetails

		insert into @tblnum
			SELECT NUMBER from dbo.udf_NumberToTable(@max,1,NULL)  t			
		
		-->> Main Element (spliting the child records for Main Element having Child Quantity > 1)
		insert into @tblElementChildDetails
			select t.MainElementIdentity,PACKAGEID,PACKAGEDEPARTUREID,DEPARTUREDATE,ELEMENTID,EAge,1 
			from @tblElementChildDetails t inner join @tblnum b on b.value  between 1 and t.Ecnt 
			where t.Ecnt > 1
		delete from @tblElementChildDetails where Ecnt>1
		
		-->> Optional Element (spliting the child records for Optional Element having Child Quantity > 1)
		insert into @tblOptionalChildDetails
			select OCD.PACKAGEDEPARTUREIDentity,OCD.PACKAGEDEPARTUREID,OCD.PackageOptionID ,OCD.OAge,1 ,OCD.PACKAGEID ,OCD.DEPARTUREDATE 
			from @tblOptionalChildDetails OCD inner join @tblnum b on b.value  between 1 and OCD.OCnt  
			where OCD.Ocnt > 1
		delete from @tblOptionalChildDetails where Ocnt>1
		*/


		
		-->> Main Element containing the splited records
		insert into @tblSplitElementChildDetails
			(PACKAGEID, OccupancyID, ChildCapacity, NoOfChild, PACKAGEDEPARTUREID, DEPARTUREDATE, ELEMENTID, ChildAge) --Rupesh PK.(05)
			select ECD.PACKAGEID,DT.OccupancyID,DT.ChildCapacity,DT.NoOfChild,ECD.PACKAGEDEPARTUREID,ECD.DEPARTUREDATE
					,ECD.ELEMENTID ,ECD.EAge
			from @tblElementChildDetails ECD inner join @tblDataTable DT on ECD.ELEMENTID =DT.ElementID and ECD.PACKAGEID =DT.PACKAGEID and 
			ECD.PACKAGEDEPARTUREID =DT.PACKAGEDEPARTUREID and ECD.DEPARTUREDATE =DT.DEPARTUREDATE 
			order by ECD.ELEMENTID,ECD.DEPARTUREDATE,ECD.ChildIdentity 
		
		-->> Optional Element containing the splited records
		insert into @tblSplitOptionalChildDetails
			(PACKAGEID, OccupancyID, ChildCapacity, NoOfChild, PACKAGEDEPARTUREID, DEPARTUREDATE, PackageOptionId, ChildAge, OptionDATE) --Rupesh PK.(05)
			select ODT.PACKAGEID,ODT.OccupancyID,ODT.ChildCapacity,ODT.NoOfChild,OCD.PACKAGEDEPARTUREID,ODT.DEPARTUREDATE
					,OCD.PackageOptionID ,OCD.OAge,ODT.OptionDATE 
			from @tblOptionalChildDetails OCD inner join @tblOptionalDataTable ODT on OCD.PackageOptionID  =ODT.PackageOptionID and OCD.PACKAGEID =ODT.PACKAGEID and 
			OCD.PACKAGEDEPARTUREID =ODT.PACKAGEDEPARTUREID and OCD.DEPARTUREDATE =ODT.DEPARTUREDATE
			order by OCD.PackageOptionID ,OCD.DEPARTUREDATE ,OCD.OptionalChildIdentity 
			




	IF ISNULL(@DoNotConsiderAgeBandForAdditionalChild,0) = 0 --> Child with MIN age will be the First Child (This is within a ROOM only)
	BEGIN


	SET @RoomId=1
	
	-->> Loop through the Element child record and get the room list
	Select @minid = MIN(ID), @maxID = MAX(ID) from @tblSplitElementChildDetails
	while @minid <= @maxID
		Begin
		select @PackageElementId=SECD.ElementID,@DepartureDate=SECD.DEPARTUREDATE,@ChildCapacity=DT.ChildCapacity from @tblSplitElementChildDetails SECD 
		inner join @tblDataTable DT on SECD.ElementID=DT.ElementID where SECD.id=@minid 
		
		select top 1 @PreviousDepartureDate=DEPARTUREDATE,@PreviousPackageElementId=ELEMENTID from @tblFinalChildDetails order by id desc
		if (@DepartureDate <> @PreviousDepartureDate or @PackageElementId <> @PreviousPackageElementId)
			set @ChildCapacity=0

		if @ChildCapacity =0
			Begin 
				update DT set DT.ChildCapacity =SECD.ChildCapacity 
				from @tblDataTable DT inner join @tblSplitElementChildDetails SECD on SECD.ElementID=DT.ElementID 
				where DT.ElementID=@PackageElementId
				
				select @ChildCapacity=DT.ChildCapacity 
				from @tblSplitElementChildDetails SECD inner join @tblDataTable DT on SECD.ElementID=DT.ElementID
				where SECD.id=@minid 

				SET @RoomId=@RoomId+1
			end
		
		insert into @tblFinalChildDetails
		(PACKAGEID, OccupancyID, ChildCapacity, NoOfChild, PACKAGEDEPARTUREID, DEPARTUREDATE, ELEMENTID, ChildAge, LogicalRoomID) --Rupesh PK.(05)
			select SECD.PACKAGEID,SECD.OccupancyID,SECD.ChildCapacity,SECD.NoOfChild,SECD.PACKAGEDEPARTUREID,
				SECD.DEPARTUREDATE,SECD.ELEMENTID ,SECD.ChildAge,@RoomId
				from @tblSplitElementChildDetails SECD where id=@minid
				and @ChildCapacity>0

		update DT
		set DT.ChildCapacity =DT.ChildCapacity-1
		from @tblDataTable DT where DT.ElementID=@PackageElementId
		
		set @minid = @minid + 1
	end
	

	-->> Loop through the Optional child record and get the room list
	declare @Ominid int ,@OmaxID int,@PackageOptionId int ,@OChildCapacity int,@ORoomId int,@ODepartureDate DATETIME,
	@OPreviousDepartureDate DATETIME,@OPreviousPackageOptionId int
	-- Rupesh PK.(02) commented the code as Rooming List of Optional is not needed. All calculation are based on Element Rooming List
	/*SET @ORoomId=1
	Select @Ominid = MIN(ID), @OmaxID  = MAX(ID) from @tblSplitOptionalChildDetails
	while @Ominid <= @OmaxID 
		Begin
		select @PackageOptionId=SOCD.PackageOptionId,@ODepartureDate=SOCD.DEPARTUREDATE ,@OChildCapacity=DT.ChildCapacity from @tblSplitOptionalChildDetails SOCD 
		inner join @tblOptionalDataTable DT on SOCD.PackageOptionId =DT.PackageOptionID  where SOCD.id=@Ominid 

		select top 1 @OPreviousDepartureDate=DEPARTUREDATE ,@OPreviousPackageOptionId=PackageOptionId from @tblFinalOptionalChildDetails order by id desc
		if (@ODepartureDate <> @OPreviousDepartureDate or @PackageOptionId <> @OPreviousPackageOptionId)
			set @OChildCapacity=0
		
		if @OChildCapacity =0
			Begin 
				update DT set DT.ChildCapacity =SOCD.ChildCapacity 
				from @tblOptionalDataTable DT inner join @tblSplitOptionalChildDetails SOCD on SOCD.PackageOptionId=DT.PackageOptionID  
				where DT.PackageOptionID=@PackageOptionId
				
				select @OChildCapacity=DT.ChildCapacity 
				from @tblSplitOptionalChildDetails SOCD inner join @tblOptionalDataTable DT on SOCD.PackageOptionId =DT.PackageOptionID 
				where SOCD.id=@Ominid 
				
				SET @ORoomId=@ORoomId+1
			end
		
		insert into @tblFinalOptionalChildDetails
			select SOCD.PACKAGEID,SOCD.OccupancyID,SOCD.ChildCapacity,SOCD.NoOfChild,SOCD.PACKAGEDEPARTUREID,
				SOCD.DEPARTUREDATE,SOCD.PackageOptionId ,SOCD.ChildAge,@ORoomId,SOCD.OptionDATE 
				from @tblSplitOptionalChildDetails SOCD where id=@Ominid
				and @OChildCapacity>0
		
		update DT
		set DT.ChildCapacity =DT.ChildCapacity-1
		from @tblOptionalDataTable DT where DT.PackageOptionID =@PackageOptionId
		
		set @Ominid = @Ominid + 1
	end*/
	INSERT INTO @tblFinalOptionalChildDetails
	(PACKAGEID, OccupancyID, ChildCapacity, NoOfChild, PACKAGEDEPARTUREID, DEPARTUREDATE, PackageOptionID, ChildAge, LogicalRoomID, OptionDATE) --Rupesh PK.(05)
	SELECT SOCD.PACKAGEID,
		   SOCD.OccupancyID,
		   SOCD.ChildCapacity,
		   SOCD.NoOfChild,
		   SOCD.PACKAGEDEPARTUREID,
		   SOCD.DEPARTUREDATE,
		   SOCD.PackageOptionId,
		   SOCD.ChildAge,
		   NULL AS LogicalRoomID,
		   SOCD.OptionDATE 
	FROM @tblSplitOptionalChildDetails SOCD
	-- EOC Rupesh PK.(02)	
				
	END
	ELSE --> Child with MIN age will be the First Child (This is throughout BOOKING)
	BEGIN
		insert into @tblFinalChildDetails
		(PACKAGEID, OccupancyID, ChildCapacity, NoOfChild, PACKAGEDEPARTUREID, DEPARTUREDATE, ELEMENTID, ChildAge, LogicalRoomID) --Rupesh PK.(05)
			select SECD.PACKAGEID,SECD.OccupancyID,SECD.ChildCapacity,SECD.NoOfChild,SECD.PACKAGEDEPARTUREID,
				SECD.DEPARTUREDATE,SECD.ELEMENTID ,SECD.ChildAge,NULL 
				from @tblSplitElementChildDetails SECD 
		
		
		insert into @tblFinalOptionalChildDetails
		(PACKAGEID, OccupancyID, ChildCapacity, NoOfChild, PACKAGEDEPARTUREID, DEPARTUREDATE, PackageOptionID, ChildAge, LogicalRoomID, OptionDATE) --Rupesh PK.(05)
			select SOCD.PACKAGEID,SOCD.OccupancyID,SOCD.ChildCapacity,SOCD.NoOfChild,SOCD.PACKAGEDEPARTUREID,
				SOCD.DEPARTUREDATE,SOCD.PackageOptionId ,SOCD.ChildAge,NULL,SOCD.OptionDATE 
				from @tblSplitOptionalChildDetails SOCD 
				
	END 
		
				
	-- BOC Rupesh PK.(03)
	UPDATE TMP 
		SET TMP.OptionDATE = POI.OPTIONALOPTIONDEPARTURESTARTDATE  
	FROM @tblFinalOptionalChildDetails TMP 
	INNER JOIN  #tbl_PackageOptionalInfo POI ON TMP.PackageOptionID = POI.PackageOPTIONID AND 
												TMP.DEPARTUREDATE = POI.PACKAGEDEPARTURESTARTDATE
	-- EOC Rupesh PK.(03)


	INSERT INTO @TMPBTPT 
		(
			BOOKINGTYPEID ,
			PRICETYPEID 	
		)
		SELECT distinct TMP1.VALUEID,
			TMP2.VALUEID
		FROM dbo.UDF_LIST_TO_TABLE(@rvc_BookingTypeID) TMP1  
		INNER JOIN dbo.UDF_LIST_TO_TABLE(@rvc_PriceTypeID) TMP2 ON TMP1.TABLEID = TMP2.TABLEID

    
	SELECT	@i_ROEBASEDONBOOKINGDATE2 = ISNULL(OS.ROEBASEDONBOOKINGDATE, 0)
	FROM	  ORGANISATION_SETTINGS OS
				INNER JOIN ORGANISATION O ON O.ORGANISATIONID = OS.ORGANISATIONID
	WHERE	  O.PARENT_ORGANISATIONID IS NULL

	
	IF ISNULL(@DoNotConsiderAgeBandForAdditionalChild,0) = 0 --> Child with MIN age will be the First Child (This is within a ROOM only)
	BEGIN
		--Main Element
		-->> Fetch the First child in the room
		INSERT INTO @tbl_FirstChildInfo
				(
					Age,
					RoomNO,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					ELEMENTID ,
					DEPARTUREDATE
				)
			SELECT MIN(ChildAge),
			   LogicalRoomID , 
			   PackageID,
			   PACKAGEDEPARTUREID ,
			   ELEMENTID ,
			   DEPARTUREDATE
	    FROM @tblFinalChildDetails 
		GROUP BY LogicalRoomID ,PackageID,PACKAGEDEPARTUREID ,ELEMENTID ,DEPARTUREDATE

		-->> Update PaxID for the first Child
		UPDATE FC
		SET FC.PaxID = BC.ID --,
		FROM @tbl_FirstChildInfo FC
		INNER JOIN @tblFinalChildDetails BC ON FC.Age = BC.ChildAge AND FC.RoomNO = BC.LogicalRoomID AND
		 FC.PACKAGEID = BC.PACKAGEID AND FC.PACKAGEDEPARTUREID  =BC.PACKAGEDEPARTUREID AND 
		 FC.ELEMENTID = BC.ELEMENTID AND FC.DEPARTUREDATE =BC.DEPARTUREDATE  
		
		
	  --Optional Element 
	  -- Rupesh PK.(02) commented and rewritten below
	/*-->> Fetch the First child in the room
		INSERT INTO @tbl_FirstOptionalChildInfo
				(
					Age,
					RoomNO,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					PackageOptionID ,
					DEPARTUREDATE
				)
		SELECT MIN(ChildAge),
			   LogicalRoomID , 
			   PackageID,
			   PACKAGEDEPARTUREID ,
			   PackageOptionID ,
			   DEPARTUREDATE
	    FROM @tblFinalOptionalChildDetails 
		GROUP BY LogicalRoomID ,PackageID,PACKAGEDEPARTUREID ,PackageOptionID ,DEPARTUREDATE

		-->> Update PaxID for the first Child
		UPDATE FOCI
		SET FOCI.PaxID = FOCD.ID ,
			FOCI.OptionDATE =FOCD.OptionDATE  
		FROM @tbl_FirstOptionalChildInfo FOCI
		INNER JOIN @tblFinalOptionalChildDetails FOCD ON FOCI.Age = FOCD.ChildAge AND FOCI.RoomNO = FOCD.LogicalRoomID AND
		 FOCI.PACKAGEID = FOCD.PACKAGEID AND FOCI.PACKAGEDEPARTUREID  =FOCD.PACKAGEDEPARTUREID AND 
		 FOCI.PackageOptionID = FOCD.PackageOptionID AND FOCI.DEPARTUREDATE =FOCD.DEPARTUREDATE*/
		 -->> Fetch First Child record 
		 -->> This also can be elimimated after proper analysing
		INSERT INTO @tbl_FirstOptionalChildInfo
				(
					Age,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					DEPARTUREDATE
				)
			SELECT MIN(ChildAge), 
				   PackageID,
				   PACKAGEDEPARTUREID ,
				   DEPARTUREDATE
			FROM @tblFinalOptionalChildDetails 
			GROUP BY PackageID,PACKAGEDEPARTUREID,DEPARTUREDATE
		
		-->> Update PaxID for Firxt Child
		UPDATE FOCI
		SET FOCI.PaxID = FOCD.ID ,
		 FOCI.PackageOptionID =FOCD.PackageOptionID ,
		 FOCI.OptionDATE =FOCD.OptionDATE
		FROM @tbl_FirstOptionalChildInfo FOCI
		INNER JOIN @tblFinalOptionalChildDetails FOCD ON FOCI.Age = FOCD.ChildAge AND FOCI.PACKAGEID= FOCD.PACKAGEID  AND 
		FOCI.PACKAGEDEPARTUREID=FOCD.PACKAGEDEPARTUREID AND FOCI.DEPARTUREDATE =FOCD.DEPARTUREDATE
		-- EOC Rupesh PK.(02)

		--Main Element	
		-->> Insert First Child record into the temp table
		--BOC Ankita S(08)
		IF @rb_SearchbyBookDateAndOrgFlag=1
			BEGIN
		INSERT INTO @tbl_ChildInfo
		        (
					PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					ELEMENTID ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated 
				)
		     SELECT  FCI.PaxID,FCI.RoomNO,FCI.Age,0,FCI.PACKAGEID ,FCI.PACKAGEDEPARTUREID ,FCI.ELEMENTID ,PP.PACKAGEPRICEID 
				 ,FCI.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FCI.DEPARTUREDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0  
		     FROM @tbl_FirstChildInfo FCI
		     inner join Package_Price PP on FCI.PACKAGEID =PP.PACKAGEID 
		     inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
		     where FCI.DEPARTUREDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE and FCI.ELEMENTID =PP.PACKAGEELEMENTID 
		     -- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
		     AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
		     AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
			 AND (@rd_BOOKINGDATE between isnull(pp.BOOKFROMDATE,cast('17530101' as datetime)) and isnull(pp.BOOKTODATE,cast('99991230' as datetime)))  
			END
		--EOC Ankita S(08)
		ELSE 
			BEGIN
		INSERT INTO @tbl_ChildInfo
		        (
					PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					ELEMENTID ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated 
				)
		     SELECT  FCI.PaxID,FCI.RoomNO,FCI.Age,0,FCI.PACKAGEID ,FCI.PACKAGEDEPARTUREID ,FCI.ELEMENTID ,PP.PACKAGEPRICEID 
				 ,FCI.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FCI.DEPARTUREDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0  
		     FROM @tbl_FirstChildInfo FCI
		     inner join Package_Price PP on FCI.PACKAGEID =PP.PACKAGEID 
		     inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
		     where FCI.DEPARTUREDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE and FCI.ELEMENTID =PP.PACKAGEELEMENTID 
		     -- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			END
		    
		
		--Optional Element		
		/*-->> Insert First Child record into the temp table 
		-->> Rupesh PK.(04) commented as it was affecting the rooming list functionality
		INSERT INTO @tbl_tmpOptionalChildInfo --Rupesh PK.(04) Renamed the table @tbl_OptionalChildInfo to @tbl_tmpOptionalChildInfo
		        (
					PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					PackageOptionId ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated 
					,PackageElementID -- Rupesh PK.(02)
				)
		     SELECT  FOCI.PaxID,FOCI.RoomNO,FOCI.Age,0,FOCI.PACKAGEID ,FOCI.PACKAGEDEPARTUREID ,FOCI.PackageOptionID ,PP.PACKAGEPRICEID 
				 ,FOCI.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FOCI.OptionDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0  
					,PO.PACKAGEELEMENTID -- Rupesh PK.(02)
		     FROM @tbl_FirstOptionalChildInfo FOCI
		     inner join Package_Price PP on FOCI.PACKAGEID =PP.PACKAGEID 
		     inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
		     INNER JOIN PACKAGE_OPTION PO ON PO.PACKAGEOPTIONID = PP.PACKAGEOPTIONID -- Rupesh PK.(02)
		     where FOCI.OptionDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE and FOCI.PackageOptionID =PP.PACKAGEOPTIONID
		     -- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02) 
		*/
		--Main Element	
		-->> Insert Second Child record into the temp table
		--BOC Ankita S(08)
		IF @rb_SearchbyBookDateAndOrgFlag=1
			BEGIN
		INSERT INTO @tbl_ChildInfo
				(
					PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					ELEMENTID ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
				)
			SELECT FCD.ID,FCD.LogicalRoomID,FCD.ChildAge,1,FCD.PACKAGEID ,FCD.PACKAGEDEPARTUREID ,FCD.ELEMENTID ,PP.PACKAGEPRICEID
				,FCD.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FCD.DEPARTUREDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0  
			FROM @tblFinalChildDetails FCD
			inner join Package_Price PP on FCD.PACKAGEID =PP.PACKAGEID 
			inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
			LEFT OUTER JOIN @tbl_FirstChildInfo FC ON FC.PaxID = FCD.ID  
			WHERE FC.PaxID IS NULL and FCD.DEPARTUREDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE 
			and FCD.ELEMENTID =PP.PACKAGEELEMENTID 
			-- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)

			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
			 AND (@rd_BOOKINGDATE between isnull(pp.BOOKFROMDATE,cast('17530101' as datetime)) and isnull(pp.BOOKTODATE,cast('99991230' as datetime)))  
			END
		--EOC Ankita S(08)
		ELSE
			BEGIN
		INSERT INTO @tbl_ChildInfo
				(
					PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					ELEMENTID ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
				)
			SELECT FCD.ID,FCD.LogicalRoomID,FCD.ChildAge,1,FCD.PACKAGEID ,FCD.PACKAGEDEPARTUREID ,FCD.ELEMENTID ,PP.PACKAGEPRICEID
				,FCD.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FCD.DEPARTUREDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0  
			FROM @tblFinalChildDetails FCD
			inner join Package_Price PP on FCD.PACKAGEID =PP.PACKAGEID 
			inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
			LEFT OUTER JOIN @tbl_FirstChildInfo FC ON FC.PaxID = FCD.ID  
			WHERE FC.PaxID IS NULL and FCD.DEPARTUREDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE 
			and FCD.ELEMENTID =PP.PACKAGEELEMENTID 
			-- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			 END
		--Optional Element	
		-->> Insert Second Child record into the temp table
		--BOC Ankita S(08)
		IF @rb_SearchbyBookDateAndOrgFlag=1
			BEGIN
		INSERT INTO @tbl_tmpOptionalChildInfo --Rupesh PK.(04) Renamed the table @tbl_OptionalChildInfo to @tbl_tmpOptionalChildInfo
				(
					PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					PackageOptionId ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
					,PackageElementID -- Rupesh PK.(02)
				)
			SELECT FOCD.ID,FOCD.LogicalRoomID,FOCD.ChildAge,1,FOCD.PACKAGEID ,FOCD.PACKAGEDEPARTUREID ,FOCD.PackageOptionID ,PP.PACKAGEPRICEID
				,FOCD.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FOCD.OptionDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0 
					,PO.PACKAGEELEMENTID -- Rupesh PK.(02)
			FROM @tblFinalOptionalChildDetails FOCD
			inner join Package_Price PP on FOCD.PACKAGEID =PP.PACKAGEID 
			inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
			INNER JOIN PACKAGE_OPTION PO ON PO.PACKAGEOPTIONID = PP.PACKAGEOPTIONID -- Rupesh PK.(02)
			--LEFT OUTER JOIN @tbl_FirstOptionalChildInfo FOCI ON FOCI.PaxID = FOCD.ID  -->> Rupesh PK.(04) commented as it was affecting the rooming list functionality
			WHERE --FOCI.PaxID IS NULL and -->> Rupesh PK.(04) commented as it was affecting the rooming list functionality
			FOCD.OptionDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE 
			and FOCD.PackageOptionID  =PP.PACKAGEOPTIONID
			-- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			  AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
			 
			  AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
			  AND (@rd_BOOKINGDATE between isnull(pp.BOOKFROMDATE,cast('17530101' as datetime)) and isnull(pp.BOOKTODATE,cast('99991230' as datetime))) 
			END
		--EOC Ankita S(08)
		ELSE
		BEGIN
		INSERT INTO @tbl_tmpOptionalChildInfo --Rupesh PK.(04) Renamed the table @tbl_OptionalChildInfo to @tbl_tmpOptionalChildInfo
				(
					PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					PackageOptionId ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
					,PackageElementID -- Rupesh PK.(02)
				)
			SELECT FOCD.ID,FOCD.LogicalRoomID,FOCD.ChildAge,1,FOCD.PACKAGEID ,FOCD.PACKAGEDEPARTUREID ,FOCD.PackageOptionID ,PP.PACKAGEPRICEID
				,FOCD.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FOCD.OptionDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0 
					,PO.PACKAGEELEMENTID -- Rupesh PK.(02)
			FROM @tblFinalOptionalChildDetails FOCD
			inner join Package_Price PP on FOCD.PACKAGEID =PP.PACKAGEID 
			inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
			INNER JOIN PACKAGE_OPTION PO ON PO.PACKAGEOPTIONID = PP.PACKAGEOPTIONID -- Rupesh PK.(02)
			--LEFT OUTER JOIN @tbl_FirstOptionalChildInfo FOCI ON FOCI.PaxID = FOCD.ID  -->> Rupesh PK.(04) commented as it was affecting the rooming list functionality
			WHERE --FOCI.PaxID IS NULL and -->> Rupesh PK.(04) commented as it was affecting the rooming list functionality
			FOCD.OptionDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE 
			and FOCD.PackageOptionID  =PP.PACKAGEOPTIONID
			-- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			 END
			 -- BOC Rupesh PK.(05) Moved the code here with all the comments
			 -- BOC Rupesh PK.(02)		
			INSERT INTO @tbl_ElementInfo (Age,ElementID,DepartureDate ,IsAdditionalChild)--Rupesh PK.(04)
			SELECT C.Age,
				   C.ELEMENTID,
				   C.DEPARTUREDATE,
				   C.IsAdditionalChild
			FROM @tbl_ChildInfo C
			ORDER BY RoomNO, ID 
	
			--BOC Rupesh PK.(04)
			insert into @tbl_OptionalChildInfo (PaxID,RoomNO,Age,IsAdditionalChild,PACKAGEID ,PACKAGEDEPARTUREID ,PackageOptionId ,PackagePriceId,
			                        			DEPARTUREDATE,PRICEAMT,ROE,ISCHILDSHARING,IsUpdated,PackageElementID )
				select 	PaxID, RoomNO, Age, IsAdditionalChild,	PACKAGEID, PACKAGEDEPARTUREID ,PackageOptionId ,PackagePriceId ,
						DEPARTUREDATE ,PRICEAMT ,ROE ,ISCHILDSHARING ,IsUpdated,PackageElementID 
				from @tbl_tmpOptionalChildInfo
				order by PackageOptionID,PaxID

		
		
			DECLARE @i_Seq INT, @i_PackageOptionID INT,@i_PackageElementID INT
			SELECT @i_Seq = 0, @i_PackageOptionID = 0,@i_PackageElementID=0

			UPDATE OCI
			SET OCI.SEQ = @i_Seq ,
				@i_Seq = CASE WHEN @i_PackageOptionID = OCI.PackageOptionID 
						  THEN @i_Seq + 1
						  ELSE 1
						  END,		 
				@i_PackageOptionID = OCI.PackageOptionID 
			FROM @tbl_OptionalChildInfo OCI
	
			SET @i_Seq = 0
			UPDATE EI
			SET EI.SEQ = @i_Seq ,
				@i_Seq = CASE WHEN @i_PackageElementID = EI.ElementID  
						  THEN @i_Seq + 1
						  ELSE 1
						  END,		 
				@i_PackageElementID = EI.ElementID 
			FROM @tbl_ElementInfo EI
			--EOC Rupesh PK.(04)

			UPDATE O
				SET O.IsAdditionalChild = E.IsAdditionalChild,
					O.AdditionalUpdated = 1
			FROM @tbl_OptionalChildInfo O
			INNER JOIN @tbl_ElementInfo E ON E.SEQ = O.SEQ AND --Rupesh PK.(04)
											 E.Age = O.Age AND 
											 ISNULL(E.ELEMENTID,0) = ISNULL(O.PackageElementID,0) AND
											 E.DepartureDate = O.DEPARTUREDATE 
			WHERE ISNULL(O.PackageElementID,0) > 0

			-- BOC Rupesh PK.(05)
			UPDATE O
				SET O.IsAdditionalChild = E.IsAdditionalChild,
					O.AdditionalUpdated = 1
			FROM @tbl_OptionalChildInfo O
			INNER JOIN @tbl_ElementInfo E ON E.SEQ = O.SEQ AND --Rupesh PK.(04)
											 E.Age = O.Age AND 
											 E.DepartureDate = O.DEPARTUREDATE 
			WHERE ISNULL(O.PackageElementID,0) = 0
				  AND O.AdditionalUpdated = 0
			-- EOC Rupesh PK.(05)
		
			UPDATE O
				SET O.IsAdditionalChild = E.IsAdditionalChild,
					O.AdditionalUpdated = 1
			FROM @tbl_OptionalChildInfo O
			INNER JOIN @tbl_ElementInfo E ON E.Age = O.Age AND 
											 --ISNULL(E.ELEMENTID,0) = ISNULL(O.PackageElementID,0) AND -- Rupesh PK.(05)
											 E.DepartureDate = O.DEPARTUREDATE 
			WHERE O.AdditionalUpdated = 0 AND
				  ISNULL(O.PackageElementID,0) = 0 -- Rupesh PK.(05) changed the condition from >0 to =0
				  
	
	

			UPDATE O
				SET O.IsAdditionalChild = E.IsAdditionalChild,
					O.AdditionalUpdated = 1
			FROM @tbl_OptionalChildInfo O
			INNER JOIN @tbl_ElementInfo E ON E.SEQ = O.SEQ AND --Rupesh PK.(04) replaced @tbl_ChildInfo with @tbl_ElementInfo
										   E.Age = O.Age
			WHERE O.AdditionalUpdated = 0


			UPDATE O
				SET O.IsAdditionalChild = 0,
					O.AdditionalUpdated = 1
			FROM @tbl_OptionalChildInfo O
			INNER JOIN @tbl_ElementInfo E ON E.Age = O.Age--Rupesh PK.(04)replaced @tbl_ChildInfo with @tbl_ElementInfo
			WHERE O.AdditionalUpdated = 0	  
			-- EOC Rupesh PK.(02) 		
	END
	ELSE --> Child with MIN age will be the First Child (This is throughout BOOKING)
	BEGIN
		--Main Element
		-->> Fetch First Child record 
		INSERT INTO @tbl_FirstChildInfo
				(
					Age,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					DEPARTUREDATE
				)
			SELECT MIN(ChildAge), 
				   PackageID,
				   PACKAGEDEPARTUREID ,
				   DEPARTUREDATE
			FROM @tblFinalChildDetails 
			GROUP BY PackageID,PACKAGEDEPARTUREID,DEPARTUREDATE
		
		-->> Update PaxID for Firxt Child
		UPDATE FC
		SET FC.PaxID = BC.ID ,
		 FC.ELEMENTID =BC.ELEMENTID  
		FROM @tbl_FirstChildInfo FC
		INNER JOIN @tblFinalChildDetails BC ON FC.Age = BC.ChildAge AND FC.PACKAGEID= BC.PACKAGEID  AND 
		FC.PACKAGEDEPARTUREID=BC.PACKAGEDEPARTUREID AND FC.DEPARTUREDATE =BC.DEPARTUREDATE  

		--Optional Element 
		-->> Fetch First Child record 
		INSERT INTO @tbl_FirstOptionalChildInfo
				(
					Age,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					DEPARTUREDATE
				)
			SELECT MIN(ChildAge), 
				   PackageID,
				   PACKAGEDEPARTUREID ,
				   DEPARTUREDATE
			FROM @tblFinalOptionalChildDetails 
			GROUP BY PackageID,PACKAGEDEPARTUREID,DEPARTUREDATE
		
		-->> Update PaxID for Firxt Child
		UPDATE FOCI
		SET FOCI.PaxID = FOCD.ID ,
		 FOCI.PackageOptionID =FOCD.PackageOptionID ,
		 FOCI.OptionDATE =FOCD.OptionDATE
		FROM @tbl_FirstOptionalChildInfo FOCI
		INNER JOIN @tblFinalOptionalChildDetails FOCD ON FOCI.Age = FOCD.ChildAge AND FOCI.PACKAGEID= FOCD.PACKAGEID  AND 
		FOCI.PACKAGEDEPARTUREID=FOCD.PACKAGEDEPARTUREID AND FOCI.DEPARTUREDATE =FOCD.DEPARTUREDATE  
		
		
		
		--Main Element	
		-->> Insert First Child record into the temp table
		--BOC Ankita S(08)
		IF @rb_SearchbyBookDateAndOrgFlag=1
			BEGIN
		INSERT INTO @tbl_ChildInfo
		        (	PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					ELEMENTID ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
				)
			 SELECT  FCI.PaxID,FCI.RoomNO,FCI.Age,0,FCI.PACKAGEID ,FCI.PACKAGEDEPARTUREID ,FCI.ELEMENTID ,PP.PACKAGEPRICEID 
				 ,FCI.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FCI.DEPARTUREDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
					ELSE
						1.0
					END
					) AS ROE ,1 ,0  
		     FROM @tbl_FirstChildInfo FCI
		     inner join Package_Price PP on FCI.PACKAGEID =PP.PACKAGEID 
		     inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
		     where FCI.DEPARTUREDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE and FCI.ELEMENTID =PP.PACKAGEELEMENTID
		     -- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
		     
			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
			 AND (@rd_BOOKINGDATE between isnull(pp.BOOKFROMDATE,cast('17530101' as datetime)) and isnull(pp.BOOKTODATE,cast('99991230' as datetime)))  
			END
		--EOC Ankita S(08)
		ELSE
			BEGIN
		INSERT INTO @tbl_ChildInfo
		        (	PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					ELEMENTID ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
				)
			 SELECT  FCI.PaxID,FCI.RoomNO,FCI.Age,0,FCI.PACKAGEID ,FCI.PACKAGEDEPARTUREID ,FCI.ELEMENTID ,PP.PACKAGEPRICEID 
				 ,FCI.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FCI.DEPARTUREDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
					ELSE
						1.0
					END
					) AS ROE ,1 ,0  
		     FROM @tbl_FirstChildInfo FCI
		     inner join Package_Price PP on FCI.PACKAGEID =PP.PACKAGEID 
		     inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
		     where FCI.DEPARTUREDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE and FCI.ELEMENTID =PP.PACKAGEELEMENTID
		     -- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FCI.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
		     END
		--Optional Element	
		-->> Insert First Child record into the temp table
		--BOC Ankita S(08)
		IF @rb_SearchbyBookDateAndOrgFlag=1
			BEGIN
		INSERT INTO @tbl_tmpOptionalChildInfo --Rupesh PK.(04) Renamed the table @tbl_OptionalChildInfo to @tbl_tmpOptionalChildInfo
		        (	PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					PackageOptionId ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
					,PackageElementID -- Rupesh PK.(02)
				)
			 SELECT  FOCI.PaxID,FOCI.RoomNO,FOCI.Age,0,FOCI.PACKAGEID ,FOCI.PACKAGEDEPARTUREID ,FOCI.PackageOptionID ,PP.PACKAGEPRICEID 
				 ,FOCI.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FOCI.OptionDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
					ELSE
						1.0
					END
					) AS ROE ,1 ,0  
					,PO.PACKAGEELEMENTID -- Rupesh PK.(02)
		     FROM @tbl_FirstOptionalChildInfo FOCI
		     inner join Package_Price PP on FOCI.PACKAGEID =PP.PACKAGEID 
		     inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
		     INNER JOIN PACKAGE_OPTION PO ON PO.PACKAGEOPTIONID = PP.PACKAGEOPTIONID -- Rupesh PK.(02)
		     where FOCI.OptionDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE and FOCI.PackageOptionID =PP.PACKAGEOPTIONID
		     -- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
		
			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
			 AND (@rd_BOOKINGDATE between isnull(pp.BOOKFROMDATE,cast('17530101' as datetime)) and isnull(pp.BOOKTODATE,cast('99991230' as datetime)))  
			END
		--EOC Ankita S(08)
		ELSE
		BEGIN
		INSERT INTO @tbl_tmpOptionalChildInfo --Rupesh PK.(04) Renamed the table @tbl_OptionalChildInfo to @tbl_tmpOptionalChildInfo
		        (	PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					PackageOptionId ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
					,PackageElementID -- Rupesh PK.(02)
				)
			 SELECT  FOCI.PaxID,FOCI.RoomNO,FOCI.Age,0,FOCI.PACKAGEID ,FOCI.PACKAGEDEPARTUREID ,FOCI.PackageOptionID ,PP.PACKAGEPRICEID 
				 ,FOCI.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FOCI.OptionDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
					ELSE
						1.0
					END
					) AS ROE ,1 ,0  
					,PO.PACKAGEELEMENTID -- Rupesh PK.(02)
		     FROM @tbl_FirstOptionalChildInfo FOCI
		     inner join Package_Price PP on FOCI.PACKAGEID =PP.PACKAGEID 
		     inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
		     INNER JOIN PACKAGE_OPTION PO ON PO.PACKAGEOPTIONID = PP.PACKAGEOPTIONID -- Rupesh PK.(02)
		     where FOCI.OptionDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE and FOCI.PackageOptionID =PP.PACKAGEOPTIONID
		     -- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FOCI.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
		END
		--Main Element	
		-->> Insert Second Child record into the temp table
		--BOC Ankita S(08)
		IF @rb_SearchbyBookDateAndOrgFlag=1
			BEGIN
		INSERT INTO @tbl_ChildInfo
				(	PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					ELEMENTID ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
				)
			SELECT FCD.ID,FCD.LogicalRoomID,FCD.ChildAge,1,FCD.PACKAGEID ,FCD.PACKAGEDEPARTUREID ,FCD.ELEMENTID ,PP.PACKAGEPRICEID
				 ,FCD.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FCD.DEPARTUREDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0	
			FROM @tblFinalChildDetails FCD
			inner join Package_Price PP on FCD.PACKAGEID =PP.PACKAGEID 
			inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
			LEFT OUTER JOIN @tbl_FirstChildInfo FC ON FC.PaxID = FCD.ID  
			WHERE FC.PaxID IS NULL and FCD.DEPARTUREDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE 
			and FCD.ELEMENTID =PP.PACKAGEELEMENTID 
			-- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
				
			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
			 AND (@rd_BOOKINGDATE between isnull(pp.BOOKFROMDATE,cast('17530101' as datetime)) and isnull(pp.BOOKTODATE,cast('99991230' as datetime)))  
			END
		--EOC Ankita S(08)
		ELSE
			BEGIN
		INSERT INTO @tbl_ChildInfo
				(	PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					ELEMENTID ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
				)
			SELECT FCD.ID,FCD.LogicalRoomID,FCD.ChildAge,1,FCD.PACKAGEID ,FCD.PACKAGEDEPARTUREID ,FCD.ELEMENTID ,PP.PACKAGEPRICEID
				 ,FCD.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FCD.DEPARTUREDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0	
			FROM @tblFinalChildDetails FCD
			inner join Package_Price PP on FCD.PACKAGEID =PP.PACKAGEID 
			inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
			LEFT OUTER JOIN @tbl_FirstChildInfo FC ON FC.PaxID = FCD.ID  
			WHERE FC.PaxID IS NULL and FCD.DEPARTUREDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE 
			and FCD.ELEMENTID =PP.PACKAGEELEMENTID 
			-- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FCD.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
				END
		--Optional Element	
		-->> Insert Second Child record into the temp table
		--BOC Ankita S(08)
		IF @rb_SearchbyBookDateAndOrgFlag=1
			BEGIN
		INSERT INTO @tbl_tmpOptionalChildInfo --Rupesh PK.(04) Renamed the table @tbl_OptionalChildInfo to @tbl_tmpOptionalChildInfo
				(	PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					PackageOptionId ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
					,PackageElementID -- Rupesh PK.(02)
				)
			SELECT FOCD.ID,FOCD.LogicalRoomID,FOCD.ChildAge,1,FOCD.PACKAGEID ,FOCD.PACKAGEDEPARTUREID ,FOCD.PackageOptionID ,PP.PACKAGEPRICEID
				 ,FOCD.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FOCD.OptionDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0	
					,PO.PACKAGEELEMENTID 
			FROM @tblFinalOptionalChildDetails FOCD
			inner join Package_Price PP on FOCD.PACKAGEID =PP.PACKAGEID 
			inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
			INNER JOIN PACKAGE_OPTION PO ON PO.PACKAGEOPTIONID = PP.PACKAGEOPTIONID -- Rupesh PK.(02)
			LEFT OUTER JOIN @tbl_FirstOptionalChildInfo FOCI ON FOCI.PaxID = FOCD.ID  
			WHERE FOCI.PaxID IS NULL and FOCD.OptionDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE 
			and FOCD.PackageOptionID  =PP.PACKAGEOPTIONID 		
			-- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)

			 AND PP.PACKAGEPRICEVALIDATED =1 AND PP.PACKAGEPRICEINTERNETAVAILABLE =1 --SNELA(07)
			 AND (@rd_BOOKINGDATE between isnull(pp.BOOKFROMDATE,cast('17530101' as datetime)) and isnull(pp.BOOKTODATE,cast('99991230' as datetime)))  
			END
		--EOC Ankita S(06)
		ELSE
			BEGIN
		INSERT INTO @tbl_tmpOptionalChildInfo --Rupesh PK.(04) Renamed the table @tbl_OptionalChildInfo to @tbl_tmpOptionalChildInfo
				(	PaxID,
					RoomNO,
					Age,
					IsAdditionalChild,
					PACKAGEID , 
					PACKAGEDEPARTUREID ,
					PackageOptionId ,
					PackagePriceId,
					DEPARTUREDATE,
					PRICEAMT, 
					ROE,
					ISCHILDSHARING,
					IsUpdated
					,PackageElementID -- Rupesh PK.(02)
				)
			SELECT FOCD.ID,FOCD.LogicalRoomID,FOCD.ChildAge,1,FOCD.PACKAGEID ,FOCD.PACKAGEDEPARTUREID ,FOCD.PackageOptionID ,PP.PACKAGEPRICEID
				 ,FOCD.DEPARTUREDATE,PP.PACKAGEPRICEAMOUNT,
				 (CASE WHEN PP.CURRENCYID <> @ri_CurrencyID THEN
						(SELECT ISNULL(EXCHANGERATEVALUE,0) FROM EXCHANGE_RATE WHERE 
						(@i_ROEBASEDONBOOKINGDATE2 =2 OR FOCD.OptionDATE BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND (@i_ROEBASEDONBOOKINGDATE2 <>2 OR GETDATE() BETWEEN EXCHANGERATESTARTDATE AND EXCHANGERATEENDDATE) 
						AND CURRENCYID = PP.CURRENCYID AND TOCURRENCYID_CURRENCYID = @ri_CurrencyID)
 					ELSE
						1.0
					END
					) AS ROE ,1 ,0	
					,PO.PACKAGEELEMENTID 
			FROM @tblFinalOptionalChildDetails FOCD
			inner join Package_Price PP on FOCD.PACKAGEID =PP.PACKAGEID 
			inner join @TMPBTPT BTPT on PP.BOOKINGTYPEID =BTPT.BOOKINGTYPEID and PP.PRICETYPEID =BTPT.PRICETYPEID
			INNER JOIN PACKAGE_OPTION PO ON PO.PACKAGEOPTIONID = PP.PACKAGEOPTIONID -- Rupesh PK.(02)
			LEFT OUTER JOIN @tbl_FirstOptionalChildInfo FOCI ON FOCI.PaxID = FOCD.ID  
			WHERE FOCI.PaxID IS NULL and FOCD.OptionDATE between PP.PACKAGEPRICEFROMDATE and PP.PACKAGEPRICETODATE 
			and FOCD.PackageOptionID  =PP.PACKAGEOPTIONID 		
			-- BOC Rupesh PK.(02)
		     AND(((PP.PACKAGEPRICEMONDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 2))
				OR ((PP.PACKAGEPRICETUESDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 3))
				OR ((PP.PACKAGEPRICEWEDNESDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 4))
				OR ((PP.PACKAGEPRICETHURSDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 5))
				OR ((PP.PACKAGEPRICEFRIDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 6))
				OR ((PP.PACKAGEPRICESATURDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 7))
				OR ((PP.PACKAGEPRICESUNDAY = 1) AND (DATEPART(DW, FOCD.DEPARTUREDATE) = 1)))
		     -- EOC Rupesh PK.(02)
			 END
			 -- BOC Rupesh PK.(05) Moved the code here
			 insert into @tbl_OptionalChildInfo (PaxID,RoomNO,Age,IsAdditionalChild,PACKAGEID ,PACKAGEDEPARTUREID ,PackageOptionId ,PackagePriceId,
			                        	DEPARTUREDATE,PRICEAMT,ROE,ISCHILDSHARING,IsUpdated,PackageElementID )
			select 	PaxID, RoomNO, Age, IsAdditionalChild,	PACKAGEID, PACKAGEDEPARTUREID ,PackageOptionId ,PackagePriceId ,
					DEPARTUREDATE ,PRICEAMT ,ROE ,ISCHILDSHARING ,IsUpdated,PackageElementID 
			from @tbl_tmpOptionalChildInfo
			order by PackageOptionID,PaxID
			 -- EOC Rupesh PK.(05)
	END
	
	/* -->> Rupesh PK.(05) moved it on top in the IF condition so that this is process is followed only when RoomList needs to be considered
	-- BOC Rupesh PK.(02)		
	INSERT INTO @tbl_ElementInfo (Age,ElementID,DepartureDate ,IsAdditionalChild)--Rupesh PK.(04)
	SELECT C.Age,
		   C.ELEMENTID,
		   C.DEPARTUREDATE,
		   C.IsAdditionalChild
	FROM @tbl_ChildInfo C
	ORDER BY RoomNO, ID 
	
	--BOC Rupesh PK.(04)
	insert into @tbl_OptionalChildInfo (PaxID,RoomNO,Age,IsAdditionalChild,PACKAGEID ,PACKAGEDEPARTUREID ,PackageOptionId ,PackagePriceId,
			                        	DEPARTUREDATE,PRICEAMT,ROE,ISCHILDSHARING,IsUpdated,PackageElementID )
		select 	PaxID, RoomNO, Age, IsAdditionalChild,	PACKAGEID, PACKAGEDEPARTUREID ,PackageOptionId ,PackagePriceId ,
				DEPARTUREDATE ,PRICEAMT ,ROE ,ISCHILDSHARING ,IsUpdated,PackageElementID 
		from @tbl_tmpOptionalChildInfo
		order by PackageOptionID,PaxID

		
		
	DECLARE @i_Seq INT, @i_PackageOptionID INT,@i_PackageElementID INT
	SELECT @i_Seq = 0, @i_PackageOptionID = 0,@i_PackageElementID=0

	UPDATE OCI
	SET OCI.SEQ = @i_Seq ,
		@i_Seq = CASE WHEN @i_PackageOptionID = OCI.PackageOptionID 
				  THEN @i_Seq + 1
				  ELSE 1
				  END,		 
		@i_PackageOptionID = OCI.PackageOptionID 
	FROM @tbl_OptionalChildInfo OCI
	
	SET @i_Seq = 0
	UPDATE EI
	SET EI.SEQ = @i_Seq ,
		@i_Seq = CASE WHEN @i_PackageElementID = EI.ElementID  
				  THEN @i_Seq + 1
				  ELSE 1
				  END,		 
		@i_PackageElementID = EI.ElementID 
	FROM @tbl_ElementInfo EI
	--EOC Rupesh PK.(04)

	UPDATE O
		SET O.IsAdditionalChild = E.IsAdditionalChild,
			O.AdditionalUpdated = 1
	FROM @tbl_OptionalChildInfo O
	INNER JOIN @tbl_ElementInfo E ON E.SEQ = O.SEQ AND --Rupesh PK.(04)
								     E.Age = O.Age AND 
									 ISNULL(E.ELEMENTID,0) = ISNULL(O.PackageElementID,0) AND
									 E.DepartureDate = O.DEPARTUREDATE 
	WHERE ISNULL(O.PackageElementID,0) > 0

	
		
	UPDATE O
		SET O.IsAdditionalChild = E.IsAdditionalChild,
			O.AdditionalUpdated = 1
	FROM @tbl_OptionalChildInfo O
	INNER JOIN @tbl_ElementInfo E ON E.Age = O.Age AND 
								     --ISNULL(E.ELEMENTID,0) = ISNULL(O.PackageElementID,0) AND -- Rupesh PK.(05)
									 E.DepartureDate = O.DEPARTUREDATE 
	WHERE O.AdditionalUpdated = 0 AND
		  ISNULL(O.PackageElementID,0) = 0 -- Rupesh PK.(05) changed the condition from >0 to =0
		  AND O.AdditionalUpdated = 0 -- Rupesh PK.(05)
	
	
		  

	

	UPDATE O
		SET O.IsAdditionalChild = E.IsAdditionalChild,
			O.AdditionalUpdated = 1
	FROM @tbl_OptionalChildInfo O
	INNER JOIN @tbl_ElementInfo E ON E.SEQ = O.SEQ AND --Rupesh PK.(04) replaced @tbl_ChildInfo with @tbl_ElementInfo
								   E.Age = O.Age
	WHERE O.AdditionalUpdated = 0


	UPDATE O
		SET O.IsAdditionalChild = 0,
			O.AdditionalUpdated = 1
	FROM @tbl_OptionalChildInfo O
	INNER JOIN @tbl_ElementInfo E ON E.Age = O.Age--Rupesh PK.(04)replaced @tbl_ChildInfo with @tbl_ElementInfo
	WHERE O.AdditionalUpdated = 0	  
	-- EOC Rupesh PK.(02)
	*/

		--Main Element	
		--FOR CHILD SHARING
		-->> If there exists a Package Child Rate (Child Band) set then pick data from 'dbo.Package_Child_Rate'
		UPDATE CI
			SET AdditionalChildAmount= (PCR.ADDITIONALPACKAGECHILDRATEAMOUNT * isnull(CI.ROE,1)),     
			IsUpdated = 1
		FROM dbo.Package_Child_Rate PCR  
		INNER JOIN @tbl_ChildInfo CI  ON PCR.PackagePriceID=CI.PackagePriceID
		WHERE CI.AGE BETWEEN PCR.PackageChildRateFromAge AND PCR.PackageChildRateToAge  
		AND CI.ISCHILDSHARING =1 and CI.IsAdditionalChild =1

		--Main Element	
		-- If NO child Band is set then fetch Prices from Child Policy
		--BOC Ankita S(08)
		IF @rb_SearchbyBookDateAndOrgFlag=1
			BEGIN
		UPDATE CI
			SET AdditionalChildAmount=  ISNULL(CI.PRICEAMT,0) * (CAB.Addi_child_sell  / 100)      
		FROM dbo.PACKAGE_PRICE SP  
		INNER JOIN dbo.CHILD_POLICY CP ON CP.CHILDPOLICYID = SP.CHILDPOLICYID     
		INNER JOIN dbo.CHILD_AGE_BAND CAB ON CAB.CHILDPOLICYID = CP.CHILDPOLICYID 
		INNER JOIN  @tbl_ChildInfo CI  ON SP.PACKAGEPRICEID=CI.PackagePriceID
	    WHERE CI.AGE BETWEEN CAB.CHILDAGEBANDFROMAGE AND CAB.CHILDAGEBANDTOAGE   
	    AND CI.ISCHILDSHARING =1 AND IsUpdated=0 and CI.IsAdditionalChild =1
		AND SP.PACKAGEPRICEVALIDATED =1 AND SP.PACKAGEPRICEINTERNETAVAILABLE =1--SNELA(07)
	    
		AND SP.PACKAGEPRICEVALIDATED =1 AND SP.PACKAGEPRICEINTERNETAVAILABLE =1--SNELA(07)
		AND (@rd_BOOKINGDATE between isnull(SP.BOOKFROMDATE,cast('17530101' as datetime)) and isnull(SP.BOOKTODATE,cast('99991230' as datetime)))  
			END
		--EOC Ankita S(08)
		ELSE
			BEGIN
		UPDATE CI
			SET AdditionalChildAmount=  ISNULL(CI.PRICEAMT,0) * (CAB.Addi_child_sell  / 100)      
		FROM dbo.PACKAGE_PRICE SP  
		INNER JOIN dbo.CHILD_POLICY CP ON CP.CHILDPOLICYID = SP.CHILDPOLICYID     
		INNER JOIN dbo.CHILD_AGE_BAND CAB ON CAB.CHILDPOLICYID = CP.CHILDPOLICYID 
		INNER JOIN  @tbl_ChildInfo CI  ON SP.PACKAGEPRICEID=CI.PackagePriceID
	    WHERE CI.AGE BETWEEN CAB.CHILDAGEBANDFROMAGE AND CAB.CHILDAGEBANDTOAGE   
	    AND CI.ISCHILDSHARING =1 AND IsUpdated=0 and CI.IsAdditionalChild =1
		END
		
		--Main Element	
		Update CI
			SET AdditionalChildAmount=  ISNULL(CI.AdditionalChildAmount,ISNULL(CI.PRICEAMT,0))
		FROM @tbl_ChildInfo CI where CI.IsAdditionalChild =1
		
		--Optional Element	
		--FOR CHILD SHARING
		-->> If there exists a Package Child Rate (Child Band) set then pick data from 'dbo.Package_Child_Rate'
		UPDATE OCI
			SET AdditionalChildAmount= (PCR.ADDITIONALPACKAGECHILDRATEAMOUNT * isnull(OCI.ROE,1)),     
			IsUpdated = 1
		FROM dbo.Package_Child_Rate PCR  
		INNER JOIN @tbl_OptionalChildInfo OCI  ON PCR.PackagePriceID=OCI.PackagePriceID
		WHERE OCI.AGE BETWEEN PCR.PackageChildRateFromAge AND PCR.PackageChildRateToAge  
		AND OCI.ISCHILDSHARING =1 and OCI.IsAdditionalChild =1
		
		--Optional Element	
		-- If NO child Band is set then fetch Prices from Child Policy
		--BOC Ankita S(08)
		IF @rb_SearchbyBookDateAndOrgFlag=1
			BEGIN
		UPDATE OCI
			SET AdditionalChildAmount=  ISNULL(OCI.PRICEAMT,0) * (CAB.Addi_child_sell / 100)      
		FROM dbo.PACKAGE_PRICE SP 
		INNER JOIN dbo.CHILD_POLICY CP ON CP.CHILDPOLICYID = SP.CHILDPOLICYID     
		INNER JOIN dbo.CHILD_AGE_BAND CAB ON CAB.CHILDPOLICYID = CP.CHILDPOLICYID 
		INNER JOIN  @tbl_OptionalChildInfo OCI  ON SP.PACKAGEPRICEID=OCI.PackagePriceID
	    WHERE OCI.AGE BETWEEN CAB.CHILDAGEBANDFROMAGE AND CAB.CHILDAGEBANDTOAGE   
	    AND OCI.ISCHILDSHARING =1 AND IsUpdated=0 and OCI.IsAdditionalChild =1
		AND SP.PACKAGEPRICEVALIDATED =1 AND SP.PACKAGEPRICEINTERNETAVAILABLE =1--SNELA(07)
	    
		AND SP.PACKAGEPRICEVALIDATED =1 AND SP.PACKAGEPRICEINTERNETAVAILABLE =1--SNELA(07)
		AND (@rd_BOOKINGDATE between isnull(SP.BOOKFROMDATE,cast('17530101' as datetime)) and isnull(SP.BOOKTODATE,cast('99991230' as datetime)))  
			END
		--EOC Ankita S(08)
		ELSE
			BEGIN
		UPDATE OCI
			SET AdditionalChildAmount=  ISNULL(OCI.PRICEAMT,0) * (CAB.Addi_child_sell / 100)      
		FROM dbo.PACKAGE_PRICE SP 
		INNER JOIN dbo.CHILD_POLICY CP ON CP.CHILDPOLICYID = SP.CHILDPOLICYID     
		INNER JOIN dbo.CHILD_AGE_BAND CAB ON CAB.CHILDPOLICYID = CP.CHILDPOLICYID 
		INNER JOIN  @tbl_OptionalChildInfo OCI  ON SP.PACKAGEPRICEID=OCI.PackagePriceID
	    WHERE OCI.AGE BETWEEN CAB.CHILDAGEBANDFROMAGE AND CAB.CHILDAGEBANDTOAGE   
	    AND OCI.ISCHILDSHARING =1 AND IsUpdated=0 and OCI.IsAdditionalChild =1
	    END
	    --Optional Element	
		Update OCI
			SET AdditionalChildAmount=  ISNULL(OCI.AdditionalChildAmount,ISNULL(OCI.PRICEAMT,0))
		FROM @tbl_OptionalChildInfo OCI where OCI.IsAdditionalChild =1
	    
			
	IF OBJECT_ID('tempdb..#tbl_ChildFinalInfo') IS NOT NULL
		BEGIN
	     insert into  #tbl_ChildFinalInfo(PaxID ,RoomNO ,Age ,IsAdditionalChild ,AdditionalChildAmount ,PACKAGEID ,PACKAGEDEPARTUREID 
										,ELEMENTID ,PackagePriceID ,DEPARTUREDATE ,PRICEAMT ,ROE ,ISCHILDSHARING ,IsUpdated,PackageOptionId,IsOptional)
			 SELECT PaxID ,RoomNO ,Age ,IsAdditionalChild ,AdditionalChildAmount ,PACKAGEID ,PACKAGEDEPARTUREID 
			,ELEMENTID ,PackagePriceID ,DEPARTUREDATE ,PRICEAMT ,ROE ,ISCHILDSHARING ,IsUpdated ,Null,0 FROM @tbl_ChildInfo
			
		insert into  #tbl_ChildFinalInfo(PaxID ,RoomNO ,Age ,IsAdditionalChild ,AdditionalChildAmount ,PACKAGEID ,PACKAGEDEPARTUREID 
										,ELEMENTID ,PackagePriceID ,DEPARTUREDATE ,PRICEAMT ,ROE ,ISCHILDSHARING ,IsUpdated,PackageOptionId,IsOptional)
			 SELECT PaxID ,RoomNO ,Age ,IsAdditionalChild ,AdditionalChildAmount ,PACKAGEID ,PACKAGEDEPARTUREID 
			,Null ,PackagePriceID ,DEPARTUREDATE ,PRICEAMT ,ROE ,ISCHILDSHARING ,IsUpdated ,PackageOptionId,1 FROM @tbl_OptionalChildInfo
			
		END

END
GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO

---------

SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

IF EXISTS (SELECT * FROM SYSOBJECTS WHERE ID = OBJECT_ID(N'[DBO].[USP_UPDATE_DELETE_PUR_MESSAGE_B2CB2B]') AND OBJECTPROPERTY(ID, N'ISPROCEDURE') = 1)
DROP PROCEDURE [DBO].[USP_UPDATE_DELETE_PUR_MESSAGE_B2CB2B]
GO
/**************************************************************************
* CREATED BY  	: RAVISH CHODANKAR
* ON	      	: 18 AUG 2015
* DESCRIPTION 	: 
*
***************************************************************************
*	WHO				WHEN			WHAT
*	-------------   -------------   --------------------------------------------------------
*	Purva(01)		31 Oct 2015		Requests go out without prices when sending multiple request with some of them ‘send with prices’ ticked. [Issue : 67110 | CR : TCASIA0012 | Client : TCAsia]
*   Khaja(02)       30 Nov 2015		Script error on confirming multiple gaps when one of the services has got a PIA raised against it. [Issue : 69784 | CR : TCASIA012 | Client : TCAsia]
*	Clerance(03)	30 Dec 2015		Performance Changes - MULTISERVICESERVICEIDS column data is moved into new table  [TCAsia-Purchasing Module]
*   Purva(04)		04 Apr 2016		Fixed internal Issue. [CR: CR205 | Client : TCAsia]
*	Sanket(05)		25 Sep 2018		Fixed Defect#96787:  Accom request messages failing because of limited messageid size. TCA use Request action with multiple services and total size of the @RVC_MESSAGEID goes more than 500 chars.	[Client: TCAsia]
*   Sainath(06)     27 Jun 2019     101856 : Gareth - R710.6 - Blank Message Status [CR : TCA-97/TCASIA012 | Client : TCAsia]
**************************************************************************/
CREATE  PROCEDURE [DBO].[USP_UPDATE_DELETE_PUR_MESSAGE_B2CB2B]
(
	@RVC_MESSAGEIDS VARCHAR(MAX),			--Purva(01) INT -> VARCHAR	--Sanket(05)
	@RI_ISUPDATED BIT	
)
AS
BEGIN
	SET NOCOUNT ON
	--BOC Purva(01)
	DECLARE @TMP_MESSAGE TABLE
	(
		TMPID INT IDENTITY(1,1),
		MESSAGEID INT
	)

	IF (@RVC_MESSAGEIDS <> '')
	BEGIN
		INSERT INTO @TMP_MESSAGE(MESSAGEID)
		SELECT DISTINCT VALUENAME
		FROM DBO.UDF_STR_LIST_TO_TABLE(@RVC_MESSAGEIDS)
	END
	--EOC Purva(01)

	IF ISNULL(@RI_ISUPDATED,0) = 1
	BEGIN
		--BOC Clerance(03)
		--UPDATE MESSAGE SET MESSAGEQUEUED = 1 WHERE MESSAGEID IN (SELECT MESSAGEID FROM @TMP_MESSAGE)  --Purva(01) = @RI_MESSAGE_ID
		UPDATE M
		SET MESSAGEQUEUED=1 
		FROM DBO.MESSAGE M INNER JOIN @TMP_MESSAGE TMP ON M.MESSAGEID=TMP.MESSAGEID
		--EOC Clerance(03)
	END
	ELSE
	BEGIN
		
		--BOC Sainath(06)
		IF NOT EXISTS(SELECT 1 FROM MESSAGE M WITH(NOLOCK) INNER JOIN @TMP_MESSAGE TMP ON TMP.MESSAGEID = M.MESSAGEID)
			RETURN 

		DELETE TMP 
		FROM @TMP_MESSAGE TMP
		INNER JOIN MESSAGE M WITH(NOLOCK) ON M.MESSAGEID = TMP.MESSAGEID
		WHERE M.MESSAGEQUEUED = 1
		--EOC Sainath(06)
		--BOC Purva(04)
		UPDATE BSPH
		SET BSPH.OLDSERVICEID = NULL
		FROM @TMP_MESSAGE TMP
			 INNER JOIN DBO.PURCHASING_SUPPLIER_MESSAGING_DATA PSMD WITH(NOLOCK) ON PSMD.MESSAGEID = TMP.MESSAGEID 			 
			 INNER JOIN DBO.PURCHASING_SUPPLIER_MESSAGING_SERVICE_DATA PSMSD WITH(NOLOCK) ON PSMSD.PURCHASINGSUPPLIERMESSAGINGDATAID = PSMD.PURCHASINGSUPPLIERMESSAGINGDATAID 			 
			 INNER JOIN DBO.BOOKED_SERVICE_PURCHASING_HISTORY BSPH WITH(NOLOCK) ON BSPH.BOOKEDSERVICEID = PSMSD.BOOKEDSERVICEID
		WHERE ISNULL(BSPH.OLDSERVICEID,0) > 0 AND PSMD.ACTIONID = 11
		--EOC Purva(04)

		DELETE FROM DBO.PURCHASING_SUPPLIER_MESSAGING_CHILD_DATA WHERE PURCHASINGSERVICEMESSAGINGDATAID IN (SELECT PURCHASINGSERVICEMESSAGINGDATAID FROM DBO.PURCHASING_SUPPLIER_MESSAGING_DATA WITH(NOLOCK)  WHERE MESSAGEID IN (SELECT MESSAGEID FROM @TMP_MESSAGE))  --Purva(01) =@RI_MESSAGE_ID) --Khaja(02)
		DELETE FROM DBO.PURCHASING_SUPPLIER_MESSAGING_DAYWISE_DATA  WHERE PURCHASINGSERVICEMESSAGINGDATAID IN (SELECT PURCHASINGSERVICEMESSAGINGDATAID FROM DBO.PURCHASING_SUPPLIER_MESSAGING_DATA  WITH(NOLOCK)  WHERE MESSAGEID IN (SELECT MESSAGEID FROM @TMP_MESSAGE))  --Purva(01) =@RI_MESSAGE_ID)
		DELETE FROM DBO.PURCHASING_SUPPLIER_MESSAGING_SERVICE_DATA WHERE PURCHASINGSERVICEMESSAGINGDATAID IN (SELECT PURCHASINGSERVICEMESSAGINGDATAID FROM DBO.PURCHASING_SUPPLIER_MESSAGING_DATA  WITH(NOLOCK)   WHERE MESSAGEID IN (SELECT MESSAGEID FROM @TMP_MESSAGE))  --Purva(01) =@RI_MESSAGE_ID)		
		DELETE FROM DBO.PURCHASING_SUPPLIER_MESSAGING_DATA WHERE MESSAGEID IN (SELECT MESSAGEID FROM @TMP_MESSAGE)  --Purva(01)  = @RI_MESSAGE_ID
		--DELETE FROM PURCHASING_SUPPLIER_MESSAGING_SERVICE_DATA WHERE PURCHASINGSERVICEMESSAGINGDATAID IN (SELECT PURCHASINGSERVICEMESSAGINGDATAID FROM PURCHASING_SUPPLIER_MESSAGING_DATA WHERE MESSAGEID IN (SELECT MESSAGEID FROM @TMP_MESSAGE))  --Purva(01) =@RI_MESSAGE_ID) --Khaja(02)
		DELETE PCSM
		FROM DBO.PURCHASING_CONSOLIDATED_SUPPLIER_MESSAGES PCSM
		INNER JOIN @TMP_MESSAGE TMP ON PCSM.MESSAGEID=TMP.MESSAGEID --Clerance(03)
		DELETE FROM DBO.MESSAGE WHERE MESSAGEID IN (SELECT MESSAGEID FROM @TMP_MESSAGE)  --Purva(01) = @RI_MESSAGE_ID
	END	
END
GO
SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO
