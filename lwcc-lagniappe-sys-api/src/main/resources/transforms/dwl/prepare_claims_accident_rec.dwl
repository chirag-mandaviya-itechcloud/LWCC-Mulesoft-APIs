%dw 2.0
import * from dw::core::Strings
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
fun mapWhere(vi) = if(!isEmpty(vi)) vi match {
	case vi if (vi == 'Employer\'s Premise') -> "E"
    case vi if (vi == 'Injured Worker\'s Residence') -> "R"
    case vi if (vi == 'Other') -> "X"    
    else -> null
} else null
---
Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.ACCIDENT_REC", [
	payload.'claim-object'.Name, 
	payload.'claim-object'.ClaimType,
	payload.'claim-object'.DT_Cause_of_Accident_Code__c,
	null, 	// payload."accident_code",
	if(!isEmpty(payload.'claim-object'.DT_What_was_employee_doing__c)) substring((payload.'claim-object'.DT_What_was_employee_doing__c),0,60) else null,
	if(!isEmpty(payload.'claim-object'.DT_What_was_employee_doing__c) and sizeOf(payload.'claim-object'.DT_What_was_employee_doing__c) > 60) substring((payload.'claim-object'.DT_What_was_employee_doing__c),60,120) else null,
	if(!isEmpty(payload.'claim-object'.DT_What_was_employee_doing__c) and sizeOf(payload.'claim-object'.DT_What_was_employee_doing__c) > 120) substring((payload.'claim-object'.DT_What_was_employee_doing__c),120,180) else null,
	if(!isEmpty(payload.'claim-object'.DT_What_was_employee_doing__c) and sizeOf(payload.'claim-object'.DT_What_was_employee_doing__c) > 180) substring((payload.'claim-object'.DT_What_was_employee_doing__c),180,240) else null,
	if(!isEmpty(payload.'injury-details'[0].DT_How_did_injury_occur__c)) substring((payload.'injury-details'[0].DT_How_did_injury_occur__c),0,60) else null,
	if(!isEmpty(payload.'injury-details'[0].DT_How_did_injury_occur__c) and sizeOf(payload.'injury-details'[0].DT_How_did_injury_occur__c) > 60) substring((payload.'injury-details'[0].DT_How_did_injury_occur__c),60,120) else null,
	if(!isEmpty(payload.'injury-details'[0].DT_How_did_injury_occur__c) and sizeOf(payload.'injury-details'[0].DT_How_did_injury_occur__c) > 120) substring((payload.'injury-details'[0].DT_How_did_injury_occur__c),120,180) else null,
	if(!isEmpty(payload.'injury-details'[0].DT_How_did_injury_occur__c) and sizeOf(payload.'injury-details'[0].DT_How_did_injury_occur__c) > 180) substring((payload.'injury-details'[0].DT_How_did_injury_occur__c),180,240) else null, 
	payload.'claim-object'.DT_Nature_of_Accident_Code__c,	
	payload.'claim-object'.DT_Accident_Time__c,
	null, 	// payload."acc_day_start_work_time"
	null, 	// payload."acc_on_premises_flag"
	null, 	// payload."injury_occupation" 
	payload.'claim-object'.DT_Primary_Accident_Location__c,
	null, 	// payload."safety_appl_prov_flag"
	null, 	// payload."safety_appl_used_flag" 
	payload.'claim-object'.DT_Parish__c, 
	mapBool((payload."claim-object".DT_Intial_Treatment__c splitBy  ";") contains "Hospitalized > 24 hours" ),
	null, 	// payload."out_patient_flag"
	null, 	// payload."emerg_room_flag"
	null, 	// payload."in_house_treatment_flag"
	null, 	// payload."first_aid_flag"
	payload.'claim-object'.DT_Witness__c,	// 2nd round
	null, 	// payload."witness_addr1"
	null, 	// payload."witness_addr2"
	null, 	// payload."witness_city"
	null, 	// payload."witness_state"
	null, 	// payload."witness_zip"
	null, 	// payload."witness_zip4"
	null, 	// payload."witness_phone"  
	payload.'claim-object'.DT_Accident_Zip__c,																
	null, 	// payload."dci_loss_coverage_code"
	null, 	// payload."surgery_ind"
	payload.'claim-object'.DT_Accident_State__c,
	null, 	// payload."mechanical_defect_ind"
	null, 	// payload."unsafe_act_ind"
	null, 	// payload."accident_source_code"
	null, 	// payload."event_type_code"
	null, 	// payload."head_injury_ind"
	null, 	// payload."burns_2_3_ind"
	null, 	// payload."broken_bone_ind"
	null, 	// payload."back_ems_ind"
	null, 	// payload."back_with_prior_ind"
	mapYN(payload.'claim-object'.DT_Questionable_claim__c), 
	null, 	// payload."intox_ind"
	null, 	// payload."field_invest_ind"
	null, 	// payload."field_invest_comp_date"
	null, 	// payload."field_invest_waive_ind"
	null, 	// payload."field_invest_waive_reason"
	null, 	// payload."field_invest_assigned"
	null, 	// payload."fi_comp_code"
	null, 	// payload."fi_contact"
	null, 	// payload."fi_location"
	null, 	// payload."fi_enter_user"
	null, 	// payload."fi_enter_date"
	null, 	// payload."fi_comp_oth"
	null, 	// payload."fi_rep_spec"			
	null, 	// payload."acc_source_text"
	null, 	// payload."work_process_text"
	null, 	// payload."safeguard_provided_ind"
	null, 	// payload."safeguard_used_ind"
	mapBool((payload."claim-object".DT_Intial_Treatment__c splitBy  ";") contains "No medical treatment" ),
	mapBool((payload."claim-object".DT_Intial_Treatment__c splitBy  ";") contains "Minor (first aid)" ),
	mapBool((payload."claim-object".DT_Intial_Treatment__c splitBy  ";") contains "Minor (clinic)" ),
	mapBool((payload."claim-object".DT_Intial_Treatment__c splitBy  ";") contains "Emergency care" ), 
	mapBool((payload."claim-object".DT_Intial_Treatment__c splitBy  ";") contains "Future Major Medical / Lost Time anticipated" ), 
	mapWhere(payload.'claim-object'.DT_Where_did_accident_happen__c),
	null, 	// payload."death_ind"
	null, 	// payload."brain_inj_ind"
	null, 	// payload."spinal_inj_ind"
	null, 	// payload."amputation_ind"
	null, 	// payload."burns_ind"
	null, 	// payload."multi_inj_ind"
	mapBool(payload.'claim-object'.DT_Is_CAT__c), 	// payload."cat_ind"
	payload.'claim-object'.DT_Accident_Description__c, 	
	payload.'claim-object'.DT_Questionable_claim_explanation__c
	])