%dw 2.0
import * from dw::test::Asserts
output application/java
---
payload.errorCode must equalTo("NOT_FOUND")