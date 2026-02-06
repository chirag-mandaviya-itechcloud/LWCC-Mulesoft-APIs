%dw 2.0
output application/java
fun mapBool(vi) = if(!isEmpty(vi)) vi match {
	case vi if (vi) -> "Y"
    case vi if (!vi) -> "N"
    else -> null
} else null
fun mapYN(vi) = if(!isEmpty(vi)) vi match {
	case vi if (vi == 'Yes') -> "Y"
    case vi if (vi == 'No') -> "N"
    else -> null
} else null
---
Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INV_PLCY_HLDR_FOLUP_REC", [
	payload.claimNumber,
	payload.contactPhone,
	mapBool(payload.contactTextFlag),
	payload.phEmailAddr,
	payload.contactPosition,
	mapYN(payload.positionRemaining),
	mapYN(payload.transDutyInd)
])