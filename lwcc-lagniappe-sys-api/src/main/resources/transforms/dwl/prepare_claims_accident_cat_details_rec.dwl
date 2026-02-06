%dw 2.0
output application/java
---
Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.ACCIDENT_CAT_DETAILS_REC", [
	payload.'claim-object'.DT_Claim_involves_the_following__c, 
	payload.'claim-object'.Name
 	])