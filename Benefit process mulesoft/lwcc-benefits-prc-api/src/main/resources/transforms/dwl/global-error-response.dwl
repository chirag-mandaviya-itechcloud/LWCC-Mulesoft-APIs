
%dw 2.0
output application/json
---
{
	"errorType": (error.errorType.identifier) as String  default "FAILURE", 
 	"errorCode":  (error.errorMessage.attributes.statusCode)  default 500,
  	"errorMessage":  error.errorMessage.payload.message  default error.description,
  	"transactionId": vars.correlationId
}