%dw 2.0
import * from dw::test::Asserts
---
payload must equalTo({
  "claim-number": 219263,
  "claim-unit-code": "ESZEKELY",
  "claim_enter_date": "2024-06-12T00:00:00"
})