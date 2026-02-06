%dw 2.0
output application/java
fun mapYN(vi) = if(!isEmpty(vi)) vi match {
	case vi if (vi == 'Yes') -> "Y"
    case vi if (vi == 'No') -> "N"
    else -> null
} else null
---
Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INV_IW_REC", [
	payload.claimNumber,
	mapYN(payload.rsTaken),
	payload.resultCode,
	payload.resultComments,
	payload.othrHltPrbl,
	payload.totalIwisScore
])