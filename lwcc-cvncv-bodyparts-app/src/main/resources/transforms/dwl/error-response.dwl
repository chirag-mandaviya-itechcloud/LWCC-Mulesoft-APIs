%dw 2.0
output application/json
---
{
	"errorCode": error.errorType.identifier,
	"errorMessage": "FAILURE",
	"errorDescription": error.description,
	"transactionId": attributes.headers.'x-correlation-id' default correlationId,
  	"timeStamp": now()
}