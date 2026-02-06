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
fun deniedInd(vi) = if(!isEmpty(vi)) vi match {
	case vi if (vi == 'Denied') -> "Y"
    case vi if (vi == 'Accepted') -> "N"
    else -> null
} else null
fun nullcheck(field) = if(!isEmpty(field)) field else null 
fun mapLang(l) = if(!isEmpty(l)) l match {
    case lang if (lang == 'English') -> "eng"
    case lang if (lang == 'French') -> "fre"
    case lang if (lang == 'Spanish') -> "spa"
    case lang if (lang == 'Vietnamese') -> "vie"
    else -> null        
} else null
fun mapGender(vi) = if(!isEmpty(vi)) vi match {
	case vi if (vi == 'Male') -> "M"
    case vi if (vi == 'Female') -> "F"
    case vi if (vi == 'Unknow') -> "U"
    else -> null
} else null
fun mapStatus(vi,z) = vi match {
	case vi if (vi == 'Draft') -> "N/A"
	case vi if (vi == 'Cancelled') -> "N/A"
    case vi if (vi == 'Intake Pending') -> "J"
    case vi if (vi == 'Pending') -> "K"
    case vi if (vi == 'Closed') -> "Z"
    case vi if (vi == 'Open') -> if(z == 'Medical Only') "D" else "A"
    else -> null
}


---
Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.CLAIM_REC", 
[
	payload.'claim-object'.sfRecordId, 
	dateformat(payload.'claim-object'.Date_of_Accident__c), 
	payload.'injured-worker'[0].FirstName, 
	upper(substring(payload.'injured-worker'[0].MiddleName, 0, 1)),	// NEW bugfix/12990
	payload.'injured-worker'[0].LastName, 
	payload.'injured-worker'[0].vlocity_ins__SocialSecurityNumber__c, 
	payload.'claim-object'.Name, 
	now() as String {format: "yyyy-MM-dd hh:mm:ss"},   // payload."claim_process_date",  DB MANDATORY FIELD
	mapStatus(payload.'claim-object'.Claim_Status__c, payload.'claim-object'.ClaimType),
	dateformat(payload.'claim-object'.DT_Claim_Closure_Date__c), 	// 2nd round
	null,	// payload."bus_seq_num-TBD",
	dateformat(substring(payload.'claim-object'.ReportDate,0,10)), 
	null,	// payload."c7_recv_date-TBD",
	payload.'injured-worker'[0].MailingStreet,
	payload.'injured-worker'[0].DT_Care_Of__c,	// payload."claimant_addr2-TBD",
	payload.'injured-worker'[0].MailingCity,
	dateformat(payload.'injured-worker'[0].Birthdate),
	dateformat(payload.'injured-worker'[0].DT_Deceased_Date__c),
	payload.'injured-worker'[0].Phone,
	mapGender(payload.'injured-worker'[0].FinServ__Gender__c),
	payload.'injured-worker'[0].mailingstatecode,
	substring(payload.'injured-worker'[0].MailingPostalCode, 0, 5),
    if(!isEmpty(substring(payload.'injured-worker'[0].MailingPostalCode, 5, 10))) (
        substring(payload.'injured-worker'[0].MailingPostalCode, 5, 10)) else null, // payload."claimant_zip4",
	null,	// payload."claim_status_reason_code-TBD",
	null,	// payload."claim_unit_code-TBD",
	null,	// payload."claim_update_date-TBD",
	dateformat(payload.'claim-object'.DT_Date_disabled__c), 
	null,	// payload."eligibility_code-TBD",
	mapBool(payload.'claim-object'.DT_Pay_No_Bill__c),
	null,	// payload."eye_read_code2-TBD",
	null,	// payload."eye_read_code3-TBD",
	null,	// payload."eye_read_code4-TBD",
	null,	// payload."index_request_date-TBD",
	null,	// payload."intake_memo-TBD",
	if(!isEmpty(payload.'claim-object'.DT_Risk_Location_Name__c)) (payload.'claim-object'.DT_Risk_Location_Name__c as Number) else null,  
	payload.'claim-participant'[0].DT_Marital_status__c,
	null,	// payload."name_addr_change_date-TBD",
	null,	// payload."name_addr_user_name-TBD",
	payload.'claim-object'.DT_PolicyNumberId__c as Number,
	null,	// payload."prior_claimant_addr1-TBD",
	null,	// payload."prior_claimant_addr2-TBD",
	null,	// payload."prior_claimant_city-TBD",
	null,	// payload."prior_claimant_state-TBD",
	null,	// payload."prior_claimant_zip-TBD",
	null,	// payload."prior_claimant_zip4-TBD",	
	payload.'claim-object'.DT_Reinsurance_Number__c as Number default null,	// payload."reinsurance_num-TBD",
    dateformat(payload.'claim-object'.DT_Actual_Return_to_Work_Date__c), 
	null,	// payload."return_work_flag-TBD",
	null,	// payload."severity_code-TBD",
	null,	// payload."tpl_num-TBD",
	null,	// payload."treating_doctor_num",
	null,	// payload."treating_hospital_num",
 	if (payload.'claim-object'.DT_Claim_Completed_By__c == null and payload.'claim-object'.DT_Claim_Completed_By_Last_Name__c == null) null else (payload.'claim-object'.DT_Claim_Completed_By__c default "") ++ ' ' ++ (payload.'claim-object'.DT_Claim_Completed_By_Last_Name__c default "")  ,
	payload.'claim-object'.DT_Claim_Completed_By_phone__c,
	null,	// payload."claimant_blind_flag-TBD",
	null,	// payload."claimant_over65_flag-TBD",
	null,	// payload."spouse_blind_flag-TBD",
	null,	// payload."spouse_over65_flag-TBD",
	if(!isEmpty(payload.'claim-participant'[0].DT_Dependent_Children__c)) payload.'claim-participant'[0].DT_Dependent_Children__c as Number else null,
	null,	// payload."num_oth_dependents-TBD",
	payload.'claim-participant'[0].DT_Salary_Continued__c,
    dateformat(payload.'claim-participant'[0].DT_Last_date_worked__c), 
	null,	// payload."enter_user_name",  NOT SFDC MAPPED
	null,	// payload."claim_enter_date",
	null,	// payload."update_user_name", NOT SFDC MAPPED
	null,	// payload."dci_report_mon",
	null,	// payload."dci_report_day",
	null,	// payload."dci_report_yyyy",
	null,	// payload."dci_status_code",
	null,	// payload."max_med_improve_date",
	payload.'claim-object'.DT_Jurisdiction_State__c,  
	if(payload.'injured-worker'[0].MailingCountry == 'United States') "US" else "XX", // Mapping country only for US  - payload.'claim-object'.DT_Country__c
	null,	// payload."prior_claimant_country", 
    payload.'claim-participant'[0].DT_At_same_wage__c,   
	payload.'injured-worker'[0].DT_Race__c,
	null,	// payload."prior_claimant_county",   
	payload.'claim-participant'[0].DT_County__c,
	payload.'claim-object'.DT_Reporting_Mechanism__c,	
	payload.'claim-object'.Manual_Owner_Assigned_Alias__c,
	null,	// payload."owcp_num",
	null,	// payload."first_report_sent_date", 
	substring(payload.'claim-object'.DT_Injury_Type__c,0,2),
	null,	// payload."recovery_unit_code",
	null,	// payload."recovery_assign_date",
	null,	// payload."plaintiff_atty_num",
	null,	// payload."recovery_status_code",
	null,	// payload."recovery_status_date",
	null,	// payload."recovery_update_user",
	null,	// payload."patient_advocate_code",
	null,	// payload."treating_doctor_seq",
	null,	// payload."treating_hospital_seq",
	null,	// payload."case_manager_code",
	null,	// payload."case_manager_status_code",
	null,	// payload."pa_status_code",
	null,	// payload."pa_status_date",
	null,	// payload."case_manager_status_date",
	payload.'claim-object'.DT_Drug_Screen__c,	// 2nd round
	null,	// payload."team_number",
	null,	// payload."upd_flag",
	payload.'claim-object'.DT_Group_Code__c,	// payload."triage_code",
	null,	// payload."defense_atty_num",
	null,	// payload."e1_loc_seq_num",
	payload.'claim-object'.DT_Late_Reporting_Reason__c,		
	null,	// payload."sif_unit_code",
	null,	// payload."sif_status_code",
	null,	// payload."sif_status_date",
	null,	// payload."tpl_unit_code",
	null,	// payload."tpl_status_code",
	null,	// payload."tpl_status_date",
	null,	// payload."schi_ind",
	mapBool(payload.'claim-object'.DT_Restricted_Claim__c),		
	null,	// payload."drivers_license",
	null,	// payload."height_feet",
	null,	// payload."height_inches",
	null,	// payload."weight",
	null,	// payload."hair_color",
	null,	// payload."eye_color",
	null,	// payload."other_descr",
	null,	// payload."education",
	null,	// payload."multi_ind",
	null,	// payload."el_claim_flag",
	null,	// payload."plcy_id",
	null,	// payload."e1_addr_type",
	null,	// payload."ocm_ind",
	null,	// payload."plaintiff_atty_eff_date",
	null,	// payload."plaintiff_atty_end_date",
	null,	// payload."rx_sev_ind",
	null,	// payload."rx_sev_date",
	null,	// payload."pay_no_bills_flag",
	dateformat(payload.'claim-object'.DT_Pay_no_bill_On_Or_after_date__c),	// 2nd round
	null,	// payload."pay_no_bill_from_date",
	null,	// payload."pay_no_bill_to_date",
	null,	// payload."no_pay_reason",
	null,	// payload."serious_acdn_clm_ind",
	null,	// payload."mdcr_elig_chk",
	null,	// payload."unable_to_confirm_ssn",
	null,	// payload."unable_to_confirm_ssn_rsn",
	mapBool(payload.'injured-worker'[0].DT_Date_of_Birth_Not_Available__c),	// payload."claimant_dob_not_available",
	null,	// payload."rpt_mdcr_elig_rsn",
	null,	// payload."intake_acc_descr",
	null,	// payload."cali_saints_flag",
	null,	// payload."icr_rvw_comp_ind",
	null,	// payload."icr_rvw_comp_ind_user",
	null,	// payload."icr_rvw_comp_ind_date",
	null,	// payload."index_upd_date",
	null,	// payload."last_index_plcy",
	null,	// payload."last_index_acc_dt",
    payload.'claim-participant'[0].DT_Physical_restriction__c,
	null,	// payload."released_rtw_date",
	payload.'claim-participant'[0].DT_Days_worked_Per_week__c,	
	payload.'claim-object'.DT_Claim_Completed_By_email__c,		
	payload.'claim-object'.DT_Point_of_Contact_Last_Name__c,
	payload.'claim-object'.DT_Point_of_Contact_Phone__c,
	payload.'claim-object'.DT_Point_of_Contact_Email__c,
	null,	// payload."sif_num", 
	payload.'claim-object'.DT_Denial_Reason_Type__c,
	substring(payload.'claim-object'.DT_Denial_Reason_Detail__c,1,2),
	null,	// payload."juris_cnum",
	dateformat(payload.'claim-object'.DT_Denial_Date__c),	// payload."froi_denial_date",
	null,	// payload."froi_trnsctn_typ", 
    dateformat(payload.'claim-object'.DT_Initial_Actual_RTW_Date__c),
    dateformat(payload.'claim-object'.DT_Initial_Released_to_RTW__c),
	null,	// payload."froi_update_date",
	null,	// payload."init_act_rtw_enter_date",
	null,	// payload."init_rel_rtw_enter_date",	
	null,	// payload."fraud_non_comp_code",
	payload.'injured-worker'[0].Email,
	null,	// payload."flag_7c_origin",
	null,	// payload."alt_phone",	
	null,	// payload."alt_phone_type",
	null,	// payload."alt_phone_update_date",
	payload.'injured-worker'[0].OtherPhone,
	null,	// payload."claimant_phone_update_date",
	payload.'injured-worker'[0].MobilePhone,
	null,	// payload."cell_phone_update_date",
	mapLang(payload.'injured-worker'[0].FinServ__PrimaryLanguage__c),
	payload.'claim-object'.DT_Point_of_Contact_Name__c,	// payload."contact_first_name",
	null,	// payload."contact_text_flag",
	mapYN(payload.'claim-object'.DT_Aware_of_a_lawsuit_being_filed__c),
	null,	// payload."mep_eligible_ind",	
	null,	// payload."vpay_member_id",
	null,	// payload."mep_ind_update_date",
	null,	// payload."mep_ind_update_user",
	null,	// payload."rfe_ind",	
	null,	// payload."rfe_ind_update_date",
	null,	// payload."rfe_ind_update_user",
	null,	// payload."not_elig_elec_pymnt_ind",
	null,	// payload."not_elig_update_date",
	null,	// payload."not_elig_update_user",
	deniedInd(payload.'claim-object'.DT_Compensability_Decision__c),	// payload."denied_ind",
	null,	// payload."tpa_ind",
	null,	// payload."tpa_cnum",
	payload.'claim-object'.DT_Compensability_Decision__c,	// new 2nd round
	payload.'claim-object'.DT_Accident_Details__c, // new 2nd round
	payload.'claim-object'.DT_Wages__c,  // new 2nd round
	payload.'claim-object'.DT_Claim_Flags__c,	// new 2nd round
	mapBool(payload.'claim-object'.DT_Minor_Automated_Claim__c),		// minor_mo_ind
	payload.'claim-object'.DT_Risk_Alerts__c,
    payload.'claim-object'.DT_Risk_Alert_Comments__c,
    dateformat(payload.'claim-object'.DT_Compensability_Decision_Date__c),
    payload.'injured-worker'[0].DT_Medicare_Eligibility__c,
    payload.'claim-object'.DT_No_Medical_Paid__c,
    dateformat(payload.'claim-object'.DT_OWC_DOL_Approval_Date__c),    
    dateformat(payload.'claim-object'.DT_Last_Reinsurance_Report_Date__c)
    
]
)