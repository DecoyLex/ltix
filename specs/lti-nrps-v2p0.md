# Learning Tools Interoperability (LTI)® Names and Role Provisioning Services
1EdTech Final Release
Version 2.0

|  |  |
| --- | --- |
| Date Issued: | 16 April 2019 |
| Status: | This document is made available for adoption by the public community at large. |
| This version: | <https://www.imsglobal.org/spec/lti-nrps/v2p0/> |
| Latest version: | <https://www.imsglobal.org/spec/lti-nrps/latest/> |
| Errata: | <https://www.imsglobal.org/spec/lti-nrps/v2p0/errata/> |

## IPR and Distribution Notices

Recipients of this document are requested to submit, with their comments, notification of any relevant patent claims or other intellectual property rights of which they may be aware that might be infringed by any implementation of the specification set forth in this document, and to provide supporting documentation.

1EdTech takes no position regarding the validity or scope of any intellectual property or other rights that might be claimed to pertain to the implementation or use of the technology described in this document or the extent to which any license under such rights might or might not be available; neither does it represent that it has made any effort to identify any such rights. Information on 1EdTech's procedures with respect to rights in 1EdTech specifications can be found at the 1EdTech Intellectual Property Rights web page: <http://www.imsglobal.org/ipr/imsipr_policyFinal.pdf>.

Copyright © 2019 1EdTech Consortium. All Rights Reserved.

Use of this specification to develop products or services is governed by the license with 1EdTech found on the 1EdTech website: <http://www.imsglobal.org/speclicense.html>.

Permission is granted to all parties to use excerpts from this document as needed in producing requests for proposals.

The limited permissions granted above are perpetual and will not be revoked by 1EdTech or its successors or assigns.

THIS SPECIFICATION IS BEING OFFERED WITHOUT ANY WARRANTY WHATSOEVER, AND IN PARTICULAR, ANY WARRANTY OF NONINFRINGEMENT IS EXPRESSLY DISCLAIMED. ANY USE OF THIS SPECIFICATION SHALL BE MADE ENTIRELY AT THE IMPLEMENTER'S OWN RISK, AND NEITHER THE CONSORTIUM, NOR ANY OF ITS MEMBERS OR SUBMITTERS, SHALL HAVE ANY LIABILITY WHATSOEVER TO ANY IMPLEMENTER OR THIRD PARTY FOR ANY DAMAGES OF ANY NATURE WHATSOEVER, DIRECTLY OR INDIRECTLY, ARISING FROM THE USE OF THIS SPECIFICATION.

Public contributions, comments and questions can be posted here: <http://www.imsglobal.org/forums/ims-glc-public-forums-and-resources>.

© 2019 1EdTech Consortium, Inc. All Rights Reserved.

Trademark information: <http://www.imsglobal.org/copyright.html>

## Abstract

The Learning Tools Interoperability (LTI)® Names and Role Provisioning Services is an LTI™ specification for providing
access to a list of users and their roles within context of a course,
program or other grouping. The LTI™ specification enables instructors to
automate the provision of student lists via LTI to an external tool. LTI
does not pass user information in its default configuration. Using the LTI
Names and Role Provisioning Services, user information can be passed in a
safe and secure manner. The Names and Role Provisioning Services also allows
instructors to be provided a display showing the activity of all of their
students, whether or not they have accessed the tools. An earlier iteration
of this spec was formerly called LTI Membership Services.

## Table of Contents

1. Introduction
   1. Overview
      1. Conformance Statements
      2. Document Set
   2. Terminology
      1. Organization
      2. Role
      3. Membership
      4. Tool Platform and Tool
2. Context Membership
   1. Membership container media type
   2. Sharing of personal data
   3. Membership status
   4. Using the service
      1. Role query parameter
      2. Limit query parameter
      3. Membership differences
3. Resource Link Membership Service
   1. Access restriction
   2. Message section
   3. Membership filtered
   4. Basic Outcome
   5. Substitution parameters
   6. Binding with LTI Core
      1. LTI 1.3 integration
      2. LTI 1.1 integration
4. Revision history
   1. Version History
   2. Changes in this version
5. References
   1. Normative references
   2. Informative references
6. List of Contributors

## Introduction

### Overview

The Names and Role Provisioning Services is based on 1EdTech Learning Information Services (LIS) [LIS-20] and W3C Organization Ontology [W3C-ORG]. It is concerned with providing access to data about users’ roles within organizations, a course being an example of an organization. So a very common purpose for this service is to provide a roster (list of enrolments) for a course.

#### Conformance Statements

All sections marked as non-normative, all authoring guidelines, diagrams, examples, and notes in this specification are non-normative. Everything else in this specification is normative.

The key words "*MUST*", "*MUST NOT*", "*REQUIRED*", "*SHALL*", "*SHALL NOT*", "*SHOULD*",
"*SHOULD NOT*", "*RECOMMENDED*", "*MAY*", and "*OPTIONAL*" in this document are to
be interpreted as described in [RFC2119].

An implementation of this specification that fails to
implement a *MUST*/*REQUIRED*/*SHALL* requirement or fails to abide by a
*MUST NOT*/*SHALL NOT* prohibition is considered nonconformant.
*SHOULD*/*SHOULD NOT*/*RECOMMENDED* statements constitute a best practice.
Ignoring a best practice does not violate conformance but a decision to
disregard such guidance should be carefully considered.
*MAY*/*OPTIONAL* statements indicate that implementers are entirely free to
choose whether or not to implement the option.

The [Conformance and Certification Guide](#document-set) for this
specification may introduce greater normative constraints than those defined
here for specific service or implementation categories.

#### Document Set

##### Normative Documents

LTI Advantage Conformance Certification Guide [LTI-CERT-13]
:   The LTI Advantage Conformance Certification Guide describes the procedures
    for testing Platforms and Tools against the LTI v1.3 and LTI Advantage services
    using the 1EdTech certification test suite.

##### Informative Documents

LTI Advantage Implementation Guide [LTI-IMPL-13]
:   The LTI Advantage Implementation Guide provides information to lead
    you to successful implementation and certification of the LTI Core v1.3 specification
    and the set of LTI Advantage specifications.

### Terminology

#### Organization

An organization is a collection of people organized into a group for a common purpose or specific reason. Organizations can be part of a hierarchical structure.

#### Role

The type of involvement a person has within an organization. In the case of a course, the typical roles are Instructor, Teaching Assistant and Learner.

#### Membership

A relationship between a person and an organization which involves at least one role. A person cannot be a member of an organization without being assigned a role.

#### Tool Platform and Tool

This version of the specification uses the LTI 1.3 terminology of Tool Platform and Tool,
which respectively refer to Tool Consumer and Tool Provider used in the previous LTI specifications.

## Context Membership

### Membership container media type

The accompanying HTML documentation defines the following media type used by the membership service:

* 'application/vnd.ims.lti-nrps.v2.membershipcontainer+json'

```json
{
"id" : "https://lms.example.com/sections/2923/memberships",
"context": {
  "id": "2923-abc",
  "label": "CPS 435",
  "title": "CPS 435 Learning Analytics",
},
"members" : [
  {
    "status" : "Active",
    "name": "Jane Q. Public",
    "picture" : "https://platform.example.edu/jane.jpg",
    "given_name" : "Jane",
    "family_name" : "Doe",
    "middle_name" : "Marie",
    "email": "jane@platform.example.edu",
    "user_id" : "0ae836b9-7fc9-4060-006f-27b2066ac545",
    "lis_person_sourcedid": "59254-6782-12ab",
    "roles": [
      "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
    ]
  }
]
}
```

Figure 1 Example of application/vnd.ims.lti-nrps.v2.membershipcontainer+json media type.

### Sharing of personal data

Which member data is actually passed to the Tool relies on the agreement between the Platform and the Tool.
At a minimum, the member must contain:

* `user_id`: as communicated in the LtiResourceLinkRequest under `sub`
* `roles`: an array of roles with values as defined in [LTI-13]

A context parameter must be present that must contain:

* `id`: id of the context

Any other member attributes will need an explicit consent from the Platform to be shared with the Tool.
The Platform may delegate that consent to the actual member, therefore a Tool should never rely
on additional member attributes to be present.

### Membership status

Each membership has a status of either `Active` or `Inactive`. If the status is not specified then a status of `Active` must be assumed.

When reporting differences a membership (see below) may have a status of `Deleted` which means that the membership no longer exists. A normal request for a memberships list will only return current memberships and hence none will have a status of `Deleted`.

### Using the service

The only action defined for this service is an HTTP GET request. This should be sent to the endpoint provided and include an 'Accept' header with a value of 'application/vnd.ims.lti-nrps.v2.membershipcontainer+json'. The request must be properly secured
as per the LTI Security Framework used by the LTI integration.

#### Role query parameter

By default all the current memberships will be returned by a request to this service. However, this may be limited to only those memberships with a specified role by passing its URI in a query parameter named 'role'. For example, a query parameter of 'role=http%3A%2%2Fpurl.imsglobal.org%2Fvocab%2Flis%2Fv2%2Fmembership%23Learner' will filter the memberships to just those which have a Learner role. Since this is a context-level role, the parameter could be simplified to 'role=Learner', following the same rule which applies to the 'roles' parameter in a 'LtiResourceLinkRequest' message.

#### Limit query parameter

The Tool may specify a maximum number of members to be returned in the response from the Platform. The Platform may use this as a guide to the number it returns but may include more or less than the value provided. If the response from a Platform does not comprise all of the members a `rel="next"` header link will be included to indicate how to request the next set of members. The absence of a `rel="next"` header link indicates that no more members are available. See [RFC8288].

```json
Link: <https://lms.example.com/sections/2923/memberships?p=2>; rel="next"
```

#### Membership differences

A response by the Names and Role Provisioning Services may include a `rel="differences"` header link. When present, this URL should be complete and opaque; users of this URL should not need to decorate it further (nor should further decoration be necessarily supported). When present this will specify a *differences URL* which the service user may use to obtain a report of all the differences in the membership between the time the differences URL was created and the time the URL is used (the *current time*). If a membership has been deleted during this interim period, it may be included in the response with a status of `Deleted`. All other entries in the response represent memberships which have been added or changed; for the latter the entry will be the state of the membership at the current time. This option is not intended to provide a history of all the changes which have taken place, merely to report any differences between the state of a membership at the current time and the state of the entire roster at the time the differences URL was created and provided in the initial service response. For example, a platform might provide this differences URL, encoding the earliest time to begin considering roster differences to report (there is no requirement for platforms to use this pattern, however). See [RFC8288].

```json
Link: <https://lms.example.com/sections/2923/memberships?since=1422554502>; rel="differences"
```

## Resource Link Membership Service

Optionaly, a platform may offer a Resource Link level membership service. The endpoint is the same
as the context membership service. The tool needs to append an additional query parameter `rlid` with
a value of the Resource Link id as communicated in LtiResourceLinkRequest
`https://purl.imsglobal.org/spec/lti/claim/resource_link` claim.

Filtering per role, using limit and differences as defined above also apply to Resource Link membership
service.

* 'application/vnd.ims.lti-nrps.v2.membershipcontainer+json'

```json
{
"id" : "https://lms.example.com/sections/2923/memberships?rlid=49566-rkk96",
"context": {
  "id": "2923-abc",
  "label": "CPS 435",
  "title": "CPS 435 Learning Analytics",
},
"members" : [
  {
    "status" : "Active",
    "name": "Jane Q. Public",
    "picture" : "https://platform.example.edu/jane.jpg",
    "given_name" : "Jane",
    "family_name" : "Doe",
    "middle_name" : "Marie",
    "email": "jane@platform.example.edu",
    "user_id" : "0ae836b9-7fc9-4060-006f-27b2066ac545",
    "lis_person_sourcedid": "59254-6782-12ab",
    "lti11_legacy_user_id": "668321221-2879",
    "roles": [
      "Instructor",
      "Mentor"
    ],
    "message" : [
      {
        "https://purl.imsglobal.org/spec/lti/claim/message_type" : "LtiResourceLinkRequest",
        "https://purl.imsglobal.org/spec/lti-bo/claim/basicoutcome" : {
          "lis_result_sourcedid": "example.edu:71ee7e42-f6d2-414a-80db-b69ac2defd4",
          "lis_outcome_service_url": "https://www.example.com/2344"
        },
        "https://purl.imsglobal.org/spec/lti/claim/custom": {
          "country" : "Canada",
          "user_mobile" : "123-456-7890"
        }
      }
    ]
  }
]
}
```

Figure 2 Example of application/vnd.ims.lti-nrps.v2.membershipcontainer+json media type for resource link.

### Access restriction

A platform must deny access to this request if the Resource Link is not owned by the Tool making the
request or the resource link is not present in the Context.

### Message section

When queried in the context of a Resource Link, an additional message section is added per member.
This element must contain any context or resource link specific message parameters,
including any extension or custom parameters, which would be included in the message
from the specified Resource Link and which contain data specific to the member.

The parameters must be included using the LTI 1.3 claims format defined in [LTI-13].

### Membership filtered

A platform may return a subset of the context memberships, reflecting which members can actually
access the Resource Link.

### Basic Outcome

The ability to query Resource Link membership has usually been used to discover the `lis_result_sourcedid`
ahead of the learner actually launching the resource. If the Tool integration still relies on
Basic Outcome, the platform should include in the message section the Basic Oucome claim
`https://purl.imsglobal.org/spec/lti-bo/claim/basicoutcome` as defined in [LTI-BO-10].

### Substitution parameters

Any substitution parameters pertaining to member information should be resolved.
For example, any custom parameter whose value uses a '$User' or '$Person' substitution variable should be included
and resolved if supported by the platform.

### Binding with LTI Core

#### LTI 1.3 integration

##### Claim for inclusion in LTI messages

The claim to include Names and Role Provisioning Service parameter in LTI 1.3 messages is:
`https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice`.

It contains 2 properties: `context_memberships_url` (service url) and `service_version`. The service URL is always
fully resolved, and matches the context of the launch. The `service_versions` specifies the versions of the service that are
supported on that end point.

```json
"https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice": {
    "context_memberships_url": "https://www.myuniv.example.com/2344/memberships",
    "service_versions": ["2.0"]
  }
```

##### Scope and Service security

All service requests should be secured by including a properly scoped access token
in the Authorization header as per the 1EdTech Security Framework [SEC-10].

The scope to request to access this service is:

| Scope | Description | Allowed HTTP Methods |
| --- | --- | --- |
| `https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly` | Tool can query context's enrollment | context\_memberships\_url : GET |

#### LTI 1.1 integration

A platform may offer this version of the service to LTI 1.1 tools.

The service endpoint is passed using the custom parameter: `custom_context_memberships_v2_url`.

All service requests should be secured by signing them using the lti\_oauth\_body\_hash\_ws\_security
Web Services Security Profile as described in the Security document [LTI-SEC-14].

##### Use LTI 1.3 message type name and claims

When accessing membership for a given resource link id, the message type used in the message
section must be `LtiResourceLinkRequest`, not `basic-lti-launch-request`
even if this version of the service is used under a 1.1 integration.

The message section must use the LTI 1.3 claims format.

## Revision history

LTI Names and Role Provisioning Services v2.0 follows from, and replaces, the Membership Services
v1.0 specification (later rebranded as 1EdTech Membership Services).

### Version History

| Version number | Release date | Comments |
| --- | --- | --- |
| Membership Service v1.0 | 24 May 20016 | The first version of the Membership Service specification. |
| Names and Role Provisioning Services v2.0 | 16 April 2019 | Replaces the Membership Service specification. |

### Changes in this version

## References

### Normative references

[LIS-20]
:   [1EdTech Learning Information Services v2.0](https://www.imsglobal.org/lis/). Linda Feng; W. Lee; Colin Smythe. 1EdTech Consortium. June 2011. URL: <https://www.imsglobal.org/lis/>

[LTI-13]
:   [1EdTech Learning Tools Interoperability® Core Specification v1.3](https://www.imsglobal.org/spec/lti/v1p3/). C. Vervoort; N. Mills. 1EdTech Consortium. April 2019. 1EdTech Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/>

[LTI-CERT-13]
:   [1EdTech Learning Tools Interoperability® Advantage Conformance Certification Guide](https://www.imsglobal.org/spec/lti/v1p3/cert/). D. Haskins; M. McKell. 1EdTech Consortium. April 2019. 1EdTech Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/cert/>

[RFC2119]
:   [Key words for use in RFCs to Indicate Requirement Levels](https://tools.ietf.org/html/rfc2119). S. Bradner. IETF. March 1997. Best Current Practice. URL: <https://tools.ietf.org/html/rfc2119>

[RFC8288]
:   [Web Linking](https://tools.ietf.org/html/rfc8288). M. Nottingham. IETF. October 2017. Proposed Standard. URL: <https://tools.ietf.org/html/rfc8288>

[SEC-10]
:   [1EdTech Security Framework v1.0](https://www.imsglobal.org/spec/security/v1p0/). C. Smythe; C. Vervoort; M. McKell; N. Mills. 1EdTech Consortium. April 2019. 1EdTech Final Release. URL: <https://www.imsglobal.org/spec/security/v1p0/>

[W3C-ORG]
:   [The Organization Ontology](https://www.w3.org/TR/vocab-org/). Dave Reynolds. W3C. January 2014. URL: <https://www.w3.org/TR/vocab-org/>

### Informative references

[LTI-BO-10]
:   [Learning Tools Interoperability v1.0 Outcomes Management](https://www.imsglobal.org/specs/ltiomv1p0/specification). Stephen Vickers. 1EdTech Consortium. January 5, 2015. URL: <https://www.imsglobal.org/specs/ltiomv1p0/specification>

[LTI-IMPL-13]
:   [1EdTech Learning Tools Interoperability (LTI)® Advantage Implementation Guide](https://www.imsglobal.org/spec/lti/v1p3/impl/). C. Vervoort; J. Rissler; M. McKell. 1EdTech Consortium. April 2019. 1EdTech Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/impl/>

[LTI-SEC-14]
:   [1EdTech Learning Tools Interoperability (LTI) Security Version 2.0](https://www.imsglobal.org/specs/ltiv2p0/security). Greg McFall; Lance Neumann; Stephen Vickers. 1EdTech Consortium. January 2014. URL: <https://www.imsglobal.org/specs/ltiv2p0/security>

## List of Contributors

The following individuals contributed to the development of this document:

| Name | Organization | Role |
| --- | --- | --- |
| Paul Gray | Learning Objects |  |
| Viktor Haag | D2L |  |
| Dereck Haskins | 1EdTech |  |
| Martin Lenord | Turnitin |  |
| Karl Lloyd | Instructure |  |
| Mark McKell | 1EdTech |  |
| Nathan Mills | Instructure |  |
| Bracken Mosbacker | Lumen Learning |  |
| Marc Phillips | Instructure |  |
| Eric Preston | Blackboard | Editor |
| James Rissler | 1EdTech | Editor |
| Charles Severance | University of Michigan |  |
| Lior Shorshi | McGraw-Hill Education |  |
| Colin Smythe | 1EdTech |  |
| Claude Vervoort | Cengage | Editor |
