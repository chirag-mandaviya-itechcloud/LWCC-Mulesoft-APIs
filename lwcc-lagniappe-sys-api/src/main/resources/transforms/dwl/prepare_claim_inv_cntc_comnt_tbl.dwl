%dw 2.0
import * from dw::core::Strings
output application/java
fun tailRecursiveSplit(str: Binary, size: Number, arr: Array<String> = []) = 
  if ( sizeOf(str) > size ) tailRecursiveSplit(last(str,sizeOf(str)-size), size, arr + first(str,size)) else (arr + str)
var commentArray = if(!isEmpty(payload.resultComments)) (if(sizeOf(payload.resultComments)>=4000) tailRecursiveSplit(payload.resultComments,4000) else [payload.resultComments]) else [null]
fun toClaimContactComment(comment) = Db::prepareStruct("PKG_DGTL_CLM_INVSTG_INTFC.CLM_CNTC_COMNT_REC", [
	payload.claimNumber,
	comment
	 ])
---
Db::prepareArray("PKG_DGTL_CLM_INVSTG_INTFC.CLM_CNTC_COMNT_TBL", 
	commentArray map (item, index) -> (toClaimContactComment(item))
	)
