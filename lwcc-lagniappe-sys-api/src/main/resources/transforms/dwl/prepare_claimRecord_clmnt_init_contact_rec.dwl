%dw 2.0
output application/java
---
Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.CLMNT_INIT_CONTACT_REC", [
	payload.'claim-object'.Name, 
	payload.'injured-worker'.vlocity_ins__DriversLicenseNumber__c, 
	payload.'injured-worker'.DT_Education_Code__c, 
	payload.'injured-worker'.DT_Eye_Color__c, 
	payload.'injured-worker'.DT_Hair_Color__c, 
	payload.'injured-worker'.DT_IW_Hobbies__c, 
	payload.'injured-worker'.DT_Height_ft__c, 
	payload.'injured-worker'.DT_Height_Inch__c, 	
	payload.'injured-worker'.DT_Weight_lbs__c,
	null,
	null,
	null
])