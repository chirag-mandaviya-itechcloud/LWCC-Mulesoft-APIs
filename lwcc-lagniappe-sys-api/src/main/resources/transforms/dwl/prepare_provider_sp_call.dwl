%dw 2.0
output application/java
fun dateformat(d: DateTime) = d as String {format: "yyyy-MM-dd HH:mm:ss"} 
---
Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.PROVIDER_REC", [
	payload.operation, 
	payload.dtStatus, 
	payload.lgappClaimNum, 
	payload.individualVendorNum, 
	payload.individualVendorSeq, 
	if (payload.effectiveDate != null) dateformat(payload.effectiveDate >> "CST") else null, 
	if (payload.expirationDate != null) (dateformat(payload.expirationDate >> "CST")) else null, 
	payload.lastModifiedById, 
	if(payload.lastModifiedDate != null) dateformat(payload.lastModifiedDate >> "CST") else dateformat(now() >> "CST"),  
	if (payload.copDate != null) (dateformat(payload.copDate >> "CST")) else null, 
	payload.sfRecordId
])