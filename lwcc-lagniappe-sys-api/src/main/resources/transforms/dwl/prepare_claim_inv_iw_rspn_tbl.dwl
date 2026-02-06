%dw 2.0
output application/java
fun mapYN(vi) = if(!isEmpty(vi)) vi match {
	case vi if (vi == 'Yes') -> "Y"
    case vi if (vi == 'No') -> "N"
    else -> null
} else null
var res1 = Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INV_IW_RSPN_REC", [
		payload.claimNumber,
		payload.iwis1,
		1 as Number
	])
var res2 = Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INV_IW_RSPN_REC", [
		payload.claimNumber,
		payload.iwis2,
		2 as Number
	])
var res3 = Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INV_IW_RSPN_REC", [
		payload.claimNumber,
		payload.iwis3,
		3 as Number
	])
var res4 = Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INV_IW_RSPN_REC", [
		payload.claimNumber,
		mapYN(payload.iwis4),
		4 as Number
	])		
---
Db::prepareArray("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INV_IW_RSPN_TBL", [res1,res2,res3,res4])
