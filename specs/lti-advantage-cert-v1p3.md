# Learning Tools Interoperability Advantage Conformance Certification Guide

Final Release
Spec Version 1.3

Final Release

|                   |                                                                                |
| ----------------- | ------------------------------------------------------------------------------ |
| Document Version: | 3                                                                              |
| Date Issued:      | 16 April 2019                                                                  |
| Status:           | This document is made available for adoption by the public community at large. |
| This version:     | <https://www.imsglobal.org/spec/lti/v1p3/cert/>                                |
| Latest version:   | <https://www.imsglobal.org/spec/lti/latest/cert/>                              |
| Errata:           | <https://www.imsglobal.org/spec/lti/v1p3/errata/>                              |

## IPR and Distribution Notice

Recipients of this document are requested to submit, with their comments, notification of any relevant patent claims or other intellectual property rights of which they may be aware that might be infringed by any implementation of the specification set forth in this document, and to provide supporting documentation.

1EdTech takes no position regarding the validity or scope of any intellectual property or other rights that might be claimed to pertain implementation or use of the technology described in this document or the extent to which any license under such rights might or might not be available; neither does it represent that it has made any effort to identify any such rights. Information on 1EdTech's procedures with respect to rights in 1EdTech specifications can be found at the 1EdTech Intellectual Property Rights webpage: <http://www.imsglobal.org/ipr/imsipr_policyFinal.pdf> .

Use of this specification to develop products or services is governed by the license with 1EdTech found on the 1EdTech website: <http://www.imsglobal.org/speclicense.html>.

Permission is granted to all parties to use excerpts from this document as needed in producing requests for proposals.

The limited permissions granted above are perpetual and will not be revoked by 1EdTech or its successors or assigns.

THIS SPECIFICATION IS BEING OFFERED WITHOUT ANY WARRANTY WHATSOEVER, AND IN PARTICULAR, ANY WARRANTY OF NONINFRINGEMENT IS EXPRESSLY DISCLAIMED. ANY USE OF THIS SPECIFICATION _SHALL_ BE MADE ENTIRELY AT THE IMPLEMENTER'S OWN RISK, AND NEITHER THE CONSORTIUM, NOR ANY OF ITS MEMBERS OR SUBMITTERS, _SHALL_ HAVE ANY LIABILITY WHATSOEVER TO ANY IMPLEMENTER OR THIRD PARTY FOR ANY DAMAGES OF ANY NATURE WHATSOEVER, DIRECTLY OR INDIRECTLY, ARISING FROM THE USE OF THIS SPECIFICATION.

Public contributions, comments and questions can be posted here: <http://www.imsglobal.org/forums/ims-glc-public-forums-and-resources> .

© 2024 1EdTech™ Consortium, Inc. All Rights Reserved.

Trademark information: <http://www.imsglobal.org/copyright.html>

## Abstract

This document describes the LTI Advantage Certification procedures and outcomes. The basic conception of conformance to the LTI Advantage specifications is outlined, as are the test procedures for Learning Platforms and Learning Tools. Finally, the states of Certification provided are explained.

## Table of Contents

1.  Abstract
2.  1. Documentation
3.  2. Conformance Certification Options
    1. 2.1 LTI Advantage Certified
    1. 2.2 LTI Advantage Complete
4.  3. Introduction
    1. 3.1 Scope and Context
    1. 3.2 Status of this Document
    1. 3.3 Structure of this Document
    1. 3.4 Nomenclature
    1. 3.5 Conformance Statements
5.  4. The Certification Process
    1. 4.1 Certification Testing Process
    1. 4.2 General Requirements for Certification Testing Setup
       1. 4.2.1 Requirements for Certification for Learning Platforms
       2. 4.2.2 Requirements for Certification for Tools
    1. 4.3 Bugs/Issues with the Certification Suite
6.  5. Learning Platform Certification
    1. 5.1 LTI Core testing
       1. 5.1.1 Full Student Payload testing
       2. 5.1.2 Student Payload without PII testing
       3. 5.1.3 Full Instructor Payload testing
       4. 5.1.4 Teacher/Instructor Payload without PII testing
    1. 5.2 Deep Linking Message testing
    1. 5.3 Names and Role Provisioning Services Testing
    1. 5.4 Assignment and Grade Services Testing
    1. 5.5 Submission of Completion
7.  6. Tool Certification
    1. 6.1 LTI Core testing
       1. 6.1.1 Known "Bad" Payloads
       2. 6.1.2 Valid Teacher Launches
       3. 6.1.3 Valid Student Launches
    1. 6.2 Deep Linking Message testing
    1. 6.3 Names and Role Provisioning Services Testing
    1. 6.4 Assignment and Grade Services Testing
    1. 6.5 Submission of Completion
8.  A. Revision History
9.  B. References
    1.  B.1 Normative references
10. C. List of Contributors

## 1. Documentation

The following LTI v1.3 and LTI Advantage related specification documents are available:

- IMS Security Framework Version 1.0 [SEC-10] specification
- LTI Core Version 1.3 [LTI-13] specification
- Deep Linking Version 2.0 [LTI-DL-20] specification
- Names and Role Provisioning Services Version 2.0 [LTI-NRPS-20] specification
- Assignment and Grade Services Version 2.0 [LTI-AGS-20] specification
- LTI Advantage Implementation Guide [LTI-IMPL-13] specification

## 2. Conformance Certification Options

Two LTI Advantage Certification options are possible:

- LTI Advantage Certified
- LTI Advantage Complete

### 2.1 LTI Advantage Certified

Any _Tool_ that completes certification for LTI v1.3 Core and either one or two services is considered LTI Advantage Certified. Note that this designation is **only** available for Tools. _Learning Platforms_ _MUST_ complete certification for LTI v1.3 Core and all services as listed below and are not eligible for LTI Advantage Certified.

### 2.2 LTI Advantage Complete

Any _Tool_ that completes LTI Core and all three services is considered LTI Advantage Complete. For _Learning Platforms_ LTI Advantage Complete this is the only certification option available.

## 3. Introduction

### 3.1 Scope and Context

The Learning Tools Interoperability® (LTI®) Advantage set of specifications is designed to be the full implementation of LTI version 1.3 and the three core services enumerated below. These four components together constitute what is called "LTI Advantage". Certification to LTI Advantage requires implementation of:

- LTI Core Version 1.3
- Deep Linking Version 2.0
- Names and Role Provisioning Services Version 2.0
- Assignment and Grade Services Version 2.0

The purpose of this document is to provide details of the certification process for LTI Advantage and to describe the certifications necessary for each of the components. The conformance certification test components created by IMS Global are made available for:

- Learning Platforms that consume Tools that utilize Learning Tools Interoperability
- Tools that provides interoperability functions to be utilized by Learning Platforms

### 3.2 Status of this Document

IMS strongly encourages its members and the community to provide feedback to continue the evolution and improvement of the LTI Advantage specifications. Public contributions, comments and questions can be posted here: <https://www.imsglobal.org/forums/ims-glc-public-forums-and-resources/learning-tools-interoperability-public-forum>

### 3.3 Structure of this Document

The structure of this document is:

| Document Section                      | Explanation                                                                     |
| :------------------------------------ | :------------------------------------------------------------------------------ |
| 4\. The Certification Process         | The formal process to be undertaken by a vendor wishing to obtain certification |
| 5\. Certification Steps for Platforms | The steps to be taken by suppliers for certifying a Learning Platform           |
| 6\. Certification Steps for Tools     | The steps to be taken by suppliers for certification by the Tool                |
| A. References                         |                                                                                 |

### 3.4 Nomenclature

| Acronym/Abbreviation         | Actual Name or Explanation                                                                                                                                                                                                                                                                          |
| :--------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| API                          | Application Programming Interface                                                                                                                                                                                                                                                                   |
| HTTP                         | HyperText Transfer Protocol                                                                                                                                                                                                                                                                         |
| REST                         | Representational State Transfer                                                                                                                                                                                                                                                                     |
| TLS                          | Transport Layer Security (for HTTP)                                                                                                                                                                                                                                                                 |
| JSON                         | Javascript Object Notation                                                                                                                                                                                                                                                                          |
| JWT (jot)                    | JSON Web Token                                                                                                                                                                                                                                                                                      |
| JWK                          | JSON Web Key - used to verify signature of signed JWT                                                                                                                                                                                                                                               |
| JWKS                         | Web-available URL for Public Key Retrieval                                                                                                                                                                                                                                                          |
| "Well-Known URL" (syn. JWKS) | Web-available URL for Public Key Retrieval                                                                                                                                                                                                                                                          |
| OAuth2                       | Generalized Shorthand for a TLS-secured scheme for authorization token retrieval and use. Usually meant as a synonym for the use of Bearer Tokens in authorization schemes for access to protected resources via web URLs.                                                                          |
| Private Key                  | Cryptographic Asymmetric Key for Signing                                                                                                                                                                                                                                                            |
| Public Key                   | Cryptographic Asymmetric Key for Verification of JWT Signature                                                                                                                                                                                                                                      |
| RSA                          | Rivest-Shamir-Adleman cryptosystem                                                                                                                                                                                                                                                                  |
| RSA 256                      | RSA Cryptographic key length used in Certification Processes                                                                                                                                                                                                                                        |
| "Symmetric cryptosystem"     | Disallowed methods of cryptographic signing for all LTI Launches for LTI v 1.3 as well as the retrieval of OAuth2 tokens in LTI 1.3. Examples include TwoFish, Blowfish, AES, RC4, DES and others where a single key or derived variant of a single key is used for both encryption and decryption. |

### 3.5 Conformance Statements

As well as sections marked as non-normative, all authoring guidelines, diagrams, examples, and notes in this specification are non-normative. Everything else in this specification is normative.

The key words _MAY_, _MUST_, _MUST NOT_, _OPTIONAL_, _RECOMMENDED_, _REQUIRED_, _SHALL_, _SHALL NOT_, _SHOULD_, and _SHOULD NOT_ in this document are to be interpreted as described in [RFC2119].

An implementation of this specification that fails to implement a MUST/REQUIRED/SHALL requirement or fails to abide by a MUST NOT/SHALL NOT prohibition is considered nonconformant. SHOULD/SHOULD NOT/RECOMMENDED statements constitute a best practice. Ignoring a best practice does not violate conformance but a decision to disregard such guidance should be carefully considered. MAY/OPTIONAL statements indicate that implementers are entirely free to choose whether or not to implement the option.

## 4. The Certification Process

### 4.1 Certification Testing Process

Conformance Certification is an IMS member benefit. You _MUST_ to be a member of IMS Global as a Learning Tools/Content Alliance, Affiliate, or Contributing Member in order to test your product. Membership options and benefits are detailed here: <https://www.imsglobal.org/imsmembership.html>. The process for certification testing implementations of LTI Advantage includes the following:

- Go to the IMS Certification Test Suite for LTI Advantage. The link to the Certification Suite is: <https://ltiadvantagevalidator.imsglobal.org/ltiadv/certification.html>
- (Optional) Print the PDF of instructions for either the Tool or the Platform testing instructions
- Input the required setup parameters which include:
- Your Full Name
- Your Email Address
- Your Organization's Name
- The Product Name to be tested
- The Product Version to be tested
- The setup parameters for the testing that you plan to run
- Follow the instructions for running each test
- Once all tests have been successfully run, go to the Results page and submit test results for consideration of certification

NOTE: **All** tests _MUST_ be passed for either the Platform or the Tool to be considered compliant and apply for certification. It is _possible_ in rare circumstances that a Tool may not have the need for one of the three services that comprise LTI Advantage. The Certification Suite will provide feedback opportunities for those cases. However, in general **all** tests are always _REQUIRED_.

### 4.2 General Requirements for Certification Testing Setup

Nearly all communication between Learning Platforms and Tools in LTI v1.3 is done via the mechanism of the JSON Web Token or JWT (pronounced "jot"). This is a significant change from previous versions of LTI. Security of the JWT is achieved through the use of TLS-secured web channels, as well as signing of the JWT with asymmetric cryptosystems. Note that **in production** Learning Platforms may utilize most any asymmetric cryptography that is available for general use for the signing and verification of signatures for the JWT - provided that the Tools can work with the system used as well. However, for the purposes of commonality, a minimum set of RSA 256 will be required to be offered by all Learning Platforms (for the production of the keys) and Tools (for the utilization of the provided keys). As such, RSA 256 will be the only option provided in the Certification Suite provided by IMS Global for certification testing. Note, then, the following requirements:

- All Learning Platforms and Tools **_MUST_** provide the mechanisms (the libraries) for signing and verification of signatures for JWTs signed with RSA 256.
- The signing of a JWT with a public key _SHALL NOT_ be legal or respected. All JWT instances to be signed _MUST_ be signed only with the provided private key to be used for that portion of the communication.
- The use of Symmetric Cryptosystems _SHALL NOT_ be considered legal and use of them is expressly forbidden.
- All communication endpoints **_MUST_ be secured with TLS (SSL-alone is expressly forbidden).**

#### 4.2.1 Requirements for Certification for Learning Platforms

All tests for LTI Advantage for the Learning Platform are _REQUIRED_. The rough order of the testing is:

1.  Tests for LTI v1.3 Core
2.  Tests for Deep Linking
3.  Tests for Names and Role Provisioning Services
4.  Tests for Assignment and Grade Services

Please note of the following requirements for Platform Testing:

- A Platform **_MUST_** provide a Well-Known URL (JWKS) for the retrieval of Public Cryptographic keys in the setup of the certification testing.
- A Platform **_MUST_** provide access to an OAuth2 Services URL where a bearer token can be retrieved.
- A Platform **_MUST_** provide a unique client_id that is used to retrieve a OAuth2 bearer token - scoped for use in a service call to the testing system. Please note that testing will not be possible without the use of a unique client_id. Please do not attempt to use a key that might conflict with others such as "client123", etc.
- A Platform **_MUST_** provide to the Certification Suite a Private RSA 256 Key that is used to sign requests to the OAuth2 Services URL.
- A Platform **_MUST_** use the OIDC workflow for the initiation of the launches in LTI 1.3. This means that the Tool-provided OIDC initialization endpoint _MUST_ be used on each launch, and the registered URLs _MUST_ be checked and verified for each of the redirects to the final launch attempts.

Each of the above parameters is _REQUIRED_ in the testing setup.

#### 4.2.2 Requirements for Certification for Tools

All tests for LTI Advantage for the Tool are _REQUIRED_. The rough order of the testing will be:

1.  Tests for LTI v1.3 Core
2.  Tests for Deep Linking
3.  Tests for Names and Role Provisioning Services
4.  Tests for Assignment and Grade Services

If it is the case that one of the services is not to be tested, please provide the reason why the service omitted does not apply to the Tool in question. Note that in most cases exceptions are not allowed.

Additionally, note that all launches will be required to go through the OIDC initialization and launch process. **There are no exceptions to the requirement that OIDC always will be used.**

##### 4.2.2.1 JWKS Exchange Options

LTI 1.3 did not originally specify what mechanisms LTI Tools must use for making their public keys available to platforms. However, the LTI community has most broadly supported an LTI Tool providing a [JWKS URI](https://www.imsglobal.org/spec/lti/v1p3/impl#tool-s-jwk-set) and it is recommended that Tools provide that option. The certification suite supports anoter option as well, but that will be removed in the future. For a tool, the two options are:

- We provide a JWKS URI (Recommended)
- We provide a PEM Public Key

### 4.3 Bugs/Issues with the Certification Suite

If you encounter problems or bugs in the certification suite please send an email issue to <bug-report@imsglobal.org>. You may alternatively log an issue directly in Github at <https://github.com/IMSGlobal/certificationsuite-issues/issues>

## 5. Learning Platform Certification

The testing is designed to be done in a linear fashion, from start to finish. While it is permitted to go forward and backward in the testing without running a test, note that skipped tests are considered failures in the case of a submission for certification.

### 5.1 LTI Core testing

Four distinct payloads are _REQUIRED_ to be tested in LTI Core testing:

- Full Student Payload
- Student Payload without PII
- Full Instructor Payload
- Teacher/Instructor Payload without PII

#### 5.1.1 Full Student Payload testing

Submit an OIDC initialization request to the OIDC initialization endpoint <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/oidcinitialize.html>, being sure that the target_link_uri is set to URL <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/toollaunch.html>. The redirect URL in the resulting OIDC return _MUST_ be <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/oidcredirecturl.html>, as that is the registered URL for Platform testing for standard LTI 1.3 launches. After reception of the OIDC return message, post the full PII Student Payload the registered redirect URL from above. Note that this payload _MUST_ have the full information on the Learner/Student (including name, email, etc.). Once the payload has been received, press the "Continue" button to load the first test. Run each test in the following manner.

1.  (Optional) Open the Test Payload tab and inspect the JWT payload
2.  Open the Test Option tab
3.  Update Test Options provided (if possible or needed)
4.  Click the Button "Run Test"
5.  When the test is complete, the tab "Test Results" will be active. Please click the button "Confirm Results" to save the test results for this particular test
6.  Note that confirming results sets the test in the Certification Suite to PASS or FAIL as necessary
7.  Press the Navigation Button "Next Test" in the upper right hand corner to load the next test

The tests required for the Full Student Payload are:

| Test Name                           | Test Description                                                                                                                                           |
| :---------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Payload is LTI 1.3                  | Tests that JWT received conforms to format of 1.3 Core Launch JWT                                                                                          |
| Payload Timestamps Valid            | The iat and exp Timestamps are valid                                                                                                                       |
| Payload Signed with RSA 256         | Header for JWT confirmed that signing done is RSA 256                                                                                                      |
| Payload Signature Valid             | The KID in the JWT Header corresponds to the correct Public Key on the Well-Known URL and the Public Key for this KID correctly verifies the JWT Signature |
| Payload is Complete                 | All Required 1.3 Core Launch Claims are present                                                                                                            |
| Payload LTI Version                 | Required LTI Version Claim is set correctly to 1.3.0                                                                                                       |
| Payload Roles Correct               | The Roles in the JWT are those of the Learner/Student and not an Instructor                                                                                |
| Payload is Free of Extra Whitespace | There _MUST NOT_ be extra Whitespace before or after any values in the JWT                                                                                 |
| Payload Expected Received           | You _MUST_ Affirm that All Expected Values in the JWT were received                                                                                        |

#### 5.1.2 Student Payload without PII testing

Submit an OIDC initialization request to the OIDC initialization endpoint <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/oidcinitialize.html>, being sure that the target_link_uri is set to URL <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/toollaunch.html>. The redirect URL in the resulting OIDC return _MUST_ be <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/oidcredirecturl.html>, as that is the registered URL for Platform testing for standard LTI 1.3 launches. After reception of the OIDC return message, submit a "student" payload that does not contain Personal Identifying Information to the registered redirect URL detailed above. Note that this payload _MUST_ only have information on the Learner/Student needed to identify the student without PII. Once the payload has been received, press the "Continue" button to load the first test. Run each test in the same manner as was done with the previous payload.

The tests required for the Student Payload Without PII are:

| Test Name                           | Test Description                                                                                                                                           |
| :---------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Payload is LTI 1.3                  | Tests that JWT received conforms to format of 1.3 Core Launch JWT                                                                                          |
| Payload Timestamps Valid            | The iat and exp Timestamps are valid                                                                                                                       |
| Payload Signed with RSA 256         | Header for JWT confirmed that signing done is RSA 256                                                                                                      |
| Payload Signature Valid             | The KID in the JWT Header corresponds to the correct Public Key on the Well-Known URL and the Public Key for this KID correctly verifies the JWT Signature |
| Payload is Complete                 | All Required 1.3 Core Launch Claims are present                                                                                                            |
| Payload LTI Version                 | Required LTI Version Claim is set correctly to 1.3.0                                                                                                       |
| Payload Roles Correct               | The Roles in the JWT are those of the Learner/Student and not an Instructor                                                                                |
| Payload Without PII                 | No Personal Identifying Information is present in the claims provided in the JWT for PII                                                                   |
| Payload is Free of Extra Whitespace | There _MUST NOT_ be extra Whitespace before or after any values in the JWT                                                                                 |
| Payload Expected Received           | You _MUST_ Affirm that All Expected Values in the JWT were received                                                                                        |

#### 5.1.3 Full Instructor Payload testing

Submit a OIDC initialization request to the OIDC initialization endpoint <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/oidcinitialize.html>, being sure that the target_link_uri is set to URL <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/toollaunch.html>. The redirect URL in the resulting OIDC return _MUST_ be <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/oidcredirecturl.html>, as that is the registered URL for Platform testing for standard LTI 1.3 launches. After reception of the OIDC return message, submit a "full teacher" payload to the redirect URL from above. Note that this payload _MUST_ have the full information on the Teacher/Instructor (including name, email, etc.). Once the payload has been received, press the "Continue" button to load the first test. Run each test in the same manner that was done with the previous payloads.

The tests required for the Full Teacher Payload are:

| Test Name                           | Test Description                                                                                                                                           |
| :---------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Payload is LTI 1.3                  | Tests that JWT received conforms to format of 1.3 Core Launch JWT                                                                                          |
| Payload Timestamps Valid            | The iat and exp Timestamps are valid                                                                                                                       |
| Payload Signed with RSA 256         | Header for JWT confirmed that signing done is RSA 256                                                                                                      |
| Payload Signature Valid             | The KID in the JWT Header corresponds to the correct Public Key on the Well-Known URL and the Public Key for this KID correctly verifies the JWT Signature |
| Payload is Complete                 | All Required 1.3 Core Launch Claims are present                                                                                                            |
| Payload LTI Version                 | Required LTI Version Claim is set correctly to 1.3.0                                                                                                       |
| Payload Roles Correct               | The Roles in the JWT are those of the Instructor and not a Student                                                                                         |
| Payload is Free of Extra Whitespace | There _MUST NOT_ be extra Whitespace before or after any values in the JWT                                                                                 |
| Payload Expected Received           | You _MUST_ Affirm that All Expected Values in the JWT were received                                                                                        |

#### 5.1.4 Teacher/Instructor Payload without PII testing

Submit an OIDC initialization request to the OIDC initialization endpoint <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/oidcinitialize.html>, being sure that the target_link_uri is set to URL <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/toollaunch.html>. The redirect URL in the resulting OIDC return _MUST_ be <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/oidcredirecturl.html>, as that is the registered URL for Platform testing for standard LTI 1.3 launches. After reception of the OIDC return message, submit a "teacher" payload that does not contain Personal Identifying Information to the redirect URL noted above. Note that this payload _MUST_ only have information on the Teacher/Instructor needed to identify the teacher without PII. Note that email address _is allowed_ in this payload. Once the payload has been received, press the "Continue" button to load the first test. Run each test in the same manner as was done with the previous payloads.

The tests required for the Teacher Payload Without PII are:

| Test Name                           | Test Description                                                                                                                                           |
| :---------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Payload is LTI 1.3                  | Tests that JWT received conforms to format of 1.3 Core Launch JWT                                                                                          |
| Payload Timestamps Valid            | The iat and exp Timestamps are valid                                                                                                                       |
| Payload Signed with RSA 256         | Header for JWT confirmed that signing done is RSA 256                                                                                                      |
| Payload Signature Valid             | The KID in the JWT Header corresponds to the correct Public Key on the Well-Known URL and the Public Key for this KID correctly verifies the JWT Signature |
| Payload is Complete                 | All Required 1.3 Core Launch Claims are present                                                                                                            |
| Payload LTI Version                 | Required LTI Version Claim is set correctly to 1.3.0                                                                                                       |
| Payload Roles Correct               | The Roles in the JWT are those of the Instructor and not a Student                                                                                         |
| Payload Without PII                 | No Personal Identifying Information is present in the claims provided in the JWT for PII                                                                   |
| Payload is Free of Extra Whitespace | There _MUST NOT_ be extra Whitespace before or after any values in the JWT                                                                                 |
| Payload Expected Received           | You _MUST_ Affirm that All Expected Values in the JWT were received                                                                                        |

### 5.2 Deep Linking Message testing

Deep Linking is tested in a similar fashion to the LTI Core testing. The differences are that the Deep Linking OIDC workflow has its own set of URLs unconnected to the standard LTI Launch URLs. Additionally, the DeepLinkingRequest message type is different from the LTI Core launch. However, the principle is the same.

Submit an OIDC initialization request to the OIDC initialization endpoint <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/oidcinitialize.html>, being sure that the target_link_uri is set to URL <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/deeplinklaunch.html> for the Deep Linking launch. The redirect URL in the resulting OIDC return _MUST_ be <https://ltiadvantagevalidator.imsglobal.org/ltiplatform/deeplinkredirecturl.html>, as that is the registered URL for Platform testing for Deep Linking launches. After reception of the OIDC return message from the Certification Suite, submit the Deep Linking Launch to the redirect URL noted above. **The Deep Linking Response message _MUST_ immediately be returned to the window or iFrame that sent the Deep Linking Request message**. Once the Request has been submitted and the Response received, please press the "Continue" button to begin the testing. Run each test in the same manner as was done with the LTI 1.3 payloads.

The required tests for Deep Linking are:

| Test Name                   | Test Description                                                                                                                                           |
| :-------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Payload is LTI 1.3          | Tests that JWT received conforms to format of 1.3 Deep Linking JWT                                                                                         |
| Payload Timestamps Valid    | The iat and exp Timestamps are valid                                                                                                                       |
| Payload Signed with RSA 256 | Header for JWT confirmed that signing done is RSA 256                                                                                                      |
| Payload Signature Valid     | The KID in the JWT Header corresponds to the correct Public Key on the Well-Known URL and the Public Key for this KID correctly verifies the JWT Signature |
| Payload is Complete         | All Required 1.3 Deep Linking Claims are present                                                                                                           |
| Payload LTI Version         | Required LTI Version Claim is set correctly to 1.3.0                                                                                                       |
| Proof of LTI Link           | You _MUST_ Upload a Screenshot of your Learning Platform showing the absorbed LTI Link from the Deep Linking Response just sent                            |

### 5.3 Names and Role Provisioning Services Testing

The Names and Role Provisioning Services is one that is called by the Tool into the Learning Platform based on the parameters sent in the LTI Core launch. As such, the certification for this service will begin in a similar fashion to the LTI Core 1.3 testing. An LTI 1.3 Launch Payload will be sent to the Certification Suite that contains the required Names and Role claims. From that point the testing will begin.

Find the Names and Role payload submission page in the Certification Suite (it is the first page following Deep Linking testing). Submit a standard LTI 1.3 Instructor launch utilizing the exact OIDC workflow from section 3.1.4 above. Be sure to include the Names and Role claims in the message. Once the Payload has been submitted, please press the "Continue" button to begin the testing. Run each test in the same manner as was done with the LTI 1.3 Core payloads.

The required tests for the Names and Role Provisioning Services testing are:

| Test Name                      | Test Description                                                                                                                                                                                   |
| :----------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Payload is LTI 1.3             | Tests that JWT received conforms to format of 1.3 Core Launch JWT                                                                                                                                  |
| Payload Timestamps Valid       | The iat and exp Timestamps are valid                                                                                                                                                               |
| Payload Signature Valid        | The KID in the JWT Header corresponds to the correct Public Key on the Well-Known URL and the Public Key for this KID correctly verifies the JWT Signature                                         |
| Payload is Complete            | All Required 1.3 Core Launch Claims are present in addition to the required Names and Role Claim                                                                                                   |
| Generate OAuth2 Call           | Test Generates OAuth2 call with for the test utilizing the Private Key provided for the Tool, and submits to the OAuth2 server with the correct role parameter - expecting a Bearer Token response |
| Do Names and Roles Call        | Test uses Bearer Token just received to make GET to URL for Names and Roles for this Context - expecting a Names and Roles response                                                                |
| Names and Roles Payload        | Test confirms Payload type complete and formatted correctly for Names and Role                                                                                                                     |
| Verify Names and Roles Headers | Test Parses the Headers in the NRPS Response and displays what (if any) were Found. You _MUST_ verify that what is found is what the GET return sent in the headers                                |

### 5.4 Assignment and Grade Services Testing

The Assignment and Grade Services (AGS) is different from other testing, in that it is split into working with two separate payloads to simulate real-world usage of grade services. AGS is called by the Tool into the Learning Platform based on the parameters sent in the LTI Core launch. As such, the initialization of the payloads for this service will begin in a similar fashion to the LTI Core 1.3 testing. An LTI 1.3 Launch Payload will be sent at two different points, each payload to the Certification Suite _MUST_ contain the required AGS claim. From that point the testing will begin for each of the payloads sent.

Find the first AGS Payload submission page in the Certification Suite (it is the first page following Names and Role testing). The Platform will be required to submit a _student payload only_ with the OIDC workflow as a standard LTI 1.3 launch, being sure to include the AGS claim in the message. Once the Payload has been submitted, please press the "Continue" button to begin the testing. Run each test for this payload in the same manner as was done with the LTI 1.3 Core payloads.

The required tests for the first Assignment and Grade payload are:

| Test Name               | Test Description                                                                                                                                                                                                                |
| :---------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Payload Signature Valid | The KID in the JWT Header corresponds to the correct Public Key on the Well-Known URL and the Public Key for this KID correctly verifies the JWT Signature                                                                      |
| Payload is Complete     | All Required 1.3 Core Launch Claims are present in addition to the required Assignment and Grade Claim                                                                                                                          |
| Generate OAuth2 Call 1  | Test Generates OAuth2 call utilizing the Private Key for the Tool provided in the test setup, and submits to the OAuth2 server with the correct role parameter - expecting a Bearer Token response **for lineitems scope only** |
| Create Line Item 1      | Test Attempts to use new Bearer Token to Create First Line Item                                                                                                                                                                 |
| Retrieve Line Item 1    | Test Attempts to use new Bearer Token to Retrieve just created First Line Item                                                                                                                                                  |
| Create Line Item 2      | Test Attempts to use Bearer Token to Create Second Line Item                                                                                                                                                                    |

At this point, if the previous testing has been successful, then we have used the lineitems URL in the LTI 1.3 launch to create two separate lineitem URLs for the provided lineitems URL. This means that at least two gradable (in our testing case) items will exist in the tested platform. (It is a good time to double-check that this is indeed true before continuing.) At this point the testing shifts to a second payload context - to fully test the potential of the AGS services provided by the platform.

Find the second AGS Payload submission page for in the Certification Suite (it is the next page following creation of the second Line Item in testing). The Platform will be required to submit a _second student payload only_ with the OIDC workflow as a standard LTI 1.3 launch, being sure to include the AGS claim in the message to the new context. Again note that it is imperative that a different context be used here, as the idea is to prove that the AGS implementation can differentiate between calls to different contexts in the platform. Once the new Payload has been submitted for the new context, please press the "Continue" button to begin the testing. Run each test for this payload in the same manner as was done with the LTI 1.3 Core payloads

| Test Name                    | Test Description                                                                                                                                                                                                                       |
| :--------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Payload Signature Valid      | The KID in the JWT Header corresponds to the correct Public Key on the Well-Known URL and the Public Key for this KID correctly verifies the JWT Signature                                                                             |
| Payload is Complete          | All Required 1.3 Core Launch Claims are present in addition to the required Assignments and Grades Claim                                                                                                                               |
| Create Line Item 3           | Test Attempts to use Bearer Token to Create Third Line Item                                                                                                                                                                            |
| Generate OAuth2 Call 2       | Test Generates OAuth2 call utilizing the Private Key for the Tool provided in the test setup, and submits to the OAuth2 server with the correct scores scope parameter - expecting a Bearer Token response **for scores scope only**   |
| Post Score Line Item 3       | Test Attempts to use new Score Bearer Token to Post a Score to the Third Line Item                                                                                                                                                     |
| Post Score Line Item 1       | Test Attempts to use Score Bearer Token to Post a Score to the First Line Item (from previous context)                                                                                                                                 |
| Generate OAuth2 Call 3       | Test Generates OAuth2 call utilizing the Private Key for the Tool provided in the test setup, and submits to the OAuth2 server with the correct results scope parameter - expecting a Bearer Token response **for results scope only** |
| Retrieve Results Line Item 3 | Test Attempts to use new Results Bearer Token to retrieve Results for the Third Line Item                                                                                                                                              |
| Retrieve Results Line Item 1 | Test Attempts to use Results Bearer Token to retrieve Results for the First Line Item (from previous context)                                                                                                                          |
| Verify Gradebook Entities    | Test Returns to the Webpage the POSTED Scores for the lineitems used. You _MUST_ CONFIRM that you received and absorbed the calls made!                                                                                                |

### 5.5 Submission of Completion

Please Submit your Testing Results from the Results page. The form for submission _MUST_ be completed in full. The form contains the following inputs:

| Submission Form Field         | Required | Description                                                                                                     |
| :---------------------------- | :------: | :-------------------------------------------------------------------------------------------------------------- |
| Contact Name 1                |    Y     | The Name of the First Contact Person for your Organization                                                      |
| Contact Email 1               |    Y     | The Email of the First Contact Person for your Organization                                                     |
| Contact Title 1               |    Y     | The Title of the First Contact Person for your Organization                                                     |
| Contact Name 2                |    Y     | The Name of the Second Contact Person for your Organization                                                     |
| Contact Email 2               |    Y     | The Email of the Second Contact Person for your Organization                                                    |
| Contact Title 2               |    Y     | The Title of the Second Contact Person for your Organization                                                    |
| Checkbox - Use Other Software |    Y     | Please Check "ON" only if You are using a Third-Party Certified Software. Leave "OFF" otherwise                 |
| Third-Party Software          |    N     | You _MUST_ List the Name of the Third-Party Package if Used                                                     |
| Checkbox - Affirmation        |    Y     | Please Check "ON" to Affirm That You and Your Group have Performed the Tests As Described in the Results Matrix |
| Comment                       |    N     | Please Input any Comments or Requests for Exemptions from the Testing Requirements                              |

Following submission of this form you will receive an email detailing the test results that are submitted for consideration.

## 6. Tool Certification

The testing is designed to be done in a linear fashion, from start to finish. While it is permitted to go forward and backward in the testing without running a test, please note that skipped tests are considered failures in the case of a submission for certification.

Please Note: Each test in Tool testing is designed to stand alone as much as possible. This means that in each case a new payload is generated by the Certification Suite and submitted to the Tool for consideration. For each test the generated JWT payload is available to inspect in the tab for the Testing Payload. The inspection of the JWT payload can be very helpful for debugging when you need it. However, in every case you are then required to give to the suite a piece of proof that your Tool received the payload and worked with it effectively. The best example proof to provide would be to input a piece of the log messages from your Tool for this test. However, in the case that the log messages are not available, you may also upload a screenshot that shows the results of the testing. **Only use screenshots to show proof of success**. In the case of failures please input the failure explanations in the provided text input and leave the success/fail toggle to "OFF".

A NOTE on the required OIDC workflow: **All launches** in the certification suite to your tool will follow the OIDC workflow before the launch takes place. This means that in your Tool setup you **_MUST_ give to the testing suite** your OIDC initialization endpoint URL, as well as provide the array (comma-separated if more than one) of your registered URLs for redirects in the OIDC workflow. In the testing below we do not specify the OIDC steps for each launch. However, all launches always follow the same requirement. We will make an OIDC call to your initialization endpoint, and your "launch URL" or "deep link launch URL" will be the target_link_uri in that packet. You **_MUST_ then return the OIDC response** with the redirect uri being equal to one of the redirect uri values that you placed in the setup. The final step, then, will be to launch a full LTI 1.3-based launch to the redirect URL as provided by the auth response. As stated above all launches described below to your Tool for testing will follow the OIDC pattern before the launch call is made.

### 6.1 LTI Core testing

Tool Testing for the 1.3 Core is split into 4 separate sections.

#### 6.1.1 Known "Bad" Payloads

The first few tests will be those that are in one or another way known to be invalid for 1.3 Core Launches. The tests below are provided for testing the Tool's response to known "bad" launches:

| Test Name                      | Test Description                                                                                      |
| :----------------------------- | :---------------------------------------------------------------------------------------------------- |
| No KID Sent in JWT header      | The KID is missing from the header of the JWT (preventing the verification of the signing of the JWT) |
| Incorrect KID in JWT header    | The KID provided is incorrect (and signing verification is impossible)                                |
| Wrong LTI Version              | The LTI version claim contains the wrong version                                                      |
| No LTI Version                 | The LTI version claim is missing                                                                      |
| Invalid LTI message            | The provided JSON is NOT a 1.3 JWT launch                                                             |
| Missing LTI Claims             | The provided 1.3 JWT launch is missing one or more required claims                                    |
| Timestamps Incorrect           | JWT iat and exp timestamp Values are Invalid                                                          |
| messsage_type Claim Missing    | The Required message_type Claim Not Present                                                           |
| role Claim Missing             | The Required role Claim Not Present                                                                   |
| deployment_id Claim Missing    | The Required deployment_id Claim Not Present                                                          |
| resource_link_id Claim Missing | The Required resource_link_id Claim Not Present                                                       |
| user Claim Missing             | The Required sub Claim Not Present                                                                    |

#### 6.1.2 Valid Teacher Launches

Following the known "bad" payload launches are valid Teacher payloads. The tests to be done next are:

| Test Name                              | Test Description                            |
| :------------------------------------- | :------------------------------------------ |
| Valid Instructor Launch                | Launch LTI 1.3 Message as Instructor        |
| Valid Instructor Launch with Roles     | Launch Instructor with Multiple Role Values |
| Valid Instructor Launch Short Role     | Launch Instructor with Short Role Value     |
| Valid Instructor Launch Unknown Role   | Launch Instructor with Unknown Role         |
| Valid Instructor Launch No Role        | Launch Instructor With No Role              |
| Valid Instructor Launch Email Only     | Launch Instructor Only Email                |
| Valid Instructor Launch Names Only     | Launch Instructor Only Names                |
| Valid Instructor No PII                | Launch Instructor No PII                    |
| Valid Instructor Email Without Context | Launch Instructor With Email No Context     |

#### 6.1.3 Valid Student Launches

Following the various valid instructor payload launches are valid Student/Learner payloads. The tests to be done next are:

| Test Name                           | Test Description                         |
| :---------------------------------- | :--------------------------------------- |
| Valid Student Launch                | Launch LTI 1.3 Message as Student        |
| Valid Student Launch with Roles     | Launch Student with Multiple Role Values |
| Valid Student Launch Short Role     | Launch Student with Short Role Value     |
| Valid Student Launch Unknown Role   | Launch Student with Unknown Role         |
| Valid Student Launch No Role        | Launch Student With No Role              |
| Valid Student Launch Email Only     | Launch Student Only Email                |
| Valid Student Launch Names Only     | Launch Student Only Names                |
| Valid Student No PII                | Launch Student No PII                    |
| Valid Student Email Without Context | Launch Student With Email No Context     |

### 6.2 Deep Linking Message testing

Deep Linking is tested in a similar fashion to the LTI Core testing. The exceptions are that the Deep Linking Payload is different and is sent (in some cases) to a different URL (based on Tool choices).

The following tests are done to test the Deep Linking workflow:

| Test Name                    | Test Description                                  |
| :--------------------------- | :------------------------------------------------ |
| Send the Request Payload     | Send Deep Linking Request Payload to the Tool     |
| Receive the Response Payload | Verify Deep Linking Response Payload was Received |
| Response Format Valid        | Verify Response is Deep Linking Response          |
| Response Timestamps Valid    | Deep Linking - Verify Response Timestamps         |
| Signature Valid              | Deep Linking - Verify JWT Signature               |
| Required Claims Verified     | Deep Linking - Verify Required Claims Present     |
| Affirm Response              | Deep Linking - Affirm Response Values Sent        |

### 6.3 Names and Role Provisioning Services Testing

Names and Role Provisioning Services is tested as pure service (without any UI). The Tool is required to acquire an OAuth2 token from the IMS Global testing OAuth2 server and then do the GET to the known service instantiation URL communicated in the testing setup. Note that the first test is a launch - it is optional but can be done if there is no consequence for doing additional instructor launches.

The required tests for the Names and Role Provisioning Services testing are:

| Test Name               | Test Description                                                                                                      |
| :---------------------- | :-------------------------------------------------------------------------------------------------------------------- |
| Valid Instructor Launch | Launch LTI 1.3 Message as Instructor - will have NRPS claim                                                           |
| Received Request        | Names and Roles - Test Verifies that a NRPS request has been received and Displays the Request received from the Tool |
| Verify JSON Header      | Names and Roles - Verify Request Header Required Parameters                                                           |
| Verify Bearer Token     | Names and Roles - Verify OAuth2 Token                                                                                 |
| Verify Bearer Scope     | Names and Roles - Verifiy OAuth2 Scopes                                                                               |

### 6.4 Assignment and Grade Services Testing

Assignments and Grade Services (AGS) is tested as pure service (without any UI). The Tool is required to acquire the OAuth2 tokens from the IMS Global testing OAuth2 server necessary to interact with the AGS system. Testing for AGS for the Tool is very different from all other testing in the Certification Suite.

Since it is possible to jump directly to testing for AGS, the Certification Suite provides the place to launch a standard, Learner-based LTI 1.3 launch into your Tool. However, that is the only prescribed test in the Certification Suite.

After that launch **it is the responsibility of the Tool alone** to work with the AGS API to create lineitems and scores in the Certification Suite. All interaction with the Gradebook simulated by the Certification Suite can be viewed on the Results page.

| Test Name               | Test Description                                                                        |
| :---------------------- | :-------------------------------------------------------------------------------------- |
| Valid Instructor Launch | Launch LTI 1.3 Message as Student - will have AGS claim for the necessary lineitems URL |

### 6.5 Submission of Completion

Please Submit your Testing Results from the Results page. The form for submission will have to be completed in full. The form contains the following inputs:

| Submission Form Field         | Required | Description                                                                                                     |
| :---------------------------- | :------: | :-------------------------------------------------------------------------------------------------------------- |
| Contact Name 1                |    Y     | The Name of the First Contact Person for your Organization                                                      |
| Contact Email 1               |    Y     | The Email of the First Contact Person for your Organization                                                     |
| Contact Title 1               |    Y     | The Title of the First Contact Person for your Organization                                                     |
| Contact Name 2                |    Y     | The Name of the Second Contact Person for your Organization                                                     |
| Contact Email 2               |    Y     | The Email of the Second Contact Person for your Organization                                                    |
| Contact Title 2               |    Y     | The Title of the Second Contact Person for your Organization                                                    |
| Checkbox - Use Other Software |    Y     | Please Check "ON" only if You are using a Third-Party Certified Software. Leave "OFF" otherwise                 |
| Third-Party Software          |    N     | You _MUST_ List the Name of the Third-Party Package if Used                                                     |
| Checkbox - Affirmation        |    Y     | Please Check "ON" to Affirm That You and Your Group have Performed the Tests As Described in the Results Matrix |
| Comment                       |    N     | Please Input any Comments or Requests for Exemptions from the Testing Requirements                              |

Following submission of this form you will receive an email detailing the test results that are submitted for consideration.

## A. Revision History

_This section is non-normative._

| Version No. | Release Date    | Comments                                                                                                                          |
| ----------- | --------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 1           | 16 April 2019   | The first formal release of the LTI v1.3 Core specification and Conformance Guide. This document is released for public adoption. |
| 2           | 10 March 2021   | Updated guidance on Tools providing a JWKS URI                                                                                    |
| 3           | 23 January 2024 | Fixed a broken link in the index; Updated Respec template                                                                         |

## B. References

### B.1 Normative references

\[LTI-13\]
[IMS Global Learning Tools Interoperability® Core Specification v1.3](https://www.imsglobal.org/spec/lti/v1p3/). C. Vervoort; N. Mills. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/>

\[LTI-AGS-20\]
[IMS Global Learning Tools Interoperability® Assignment and Grade Services](https://www.imsglobal.org/spec/lti-ags/v2p0/). C. Vervoort; E. Preston; M. McKell; J. Rissler. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti-ags/v2p0/>

\[LTI-DL-20\]
[IMS Global Learning Tools Interoperability® Deep Linking 2.0](https://www.imsglobal.org/spec/lti-dl/v2p0/). C. Vervoort; E. Preston. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti-dl/v2p0/>

\[LTI-IMPL-13\]
[IMS Global Learning Tools Interoperability® Advantage Implementation Guide](https://www.imsglobal.org/spec/lti/v1p3/impl/). C. Vervoort; J. Rissler; M. McKell. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/impl/>

\[LTI-NRPS-20\]
[IMS Global Learning Tools Interoperability® Names and Role Provisioning Services](https://www.imsglobal.org/spec/lti-nrps/v2p0/). C. Vervoort; E. Preston; J. Rissler. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti-nrps/v2p0/>

\[RFC2119\]
[Key words for use in RFCs to Indicate Requirement Levels](https://www.rfc-editor.org/rfc/rfc2119). S. Bradner. IETF. March 1997. Best Current Practice. URL: <https://www.rfc-editor.org/rfc/rfc2119>

\[SEC-10\]
[IMS Global Security Framework v1.0](https://www.imsglobal.org/spec/security/v1p0/). C. Smythe; C. Vervoort; M. McKell; N. Mills. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/security/v1p0/>

## C. List of Contributors

The following individuals contributed to the development of this document:

| Name              | Organization           | Role   |
| ----------------- | ---------------------- | ------ |
| Paul Gray         | Learning Objects       |        |
| Viktor Haag       | D2L                    |        |
| Dereck Haskins    | IMS Global             | Editor |
| Martin Lenord     | Turnitin               |        |
| Karl Lloyd        | Instructure            |        |
| Mark McKell       | IMS Global             | Editor |
| Nathan Mills      | Instructure            |        |
| Bracken Mosbacker | Lumen Learning         |        |
| Marc Phillips     | Instructure            |        |
| Eric Preston      | Blackboard             |        |
| James Rissler     | IMS Global             |        |
| James Tse         | Goggle                 |        |
| Charles Severance | University of Michigan |        |
| Lior Shorshi      | McGraw-Hill Education  |        |
| Colin Smythe      | IMS Global             |        |
| Claude Vervoort   | Cengage                |        |

1EdTech™ Consortium, Inc. ("1EdTech") is publishing the information contained in this document ("Specification") for purposes of scientific, experimental, and scholarly collaboration only.

1EdTech makes no warranty or representation regarding the accuracy or completeness of the Specification.

This material is provided on an "As Is" and "As Available" basis.

The Specification is at all times subject to change and revision without notice.

It is your sole responsibility to evaluate the usefulness, accuracy, and completeness of the Specification as it relates to you.

1EdTech would appreciate receiving your comments and suggestions.

Please contact 1EdTech through our website at [www.1edtech.org](https://www.1edtech.org).

Please refer to Document Name: Learning Tools Interoperability Advantage Conformance Certification Guide 1.3

Date: 16 April 2019
