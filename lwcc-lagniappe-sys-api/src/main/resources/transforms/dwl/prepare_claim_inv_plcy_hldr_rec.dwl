%dw 2.0
output application/java
fun dateformat(d) = if(!isEmpty(d)) d as String {format: "yyyy-MM-dd"} ++ " 00:00:00" else null
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
Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INV_PLCY_HLDR_REC", [
	payload.claimNumber,
	payload.contactPhone,
	mapBool(payload.contactTextFlag),
	payload.phEmailAddr,
	payload.contactPosition,
	payload.jobTitle,
	payload.employType,	// trans on proc api
	payload.payType,	
	payload.methodOfPayCode,  // trans on proc api
	null, //payload.wageRate,
	mapYN(payload.rtwInd),
	dateformat(payload.returnWorkDate),
	mapYN(payload.witnessInd),
	payload.rptTo,
	mapYN(payload.suprFlg),
	payload.suprNmPhn,   // sup name+phone
	payload.supEmailAddr,
	payload.vrfyAcdnFct,
	payload.jobSiteLoc,
	payload.onJobSite,
	payload.jobDty,
	payload.regJobDty,
	mapYN(payload.regJobDtyFlg),
	mapYN(payload.tplInd),
	payload.tplReason,
	mapYN(payload.drugPlcy),
	payload.workActionExpl,
	mapYN(payload.transDutyInd),
	mapYN(payload.sifOnFileInd),
	mapYN(payload.priorConditionInd),
	payload.priorConditions,
	payload.physician,
	mapYN(payload.choiceInd),
	dateformat(payload.c1RecvDate),
	dateformat(payload.lastWorkdate),
	dateformat(payload.disableDate),
	payload.drugTestingCode,  // trans on proc api
	dateformat(payload.dateHired),
	payload.policyHolderFirstName,
	payload.policyHolderLastName
])
