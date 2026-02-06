%dw 2.0
output application/java
fun dateformat(d) = if(!isEmpty(d)) d as String {format: "yyyy-MM-dd"} ++ " 00:00:00" else null
---
Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INV_IW_FOL_UP_REC", [
	payload.claimNumber,
	payload.treatmentPlan,
	dateformat(payload.nextOfficeVisit),
	payload.condition,
	dateformat(payload.rtwIndication)
])