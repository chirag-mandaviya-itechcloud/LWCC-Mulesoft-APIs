%dw 2.0
import * from dw::util::Values
output application/json

fun convertToString(value) =
  if (value is Object) 
    value mapObject ((value, key) -> (key): convertToString(value))
  else if (value is Array) 
    value map ((item) -> convertToString(item))
  else 
    if (value == null) null else value as String

    
---
{
	"benefits": convertToString(vars.getBenefit),
	"claims": convertToString(vars.getClaims.'claim-object') default [], 
	"payees": convertToString(vars.getPayees update "id" with vars.claimPayeeRecordId)	
}