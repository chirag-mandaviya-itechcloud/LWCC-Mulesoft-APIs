%dw 2.0
import try, fail from dw::Runtime
import * from dw::core::Binaries
output application/json

fun getClientId(inAuthString) =
 splitBy(fromBase64(splitBy(inAuthString, " ")[1]), ":")[0]

var vClientId = try(() -> getClientId(attributes.headers.authorization))

---
(attributes.queryParams.mode == "verbose") and 
(vClientId.success == true) and 
(vClientId.result == lower(p('health.verbose.client.id')))
