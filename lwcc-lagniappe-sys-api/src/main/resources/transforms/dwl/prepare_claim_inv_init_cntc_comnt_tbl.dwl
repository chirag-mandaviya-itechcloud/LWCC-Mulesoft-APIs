%dw 2.0
import * from dw::core::Strings
output application/java
fun tailRecursiveSplit(str: Binary, size: Number, arr: Array<String> = []) = 
  if ( sizeOf(str) > size ) tailRecursiveSplit(last(str,sizeOf(str)-size), size, arr + first(str,size)) else (arr + str)
var commentInitArray = if(!isEmpty(payload.comments)) (if(sizeOf(payload.comments)>=4000) tailRecursiveSplit(payload.comments,4000) else [payload.comments]) else [null]
fun toClaimInitialComment(comment) = Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INIT_CNTC_COMNT_REC", [
	payload.claimNumber,
	comment
	 ])
---
Db::prepareArray("PKG_DGTL_CLM_INVSTG_INTFC.CLM_INIT_CNTC_COMNT_TBL", 
	commentInitArray map (item, index) -> (toClaimInitialComment(item))
	)
