# Learning Tools Interoperability (LTI)® Core Specification

IMS Final Release
Spec Version 1.3

IMS Final Release

|  |  |
|----|----|
| Document Version: | 3 |
| Date Issued: | 16 April 2019 |
| Status: | This document is made available for adoption by the public community at large. |
| This version: | <https://www.imsglobal.org/spec/lti/v1p3/> |
| Latest version: | <https://www.imsglobal.org/spec/lti/latest/> |
| Errata: | <https://www.imsglobal.org/spec/lti/v1p3/errata/> |

## IPR and Distribution Notice

Recipients of this document are requested to submit, with their comments, notification of any relevant patent claims or other intellectual property rights of which they may be aware that might be infringed by any implementation of the specification set forth in this document, and to provide supporting documentation.

IMS takes no position regarding the validity or scope of any intellectual property or other rights that might be claimed to pertain implementation or use of the technology described in this document or the extent to which any license under such rights might or might not be available; neither does it represent that it has made any effort to identify any such rights. Information on IMS's procedures with respect to rights in IMS specifications can be found at the IMS Intellectual Property Rights webpage: <http://www.imsglobal.org/ipr/imsipr_policyFinal.pdf> .

Use of this specification to develop products or services is governed by the license with IMS found on the IMS website: <http://www.imsglobal.org/speclicense.html>.

Permission is granted to all parties to use excerpts from this document as needed in producing requests for proposals.

The limited permissions granted above are perpetual and will not be revoked by IMS or its successors or assigns.

THIS SPECIFICATION IS BEING OFFERED WITHOUT ANY WARRANTY WHATSOEVER, AND IN PARTICULAR, ANY WARRANTY OF NONINFRINGEMENT IS EXPRESSLY DISCLAIMED. ANY USE OF THIS SPECIFICATION *SHALL* BE MADE ENTIRELY AT THE IMPLEMENTER'S OWN RISK, AND NEITHER THE CONSORTIUM, NOR ANY OF ITS MEMBERS OR SUBMITTERS, *SHALL* HAVE ANY LIABILITY WHATSOEVER TO ANY IMPLEMENTER OR THIRD PARTY FOR ANY DAMAGES OF ANY NATURE WHATSOEVER, DIRECTLY OR INDIRECTLY, ARISING FROM THE USE OF THIS SPECIFICATION.

Public contributions, comments and questions can be posted here: <http://www.imsglobal.org/forums/ims-glc-public-forums-and-resources> .

© 2023 IMS Global Learning Consortium, Inc. All Rights Reserved.

Trademark information: <http://www.imsglobal.org/copyright.html>

## Abstract

The IMS Learning Tools Interoperability (LTI)® specification allows Learning Management Systems (LMS) or platforms to integrate remote tools and content in a standard way. LTI™ v1.3 builds on LTI v1.1 by incorporating a new model for security for message and service authentication.

## Table of Contents

1.  Abstract
2.  1. Overview
    1.  1.1 Terminology
    2.  1.2 Conformance Statements
    3.  1.3 Document Set
        1.  1.3.1 Normative Documents
        2.  1.3.2 Informative Documents
3.  2. History of this specification
4.  3. Key concepts and elements
    1.  3.1 Platforms and tools
        1.  3.1.1 Historical identification of LTI integration parties
        2.  3.1.2 LTI Domain Model
        3.  3.1.3 Tool Deployment
        4.  3.1.4 LTI Links
        5.  3.1.5 LTI Launch
    2.  3.2 Contexts and resources
    3.  3.3 Users and roles
    4.  3.4 Authentication, authorization, and capabilities
    5.  3.5 Messages and services
5.  4. LTI message general details
    1.  4.1 Additional login parameters
        1.  4.1.1 lti_message_hint login parameter
        2.  4.1.2 lti_deployment_id login parameter
        3.  4.1.3 client_id login parameter
    2.  4.2 JSON Web Token
    3.  4.3 Message claims
        1.  4.3.1 Message type and schemas
    4.  4.4 General LTI Launch Details
6.  5. Resource link launch request message
    1.  5.1 Resource link
    2.  5.2 Launch from a resource link
    3.  5.3 Required message claims
        1.  5.3.1 Message type claim
        2.  5.3.2 LTI Version claim
        3.  5.3.3 LTI Deployment ID claim
        4.  5.3.4 Target Link URI
        5.  5.3.5 Resource link claim
        6.  5.3.6 User Identity claims
        7.  5.3.7 Roles claim
    4.  5.4 Optional message claims
        1.  5.4.1 Context claim
        2.  5.4.2 Platform instance claim
        3.  5.4.3 Role-scope mentor claims
        4.  5.4.4 Launch presentation claim
        5.  5.4.5 Learning Information Services LIS claim
        6.  5.4.6 Custom properties and variable substitution
        7.  5.4.7 Vendor-specific extension claims
7.  6. Interacting with services
    1.  6.1 Services exposed as additional claims
    2.  6.2 Token endpoint claim and services
        1.  6.2.1 Deployment ID
8.  A. Appendix A - LTI standard vocabularies
    1.  A.1 Context type vocabulary
    2.  A.2 Role vocabularies
        1.  A.2.1 LIS vocabulary for system roles
        2.  A.2.2 LIS vocabulary for institution roles
        3.  A.2.3 LIS vocabulary for context roles
        4.  A.2.4 LTI vocabulary for system roles
9.  B. Custom parameter substitution
    1.  B.1 LTI User Variables
    2.  B.2 LIS Person Variables
    3.  B.3 LTI Context Variable
    4.  B.4 LTI ResourceLink Variables
    5.  B.5 LIS Course Template Variables
    6.  B.6 LIS Course Offering Variables
    7.  B.7 LIS Course Section Variables
    8.  B.8 LIS Group Variables
    9.  B.9 LIS Membership Variables
    10. B.10 LIS Message Variables
    11. B.11 Tool Platform Variables
    12. B.12 Custom Variables
10. C. Representing LTI links in an IMS Common Cartridge
11. D. Using Learning Information Services with LTI
12. E. Full example resource link request
13. F. Revision History
    1.  F.1 Version History
14. G. References
    1.  G.1 Normative references
15. H. List of Contributors

## 1. Overview

This document defines the LTI ecosystem for integrating platforms with external tools or applications using the IMS Security Framework [SEC-10] for message and service authentication.

### 1.1 Terminology

IRI
The Internationalized Resource Identifier (IRI) extends the Uniform Resource Identifier (URI) scheme by using characters drawn from the Universal character set rather than US-ASCII per [RFC3987].

LIS
Learning Information Services® (LIS®) is an IMS standard that defines how systems manage the exchange of information that describes people, groups, memberships, courses and outcomes.

LTI
Learning Tools Interoperability (LTI) is an IMS standard for integration of rich learning applications within educational environments.

URI
The Uniform Resource Identifier (URI) utilizes the US-ASCII character set to identify a resource. Per [RFC2396], a URI "can be further classified as a locator, a name or both." Both the Uniform Resource Locator (URL) and the Uniform Resource Name (URN) are considered subspaces of the more general URI space.

URL
A Uniform Resource Locator (URL) is a type of URI that provides a reference to resource that specifies both its location and a means of retrieving a representation of it. An HTTP URI is a URL.

URN
A Uniform Resource Name (URN) is a type of URI that provides a persistent identifier for a resource that is bound to a defined namespace. Unlike a URL, a URN is location-independent and provides no means of accessing a representation of the named resource.

UUID
A 128-bit identifier that does not require a registration authority to assure uniqueness. However, absolute uniqueness is not guaranteed although the collision probability is considered extremely low. LTI recommends use of randomly or pseudo-randomly generated version 4 UUIDs.

### 1.2 Conformance Statements

As well as sections marked as non-normative, all authoring guidelines, diagrams, examples, and notes in this specification are non-normative. Everything else in this specification is normative.

The key words *MAY*, *MUST*, *MUST NOT*, *OPTIONAL*, *RECOMMENDED*, *REQUIRED*, *SHALL*, *SHALL NOT*, *SHOULD*, and *SHOULD NOT* in this document are to be interpreted as described in [RFC2119].

An implementation of this specification that fails to implement a MUST/REQUIRED/SHALL requirement or fails to abide by a MUST NOT/SHALL NOT prohibition is considered nonconformant. SHOULD/SHOULD NOT/RECOMMENDED statements constitute a best practice. Ignoring a best practice does not violate conformance but a decision to disregard such guidance should be carefully considered. MAY/OPTIONAL statements indicate that implementers are entirely free to choose whether or not to implement the option.

The Conformance and Certification Guide for this specification may introduce greater normative constraints than those defined here for specific service or implementation categories.

### 1.3 Document Set

#### 1.3.1 Normative Documents

LTI Advantage Conformance Certification Guide [LTI-CERT-13]
The LTI Advantage Conformance Certification Guide describes the procedures for testing Platforms and Tools against the LTI v1.3 and LTI Advantage services using the IMS certification test suite.

Errata
The errata [LTI-CORE-13-ERRATA] details any erratum registered for this version of this specification since its publication.

#### 1.3.2 Informative Documents

LTI Advantage Implementation Guide [LTI-IMPL-13]
The LTI Advantage Implementation Guide provides information to lead you to successful implementation and certification of the LTI Core v1.3 specification and the set of LTI Advantage specifications.

## 2. History of this specification

LTI has its origins in the IMS Tools Interoperability specifications released in 2006. IMS then developed this into what is now referred to as Learning Tools Interoperability, or LTI. In May 2010, IMS released a version named Basic LTI that described a simple mechanism for launching tools and content from within an LMS. This provided a small but useful subset of the functionality that underlies LTI 1.3 and future releases. When IMS added a simple outcomes service in March 2011, it renamed Basic LTI as LTI 1.0, with the new release including the simple outcomes service named as LTI 1.1.

LTI version 1.3 improves upon version [LTI-11] by moving away from the use of OAuth 1.0a-style signing for authentication and towards a new security model, using OpenID Connect, signed JWTs, and OAuth2.0 workflows for authentication.

## 3. Key concepts and elements

This document uses specific terminology and concepts that are important to understand.

### 3.1 Platforms and tools

An LTI-based ecosystem consists of two principal types of software services:

**Platform**. A *tool platform* or, more simply, *platform* has traditionally been a Learning Management Systems (LMS), but it may be any kind of platform that needs to delegate bits of functionality out to a suite of *tools*.

**Tool**. The external application or service providing functionality to the *platform* is called a *tool*. Examples of *tools* might include an externally hosted testing system or a server that contains externally hosted premium content.

#### 3.1.1 Historical identification of LTI integration parties

Note that, historically, LTI referred to *platforms* as *tool consumers* and referred to *tools* as *tool providers*. As this does not align with usage of these terms within the OAuth2 and OpenID Connect communities, LTI 1.3 no longer uses these terms and shifts to the terms *platform* and *tool* to describe the parties involved in an LTI integration.

#### 3.1.2 LTI Domain Model

This non-normative diagram illustrates the general LTI domain model as defined in this document. Note that in the case of a single tenant model, some one to many relationships will de facto become one to one; for example, a tool will only have one deployment, a platform a single platform instance.

![LTI Entity model](https://www.imsglobal.org/sites/default/files/specs/images/lti/1p3/lti_entity_model.png)

*Figure 1 Diagram illustrating multiple the main entities making the LTI domain and their relationships.*

#### 3.1.3 Tool Deployment

A deployment of a tool defines the scope of contexts under which a tool is made available. For example, a tool may be deployed by the instructor into a single course, or the institution may deploy a tool across the whole institution, available to all institution's contexts, present and future.

When a user deploys a tool within their tool platform, the platform *MUST* generate an immutable `deployment_id` identifier to identify the integration. A platform *MUST* generate a unique `deployment_id` for each tool it integrates with. Every message between the platform and tool *MUST* include the `deployment_id` in addition to the `client_id`.

A platform must always generate a deployment id even if the tool is only deployed once in the platform (see multi-tenant and single-tenant model below).

A tool *MUST* thus allow multiple deployments on a given platform to share the same `client_id` and the security contract attached to it.

##### 3.1.3.1 Deployment id as account identifier

A common usage for the tool is to use the deployment id as an account identifier, for example attaching the institution's deployment to the institution's account, or a course-level deployment to a personal instructor's account.

##### 3.1.3.2 Multi-tenant: tool registered once, deployed multiple times

In this deployment model, the tool is registered once; during registration, the security contract is established, keys are exchanged and a `client_id` is created by the platform. The tool may then be subsequently deployed once or multiple times, each deployment identified by its own lti `deployment_id`.

![TBD](https://www.imsglobal.org/sites/default/files/spec/images/lti/1p3/deployments_bw.png)

*Figure 2 Diagram illustrating multiple deployments of one Tool within the Platform using the same security contract.*

##### 3.1.3.3 Single tenant: tool registered and deployed once

In this deployment model, the registration and deployment are often done at the same time, the tool only being deployed once under the given `client_id`; Each deployment gets its own security contract, and there is a one to one relation between the `client_id` and `deployment_id`.

![TBD](https://www.imsglobal.org/sites/default/files/spec/images/lti/1p3/deployments_onetoone_bw.png)

*Figure 3 Diagram illustrating multiple deployments of one Tool within the Platform using unique security contracts.*

#### 3.1.4 LTI Links

An LTI Link is a reference to a specific tool stored by a platform which may, for example, lead to a specific resource or content hosted on the tool, depending on the `message_type` of the LTI Link (see section  4.3 Message claims for more information on message_type). The LTI Link is presented by the platform that provides access to the content of the tool and may be used as a means of performing LTI launches within the context of the platform.

Typically, an LTI link contains a URL that points to the tool, along with some other metadata used for identification and presentation purposes that are unique to each link. Often LTI Links are presented to a user as an HTML link, but the two concepts should not be confused - an LTI Link is not just a URL, but may contain additional data that must be included in a launch to the tool.

Each LTI Link *MUST* be associated with a single `deployment_id` to identify the tool deployment it is linked to. A platform *MAY* display multiple instances of the same LTI Link within a page.

Each LTI Link connected to a particular resource (as described in section  3.2 Contexts and resources below) *MUST* contain a platform unique identifier named `resource_link_id`. When an LTI Link is associated with a resource, it is referred to as a Resource Link (see section  5.1 Resource link for more details).

#### 3.1.5 LTI Launch

An LTI Launch refers to the process in which a user interacts with an LTI Link within the platform and is subsequently "launched" into a tool. The data between tool and platform in establishing a launch are defined upon tool integration into the platform. LTI platforms and tools use `messages` to transfer the user agent from one host to another through an HTML form post redirection containing the message payload. The data of this payload is determined by the `message_type` as discussed in section  4.3.1 Message type and schemas of this document.

### 3.2 Contexts and resources

LTI generally organizes collections of *resources* into *contexts*:

**Context**. LTI uses the term *context* where you might expect to see the word "course". A context is roughly equivalent to a course, project, or other collection of *resources* with a common set of users and roles. LTI uses the word "context" instead of "course" because a course is only one kind of context (another type could be "group" or "section").

**Resource**. Typically, within a context, users can integrate many LTI content items, or *resources*, sometimes arranging them into folders like "Week 1" or "Pre-Work". Conceptually, these platform integrations serve the same general purpose as any other type of item within the structure of a context's available content. In particular, commonly, users may scatter multiple *LTI links* through the content structure for a context that is linked to a particular resource. A platform *MUST* distinguish between each of these *LTI links* by assigning a `resource_link_id` to an *LTI Link*.

While all the LTI links integrated within a single context will share the same `context_id`, each link within the context will have a unique `resource_link_id`. This allows the hosting *tool* to differentiate the content or features it shows on a resource-by-resource basis (within a context) by, for example, providing configuration options such as a resource picker to the instructor or administrator after launching from a particular link.

### 3.3 Users and roles

LTI generally recognizes that *users* make use of the integrated functionality offered by *tools* to *platforms*. These users typically come with a defined *role* with respect to the *context* within which they operate when using a tool.

**User**. An object representing a person with a current session within the *platform* and provided to the *tool*. The platform *MAY* delegate the authentication process to another system (for example, an LDAP server). A user *MUST* have a unique identifier within the platform, which acts as an OpenId Provider. Typical properties such as a first name, last name, and email address, *MAY* be shared with a tool. A tool or platform *MUST NOT* use any other attribute other than the unique identifier to identify a user when interacting between tool and platform.

**Role**. The role is one of the three main properties provided by the platform when a *user* launches via an LTI link to a *tool* (the other two items are the ID values that identify the *user* performing the launch, and the *context* containing the LTI link from which the launch initiated, all of which are optional). The role represents the level of privilege a user has been given within the context hosted by the platform. Typical roles are "learner", "instructor", and "administrator". Note that it's entirely possible that a user might have a different role in a different context (a user that is a "student" in one context may be an "instructor" in another, for example).

Tools may, in turn, use the role to determine the level of access they may give to a user.

### 3.4 Authentication, authorization, and capabilities

**Authentication**: Platforms in LTI acts as OpenID Providers and LTI Messages are OpenID tokens communicating the End-User's identity from the platform to the tool using the OpenID third-party initiated login flow. See the IMS Security Framework [SEC-10] for more details.

The platform may use other authentication mechanisms to further verify identity or associate the platform user with a pre-existing tool's user account. The tool would traditionally only do this on a user's first launch from a given platform.

**Authorization**. The process of identifying a user's right to gain access to resources or functionality. LTI addresses the overall authorization requirements for integrations between platform and tool at two different levels:

- Within the LTI layers themselves, LTI authorizes the *capabilities* (services, messages, or variables) a tool is allowed to use with the platform.

- LTI supports the authorization work of the tool itself by reliably conveying contextually rich property data to the tool via messages. For example, for some tool to authorize a particular user to read an ebook, it might require the user's identity and role within a particular course context (all properties that the platform can pass along within a launch message).

**Capability**. A formal definition of some pattern of behavior. LTI v1.3 defines three broad kinds of capabilities:

- Variable expansion

- Messages

- Services

The *platform* can advertise the capabilities it supports via the messages it sends to the *tool*.

### 3.5 Messages and services

LTI supports two different kinds of integration between platforms and tools:

- Via *messages* (intermediated by a user's browser)

- Via *services* (direct connections between platform and tool)

**Messages**. When a user clicks on the embedded link for an LTI *resource* within the platform, the platform initiates an OpenID login which ultimately results in the platform passing the LTI Message (`id_token`) to the tool as defined in the IMS Security Framework [SEC-10].

The *resource link message*, used to launch a tool's resource, is described in this document. Other kinds of launch messages might also be supported between platform and tool (in either direction).

Receivers of LTI messages *MUST* ignore any contextual data contained in the message that they do not understand.

**Services**. When a *tool* needs to directly access a *platform* (or vice-versa), LTI 1.3 names these connections *services* (not mediated by a user with a browser); typically the providers of these services host them as simple REST-like HTTP-based web services.

**Authentication for messages and services**. LTI v1.3 supports specific, separate (but related) authentication mechanisms for *messages* and *services*, defined in the IMS Security Framework [SEC-10]. LTI v1.3 requires the use of HTTPS (using TLS) for *both* messages *and* services. Additionally, implementers *MUST* use HTTPS for all URLs to resources included in messages and services (for example, URLs to service endpoints, or to static content like images and thumbnails).

## 4. LTI message general details

Messages between a platform and host are used to transfer the user agent between hosts (as described in section  3.1.3 Tool Deployment of this document). This section further details the required structure of these messages. An LTI Message is the simplest way that a platform and tool communicate. Further requirements for structuring a message may be required depending on the scenario (such as when performing an LTI Launch).

### 4.1 Additional login parameters

In addition to the OpenId 3rd Party Initiated parameters defined in the IMS Security Framework [SEC-10], this specification introduces a number of new parameters as defined below.

#### 4.1.1 lti_message_hint login parameter

The new optional parameter `lti_message_hint` may be used alongside the `login_hint` to carry information about the actual LTI message that is being launched.

Similarly to the `login_hint` parameter, `lti_message_hint` value is opaque to the tool. If present in the login initiation request, the tool *MUST* include it back in the authentication request unaltered.

#### 4.1.2 lti_deployment_id login parameter

The new optional parameter `lti_deployment_id` that if included, *MUST* contain the same deployment id that would be passed in the <https://purl.imsglobal.org/spec/lti/claim/deployment_id> claim for the subsequent LTI message launch.

This parameter may be used by the tool to perform actions that are dependent on a specific deployment. An example of this would be, using the deployment id to identify the region in which a tenant linked to the deployment lives. Subsequently changing the `redirect_url` the final launch will be directed to.

#### 4.1.3 client_id login parameter

The new optional parameter `client_id` specifies the client id for the authorization server that should be used to authorize the subsequent LTI message request. This allows for a platform to support multiple registrations from a single issuer, without relying on the `initiate_login_uri` as a key.

### 4.2 JSON Web Token

LTI messages sent from the platform are *OpenID Tokens*. Messages sent from the tool are *JSON Web Tokens* (JWT) as the tool is not typically acting as OpenID Provider.

The IMS Security Framework [SEC-10] describes the process by which a message sender encodes its message into a JWT.

### 4.3 Message claims

Each message type supplements the fundamental claims mandated by the IMS Security Framework [SEC-10] with additional claims specific to the needs of that message type. LTI message types specified in other documents may reuse some message claims defined here for the *LTI resource link launch request*, when applicable. Each message type's specification defines which claims are required and which claims are optional.

In order to preserve forward compatibility and interoperability between platforms and tools, receivers of messages *MUST* ignore any claims in messages they do not understand, and not treat the presence of such claims as an error on the part of the message sender.

#### 4.3.1 Message type and schemas

A message's [`https://purl.imsglobal.org/spec/lti/claim/message_type`](https://purl.imsglobal.org/spec/lti/claim/message_type) claim declares the general intent of the workflow. Each type of message will have its own value for this claim, indicating to the receiver of the message what kind of message the sender has sent.

Each message type has an associated `JSON Schema` definition that formally defines all its claims, and further defines which of those claims are optional or are required. An example of defining a message type is shown in the table below.

### 4.4 General LTI Launch Details

A *platform* displaying an LTI Link to a user can perform an LTI Launch to a *tool* in the following manner. Depending on the message*type of the link, the platform turns the message's payload JSON into a JWT to include in the launch request message body; each top-level property within this object becomes a \_claim* in the resulting JWT. After encoding as a JWT, the platform sends the message as a form post using the `JWT` or `id_token` parameter (see the IMS Security Framework [SEC-10]) for more details about the use of `JWT` and `id_token`), redirecting the user's browser to the tool's resource link URL.

## 5. Resource link launch request message

This document describes the composition of the *LTI resource link launch request*. The LTI ecosystem supports other kinds of messages defined in other specification documents (for example, the *content item selection request* message defined in the LTI Deep Linking [LTI-DL-20] specification).

This message type encapsulates the fundamental workflow of a user clicking a link in the presented user experience of a context hosted by the *platform* and thereby launching out to an external *tool* that will provide a related, but separate, user experience. With this workflow, the platform sends this message, and the tool receives the message.

The table below describes the name of the message type, `the message_type`, and the schema defined in the message type's launch.

| Name | Message type | Schema |
|----|----|----|
| Resource link launch request | `LtiResourceLinkRequest` | Resource Link Request message JSON |

![TBD](https://www.imsglobal.org/sites/default/files/spec/images/lti/1p3/resource_link_bw.png)

*Figure 4 Diagram illustrating the flow of the LTI resource link launch request.*

### 5.1 Resource link

LTI uses the term *resource link* to refer to a link to a resource delivered by a *tool*. LTI intends platforms to present resource links to their users in a manner similar to any other resource within the structure of a context. In particular, LTI expects that a platform may embed multiple LTI resource links (to many different tools), scattered throughout the content structure for the context.

LTI uses the `resource_link_id` property to help platforms and tools differentiate amongst multiple links embedded in a single context. While all the links within a context will share the same `context_id`, each LTI resource link will have a *platform wide* unique resource link ID. See section  3.1.2 LTI Domain Model of this document for more details.

### 5.2 Launch from a resource link

The *LTI resource link launch request* originates from within the platform starting from a single LTI resource link. It *MUST* identify the *resource link* related to the launch. It should, by best practice, include the *context* in which the launch originates; it should also, by best practice, include the *user* doing the launch except in the case where the user's identity is to remain anonymous. It should also, by best practice, include the *roles* of that user in the context of the launch and other information about the platform, the context, and the resource link, as defined in the following sections.

The tool will use this information to decide whether to grant the user access to that resource, and, if so, how to present the resource to the user. For example, the view of a resource the tool gives to a student in the context of a course may differ from the view it offers to the course's instructor or administrator.

See  E. Full example resource link request for an example of a full resource link launch message payload (the examples in the following sections are excerpts from that example).

### 5.3 Required message claims

LTI resource link launch request messages *MUST* contain all the claims included in this section (except in the case of anonymous launches, where sending the user identity is not required). Note that some of the claims compose several properties, only some of which are required.

#### 5.3.1 Message type claim

The required [`https://purl.imsglobal.org/spec/lti/claim/message_type`](https://purl.imsglobal.org/spec/lti/claim/message_type) claim's value contains a string that indicates the type of the sender's LTI message. For conformance with this specification, the claim must have the value `LtiResourceLinkRequest`.

#### 5.3.2 LTI Version claim

The required [`https://purl.imsglobal.org/spec/lti/claim/version`](https://purl.imsglobal.org/spec/lti/claim/version) claim's value contains a string that indicates the version of LTI to which the message conforms. For conformance with this specification, the claim must have the value `1.3.0`.

#### 5.3.3 LTI Deployment ID claim

The required [`https://purl.imsglobal.org/spec/lti/claim/deployment_id`](https://purl.imsglobal.org/spec/lti/claim/deployment_id) claim's value contains a case-sensitive string that identifies the platform-tool integration governing the message. It *MUST NOT* exceed 255 ASCII characters in length.

The `deployment_id` is a stable locally unique identifier within the `iss` (Issuer).

The `deployment_id` is an essential attribute for tools to associate to an account. See the section  3.1.3 Tool Deployment for more details.

#### 5.3.4 Target Link URI

The required [`https://purl.imsglobal.org/spec/lti/claim/target_link_uri`](https://purl.imsglobal.org/spec/lti/claim/target_link_uri) *MUST* be the same value as the `target_link_uri` passed by the platform in the OIDC third party initiated login request.

The target link URI is the actual endpoint for the LTI resource to display; for example, the `url` in Deep Linking `ltiResourceLink` items, or the `launch_url` in IMS Common Cartridges, or any launch URL defined in the tool configuration.

A Tool should rely on this claim rather than the initial `target_link_uri` to do the final redirection, since the login initiation request is unsigned.

#### 5.3.5 Resource link claim

The required [`https://purl.imsglobal.org/spec/lti/claim/resource_link`](https://purl.imsglobal.org/spec/lti/claim/resource_link) claim composes properties for the resource link from which the launch message occurs, as in the following example:

```
{
...
"https://purl.imsglobal.org/spec/lti/claim/resource_link": {
...
"id": "200d101f-2c14-434a-a0f3-57c2a42369fd",
...
}
...
}
```

**id** (*REQUIRED*). Opaque identifier for a placement of an LTI resource link within a *context* that *MUST* be a stable and locally unique to the `deployment_id`. This value *MUST* change if the link is copied or exported from one system or context and imported into another system or context. The value of `id` *MUST NOT* exceed 255 ASCII characters in length and is case-sensitive.

**description** (*OPTIONAL*). Descriptive phrase for an LTI resource link placement.

**title** (*OPTIONAL*). Descriptive title for an LTI resource link placement.

#### 5.3.6 User Identity claims

Since any platform-originating message is an OpenID ID Token, user claims are defined in the OpenId Connect Standard Claims \[OpenID-14\] (section 5.1). LTI messages usually expect the following claims:

**sub** (Required): This is the only required user claim (except, see anonymous launch case following). When included, per OIDC specifications, the `sub` (Subject) *MUST* be a stable locally unique to the `iss` (Issuer) identifier for the actual, authenticated End-User that initiated the launch. It *MUST NOT* exceed 255 ASCII characters in length and is case-sensitive.

**given_name**: Per OIDC specifications, given name(s) or first name(s) of the End-User. Note that in some cultures, people can have multiple given names; all can be present, with the names being separated by space characters.

**family_name**: Per OIDC specifications, surname(s) or last name(s) of the End-User. Note that in some cultures, people can have multiple family names or no family name; all can be present, with the names being separated by space characters.

**name**: Per OIDC specifications, end-User's full name in displayable form including all name parts, possibly including titles and suffixes, ordered according to the End-User's locale and preferences.

**email**: Per OIDC specifications, end-User's preferred e-mail address.

**locale**: Per OIDC specifications, end-User's preferred locale as a BCP47 language tag.

Note that a platform may also add any other claims from the OpenID Connect Standard Claims list (for example, `gender`).

##### 5.3.6.1 Anonymous launch case

At times the platform may wish to send *anonymous request messages* to avoid sending identifying user information to the tool. To accommodate for this case, the platform may in these cases not include the `sub` claim or any other user identity claims. The tool must interpret the lack of a `sub` claim as a launch request coming from an anonymous user.

#### 5.3.7 Roles claim

The required [`https://purl.imsglobal.org/spec/lti/claim/roles`](https://purl.imsglobal.org/spec/lti/claim/roles) claim's value contains a (possibly empty) array of URI values for roles that the user has within the message's associated context.

If this list is not empty, it *MUST* contain at least *one* role from the *role vocabularies* described in role vocabularies.

If the sender of the message wants to include a role from another vocabulary namespace, by best practice it should use a fully-qualified URI to identify the role. By best practice, systems should not use roles from another role vocabulary, as this may limit interoperability.

##### 5.3.7.1 Anonymous launch case

Note that the platform may, in the case of an anonymous launch, provide no user-identity claims, but may still include roles claim values. These indicate, if present, what roles the anonymous user has within the context of the launch. If the platform wishes to send no role information, it must still send the roles claim, but may leave the value of the roles claim array empty.

### 5.4 Optional message claims

LTI resource link launch request messages *MAY* contain any of the following claims. LTI defines each group of claims with its own JSON Schema, and each message type schema aggregates one or more of those.

#### 5.4.1 Context claim

The optional [`https://purl.imsglobal.org/spec/lti/claim/context`](https://purl.imsglobal.org/spec/lti/claim/context) claim composes properties for the context from within which the resource link launch occurs. The following is an example of this claim as if the resource link launch is in the context of a course:

```
{
...
"https://purl.imsglobal.org/spec/lti/claim/context": {
"id": "c1d887f0-a1a3-4bca-ae25-c375edcc131a",
"label": "CPS 435",
"title":  "CPS 435 Learning Analytics",
"type": ["http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering"]
}
...
}
```

**id** (*REQUIRED*). Stable identifier that uniquely identifies the context from which the LTI message initiates. The context id *MUST* be locally unique to the `deployment_id`. It is recommended to also be locally unique to `iss` (Issuer). The value of `id` *MUST NOT* exceed 255 ASCII characters in length and is case-sensitive.

**type** (*OPTIONAL*). An array of URI values for context types. If present, the array *MUST* include at least *one* context type from the *context type vocabulary* described in context type vocabulary. If the sender of the message wants to include a context type from another vocabulary namespace, by best practice it should use a fully-qualified URI. By best practice, systems should not use context types from another role vocabulary, as this may limit interoperability.

**label** (*OPTIONAL*). Short descriptive name for the context. This often carries the "course code" for a course offering or course section context.

**title** (*OPTIONAL*). Full descriptive name for the context. This often carries the "course title" or "course name" for a course offering context.

#### 5.4.2 Platform instance claim

The optional [`https://purl.imsglobal.org/spec/lti/claim/tool_platform`](https://purl.imsglobal.org/spec/lti/claim/tool_platform) claim composes properties associated with the platform instance initiating the launch.

A typical usage is to identify the learning institution's online learning platform as in the following example:

```
"https://purl.imsglobal.org/spec/lti/claim/tool_platform": {
    "guid": "ex/48bbb541-ce55-456e-8b7d-ebc59a38d435",
    "product_family_code": "ExamplePlatformVendor-ZLMS",
    "name": "LMS from Example University"
}
```

In a multi-tenancy case, a single platform (`iss`) will host multiple instances, but each LTI message is originating from a single instance identified by its **guid**.

**guid** (*REQUIRED*). A stable locally unique to the `iss` identifier for an instance of the tool platform. The value of `guid` is a case-sensitive string that *MUST NOT* exceed 255 ASCII characters in length. The use of Universally Unique IDentifier (UUID) defined in [RFC4122] is recommended.

**contact_email** (*OPTIONAL*). Administrative contact email for the platform instance.

**description** (*OPTIONAL*). Descriptive phrase for the platform instance.

**name** (*OPTIONAL*). Name for the platform instance.

**url** (*OPTIONAL*). Home HTTPS URL endpoint for the platform instance.

**product_family_code** (*OPTIONAL*). Vendor product family code for the type of platform.

**version** (*OPTIONAL*). Vendor product version for the platform.

#### 5.4.3 Role-scope mentor claims

The optional [`https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor`](https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor) claim's value contains an array of the user ID values which the current, launching user can access as a mentor (for example, the launching user may be a parent or auditor of a list of other users), as in the following example:

```
{
...
  "https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor": [
    "fad5fb29-a91c-770-3c110-1e687120efd9",
    "5d7373de-c76c-e2b-01214-69e487e2bd33",
    "d779cfd4-bc7b-019-9bf1a-04bf1915d4d0"
  ]
...
}
```

Different systems may use this information in different ways, LTI generally expects that the message receiver will provide the mentor with access to tracking and summary information for other users, but not necessarily access to those users' personal data or content submissions.

The sender of the message *MUST NOT* include a list of user ID values in this property unless they also provide [`http://purl.imsglobal.org/vocab/lis/v2/membership#Mentor`](http://purl.imsglobal.org/vocab/lis/v2/membership#Mentor) as one of the values passed in the `roles` claim.

#### 5.4.4 Launch presentation claim

The optional [`https://purl.imsglobal.org/spec/lti/claim/launch_presentation`](https://purl.imsglobal.org/spec/lti/claim/launch_presentation) claim composes properties that describe aspects of how the message sender expects to host the presentation of the message receiver's user experience (for example, the height and width of the viewport the message sender gives over to the message receiver), as in the following example:

```
{
...
"https://purl.imsglobal.org/spec/lti/claim/launch_presentation": {
  "document_target": "iframe",
  ...
  "return_url": "https://platform.example.edu/terms/201601/courses/7/sections/1/resources/2"
  }
...
}
```

**document_target** (*OPTIONAL*). The kind of browser window or frame from which the user launched inside the message sender's system. The value for this property *MUST* be one of: `frame`, `iframe`, or `window`.

**height**, **width** (*OPTIONAL*). Height and width of the window or frame where the content from the message receiver will be displayed to the user.

**return_url** (*OPTIONAL*). Fully-qualified HTTPS URL within the message sender's user experience to where the message receiver can redirect the user back. The message receiver can redirect to this URL after the user has finished activity, or if the receiver cannot start because of some technical difficulty.

The message receiver may want to send back a message to the message sender. If the message sender includes a `return_url` in its `launch_presentation`, it *MUST* support these four query parameters that *MAY* parameterize the redirection to the return URL:

- `lti_errormsg`, `lti_msg`. Use these query parameters to carry a user-targeted message for unsuccessful or successful (respectively) activity completion. These are intended for showing to the user.

- `lti_errorlog`, `lti_log`. Use these query parameters to carry a log-targeted message for unsuccessful or successful (respectively) activity completion. These are intended for writing to logs.

**locale** (*OPTIONAL*). Language, country, and variant as represented using the IETF Best Practices for Tags for Identifying Languages [BCP47].

#### 5.4.5 Learning Information Services LIS claim

The optional [`https://purl.imsglobal.org/spec/lti/claim/lis`](https://purl.imsglobal.org/spec/lti/claim/lis) claim's value composes properties about available Learning Information Services (LIS), usually originating from the Student Information System, as in the following example:

```
{
  "https://purl.imsglobal.org/spec/lti/claim/lis": {
    "person_sourcedid": "example.edu:71ee7e42-f6d2-414a-80db-b69ac2defd4",
    "course_offering_sourcedid": "example.edu:SI182-F16",
    "course_section_sourcedid": "example.edu:SI182-001-F16"
  }
}
```

When the platform instance has access to these values it should, by best practice, provide them in messages sent to tools.

See  D. Using Learning Information Services with LTI) for more detail on this service.

#### 5.4.6 Custom properties and variable substitution

The optional [`https://purl.imsglobal.org/spec/lti/claim/custom`](https://purl.imsglobal.org/spec/lti/claim/custom) claim acts like a key-value map of defined custom properties that a platform may associate with the resource link that initiated the launch.

Each custom property name appears as a property within the message's top-level `custom` property. A custom property value must always be of type string. Note that "empty-string" is a valid custom value (`""`); note also that `null` is *not* a valid custom value.

##### 5.4.6.1 Custom property value substitution

Senders of LTI messages *MAY* have the ability to make value substitutions for custom properties, at launch time, as described in  B. Custom parameter substitution.

##### 5.4.6.2 Custom properties and Common Cartridge

 C. Representing LTI links in an IMS Common Cartridge explains how custom properties are represented when a link is stored in a Common Cartridge.

#### 5.4.7 Vendor-specific extension claims

Vendors *MAY* extend the information model for any message type and inject additional properties into the message's JSON object by adding one or more claims. Vendors *MUST* use a fully-qualified URL as the claim name for any of their extension claims.

```
"http://www.ExamplePlatformVendor.com/session": {
  "id": "89023sj890dju080"
}
```

By best practice, vendors should define custom variables as described in  5.4.6 Custom properties and variable substitution instead of relying on extension properties.

## 6. Interacting with services

### 6.1 Services exposed as additional claims

LTI does not rely on prior knowledge of service endpoints. Rather, the platform *MUST* include in each message applicable service endpoints as fully resolved URLs (not as URL templates).

The platform *MUST* have a separate claim in the message for each service, to contain the endpoints (and possibly other properties) relevant for that service. The endpoints and properties the platform sends for a service usually vary from message to message and are always fully resolved.

### 6.2 Token endpoint claim and services

Access tokens *MUST* protect all the services described by the platform; tools *MUST* retrieve these access tokens using the JSON Web Token (JWT) Profile for OAuth 2.0 Client Authentication and Authorization Grants as specified in the LTI Security Framework - Using JSON Web Tokens with OAuth 2.0 [SEC-10].

The access token endpoint is communicated during the tool registration and used to access all services (unless explicitly stated otherwise in the service definition).

When requesting an access token, the client assertion JWT `iss` and `sub` must both be the OAuth 2 `client_id` of the tool as issued by the learning platform during registration.

#### 6.2.1 Deployment ID

A resource server, e.g., platform instance, is uniquely identified by its `issuer`, `client_id`, and `deployment_id`, therefore when requesting an OAuth2 bearer token the client (i.e., tool) *SHOULD* include the deployment ID as part of the JWT to request a token.

This is an optional claim. In addition to including the client_id, some platforms may require the token to be scoped to a given LTI deployment of that tool, and thus will require the deployment ID to be included in the token request. In the event that a platform refuses to provide a token the platform *SHOULD* follow the guidance laid out in [section 4.1 of the IMS security document](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)

The claim name is `https://purl.imsglobal.org/spec/lti/claim/deployment_id`

```
{
    "iss" : "f9660dea-d7ac-4d2c-af4c-97d26bd90d96",
    "sub" : "f9660dea-d7ac-4d2c-af4c-97d26bd90d96",
    "aud" : ["https://www.example.com/lti/auth/token"],
    "iat" : "1485907200",
    "exp" : "1485907500",
    "jti" : "29f90c047a44b2ece73d00a09364d49b",
    "https://purl.imsglobal.org/spec/lti/claim/deployment_id":
      "07940580-b309-415e-a37c-914d387c1150"
}
```

## A. Appendix A - LTI standard vocabularies

This specification uses URI values to identify certain standard vocabulary entities. This section defines the URI values for various LIS context types. LTI 1.0 through LTI 1.1.1 used URN values for these entities, and allowed the use of simple names. LTI 1.3 supports the old simple name and URN values for backward compatibility, but deprecates their use and replaces them with a URI that points to entities in an RDF ontology.

Conforming implementations *MAY* recognize the deprecated simple names (for context types and context roles) and the deprecated URN values, and *MUST* recognize the new URI values.

### A.1 Context type vocabulary

The context type vocabularies are derived from the LIS v2.0 specification [LIS-20].

| Type | Name |
|----|----|
| Course Template | `http://purl.imsglobal.org/vocab/lis/v2/course#CourseTemplate` `CourseTemplate` (deprecated) `urn:lti:context-type:ims/lis/CourseTemplate` (deprecated) |
| Course Offering | `http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering` `CourseOffering` (deprecated) `urn:lti:context-type:ims/lis/CourseOffering` (deprecated) |
| Course Section | `http://purl.imsglobal.org/vocab/lis/v2/course#CourseSection` `CourseSection` (deprecated) `urn:lti:context-type:ims/lis/CourseSection` (deprecated) |
| Group | `http://purl.imsglobal.org/vocab/lis/v2/course#Group` `Group` (deprecated) `urn:lti:context-type:ims/lis/Group` (deprecated) |

### A.2 Role vocabularies

The role vocabularies are derived from the LIS 2.0 specification [LIS-20]. LTI divides them into core and non-core roles. Core roles are those which are most likely to be relevant within LTI and hence vendors should support them by best practice. Vendors may also use the non-core rules, but they may not be widely used.

#### A.2.1 LIS vocabulary for system roles

Core system roles

`http://purl.imsglobal.org/vocab/lis/v2/system/person#Administrator` `http://purl.imsglobal.org/vocab/lis/v2/system/person#None`

Non‑core system roles

`http://purl.imsglobal.org/vocab/lis/v2/system/person#AccountAdmin` `http://purl.imsglobal.org/vocab/lis/v2/system/person#Creator` `http://purl.imsglobal.org/vocab/lis/v2/system/person#SysAdmin` `http://purl.imsglobal.org/vocab/lis/v2/system/person#SysSupport` `http://purl.imsglobal.org/vocab/lis/v2/system/person#User`

*Note*. System roles using URIs with prefixes of `http://purl.imsglobal.org/vocab/lis/v2/person#` (e.g. `http://purl.imsglobal.org/vocab/lis/v2/person#Administrator`) are all deprecated. (Note the lack of the `system` keyword in the path for these deprecated URIs.)

#### A.2.2 LIS vocabulary for institution roles

|  |  |
|----|----|
| Core institution roles | `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Administrator` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Guest` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#None` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Other` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Staff` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Student` |
| Non‑core institution roles | `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Alumni` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Instructor` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Learner` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Member` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Mentor` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#Observer` `http://purl.imsglobal.org/vocab/lis/v2/institution/person#ProspectiveStudent` |

*Note*. Institution roles using URIs with prefixes of `http://purl.imsglobal.org/vocab/lis/v2/person#` (e.g. `http://purl.imsglobal.org/vocab/lis/v2/person#Administrator`) are all deprecated. (Note the lack of the `institution` keyword in the path for these deprecated URIs.)

#### A.2.3 LIS vocabulary for context roles

Core context roles are:

|  |  |
|----|----|
| Core context roles | `http://purl.imsglobal.org/vocab/lis/v2/membership#Administrator` `http://purl.imsglobal.org/vocab/lis/v2/membership#ContentDeveloper` `http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor` `http://purl.imsglobal.org/vocab/lis/v2/membership#Learner` `http://purl.imsglobal.org/vocab/lis/v2/membership#Mentor` |
| Non‑core context roles | `http://purl.imsglobal.org/vocab/lis/v2/membership#Manager` `http://purl.imsglobal.org/vocab/lis/v2/membership#Member` `http://purl.imsglobal.org/vocab/lis/v2/membership#Officer` |

Conforming implementations *MAY* recognize the simple names for context roles; thus, for example, vendors can use the following roles interchangeably:

- [`http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor`](http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor)
- `Instructor`

However, support for simple names in this manner for context roles is deprecated; by best practice, vendors should use the full URIs for all roles (context roles included).

##### A.2.3.1 Context sub-roles

Roles within the LIS 2.0 specification [LIS-20] consist of a principal RoleType and an optional SubRoleType, according to the following format:

> `http://purl.imsglobal.org/vocab/lis/v2/membership/{`*`rolename`*`}#{`*`sub-rolename`*`}`

For example, here is the URL for principal role `Instructor`, sub-role `TeachingAssistant`:

> [`http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant`](http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant)

The list below gives the sub-roles available for each principal context role.

Principal role

Sub-role

`Administrator`

`Administrator` `Developer` `ExternalDeveloper` `ExternalSupport` `ExternalSystemAdministrator` `Support` `SystemAdministrator`

`ContentDeveloper`

`ContentDeveloper` `ContentExpert` `ExternalContentExpert` `Librarian`

`Instructor`

`ExternalInstructor` `Grader` `GuestInstructor` `Lecturer` `PrimaryInstructor` `SecondaryInstructor` `TeachingAssistant` `TeachingAssistantGroup` `TeachingAssistantOffering` `TeachingAssistantSection` `TeachingAssistantSectionAssociation` `TeachingAssistantTemplate`

`Learner`

`ExternalLearner` `GuestLearner` `Instructor` `Learner` `NonCreditLearner`

`Manager`

`AreaManager` `CourseCoordinator` `ExternalObserver` `Manager` `Observer`

`Member`

`Member`

`Mentor`

`Advisor` `Auditor` `ExternalAdvisor` `ExternalAuditor` `ExternalLearningFacilitator` `ExternalMentor` `ExternalReviewer` `ExternalTutor` `LearningFacilitator` `Mentor` `Reviewer` `Tutor`

`Officer`

`Chair` `Communications` `Secretary` `Treasurer` `Vice-Chair`

LTI does not classify any of the sub-roles as a core role. Whenever a platform specifies a sub-role, by best practice it should also include the associated principal role; for example, by best practice, a platform specifying the [`http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant`](http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant) role should always also specify the [`http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor`](http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor) role.

#### A.2.4 LTI vocabulary for system roles

LTI defines roles that are specific to LTI launches.

|  |  |
|----|----|
| `http://purl.imsglobal.org/vocab/lti/system/person#TestUser` | This is a marker role to be used in conjunction with a "real" role. It indicates this user is created by the platform for testing different user scenarios. The most common use case is when an instructor wants to view the course as a student would see it, student-preview mode. Usually a new user object is created from the instructor user, with a flag it is a "preview user". It may be ephemeral, but it may not. The instructor can switch to this user view at any time. Tools may wish to filter out this user when displaying the course roster. They may want to ignore this user when it comes to sending grades, but they should be able to treat it as a regular user. |

## B. Custom parameter substitution

By prefixing the value of a custom parameter by \$, the tool indicates the use of a substitution parameter. A substitution parameter allows the platform to pass additional runtime data to the tool in addition to the core claims highlighted above; it allows a tool to tailor its message payload to include the additional data it needs.

Support for substitution parameters is optional; each platform may support a different set of variables. If the platform supports a given variable and authorizes the tool to access it, it must resolve it at launch time. Otherwise, the substitution parameter must be passed unresolved, indicating to the tool that this variable is not supported.

Substituted values must always be of type string. Note that "empty-string" is a valid value (`""`); note also that `null` is *not* a valid value.

If the platform does not have a value for a variable that it does support, then it should by best practice indicate this by sending an empty-string value (`""`); this means that LTI tools and platforms must be prepared to accept empty-string as a valid value for all properties, even when they have strict formatting requirements (for example, a property that must have a date-time value must also be able to have an empty-string value for cases where no date has been set).

For example, if a custom property was `xstart=$CourseSection.timeFrame.begin` the custom property appearing in the LTI message would look like this:

```
{
...
"https://purl.imsglobal.org/spec/lti/claim/custom": {
  "xstart": "2017-04-21T01:00:00Z",
  ...
  }
...
}
```

However, if the platform does not support `CourseSection.timeFrame.begin` or has not authorized the tool to access that data, the parameter must be passed unresolved:

```
{
...
"https://purl.imsglobal.org/spec/lti/claim/custom": {
  "xstart": "$CourseSection.timeframe.begin",
  ...
  }
...
}
```

If the platform supports `CourseSection.timeFrame.begin` variable but there is no value for it because the course has no start date, the substitution parameter's value should be set to empty-string to indicate that no date has been set for the course's start date:

```
{
...
"https://purl.imsglobal.org/spec/lti/claim/custom": {
  "xstart": "",
  ...
  }
...
}
```

Vendors may extend the list of custom property substitution variables.

Other LTI related specifications may also define their own specific variables in addition to the core variables included in this document.

### B.1 LTI User Variables

|  |  |
|:---|:---|
| Message variable name | Corresponding LTI message value |
| `User.id` | `user.id` message property value; this may not be their real ID if they are masquerading as another user; see following. |
| `User.image` | `user.image` message property value. |
| `User.username` | Username by which the message sender knows the user (typically, the name a user logs in with). |
| `User.org` | One or more URIs describing the user's organizational properties (for example, an `ldap://` URI); by best practice, message senders should separate multiple URIs by commas. |
| `User.scope.mentor` | `role_scope_mentor` message property value. |
| `User.gradeLevels.oneRoster` | A comma-separated list of grade(s) for which the user is enrolled. The permitted vocabulary is from the `grades` field utilized in [OneRoster Users](https://www.imsglobal.org/oneroster-v11-final-specification#_Toc480452019). |
| `User.gradeLevels.*` | A comma-separated list of grade(s) for which the user is enrolled. The permitted vocabulary is from the organization or vendor specified in the place of the `*` in the field name. |

These `User` variables represent the user who is the subject of the message. There may, however, be occasions when this is not the actual user performing the action; for example, when an administrator accesses a course as one of its members. In this case, the same information about the actual user (the administrator in the example given) can be requested by using a variable name prefix of `ActualUser` (rather than `User`); for example, `ActualUser.id`. In this case, the corresponding LTI message properties will be `actual_user` properties (for example, `actual_user.id`).

### B.2 LIS Person Variables

|  |  |
|:---|:---|
| Message variable name | XPath for value from LIS database |
| `Person.sourcedId` | `personRecord/sourcedId` (`lis_person.sourcedid` property) |
| `Person.name.full` | `personRecord/person/formname/[formnameType/instanceValue/text="Full"]/formattedName/text` (`lis_person.name_full` property) |
| `Person.name.family` | `personRecord/person/name/partName[instanceName/text="Family"]/instanceValue/text` (`lis_person.name_family` property) |
| `Person.name.given` | `personRecord/person/name/partName[instanceName/text="Given"]/instanceValue/text` (`lis_person.name_given` property) |
| `Person.name.middle` | `personRecord/person/name/partName[instanceName/text="Middle"]/instanceValue/text` |
| `Person.name.prefix` | `personRecord/person/name/partName[instanceName/text="Prefix"]/instanceValue/text` |
| `Person.name.suffix` | `personRecord/person/name/partName[instanceName/text="Suffix"]/instanceValue/text` |
| `Person.gender` | `personRecord/person/demographics/gender/instanceValue/text`2 |
| `Person.gender.pronouns` | *N/A*3 |
| `Person.address.street1` | `personRecord/person/address/[addressType/instanceValue/text="Preferred"]/addressPart/nameValuePair/[instanceName/text="NonFieldedStreetAddress1"]/instanceValue/text`1 |
| `Person.address.street2` | `personRecord/person/address/[addressType/instanceValue/text="Preferred"]/addressPart/nameValuePair[instanceName/text="NonFieldedStreetAddress2"]/instanceValue/text`1 |
| `Person.address.street3` | `personRecord/person/address/[addressType/instanceValue/text="Preferred"]addressPart/nameValuePair/[instanceName/text="NonFieldedStreetAddress3"]/instanceValue/text`1 |
| `Person.address.street4` | `personRecord/person/address/[addressType/instanceValue/text="Preferred"]addressPart/nameValuePair/[instanceName/text="NonFieldedStreetAddress4"]/instanceValue/`1 |
| `Person.address.locality` | `personRecord/person/address/[addressType/instanceValue/text="Preferred"]addressPart/nameValuePair/[instanceName/text="Locality"]/instanceValue/text`1 |
| `Person.address.statepr` | `personRecord/person/address/[addressType/instanceValue/text="Preferred "]addressPart/nameValuePair/[instanceName/text="Statepr"]/instanceValue/text`1 |
| `Person.address.country` | `personRecord/person/address/[addressType/instanceValue/text="Preferred"]addressPart/nameValuePair/[instanceName/text="Country"]/instanceValue/text`1 |
| `Person.address.postcode` | `personRecord/person/address/[addressType/instanceValue/text="Preferred"]addressPart/nameValuePair/[instanceName/text="Postcode"]/instanceValue/text`1 |
| `Person.address.timezone` | `personRecord/person/address/[addressType/instanceValue/text="Preferred"]addressPart/nameValuePair/[instanceName/text="Timezone"]/instanceValue/text`1 |
| `Person.phone.mobile` | `personRecord/person/contactinfo[contactinfoType/instanceValue/text="Mobile"]/contactInfoValue/text` |
| `Person.phone.primary` | `personRecord/person/contactinfo[contactinfoType/instanceValue/text="Telephone_Primary"]/contactinfoValue/text` |
| `Person.phone.home` | `personRecord/person/contactinfo [contactinfoType/instanceValue/text="Telephone_Home"]/contactinfoValue/text` |
| `Person.phone.work` | `personRecord/person/contactinfo [contactinfoType/instanceValue/text="Telephone_Work"]/contactinfoValue /text` |
| `Person.email.primary` | `personRecord/person/contactinfo[contactinfoType/instanceValue/text="Email_Primary"]/contactinfoValue/text` (`lis.person_contact_email_primary` property) |
| `Person.email.personal` | `person/contactinfo[contactinfoType/instanceValue/text="Email_Personal"]/contactinfoValue/text` |
| `Person.webaddress` | `personRecord/person/contactinfo[contactinfoType/instanceValue/text="Web-Address"]/contactinfoValue/text` |
| `Person.sms` | `personRecord/person/contactinfo[contactinfoType/instanceValue/text="SMS"]/contactinfoValue/text` |

1 The "Preferred" instanceName is not part of the default LIS vocabulary. The IMS LTI group proposes to add this term in the LTI Profile of LIS so that LTI can support a single address instead of dealing with multiple address types as prescribed by the full LIS standard.

2 The LIS specification admits for four possible values for the Gender demographics type: `male`, `female`, `unknown`, `other`. The IMS LTI group proposes that LTI Tools be prepared to accept other arbitrary string values for this property (as more specific user-chosen values to elaborate on the `other` value) in order to align support for this information with the OpenID Connect Standard Claim, `gender`.

3 The LIS specification does not have a place to carry a person's pronoun choices. The IMS LTI group proposes to provide a simple string field to carry user-chosen values in anticipation of enhnacements to the upstream person data model as described in the LIS standard; this is the most logical place for a variable to rest to carry this information.

4 Note that the LIS specification expressly describes the value for "fullname" field as intended to be the full, displayable, *user-preferred* name value.

These `Person` variables represent the person who is the subject of the message. There may, however, be occasions when this is not the actual person performing the action; for example, when an administrator accesses a course as one of its members. In this case, the same information about the actual person (the administrator in the example given) can be requested by using a variable name prefix of `ActualPerson` (rather than `Person`); for example, `ActualPerson.sourcedId`.

### B.3 LTI Context Variable

|  |  |
|:---|:---|
| Message variable name | Corresponding LTI value |
| `Context.id` | `context.id` property. |
| `Context.org` | A URI describing the context's organizational properties; for example, an `ldap://` URI. By best practice, message senders should separate URIs using commas. |
| `Context.type` | `context.type` property. |
| `Context.label` | `context.label` property. |
| `Context.title` | `context.label` property. |
| `Context.sourcedId` | The sourced ID of the context. |
| `Context.id.history` | A comma-separated list of URL-encoded context ID values representing previous copies of the context; the ID of most recent copy should appear first in the list followed by any earlier IDs in reverse chronological order. If the context was created from scratch, not as a copy of an existing context, then this variable should have an empty value. |
| `Context.gradeLevels.oneRoster` | A comma-separated list of grade(s) for which the context is attended. The permitted vocabulary is from the `grades` field utilized in [OneRoster Classes](https://www.imsglobal.org/oneroster-v11-final-specification#_Toc480452010). |
| `Context.gradeLevels.*` | A comma-separated list of grade(s) for which the context is attended. The permitted vocabulary is from the organization or vendor specified in the place of the `*` in the field name. |

### B.4 LTI ResourceLink Variables

|  |  |
|:---|:---|
| Message variable name | Corresponding LTI value |
| `ResourceLink.id` | `resource_link.id` property |
| `ResourceLink.title` | `resource_link.title` property |
| `ResourceLink.description` | `resource_link.description` property |
| `ResourceLink.available.startDateTime` | The ISO 8601 date and time when this resource is available for learners to access. |
| `ResourceLink.available.user.startDateTime` | The ISO 8601 date and time when this resource is available for the current user to access. This date overrides that of `ResourceLink.available.startDateTime`. A value of an empty string indicates that the date for the resource should be used. |
| `ResourceLink.available.endDateTime` | The ISO 8601 date and time when this resource ceases to be available for learners to access. |
| `ResourceLink.available.user.endDateTime` | The ISO 8601 date and time when this resource ceases to be available for the current user to access. This date overrides that of `ResourceLink.available.endDateTime`. A value of an empty string indicates that the date for the resource should be used. |
| `ResourceLink.submission.startDateTime` | The ISO 8601 date and time when this resource can start receiving submissions. |
| `ResourceLink.submission.user.startDateTime` | The ISO 8601 date and time when the current user can submit to the resource. This date overrides that of `ResourceLink.submission.startDateTime`. A value of an empty string indicates that the date for the resource should be used. |
| `ResourceLink.submission.endDateTime` | The ISO 8601 date and time when this resource stops accepting submissions. |
| `ResourceLink.submission.user.endDateTime` | The ISO 8601 date and time when the current user stops being able to submit to the resource. This date overrides that of `ResourceLink.submission.endDateTime`. A value of an empty string indicates that the date for the resource should be used. |
| `ResourceLink.lineitem.releaseDateTime` | The ISO 8601 date and time set when the grades for the associated line item can be released to learner. |
| `ResourceLink.lineitem.user.releaseDateTime` | The ISO 8601 date and time set when the current user's grade for the associated line item can be released to the user. This date overrides that of `ResourceLink.lineitem.releaseDateTime`. A value of an empty string indicates that the date for the resource should be used. |
| `ResourceLink.id.history` | A comma-separated list of URL-encoded resource link ID values representing the ID of the link from a previous copy of the context; the most recent copy should appear first in the list followed by any earlier IDs in reverse chronological order. If the link was first added to the current context then this variable should have an empty value. |

### B.5 LIS Course Template Variables

|  |  |
|:---|:---|
| Message variable name | XPath for value from LIS database |
| `CourseTemplate.sourcedId` | `courseTemplateRecord/sourcedId` |
| `CourseTemplate.label` | `courseTemplateRecord/courseTemplate/label/textString` |
| `CourseTemplate.title` | `courseTemplateRecord/courseTemplate/title/textString` |
| `CourseTemplate.shortDescription` | `courseTemplateRecord/courseTemplate/catalogDescription/shortDescription` |
| `CourseTemplate.longDescription` | `courseTemplateRecord/courseTemplate/catalogDescription/longDescription` |
| `CourseTemplate.courseNumber` | `courseTemplateRecord/courseTemplate/courseNumber/textString` |
| `CourseTemplate.credits` | `courseTemplateRecord/courseTemplate/defaultCredits/textString` |

### B.6 LIS Course Offering Variables

|  |  |
|:---|:---|
| Message variable name | XPath for value from LIS database |
| `CourseOffering.sourcedId` | `courseOfferingRecord/sourcedId` (`lis_course_offering_sourcedid` property) |
| `CourseOffering.label` | `courseOfferingRecord/courseOffering/label` |
| `CourseOffering.title` | `courseOfferingRecord/courseOffering/title` |
| `CourseOffering.shortDescription` | `courseOfferingRecord/courseOffering/catalogDescription/shortDescription` |
| `CourseOffering.longDescription` | `courseOfferingRecord/courseOffering/catalogDescription/longDescription` |
| `CourseOffering.courseNumber` | `courseOfferingRecord/courseOffering/courseNumber/textString` |
| `CourseOffering.credits` | `courseOfferingRecord/courseOffering/defaultCredits/textString` |
| `CourseOffering.academicSession` | `courseOfferingRecord/courseOffering/defaultCredits/textString` |

### B.7 LIS Course Section Variables

|  |  |
|:---|:---|
| Message variable name | XPath for value from LIS database |
| `CourseSection.sourcedId` | `courseSection/sourcedId` (`lis_course_section_sourcedid` property) |
| `CourseSection.label` | `courseSectionRecord/courseSection/label` |
| `CourseSection.title` | `courseSectionRecord/courseSection/title` |
| `CourseSection.shortDescription` | `courseSectionRecord/courseSection/catalogDescription/shortDescription` |
| `CourseSection.longDescription` | `courseSectionRecord/courseSection/catalogDescription/longDescription` |
| `CourseSection.courseNumber` | `courseSectionRecord/courseSection/courseNumber/textString` |
| `CourseSection.credits` | `courseSectionRecord/courseSection/defaultCredits/textString` |
| `CourseSection.maxNumberOfStudents` | `courseSectionRecord/courseSection/maxNumberofStudents` |
| `CourseSection.numberOfStudents` | `courseSectionRecord/courseSection/numberofStudents` |
| `CourseSection.dept` | `courseSectionRecord/courseSection/org[type/textString="Dept"]/orgName/textString` |
| `CourseSection.timeFrame.begin` | `courseSectionRecord/courseSection/timeFrame/begin` |
| `CourseSection.timeFrame.end` | `courseSectionRecord/courseSection/timeFrame/end` |
| `CourseSection.enrollControl.accept` | `courseSectionRecord/courseSection/enrollControl/enrollAccept` |
| `CourseSection.enrollControl.allowed` | `courseSectionRecord/courseSection/enrollControl/enrollAllowed` |
| `CourseSection.dataSource` | `courseSectionRecord/courseSection/dataSource` |
| `CourseSection.sourceSectionId` | `createCourseSectionFromCourseSectionRequest/sourcedId` |

### B.8 LIS Group Variables

|  |  |
|:---|:---|
| Message variable name | XPath for value from LIS database |
| `Group.sourcedId` | `groupRecord/sourcedId` |
| `Group.scheme` | `groupRecord/group/groupType/scheme/textString` |
| `Group.typevalue` | `groupRecord/group/groupType/typevalue/textString` |
| `Group.level` | `groupRecord/group/groupType/typevalue/level/textString` |
| `Group.email` | `groupRecord/group/email` |
| `Group.url` | `groupRecord/group/url` |
| `Group.timeFrame.begin` | `groupRecord/group/timeframe/begin` |
| `Group.timeFrame.end` | `groupRecord/group/timeframe/end` |
| `Group.enrollControl.accept` | `groupRecord/group/enrollControl/enrollAccept` |
| `Group.enrollControl.end` | `groupRecord/group/enrollControl/enrollAllowed` |
| `Group.shortDescription` | `groupRecord/group/description/shortDescription` |
| `Group.longDescription` | `groupRecord/group/description/longDescription` |
| `Group.parentId` | `groupRecord/group/relationship[relation="Parent"]/sourcedId` |

### B.9 LIS Membership Variables

|  |  |
|:---|:---|
| Message variable name | XPath for value from LIS database |
| `Membership.sourcedId` | `membershipRecord/sourcedId` |
| `Membership.collectionSourcedid` | `membershipRecord/membership/collectionSourcedId` |
| `Membership.personSourcedId` | `membershipRecord/membership/memnber/personSourcedId` |
| `Membership.status` | `membershipRecord/membership/member/role/status` |
| `Membership.role` | `membershipRecord/membership/member/role/roleType` (`roles` property) |
| `Membership.createdTimestamp` | `membershipRecord/membership/member/role/dateTime` |
| `Membership.dataSource` | `membershipRecord/membership/member/role/dataSource` |
| `Membership.role.scope.mentor` | `role_scope_mentor` property |

### B.10 LIS Message Variables

|  |  |
|:---|:---|
| Message variable name | Corresponding LTI value |
| `Message.returnUrl` | URL for returning the user to the platform (for example, the `launch_presentation.return_url` property). |
| `Message.documentTarget` | `launch_presentation.document_target` property. |
| `Message.height` | `launch_presentation.height` property. |
| `Message.width` | `launch_presentation.width` property. |
| `Message.locale` | `launch_presentation.locale` property. |

### B.11 Tool Platform Variables

|  |  |
|:---|:---|
| Message variable name | Corresponding LTI value |
| `ToolPlatform.productFamilyCode` | `tool_platform.product_family_code` property. |
| `ToolPlatform.version` | `tool_platform.version` property. |
| `ToolPlatformInstance.guid` | `tool_platform.instance_guid` property. |
| `ToolPlatformInstance.name` | `tool_platform.instance_name` property. |
| `ToolPlatformInstance.description` | `tool_platform.instance_description` property. |
| `ToolPlatformInstance.url` | `tool_platform.instance_url` property. |
| `ToolPlatformInstance.contactEmail` | `tool_platform.instance_contact_email` property. |

### B.12 Custom Variables

Vendors may define custom variables. For example, a platform vendor may wish to provide access to certain platform-specific values of its own. Custom variable names *MUST* be globally unique. By best practice, the name of a custom variable should start with a registered domain name, where the components of the domain are listed in reverse order, as in the form in this example (where the vendor owns the `example.com` domain registration):

> `$com.example.Foo.bar`

Every custom variable is associated with a capability identified by some URI. The capability asserts that the offering vendor supports expansion of the specified variable within LTI message properties. For example, the capability associated with the `$com.example.Foo.bar` variable might be associated with this URI:

> [`http://www.example.com/var#com.example.Foo.bar`](http://www.example.com/var#com.example.Foo.bar)

## C. Representing LTI links in an IMS Common Cartridge

The format to include LTI resource links has not changed except that all launches *MUST* be sent over HTTPS (non-secure launches are no longer an option). The values of `secure_launch_url` and `secure_icon` *SHOULD* be included to maintain backwards compatibility, but they *MUST* also contain a secure HTTPS url if included. The original name of "basic LTI link" is still used to refer to LTI resource links. Self-contained, basic LTI resource links are defined in the resource section of an IMS Common Cartridge as follows:

```
<resource identifier="I_00010_R" type="imsbasiclti_xmlv1p0">
<file href="I_00001_R/BasicLTI.xml"/>
</resource>
```

The `href` in the resource entry refers to a file path in the cartridge that contains an XML description of the basic LTI link, as in the following example:

```
<?xml version="1.0" encoding="UTF-8"?>
<cartridge_basiclti_link xmlns="http://www.imsglobal.org/xsd/imslticc_v1p0"
  xmlns:blti = "http://www.imsglobal.org/xsd/imsbasiclti_v1p0"
  xmlns:lticm ="http://www.imsglobal.org/xsd/imslticm_v1p0"
  xmlns:lticp ="http://www.imsglobal.org/xsd/imslticp_v1p0"
  xmlns:xsi = "http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation = "http://www.imsglobal.org/xsd/imslticc_v1p0
    http://www.imsglobal.org/xsd/lti/ltiv1p0/imslticc_v1p0.xsd
    http://www.imsglobal.org/xsd/imsbasiclti_v1p0
    http://www.imsglobal.org/xsd/lti/ltiv1p0/imsbasiclti_v1p0.xsd
    http://www.imsglobal.org/xsd/imslticm_v1p0
    http://www.imsglobal.org/xsd/lti/ltiv1p0/imslticm_v1p0.xsd
    http://www.imsglobal.org/xsd/imslticp_v1p0
    http://www.imsglobal.org/xsd/lti/ltiv1p0/imslticp_v1p0.xsd">
  <blti:title>Grade Book</blti:title>
  <blti:description>Grade Book with many column types</blti:description>
  <blti:custom>
    <lticm:property name="keyname">value</lticm:property>
  </blti:custom>
  <blti:extensions platform="my.lms.com">
    <lticm:property name="keyname">value</lticm:property>
  </blti:extensions>
  <blti:launch_url>url to the basiclti launch URL</blti:launch_url>
  <blti:secure_launch_url>secure URL to the basiclti launch URL</blti:secure_launch_url>
  <blti:icon>url to an icon for this tool (optional)</blti:icon>
  <blti:secure_icon>secure URL to an icon for this tool (optional)></blti:secure_icon>
  <blti:vendor>
    <lticp:code>vendor.com</lticp:code>
    <lticp:name>vendor.name</lticp:name>
    <lticp:description>This is a vendor of learning tools.</lticp:description>
    <lticp:url>http://www.vendor.com/</lticp:url>
    <lticp:contact>
      <lticp:email>support@vendor.com</lticp:email>
    </lticp:contact>
  </blti:vendor>
  <cartridge_bundle identifierref="BLTI001_Bundle"/>
  <cartridge_icon identifierref="BLTI001_Icon"/>
</cartridge_basiclti_link>
```

Once the cartridge creator has defined the basic LTI link in the resources section of the cartridge manifest, the organization section of the manifest may make reference to it as needed:

```
<item identifier="BasicLTI1" identifierref="I_00010_R">
  <title>Homework Problems</title>
</item>
```

By best practice, the cartridge importer should display in the user interface the `title` in*this* referring `item` entry, rather than the `title` in the referred-to `basic_lti_link` entry.

The optional `custom` section *MAY* contain a set of key-value pairs that were associated with the link in the system that originally authored the link. For example if the link were a section in an eTextbook, there might be a setting like:

`<parameter key="section">1.2.7</parameter>`

The platform sends these properties back to the external tool when launching from the imported basic LTI link. If a basic LTI link is imported and then exported, by best practice, the platform should maintain the `custom` section across the import/export process, unless the intent is to re-author the link.

The `extensions` section allows the hosting platform to add its own key-value pairs to the link. The platform may use extensions to store information that the platform or authoring environment might use across an export-import cycle. In order to allow multiple sets of extensions to be contained in the same basic LTI descriptor, by best practice, authoring environments should add the `platform` attribute and include an identifier that identifies the authoring environment.

It is possible to include the icon for the link in the cartridge instead of including it as a URL using the `cartridge_icon` entry in the descriptor. The `identifierref` attribute points to a link that includes the icon image and a dependency is added to the resource section of the basic LTI resource entry in the manifest as shown below.

```
<resource identifier="I_00010_R" type="imsbasiclti_xmlv1p0">
  <file href="I_00001_R/BasicLTI.xml"/>
  <dependency identifierref="BLTI001_Icon"/>
</resource>

<resource identifier="BLTI001_Icon"
  type="associatedcontent/imscc_xmlv1p0/learning-application-resource">
    <file href="BLTI001_Media/learning_icon.gif"/>
  </resource>
```

## D. Using Learning Information Services with LTI

Organizations may have an IMS Learning Information Services (LIS) instance that can provide limited functionality within an LTI context. Typically, platform instances can use LIS service properties to

- Convey information to tools about the LIS sourcedid values for users and contexts (course offerings and sections).

- Provide an endpoint tools can use to provide Basic Outcomes [LTI-BO-11] back to the LIS instance (this may be useful if the platform does not provide access to the more fully featured LTI Assignment and Grade Service [LTI-AGS-20]).

The LIS services could actually be provided by a third party, Student Information System (SIS), or perhaps the LTI platform is the service provider that tools can use.

Historically, these LIS properties have been provided in basic LTI launch request messages. While they are all optional properties to include, platforms should, by best practice, include these properties when they have access to them to help ensure interoperability and traceability across IMS-standards-enabled systems.

**services.lis.course_offering_sourcedid**, **services.lis.course_section_sourcedid** (*OPTIONAL*). The LIS course (offering and section) identifiers applicable to the context of this basic LTI launch request message.

The field's content and meaning are defined by LIS v2.0 [LIS-20].

**services.lis.outcome_service_url** (*OPTIONAL*). URL endpoint for the LTI Basic Outcomes Service [LTI-BO-11]. By best practice, this URL should not change from one resource link launch request message to the next; platforms should provide a single, unchanging endpoint URL for each registered tool. This URL endpoint may support various operations/actions; by best practice, the provider of an LTI Basic Outcome Service should respond with a response of `unimplemented` for actions it does not support.

This field *MUST* appear if the platform supports the LTI Basic Outcomes Service for receiving outcomes from any resource link launch request messages sent to a particular tool.

By best practice, an LTI Basic Outcome Service will only accept outcomes for launches from a user whose roles in the context contains the Learner context role ([`http://purl.imsglobal.org/vocab/lis/v2/membership#Learner`](http://purl.imsglobal.org/vocab/lis/v2/membership#Learner)), and thus will only provide a `services.lis.result_sourcedid` value in those resource link launch request messages. However, the platform should still send the `services.lis.outcome_service_url` for all launching users in that context, regardless of whether or not it provides a `result_sourcedid` value.

**services.lis.person_sourcedid** (*OPTIONAL*). The LIS identifier for the user account that initiated the resource link launch request. The exact format of the sourced ID may vary with the LIS integration; it is simply a unique identifier for the launching user.

The field's content and meaning are defined by LIS v2.0 [LIS-20].

**services.lis.person_name_full**, **services.lis.person_name_given**, **services.lis.person_name_family** (*OPTIONAL*). Some of the LIS-known names for the user account that initiated the resource link launch request. The content and meaning of these fields are defined by LIS v2.0 [LIS-20].

**services.lis.person_contact_email_primary** (*OPTIONAL*). The LIS-known primary email `contactinfo` for the user account that initiated the resource link launch request. The content and meaning of this field is defined by LIS v2.0 [LIS-20].

**services.lis.result_sourcedid** (*OPTIONAL*). An opaque identifier that indicates the LIS Result Identifier (if any) associated with the resource link launch request (identifying a unique row and column within the service provider's gradebook).

This field's value *MUST* be unique for every combination of `context.id`, `resource_link.id`, and `user.id`. The value may change for a particular `resource_link.id` + `user.id` from one resource link launch request to the next, so the tool should retain only the most recent value received for this field (for each `context.id` + `resource_link.id` + `user.id`).

## E. Full example resource link request

The LTI resource link launch request message JSON object follows the form in this example. The smaller examples in  5. Resource link launch request message are excerpts from this more complete example message object representation. Note that the vast majority of the properties are optional and may not appear in most resource link launch request messages.

```
{
  "iss": "https://platform.example.edu",
  "sub": "a6d5c443-1f51-4783-ba1a-7686ffe3b54a",
  "aud": ["962fa4d8-bcbf-49a0-94b2-2de05ad274af"],
  "exp": 1510185728,
  "iat": 1510185228,
  "azp": "962fa4d8-bcbf-49a0-94b2-2de05ad274af",
  "nonce": "fc5fdc6d-5dd6-47f4-b2c9-5d1216e9b771",
  "name": "Ms Jane Marie Doe",
  "given_name": "Jane",
  "family_name": "Doe",
  "middle_name": "Marie",
  "picture": "https://platform.example.edu/jane.jpg",
  "email": "jane@platform.example.edu",
  "locale": "en-US",
  "https://purl.imsglobal.org/spec/lti/claim/deployment_id":
    "07940580-b309-415e-a37c-914d387c1150",
  "https://purl.imsglobal.org/spec/lti/claim/message_type": "LtiResourceLinkRequest",
  "https://purl.imsglobal.org/spec/lti/claim/version": "1.3.0",
  "https://purl.imsglobal.org/spec/lti/claim/roles": [
    "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Student",
    "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner",
    "http://purl.imsglobal.org/vocab/lis/v2/membership#Mentor"
  ],
  "https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor": [
    "fad5fb29-a91c-770-3c110-1e687120efd9",
    "5d7373de-c76c-e2b-01214-69e487e2bd33",
    "d779cfd4-bc7b-019-9bf1a-04bf1915d4d0"
  ],
  "https://purl.imsglobal.org/spec/lti/claim/context": {
      "id": "c1d887f0-a1a3-4bca-ae25-c375edcc131a",
      "label": "ECON 1010",
      "title": "Economics as a Social Science",
      "type": ["http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering"]
  },
  "https://purl.imsglobal.org/spec/lti/claim/resource_link": {
      "id": "200d101f-2c14-434a-a0f3-57c2a42369fd",
      "description": "Assignment to introduce who you are",
      "title": "Introduction Assignment"
  },
  "https://purl.imsglobal.org/spec/lti/claim/tool_platform": {
      "guid": "ex/48bbb541-ce55-456e-8b7d-ebc59a38d435",
      "contact_email": "support@platform.example.edu",
      "description": "An Example Tool Platform",
      "name": "Example Tool Platform",
      "url": "https://platform.example.edu",
      "product_family_code": "ExamplePlatformVendor-Product",
      "version": "1.0"
  },
  "https://purl.imsglobal.org/spec/lti/claim/target_link_uri":
      "https://tool.example.com/lti/48320/ruix8782rs",
  "https://purl.imsglobal.org/spec/lti/claim/launch_presentation": {
      "document_target": "iframe",
      "height": 320,
      "width": 240,
      "return_url": "https://platform.example.edu/terms/201601/courses/7/sections/1/resources/2"
  },
  "https://purl.imsglobal.org/spec/lti/claim/custom": {
    "xstart": "2017-04-21T01:00:00Z",
    "request_url": "https://tool.com/link/123"
  },
  "https://purl.imsglobal.org/spec/lti/claim/lis": {
      "person_sourcedid": "example.edu:71ee7e42-f6d2-414a-80db-b69ac2defd4",
      "course_offering_sourcedid": "example.edu:SI182-F16",
      "course_section_sourcedid": "example.edu:SI182-001-F16"
  },
  "http://www.ExamplePlatformVendor.com/session": {
      "id": "89023sj890dju080"
}

}
```

The platform turns this JSON object into a JWT to include in the resource link launch request message body. After encoding as a JWT, the platform sends the message as a form post using the `id_token` parameter (the JWT data in the following example is not complete for conciseness).

```
POST https://example.tool.com/videos/f7701643-d79a-468a-ba8e-998f98b71638
Content-Type: application/x-www-form-urlencoded

id_token=eyJhbGciOiJIAzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL3BsYXRmb3J
tLmV4YW1wbGUub3JnIiwic3ViIjoiYTZkNWM0NDMtMWY1MS00NzgzLWJhMWEtNzY4NmZmZTNiNTRhI
iwiYXVkIjpbIjk2MmZhNGQ4LWJjYmYtNDlhMC05NGIyLTJkZTA1YWQyNzRhZiJdLCJleHAiOjE1MTA
xODU3MjgsImlhdCI6MTUxMDE4NTIyOCwiYXpwIjoiOTYyZmE0ZDgtYmNiZi0...
```

## F. Revision History

*This section is non-normative.*

### F.1 Version History

| Spec Version No. | Document Version No. | Release Date | Comments |
| --- | --- | --- | --- |
| v1.0 Final |  | 17 May 2010 | The first formal release of the Final specification. This document is released for public adoption. |
| v1.1 Final |  | 13 March 2012 | Added the tool registration and grade return use cases. |
| v1.3 Final |  | 16 April 2019 | Adopts the IMS Security Framework specification for authorization/authentication flows, adds new terminology, and includes supports for the LTI Advantage services. |
| v1.3 Final |  | 14 May 2019 | Adds a clarifying statement related to the use of client_id to 6.2 Token endpoint claim and services. |
| v1.3 Final |  | 30 July 2019 | Adds target_link_uri to the example in example link request. |
| v1.3 Final |  | 29 October 2019 | Clarifies the use and descriptions of substitution parameters. |
| v1.3 Final |  | 21 September 2020 | Updates and corrects some inter-document links to point to the proper sections. |
| v1.3 Final | 1 | 1 July 2021 | Clarifies and updates parts of the specification, including: - new details about JWKS exchange options; - adds releaseDateTime for line item submissions; - adds optional TestUser role. |
| v1.3 Final | 2 | 24 January 2023 | Add deployment_id to an OAuth token request. A tool SHOULD include this on all requests going forward. (docs); Clarify allowable values for custom properties. (docs); Add locale to user information; Add new substitution variables for date management. (docs); Minor grammar corrections. |
| v1.3 Final | 3 | 7 Feb 2023 | Add User.gradeLevels.oneRoster and User.gradeLevels.*. (docs); Add Context.gradeLevels.oneRoster and Context.gradeLevels.*. (docs) |

## G. References

### G.1 Normative references

[BCP47]
[Tags for Identifying Languages](https://www.rfc-editor.org/rfc/rfc5646). A. Phillips, Ed.; M. Davis, Ed.. IETF. September 2009. Best Current Practice. URL: <https://www.rfc-editor.org/rfc/rfc5646>

[LIS-20]
[IMS Global Learning Information Services v2.0](https://www.imsglobal.org/lis/). L. Feng; W. Lee; C. Smythe. IMS Global Learning Consortium. June 2011. URL: <https://www.imsglobal.org/lis/>

[LTI-11]
[IMS Global Learning Tools Interoperability (LTI)® Implementation Guide](https://www.imsglobal.org/specs/ltiv1p1). G. McFall; M. McKell; L. Neumann; C. Severance. IMS Global Learning Consortium. March 13, 2012. URL: <https://www.imsglobal.org/specs/ltiv1p1>

[LTI-AGS-20]
[IMS Global Learning Tools Interoperability (LTI)® Assignment and Grade Services](https://www.imsglobal.org/spec/lti-ags/v2p0/). C. Vervoort; E. Preston; M. McKell; J. Rissler. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti-ags/v2p0/>

[LTI-BO-11]
[IMS Global Learning Tools Interoperability (LTI)® Basic Outcomes](https://www.imsglobal.org/spec/lti-bo/v1p1/). C. Vervoort. IMS Global Learning Consortium. 7 May 2019. URL: <https://www.imsglobal.org/spec/lti-bo/v1p1/>

[LTI-CERT-13]
[IMS Global Learning Tools Interoperability (LTI)® Advantage Conformance Certification Guide](https://www.imsglobal.org/spec/lti/v1p3/cert/). D. Haskins; M. McKell. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/cert/>

[LTI-CORE-13-ERRATA]
[IMS Global Learning Tools Interoperability (LTI)® Core Specification v1.3 Errata](https://www.imsglobal.org/spec/lti-core/v1p3/errata/). IMS Global Learning Consortium. URL: <https://www.imsglobal.org/spec/lti-core/v1p3/errata/>

[LTI-DL-20]
[IMS Global Learning Tools Interoperability (LTI)® Deep Linking 2.0](https://www.imsglobal.org/spec/lti-dl/v2p0/). C. Vervoort; E. Preston. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti-dl/v2p0/>

[LTI-IMPL-13]
[IMS Global Learning Tools Interoperability (LTI)® Advantage Implementation Guide](https://www.imsglobal.org/spec/lti/v1p3/impl/). C. Vervoort; J. Rissler; M. McKell. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/impl/>

\[OpenID-14\]
*Reference not found.*

[RFC2119]
[Key words for use in RFCs to Indicate Requirement Levels](https://www.rfc-editor.org/rfc/rfc2119). S. Bradner. IETF. March 1997. Best Current Practice. URL: <https://www.rfc-editor.org/rfc/rfc2119>

[RFC2396]
[Uniform Resource Identifiers (URI): Generic Syntax](https://www.rfc-editor.org/rfc/rfc2396). T. Berners-Lee; R. Fielding; L. Masinter. IETF. August 1998. Draft Standard. URL: <https://www.rfc-editor.org/rfc/rfc2396>

[RFC3987]
[Internationalized Resource Identifiers (IRIs)](https://www.rfc-editor.org/rfc/rfc3987). M. Duerst; M. Suignard. IETF. January 2005. Proposed Standard. URL: <https://www.rfc-editor.org/rfc/rfc3987>

[RFC4122]
[A Universally Unique IDentifier (UUID) URN Namespace](https://www.rfc-editor.org/rfc/rfc4122). P. Leach; M. Mealling; R. Salz. IETF. July 2005. Proposed Standard. URL: <https://www.rfc-editor.org/rfc/rfc4122>

[SEC-10]
[IMS Global Security Framework v1.0](https://www.imsglobal.org/spec/security/v1p0/). C. Smythe; C. Vervoort; M. McKell; N. Mills. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/security/v1p0/>

## H. List of Contributors

The following individuals contributed to the development of this document:

| Name              | Organization           | Role   |
|-------------------|------------------------|--------|
| Paul Gray         | Learning Objects       |        |
| Viktor Haag       | D2L                    |        |
| Dereck Haskins    | IMS Global             |        |
| Martin Lenord     | Turnitin               |        |
| Karl Lloyd        | Instructure            |        |
| Mark McKell       | IMS Global             |        |
| Nathan Mills      | Instructure            |        |
| Bracken Mosbacker | Lumen Learning         |        |
| Marc Phillips     | Instructure            |        |
| Al Gilmore        | Blackboard             |        |
| Eric Preston      | Blackboard             | Editor |
| James Rissler     | IMS Global             | Editor |
| Charles Severance | University of Michigan |        |
| Lior Shorshi      | McGraw-Hill Education  |        |
| Colin Smythe      | IMS Global             |        |
| Claude Vervoort   | Cengage                | Editor |
| James Tse         | Google                 |        |
| Jim Walkoski      | D2L                    |        |

IMS Global Learning Consortium, Inc. ("IMS Global") is publishing the information contained in this document ("Specification") for purposes of scientific, experimental, and scholarly collaboration only.

IMS Global makes no warranty or representation regarding the accuracy or completeness of the Specification.

This material is provided on an "As Is" and "As Available" basis.

The Specification is at all times subject to change and revision without notice.

It is your sole responsibility to evaluate the usefulness, accuracy, and completeness of the Specification as it relates to you.

IMS Global would appreciate receiving your comments and suggestions.

Please contact IMS Global through our website at http://www.imsglobal.org.

Please refer to Document Name: Learning Tools Interoperability Core Specification 1.3

Date: 16 April 2019
