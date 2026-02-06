%dw 2.0
import * from dw::test::Asserts
---
payload.errorCode must equalTo("INTERNAL_SERVER_ERROR")