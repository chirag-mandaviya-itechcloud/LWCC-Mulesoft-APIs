%dw 2.0
import * from dw::core::Strings
output application/java
fun tailRecursiveSplit(str: Binary, size: Number, arr: Array<String> = []) = 
  if ( sizeOf(str) > size ) tailRecursiveSplit(last(str,sizeOf(str)-size), size, arr + first(str,size)) else (arr + str)
var textArray = if(!isEmpty(payload.'claim-object'.DT_Compensability_Comments__c)) (if(sizeOf(payload.'claim-object'.DT_Compensability_Comments__c)>=4000) tailRecursiveSplit(payload.'claim-object'.DT_Compensability_Comments__c, 4000) else [payload.'claim-object'.DT_Compensability_Comments__c]) else [""]
fun toClaimCovComments(comment) = Db::prepareStruct("PKG_DGTL_EXPRN_CLM_INTFC.CLAIM_COV_COMMENTS_REC", [
	payload.'claim-object'.Name,
	comment
	 ])
---
Db::prepareArray("PKG_DGTL_EXPRN_CLM_INTFC.CLAIM_COV_COMMENTS_TBL", 
	textArray map (item, index) -> (toClaimCovComments(item))
	)