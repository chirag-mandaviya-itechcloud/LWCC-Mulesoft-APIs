%dw 2.0
import * from dw::test::Asserts
---
payload must equalTo({
  "claim-number": 219223,
  "claim-unit-code": null,
  "claim_enter_date": null
})