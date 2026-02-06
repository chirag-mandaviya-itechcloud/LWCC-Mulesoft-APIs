%dw 2.0
output application/json
---

{
  name: payload."Name"[0] as String default null,
  id: payload.Id[0],
  claimName: payload."DT_Claim__r".Name[0],
  dtRelationship: payload."DT_Relationship__c"[0] as String default null,
  dtPayeeStatus: payload."DT_Payee_Status__c"[0] as String default null,
  dtPayeeName: payload."DT_Payee_Name__c"[0] as String default null,
  dtAddress1: payload."DT_Address_1__c"[0] as String default null,
  dtAddress2: payload."DT_Address_2__c"[0] as String default null,
  dtCity: payload."DT_City__c"[0] as String default null,
  dtState: payload."DT_State__c"[0] as String default null,
  dtZip: payload."DT_Zip__c"[0] as String default null,
  dtPhone:payload."DT_Phone__c"[0] as String default null,
  dtExt: payload."DT_Ext__c"[0] as String default null,
  dtCountry:payload."DT_Country__c"[0] as String default null,
  dtSupportAmount: payload.DT_Support_Amount__c[0] as String default null,
  dtEnrollForAutomaticPayment:payload."DT_Enroll_for_Automatic_Payment__c"[0] as String default null,
  dtElectronicPayment:  payload."DT_Electronic_Payment__c"[0] as String default null,
  dtNotEligibleForElectronicPayments:  payload."DT_Not_eligible_for_electronic_payments__c"[0] as String default null,
  dtMobilePhone: payload.DT_Mobile_Phone__c[0] as String default null,
  dtEmail: payload.DT_Email__c[0] as String default null
}
 