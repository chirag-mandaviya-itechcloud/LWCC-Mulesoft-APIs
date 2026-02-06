%dw 2.0
import * from dw::test::Asserts
---
payload must equalTo({
  "claim-number": "219328",
  "response": "Success"
})