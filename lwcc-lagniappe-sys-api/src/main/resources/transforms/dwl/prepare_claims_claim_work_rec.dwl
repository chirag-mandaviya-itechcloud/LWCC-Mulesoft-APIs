%dw 2.0
output application/java
fun dateformat(d) = if(!isEmpty(d)) d as String {format: "yyyy-MM-dd"} ++ " 00:00:00" else null
fun mapBool(vi) = if(!isEmpty(vi)) vi match {
	case vi if (vi) -> "Y"
    case vi if (!vi) -> "N"
    else -> null
} else null
/*fun wageFrequency(vi) = if(!isEmpty(vi)) vi match {
	case vi if (vi == 'Hourly') -> "H"
    case vi if (vi == 'Daily') -> "D"
    case vi if (vi == 'Weekly') -> "W"
	case vi if (vi == 'Monthly') -> "M"
    case vi if (vi == 'Annually') -> "A"
    case vi if (vi == 'Other') -> "O"    
    else -> null
} else null*/
---
Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.CLAIM_WORK_REC", [
	null, 	// payload."avg_hours_4_weeks_prior_acc"
	null, 	// payload."certificate_num"
	payload.'claim-object'.Name,
	null, 	// payload."claimant_occupation"
	null, 	// payload."claimant_regular_dept"
	dateformat(payload.'claim-participant'[0].DT_Date_hired__c), 
	null, 	// payload."days_worked_prior_acc"
	payload.'claim-object'.DT_Employment_Status__c, 
	null, 	// payload."dci_status_code"
	null, 	// payload."employer_aware_injury_flag"
	dateformat(payload.'claim-participant'[0].DT_Date_employer_notified__c), 
	null, 	// payload."gross_earnings_pd_before_acc"
	null, 	// payload."hours_worked_last_4_weeks"
	null, 	// payload."individ_notified"
	null, 	// payload."last_day_paid"
	null, 	// payload."length_current_job"
	payload.'claim-object'.DT_Class_Code_Name__c, 	// payload."manual_class_num"
	payload.'claim-object'.DT_Manual_Class_Type_Code__c, 	// payload."manual_class_type_code"
	payload.'claim-participant'[0].DT_Occupation__c, 
	null, 	// payload."officer_partner_flag"
	payload.'claim-participant'[0].DT_Full_pay_on_injury_date__c, 
	null, 	// payload."state_where_hired"
	payload.'claim-participant'[0].DT_Wage_rate__c, 
	payload.'claim-object'.DT_Pay_Type__c, 	// payload."wage_rate_code"
	null, 	// payload."wage_rate_oth_descr"
	null, 	// payload."wks_wrkd_prior_acc_gt_26_ind"
	null 	// payload."year_hired"																			
])