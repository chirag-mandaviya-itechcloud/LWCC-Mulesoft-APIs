%dw 2.0
import * from dw::test::Asserts
---
payload must equalTo({
  "claim-number": 219274,
  "claim-unit-code": "KISIDORE",
  "claim_enter_date": "2024-06-13T00:00:00"
})