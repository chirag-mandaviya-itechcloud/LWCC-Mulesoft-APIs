%dw 2.0
output application/java
---
Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.CLMNT_INIT_CONTACT_REC", [
	payload.'claim-object'.Name, 
	payload.'injured-worker'[0].vlocity_ins__DriversLicenseNumber__c, 
	payload.'injured-worker'[0].DT_Education_Code__c, 
	payload.'injured-worker'[0].DT_Eye_Color__c, 
	payload.'injured-worker'[0].DT_Hair_Color__c, 
	payload.'injured-worker'[0].DT_IW_Hobbies__c, 
	payload.'injured-worker'[0].DT_Height_ft__c, 
	payload.'injured-worker'[0].DT_Height_Inch__c, 	
	payload.'injured-worker'[0].DT_Weight_lbs__c,
	payload.'claim-participant'[0].DT_Vehicle_Description__c,
	payload.'claim-participant'[0].DT_Marital_status__c,
	payload.'claim-participant'[0].DT_Dependent_Child_Description__c
])