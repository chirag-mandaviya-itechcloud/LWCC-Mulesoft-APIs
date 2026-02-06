%dw 2.0
import * from dw::test::Asserts
---
payload must equalTo({
  "claim-number": 1234,
  "claim-inv-type": "CCI",
  "response": "Success"
})