%dw 2.0
output application/java
fun dateformat(d: DateTime) = d as String {format: "yyyy-MM-dd HH:mm:ss"}
---
Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.BODY_PART_REC", [
	payload.operation, 
	payload.dtStatus, 
	payload.lgappClaimNum, 
	payload.bodyPartCode, 
	payload.dtMedicareRank, 
	payload.side, 
	payload.sfRecordId, 
	payload.lastModifiedById, 
	dateformat(payload.lastModifiedDate >> "CST")
])