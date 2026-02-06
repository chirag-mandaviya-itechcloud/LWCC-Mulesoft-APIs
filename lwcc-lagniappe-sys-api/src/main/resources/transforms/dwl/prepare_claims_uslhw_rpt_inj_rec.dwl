%dw 2.0
output application/java
fun dateformat(d) = if(!isEmpty(d)) d as String {format: "yyyy-MM-dd"} ++ " 00:00:00" else null
var daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
fun days(inputString) = flatten(daysOfWeek map ((day) ->
  if(inputString contains day)
    "Y"
  else
    "N"
)) joinBy ""
---
Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.USLHW_RPT_INJ_REC", [
	dateformat(payload.'claim-object'.DT_Authorization_date__c),
	null, //auth_individual_signature
	if(!isEmpty(payload.'claim-object'.DT_Class_Code_Name__c)) payload.'claim-object'.DT_Class_Code_Name__c as Number else null,
	null, //created_by
	null, //created_on	
	payload.'claim-object'.DT_Emp_doing_usual_work__c,
	payload.'claim-object'.DT_returned_to_work_hour__c,
	payload.'claim-object'.DT_Stop_work_immediately__c,
	if(!isEmpty(payload.'claim-object'.DT_Days_usually_worked__c)) days(payload.'claim-object'.DT_Days_usually_worked__c)[5] as String else null,
	if(!isEmpty(payload.'claim-object'.DT_Days_usually_worked__c)) days(payload.'claim-object'.DT_Days_usually_worked__c)[1] as String else null,
	if(!isEmpty(payload.'claim-object'.DT_Days_usually_worked__c)) days(payload.'claim-object'.DT_Days_usually_worked__c)[6] as String else null,
	if(!isEmpty(payload.'claim-object'.DT_Days_usually_worked__c)) days(payload.'claim-object'.DT_Days_usually_worked__c)[0] as String else null,
	if(!isEmpty(payload.'claim-object'.DT_Days_usually_worked__c)) days(payload.'claim-object'.DT_Days_usually_worked__c)[4] as String else null,
	if(!isEmpty(payload.'claim-object'.DT_Days_usually_worked__c)) days(payload.'claim-object'.DT_Days_usually_worked__c)[2] as String else null,
	if(!isEmpty(payload.'claim-object'.DT_Days_usually_worked__c)) days(payload.'claim-object'.DT_Days_usually_worked__c)[3] as String else null,
	payload.'claim-object'.DT_First_physician_chosen_by_emp__c,
	payload.'claim-object'.DT_How_Emp_learn_accident__c,
	null, //how_knowledge_gained2
	payload.'claim-object'.DT_Location__c,
	payload.'claim-object'.DT_Loss_of_time_beyond_acc__c,
	payload.'claim-object'.DT_Federal_Act__c,
	null, //ins_carr_notified_ind
	payload.'claim-object'.DT_Last_paid_hour__c,
	null, //last_mod_by
	null, //last_mod_on
	payload.'claim-object'.DT_Med_attention_authorized__c,
	dateformat(payload.'claim-object'.DT_Date_first_lost_time__c),
	payload.'claim-object'.DT_Date_first_lost_hour__c,
	dateformat(payload.'claim-object'.DT_Last_day_paid__c)
	])