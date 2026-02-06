%dw 2.0
output application/java
fun mapInjLoc(s) = if(!isEmpty(s)) s match {
    case side if (side == 'Index Finger or First Toe') -> "1"
    case side if (side == 'Middle Finger or Second Toe') -> "2"
    case side if (side == 'Ring Finger or Third Toe') -> "3"
    case side if (side == 'Little Finger or Fourth (Little) Toe') -> "4"
    else -> null
} else null
fun mapSide(s) = if(!isEmpty(s)) s match {
    case side if (side == 'Left') -> "L"
    case side if (side == 'Right') -> "R"
    case side if (side == 'Bilateral') -> "B"
    else -> null
} else null
fun toInjuryRec(injury) = Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.INJURY_REC", [
        payload.'claim-object'.Name,
        mapInjLoc(injury.DT_Finger_toe_injury_location__c),
        null,         // inj_cd_updt
        injury.DT_Body_Part_Code__c,
        null,         // injury_sev_code
        mapSide(injury.DT_Side__c),         // injury_side_code
        payload."injury-details"[0].Id //salesforce_record_id
         ])
---
Db::prepareArray("PKG_DGTL_EXPRN_CLM_INTFC.INJURY_TBL", payload.'injury-details' map (item, index) ->
	( toInjuryRec(item) )
)