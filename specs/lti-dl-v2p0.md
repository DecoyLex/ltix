# Learning Tools Interoperability (LTI)® Deep Linking Specification

1EdTech Final Release
Version 2.0

| Document Version: | 2 |
|---|---|
| Date Issued: | 16 April 2019 |
| Status: | This document is made available for adoption by the public community at large. |
| This version: | <https://www.imsglobal.org/spec/lti-dl/v2p0/> |
| Latest version: | <https://www.imsglobal.org/spec/lti-dl/latest/> |
| Errata: | <https://www.imsglobal.org/spec/lti-dl/v2p0/errata/> |

## IPR and Distribution Notice

Recipients of this document are requested to submit, with their comments, notification of any relevant patent claims or other intellectual property rights of which they may be aware that might be infringed by any implementation of the specification set forth in this document, and to provide supporting documentation.

IMS takes no position regarding the validity or scope of any intellectual property or other rights that might be claimed to pertain implementation or use of the technology described in this document or the extent to which any license under such rights might or might not be available; neither does it represent that it has made any effort to identify any such rights. Information on IMS's procedures with respect to rights in IMS specifications can be found at the IMS Intellectual Property Rights webpage: <http://www.imsglobal.org/ipr/imsipr_policyFinal.pdf>.

Use of this specification to develop products or services is governed by the license with IMS found on the IMS website: <http://www.imsglobal.org/speclicense.html>.

Permission is granted to all parties to use excerpts from this document as needed in producing requests for proposals.

The limited permissions granted above are perpetual and will not be revoked by IMS or its successors or assigns.

THIS SPECIFICATION IS BEING OFFERED WITHOUT ANY WARRANTY WHATSOEVER, AND IN PARTICULAR, ANY WARRANTY OF NONINFRINGEMENT IS EXPRESSLY DISCLAIMED. ANY USE OF THIS SPECIFICATION *SHALL* BE MADE ENTIRELY AT THE IMPLEMENTER'S OWN RISK, AND NEITHER THE CONSORTIUM, NOR ANY OF ITS MEMBERS OR SUBMITTERS, *SHALL* HAVE ANY LIABILITY WHATSOEVER TO ANY IMPLEMENTER OR THIRD PARTY FOR ANY DAMAGES OF ANY NATURE WHATSOEVER, DIRECTLY OR INDIRECTLY, ARISING FROM THE USE OF THIS SPECIFICATION.

Public contributions, comments and questions can be posted here: <http://www.imsglobal.org/forums/ims-glc-public-forums-and-resources>.

© 2023 IMS Global Learning Consortium, Inc. All Rights Reserved.

Trademark information: <http://www.imsglobal.org/copyright.html>

## Abstract

The Learning Tools Interoperability (LTI)® Deep Linking specification allows a Platform to more easily integrate content gathered from an external Tool. Using the Deep Linking message defined in this specification, Platform users can launch to a URI specified by an external Tool, then select specific content appropriate for their use, and receive a URI that other platform users can use at a later time for launches directly to that specific content.

## Table of Contents

- [1. Overview](#1-overview)
  - [1.1 Terminology](#11-terminology)
  - [1.2 Conformance Statements](#12-conformance-statements)
  - [1.3 Document Set](#13-document-set)
    - [1.3.1 Normative Documents](#131-normative-documents)
    - [1.3.2 Informative Documents](#132-informative-documents)
- [2. Workflow](#2-workflow)
  - [2.1 Redirection from platform to tool](#21-redirection-from-platform-to-tool)
  - [2.2 Tool user experience for deep linking](#22-tool-user-experience-for-deep-linking)
  - [2.3 Redirection back to the platform](#23-redirection-back-to-the-platform)
- [3. Content Item Types](#3-content-item-types)
  - [3.1 Link](#31-link)
  - [3.2 LTI Resource Link](#32-lti-resource-link)
  - [3.3 File](#33-file)
  - [3.4 HTML fragment](#34-html-fragment)
  - [3.5 Image](#35-image)
  - [3.6 Extending a type](#36-extending-a-type)
  - [3.7 Defining new types](#37-defining-new-types)
- [4. LTI Deep Linking interaction](#4-lti-deep-linking-interaction)
  - [4.1 JSON Web Token](#41-json-web-token)
  - [4.2 Message claims](#42-message-claims)
  - [4.3 Message type and schemas](#43-message-type-and-schemas)
  - [4.4 Deep linking request message](#44-deep-linking-request-message)
    - [4.4.1 Deep linking settings](#441-deep-linking-settings)
    - [4.4.2 Message type](#442-message-type)
    - [4.4.3 LTI version](#443-lti-version)
    - [4.4.4 Deployment ID](#444-deployment-id)
    - [4.4.5 User](#445-user)
    - [4.4.6 Launch Presentation](#446-launch-presentation)
    - [4.4.7 Platform](#447-platform)
    - [4.4.8 Context](#448-context)
    - [4.4.9 Role](#449-role)
    - [4.4.10 Role-scope mentor](#4410-role-scope-mentor)
    - [4.4.11 Custom properties](#4411-custom-properties)
  - [4.5 Deep linking response message](#45-deep-linking-response-message)
    - [4.5.1 aud](#451-aud)
    - [4.5.2 Message type](#452-message-type)
    - [4.5.3 LTI version](#453-lti-version)
    - [4.5.4 Deployment ID](#454-deployment-id)
    - [4.5.5 Data](#455-data)
    - [4.5.6 Content items](#456-content-items)
    - [4.5.7 Message](#457-message)
    - [4.5.8 Log](#458-log)
    - [4.5.9 Error message](#459-error-message)
    - [4.5.10 ErrorLog](#4510-errorlog)
  - [4.6 Message types](#46-message-types)
    - [4.6.1 Content Item Types](#461-content-item-types)
    - [4.6.2 Presentation target document](#462-presentation-target-document)
- [A. Deep linking request example](#a-deep-linking-request-example)
- [B. Deep linking response example](#b-deep-linking-response-example)
- [C. Revision history](#c-revision-history)
  - [C.1 Version History](#c1-version-history)
- [D. References](#d-references)
  - [D.1 Normative references](#d1-normative-references)
- [E. List of Contributors](#e-list-of-contributors)

## 1. Overview

IMS is developing the Learning Tools Interoperability (LTI)® Deep Linking
specification to allow a platform to more easily integrate content gathered
from an external tool. Using the deep linking message defined in this
specification, platform users can launch out to a URI specified by an
external tool, *then* select specific content appropriate for their use,
and have returned back a URI that other platform users can use at a later time
as the basis for other launches directly to that specific content.

For example, via the deep linking message, course designers can launch out to
a publisher's tool, select some course content modules appropriate to the
particular course they are working on, and get back LTI™ resource links that,
when launched by students, will go directly to the content modules rather than
some more general "table of contents page".

This document builds upon all the concepts and terms introduced in the
LTI™ 1.3 specification [[LTI-13](#bib-lti-13)], specifically:

- The notions of *platforms* and *tools* as participants in an LTI
workflow.
- The organization of collections of *resources* within *contexts*.
- The interactions of *messages* and *services*.
As with the core LTI specifications, this specification requires the use of
HTTPS (with TLS) for all messages [[RFC2818](#bib-rfc2818)]. Additionally, implementers
*SHOULD*, by best practice, use HTTPS for all URLs to resources included in
messages (for example, URLs to static content like images and thumbnails).

### 1.1 Terminology

`JWT`
: JSON Web Token is a JSON-based [[RFC7159](#bib-rfc7159)] security token
encoding that enables identity and security information to be shared across security domains. A security token is generally issued by an Identity Provider and consumed by a Relying Party that relies on its content to identify the token's subject for security-related purposes.

`LIS`
: Learning Information Services® (LIS®) is
an IMS standard that defines how systems manage the exchange of information that describes people, groups, memberships, courses and outcomes [[LIS-20](#bib-lis-20)]

`LTI`
: Learning Tools Interoperability (LTI)
is an IMS standard for integration of rich learning applications within educational environments.

`URI`
: The Uniform Resource Identifier (URI)
utilizes the US-ASCII character set to identify a resource. Per [[RFC2396](#bib-rfc2396)], a URI "can be further classified as a locator, a name or both." Both the Uniform Resource Locator ([URL](#dfn-url)) and the Uniform Resource Name ([URN](#dfn-urn)) are considered subspaces of the more general URI space.

`URL`
: A Uniform Resource Locator (URL) is a
type of [URI](#dfn-uri) that provides a reference to resource that specifies both its location and a means of retrieving a representation of it. An HTTP [URI](#dfn-uri) is a URL.

`URN`
: A Uniform Resource Name (URN) is a
type of [URI](#dfn-uri) that provides a persistent identifier for a resource that is bound to a defined namespace. Unlike a [URL](#dfn-url), a URN is location-independent and provides no means of accessing a representation of the named resource.

`UUID`
: a 128-bit identifier that does not require a
registration authority to assure uniqueness. However, absolute uniqueness is not guaranteed although the collision probability is considered extremely low. LTI recommends use of randomly or pseudo-randomly generated version 4 UUIDs [[RFC4122](#bib-rfc4122)].

### 1.2 Conformance Statements

As well as sections marked as non-normative, all authoring guidelines, diagrams, examples, and notes in this specification are non-normative. Everything else in this specification is normative.

The key words *MAY*, *MUST*, *MUST NOT*, *OPTIONAL*, *RECOMMENDED*, *REQUIRED*, *SHALL*, *SHALL NOT*, *SHOULD*, and *SHOULD NOT* in this document are to be interpreted as described in [[RFC2119](#bib-rfc2119)].

An implementation of this specification that fails to implement a MUST/REQUIRED/SHALL requirement or fails to abide by a MUST NOT/SHALL NOT prohibition is considered nonconformant. SHOULD/SHOULD NOT/RECOMMENDED statements constitute a best practice. Ignoring a best practice does not violate conformance but a decision to disregard such guidance should be carefully considered. MAY/OPTIONAL statements indicate that implementers are entirely free to choose whether or not to implement the option.

The [Conformance and Certification Guide](#document-set) for this specification may introduce greater normative constraints than those defined here for specific service or implementation categories.

### 1.3 Document Set

#### 1.3.1 Normative Documents

`LTI Advantage Conformance Certification Guide [[LTI-CERT-13](#bib-lti-cert-13)]`
: The LTI Advantage Conformance Certification Guide describes the procedures
for testing Platforms and Tools against the LTI v1.3 and LTI Advantage services using the IMS certification test suite.

#### 1.3.2 Informative Documents

`LTI Advantage Implementation Guide [[LTI-IMPL-13](#bib-lti-impl-13)]`
: The LTI Advantage Implementation Guide provides information to lead
you to successful implementation and certification of the LTI Core v1.3 specification and the set of LTI Advantage specifications.

## 2. Workflow

*Figure 1 Diagram illustrating the Deep Linking workflow between platforms and tools.*

The workflow around using the deep linking message involves three steps:

1. The platform redirects the user's browser to an endpoint hosted by the tool,
as with the core LTI resource link launch request, indicating the types of items
that may be added during this interaction.
2. The tool provides an interface allowing the user to discover and select one
or more specific items to integrate back into the platform.
3. The tool then redirects the user’s browser back to the platform along with
details of the item(s) selected (for example, LTI resource links to embed).

### 2.1 Redirection from platform to tool

The platform handles this redirection to
the tool just as with the core LTI resource link launch request. It creates an
HTML form that the browser can auto-submit via JavaScript to an endpoint hosted
by the tool using an HTTP POST.

The platform sends the same message parameters in the deep linking request
message as it would in the resource link launch request message
with the exception of the resource link claim, along with some additional parameters.

The `lti_message_type` of this new message has a value of
`LtiDeepLinkingRequest`.

The platform creates and signs the message in the same way it does with the
core LTI resource link launch request (see the LTI 1.3 [[LTI-13](#bib-lti-13)] and IMS
Security Framework [[SEC-10](#bib-sec-10)] specifications for details). Given the
intended workflow implied by this message type, the platform may intend the
tool's user experience to open within an iframe or pop-up window, to let the
current UI context in the platform remain visible and available when the user
returns from the tool's workflow; however, this is not a requirement, and
other workflows using the same deep linking request message type may re-use the
same page as the platform.

### 2.2 Tool user experience for deep linking

The tool entirely controls the user
experience for discovering and selecting content items within its body of
available resources.

The tool *SHOULD* verify the deep linking request message in the same way it
would for a resource link launch request. The parameters the tool receives in
the message *SHOULD*, by best practice, contain sufficient data to allow the tool
to identify the context from which the user is being passed, who the user is,
and what the user's role in the context is.

Where appropriate the tool can use this data to provide an appropriate
collection of items from which the user can select, or allow the user to create
a new item (and retrieve a reference to the new item).

The tool *MUST* recognize that the platform makes no guarantee that it will
actually create a resource link to the selected (or created) item(s) upon
returning the user to the platform (for example, the user may have the option
to cancel the workflow before creating a resource link in the platform).

### 2.3 Redirection back to the platform

When forming the deep linking request
message, the platform includes a `deep_link_return_url` in the `https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings` claim.
The tool *MUST* redirect the
workflow to that URL once the user has completed the selection or creation portion of the
overall flow.

By best practice, a tool *SHOULD* always ensure to redirect the user's browser back to
this endpoint, even if the user selects or creates no items. This allows the
platform to close any frames or windows it opened during the initial redirection
step.

The tool passes back to the platform details of any selected or created items
in a JSON array (this array could be empty, if no item was selected or
created).

After encoding the deep linking return message as a JWT, the tool *MUST* always perform this redirection using an
auto-submitted form as an HTTP POST request using the `JWT` parameter (see the IMS Security Framework [[SEC-10](#bib-sec-10)]) for more
details about the use of JWT), redirecting the user's browser to the platforms's `deep_link_return_url`.

The `lti_message_type` of this new message has a value of
`LtiDeepLinkingResponse`.

## 3. Content Item Types

The Deep Linking interaction may be used to exchange various types of content
item; each item type has its own definition and JSON Schema defining it. The type
is open for extension; it is expected other IMS Global specifications as well as
platforms will extend on the core set of types defined in this document.

### 3.1 Link

A link is a fully qualified URL to a resource hosted on the internet.
The item may include different rendering options (window, iframe, embed).
As a best practice, the tool *SHOULD* return all the ones that apply, allowing
the platform to use the best option based on the actual rendering context
when the item is displayed.

A link may contain different rendering instructions that the platform may use
to properly display the link; if none of those attributes are present, the
default behavior is to open the resource in a new browser window/tab.

Properties of a link are:

| Name | Description | Disposition |
|---|---|---|
| `type` | Value must be `link`. | required |
| `url` | Fully qualified URL of the resource. This link must be navigable to. | required |
| `title` | String, plain text to use as the title or heading for content. | optional |
| `text` | String, plain text description of the content item intended to be displayed
to all users who can access the item. | optional |
| `icon` | Fully qualified URL, height, and width of an icon image to be placed with the file. A platform
may not support the display of icons, but where it does, it may choose to use a local copy of the icon rather than linking to the URL provided (which would also allow it to resize the image to suit its needs).

`url`: fully qualified URL to the image file.
`width`: integer representing the width in pixels of the image.
`height`: integer representing the height in pixels of the image. | optional |
| `thumbnail` | Fully qualified URL, height, and width of a thumbnail image to be made a hyperlink. This allows
the hyperlink to be opened within the platform from text or an image, or from both.

`url`: fully qualified URL to the image file.
`width`: integer representing the width in pixels of the image.
`height`: integer representing the height in pixels of the image. | optional |
| `embed` | The `embed` property has a single required property `html`
that contains the HTML fragment to embed the resource directly inside HTML. It is commonly used as a way to embed a resource in an HTML editor. Platform must make sure to properly sanitize the HTML prior to inclusion. | optional |
| `window` | The `window` property indicates how to open the resource in a
new window/tab. The `window` property has the following optional properties:

`targetName`: String identifying the name of the window to open; this allows for a single window to be shared as the target of multiple links, preventing a proliferation of new windows/tabs.
`width`: integer representing the width in pixels of the new window
`height`: integer representing the height in pixels of the new window
`windowFeatures`: Comma-separated list of window features as per the [window.open() definition](https://developer.mozilla.org/en-US/docs/Web/API/Window/open). | optional |
| `iframe` | The `iframe` property indicates the resource can be embedded
using an iframe. The parameters indicates the dimension and the src URL for embedding:

`src`: required parameter indicating the [URL](#dfn-url) to use as the `src` of the iframe. The `src` value may differ from the link `url`.
`width`: integer representing the width in pixel of the new iframe.
`height`: integer representing the height in pixel of the new iframe. | optional |

### 3.2 LTI Resource Link

A link to an LTI resource, usually delivered by the
same tool to which the deep linking request was made to. A platform may support
links associated to other tools. How this association may happen is not
specified.

Properties of an LTI link are:

| Name | Description | Disposition |
|---|---|---|
| `type` | Value must be `ltiResourceLink`. | required |
| `url` | Fully qualified url of the resource. If absent, the base LTI [URL](#dfn-url) of the
tool must be used for launch.

If a platform receives a url then it *MUST* use this url as the target_link_uri in the LtiResourceLinkRequest payload. | optional |
| `title` | String, plain text to use as the title or heading for content. | optional |
| `text` | String, plain text description of the content item intended to be displayed
to all users who can access the item. | optional |
| `icon` | Fully qualified URL, height, and width of an icon image to be placed with the file. A platform
may not support the display of icons, but where it does, it may choose to use a local copy of the icon rather than linking to the URL provided (which would also allow it to resize the image to suit its needs).

`url`: fully qualified URL to the image file.
`width`: integer representing the width in pixels of the image.
`height`: integer representing the height in pixels of the image. | optional |
| `thumbnail` | Fully qualified URL, height, and width of a thumbnail image to be made a hyperlink. This
allows the hyperlink to be opened within the platform from text or an image, or from both.

`url`: fully qualified URL to the image file.
`width`: integer representing the width in pixels of the image.
`height`: integer representing the height in pixels of the image. | optional |
| `window` | The `window` property indicates how to open the resource in a
new window/tab. The `window` property has the following optional properties:

`targetName`: String identifying the name of the window to open; this allows for a single window to be shared as the target of multiple links, preventing a proliferation of new windows/tabs.
`width`: integer representing the width in pixels of the new window
`height`: integer representing the height in pixels of the new window
`windowFeatures`: Comma-separated list of window features as per the [window.open() definition](https://developer.mozilla.org/en-US/docs/Web/API/Window/open). | optional |
| `iframe` | The `iframe` property indicates the resource can be embedded
using an iframe. The parameters indicates the preferred dimension of the iframe:

`width`: integer representing the width in pixels of the new iframe.
`height`: integer representing the height in pixels of the new iframe. | optional |
| `custom` | A map of key/value custom parameters. Those parameters *MUST* be included
in the LtiResourceLinkRequest payload. Value may include substitution parameters as defined in the LTI Core Specification [[LTI-13](#bib-lti-13)]. Map values must be strings. Note that "empty-string" is a valid value (`""`); however, `null` is not a valid value. | optional |
| `lineItem` | A lineItem object that indicates this activity is expected to receive
scores; the platform may automatically create a corresponding line item when the resource link is created, using the maximum score as the default maximum points. The `resource_id`, `tag` and `scoreMaximum` are defined in the [[LTI-AGS-20](#bib-lti-ags-20)]. A line item created as a result of a Deep Linking interaction must be exposed in a subsequent line item service call, with the `resourceLinkId` of the associated resource link, as well as the `resourceId` and `tag` if present in the line item definition.

`label` (optional): label for the line item. If not present, the `title` of the content item must be used.
`scoreMaximum` (required): Positive decimal value indicating the maximum score possible for this activity.
`resourceId` (optional): String, tool provided ID for the resource.
`tag` (optional): String, additional information about the line item; may be used by the tool to identify line items attached to the same resource or resource link (example: grade, originality, participation).

`gradesReleased` (optional): boolean to indicate if the platform should release the grades, e.g., to learners. | optional |
| `available` | Indicates the initial start and end time this activity should be made
available to learners. A platform may choose to make an item not accessible by hiding it, or by disabling the link, or some other method which prevents the link from being opened by a learner. The initial value may subsequently be changed within the platform and the tool may use the `ResourceLink.available.startDateTime` and `ResourceLink.available.endDateTime` substitution parameters defined in LTI Core specification [[LTI-13](#bib-lti-13)] within custom parameters to get the actual values at launch time. Note there may be many factors controlling the availability of an item by the platform, and tools are not guaranteed to receive available start and end times in a launch, even if they set them when creating content.

`startDateTime` (optional): ISO 8601 date and time when the link becomes accessible [[ISO8601](#bib-iso8601)].

`endDateTime` (optional): ISO 8601 date and time when the link stops being accessible [[ISO8601](#bib-iso8601)]. | optional |
| `submission` | Indicates the initial start and end time submissions for this activity
can be made by learners. The initial value may subsequently be changed within the platform and the tool may use the `ResourceLink.submission.startDateTime` and `ResourceLink.submission.endDateTime` substitution parameters defined in LTI Core specification [[LTI-13](#bib-lti-13)] within custom parameters to get the actual values at launch time.

`startDateTime` (optional): ISO 8601 Date and time when the link can start receiving submissions [[ISO8601](#bib-iso8601)].
`endDateTime` (optional): ISO 8601 Date and time when the link stops accepting submissions [[ISO8601](#bib-iso8601)]. | optional |

### 3.3 File

A file is a resource transferred from the tool to stored and/or processed by the
platform. The [URL](#dfn-url) to the resource should be considered short lived and the
platform must process the file within a short time frame (within minutes).

Properties of a file item are

| Name | Description | Disposition |
|---|---|---|
| `type` | Value must be `file`. | required |
| `url` | Fully qualified [URL](#dfn-url) of the resource. This link may be short-lived or
expire after 1st use. | required |
| `title` | String, plain text to use as the title or heading for content. | optional |
| `text` | String, plain text description of the content item intended to be
displayed to all users who can access the item. | optional |
| `icon` | Fully qualified [URL](#dfn-url), height, and width of an icon image to be placed with the file. A
platform may not support the display of icons, but where it does, it may choose to use a local copy of the icon rather than linking to the URL provided (which would also allow it to resize the image to suit its needs).

`url`: fully qualified URL to the image file.
`width`: integer representing the width in pixels of the image.
`height`: integer representing the height in pixels of the image. | optional |
| `thumbnail` | Fully qualified [URL](#dfn-url), height, and width of a thumbnail image to be made a hyperlink. This
allows the hyperlink to be opened within the platform from text or an image, or from both.

`url`: fully qualified URL to the image file.
`width`: integer representing the width in pixels of the image.
`height`: integer representing the height in pixels of the image. | optional |
| `expiresAt` | ISO 8601 Date and time [[ISO8601](#bib-iso8601)]. The [URL](#dfn-url) will be available until
this time. No guarantees after that. (e.g. 2014-03-05T12:34:56Z). | optional |

### 3.4 HTML fragment

An HTML fragment to be embedded in html document. If the HTML fragment renders a
a single resource which is also addressable directly, the tool *SHOULD* use the
`link` type with an `embed` code.

Properties of an HTML fragment are:

| Name | Description | Disposition |
|---|---|---|
| `type` | Value must be `html`. | required |
| `html` | HTML fragment to be embedded. The platform is expected to sanitize it
against cross-site scripting attacks. | required |
| `title` | String, plain text to use as the title or heading for content. | optional |
| `text` | String, plain text description of the content item intended to be
displayed to all users who can access the item. | optional |

### 3.5 Image

Image is a [URL](#dfn-url) pointing to an image resource that *SHOULD* be
rendered directly in the browser agent using the HTML `img` tag.

Properties of image are:

| Name | Description | Disposition |
|---|---|---|
| `type` | Value must be `image`. | required |
| `url` | Fully qualified [URL](#dfn-url) of the image. | required |
| `title` | String, plain text to use as the title or heading for content. | optional |
| `text` | String, plain text description of the content item intended to be
displayed to all users who can access the item. | optional |
| `icon` | Fully qualified URL, height, and width of an icon image to be placed with the file. A
platform may not support the display of icons, but where it does, it may choose to use a local copy of the icon rather than linking to the URL provided (which would also allow it to resize the image to suit its needs).

`url`: fully qualified URL to the image file.
`width`: integer representing the width in pixels of the image.
`height`: integer representing the height in pixels of the image. | optional |
| `thumbnail` | Fully qualified URL, height, and width of a thumbnail image to be made a hyperlink. This
allows the hyperlink to be opened within the platform from text or an image, or from both.

`url`: fully qualified URL to the image file.
`width`: integer representing the width in pixels of the image.
`height`: integer representing the height in pixels of the image. | optional |
| `width` | Integer representing the width in pixels of the image. | optional |
| `height` | Integer representing the height in pixels of the image. | optional |

### 3.6 Extending a type

Type definitions may be enriched with additional properties. The key for custom
properties *SHOULD* be a fully qualified [URL](#dfn-url). This requirement does not
apply to nested properties of the added property.

For example:

```json
{
  "type": "image",
  "url": "https://www.example.com/image.png",
  "https://www.example.com/resourceMetadata": {
    "license": "CCBY4.0"
  }
}
```

*Figure 2 Example of type extension via the addition of a custom property*

### 3.7 Defining new types

The Deep linking specification defines a flow to transfer item(s) from the tool to
the platform. In the future, it is expected to be leveraged to transfer of other types of items.

When a new type is added, it must to the minimum contain a
`type` property and a value that uniquely identifies the new type.
To avoid collisions, the value must be a fully qualified [URL](#dfn-url) unless specified
otherwise by IMS Global.

## 4. LTI Deep Linking interaction

LTI platforms and tools use *messages* to transfer the user agent from one host
to the other through an HTML form post redirection containing the message
payload. The deep linking, bi-directional workflow employs separate request
and response messages:

- The deep linking [deep linking request message](#dfn-deep-linking-request-message) flows from the platform to the tool to
initiate the deep linking resource selection/creation workflow.
- The deep linking [deep linking response message](#dfn-deep-linking-response-message) flows from the tool back to the platform to
send back the results of selection/creation and close off the workflow.

### 4.1 JSON Web Token

As with the core resource link launch request, the senders of the deep linking
messages *MUST* wrap the payload in a *JSON Web Token* (JWT) [[RFC7519](#bib-rfc7519)]. This
allows the receiver of a deep linking message to trust the authenticity and origin
of the message even though the messages travel through the user's browser. For
details on the process by which message senders encode messages into JWTs, see the
IMS Security Framework specification [[SEC-10](#bib-sec-10)].

### 4.2 Message claims

Both deep linking message types consist of a set of claims that supplement the
ones mandated by the IMS Security Framework [[SEC-10](#bib-sec-10)]
specification. Additionally, both message types include many of the claims defined
in the core LTI resource link launch request message, defined in LTI
1.3 [[LTI-13](#bib-lti-13)]. This document lists the claims here, but see the above referenced
specifications for their full definitions.

### 4.3 Message type and schemas

Each deep linking message's
`https://purl.imsglobal.org/spec/lti/claim/message_type` claim value
declares the appropriate message type. Both deep linking message types
have [associated JSON schemas](#document-set) that formally define
all their claims, which claims are required, and which are optional.

| Name | Message type value | Schema |
|---|---|---|
| Deep linking request | `LtiDeepLinkingRequest` | [LTI Deep Linking Request schema](#request-schema) |
| Deep linking response | `LtiDeepLinkingResponse` | [LTI Deep Linking Response schema](#response-schema) |

### 4.4 Deep linking request message

The LTI Deep Linking request message is a signed JWT that the platform passes to the tool with the same message parameters in the deep linking request message as it would in the resource link launch request message with the exception of the resource link claim, along with some additional parameters.

An `LtiDeepLinkingRequest` JWT contains the following claims:

#### 4.4.1 Deep linking settings

The required
`https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings` claim
composes properties that characterize the kind of deep linking request the
platform user is making, as in the following example:

```json
{
  "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings": {
    "accept_types": ["link", "file", "html", "ltiResourceLink", "image"],
    "accept_media_types": "image/*,text/html",
    "accept_presentation_document_targets": ["iframe", "window", "embed"],
    "accept_multiple": true,
    "auto_create": true,
    "title": "This is the default title",
    "text": "This is the default text",
    "data": "Some random opaque data that MUST be sent back",
    "deep_link_return_url": "https://platform.example/deep_links"
  }
}
```

*Figure 3 Example of the `deep_linking_settings` claim.*

The `deep_linking_settings` claim has the following properties:

| Name | Description | Disposition |
|---|---|---|
| `deep_link_return_url` | Fully qualified URL where the tool redirects
the user back to the platform interface. This URL can be used once the tool is finished. | required |
| `accept_types` | An array of types accepted, e.g., `["link", "ltiResourceLink"]`. | required |
| `accept_presentation_document_targets` | An array of document targets supported, e.g., `["iframe", "window", "embed"]`. | required |
| `accept_media_types` | Media types [[RFC7231](#bib-rfc7231)] the platform accepts. This only
applies to File types, e.g., `"image/*,text/html"`. | optional |
| `accept_multiple` | Boolean - Whether the platform allows multiple content items to be submitted in a single response. | optional |
| `accept_lineitem` | Boolean - whether the platform in the context of that deep linking request supports or ignores line items included in LTI Resource Link items. False indicates line items will be ignored. True indicates the platform will create a line item when creating the resource link. If the field is not present, no assumption that can be made about the support of line items. | optional |
| `auto_create` | Boolean - whether any content items returned by the tool would be automatically
persisted without any option for the user to cancel the operation. The default is false. | optional |
| `title` | Default text to be used as the title or alt text for the
content item returned by the tool. This value is normally short in length, for example, suitable for use as a heading. | optional |
| `text` | Default text to be used as the visible text for the
content item returned by the tool. If no text is returned by the tool, the platform may use the value of the title parameter instead (if any). This value may be a long description of the content item. | optional |
| `data` | An opaque value which must be returned by the tool in
its response if it was passed in on the request. | optional |

#### 4.4.2 Message type

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the required
`https://purl.imsglobal.org/spec/lti/claim/message_type`
claim must have the value `LtiDeepLinkingRequest`.

#### 4.4.3 LTI version

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the required
`https://purl.imsglobal.org/spec/lti/claim/version` claim
must have the value `1.3.0`.

#### 4.4.4 Deployment ID

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the required
`https://purl.imsglobal.org/spec/lti/claim/deployment_id` claim
identifies the platform-tool integration governing the message.

#### 4.4.5 User

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the `sub`
claim identifies the user that initiated the deep linking request. Other user
related claims may be included as defined in LTI 1.3 [[LTI-13](#bib-lti-13)].

#### 4.4.6 Launch Presentation

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the optional
`https://purl.imsglobal.org/spec/lti/claim/launch_presentation` claim composes
properties that describe aspects of how the message sender expects to host the presentation
of the message receiver's user experience (for example, the height and width of the
viewport the message sender gives over to the message receiver), as in the
[Deep linking request example](#deep-linking-request-example).

#### 4.4.7 Platform

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the optional
`http://purl.imsglobal.org/lti/claim/tool_platform` claim composes properties
associated with the platform initiating the launch, as in the
[Deep linking request example](#deep-linking-request-example).

#### 4.4.8 Context

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the optional
`https://purl.imsglobal.org/spec/lti/claim/context` claim
composes properties for the platform context from within which the deep linking
request occurs (typically from within a course or course section).

#### 4.4.9 Role

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the optional
`https://purl.imsglobal.org/spec/lti/claim/roles` claim
contains a (possibly empty) array of roles that the user has within the message's
associated context.

#### 4.4.10 Role-scope mentor

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the optional
`https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor`
claim's value contains an array of the user ID values which the current,
launching user can access as a mentor (for example, the launching user may be a
parent or auditor of a list of other users).

#### 4.4.11 Custom properties

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the optional
`http://imsglobal.org/custom` claim acts like a key-value map of
defined custom properties that a platform may associate with the particular
placement of the resource link that initiated the launch. Map values must be strings. Note that
"empty-string" is a valid value (`""`); however, `null` is not a valid value.

### 4.5 Deep linking response message

The LTI Deep Linking response message is
a Tool-Originating Message as defined in the Tool-Originating messages section of the
Security Framework specification [[SEC-10](#bib-sec-10)].

The response message covers the last part of the overall deep linking workflow:
a user has finished selecting or creating one or multiple resources in the external tool, and
the user needs to be redirected back to the platform with information about the resources to be added;
the User Agent redirection is done using a form POST with the form parameter `JWT`
being the response message.

The message contains a JSON array of the items to be added. This array could be empty,
if no item were selected or created.

An `LtiDeepLinkingResponse` JWT contains the following claims in addition to the
ones required by the Security Framework specification [[SEC-10](#bib-sec-10)]:

#### 4.5.1 aud

As defined in the Security Framework specification [[SEC-10](#bib-sec-10)], the required
`aud` must contain the
case-sensitive URL used by the Platform to identify itself as an Issuer, that is
the `iss` value in the Deep Linking request message.

#### 4.5.2 Message type

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the required
`https://purl.imsglobal.org/spec/lti/claim/message_type`
claim must have the value `LtiDeepLinkingResponse`.

#### 4.5.3 LTI version

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the required
`https://purl.imsglobal.org/spec/lti/claim/version` claim
must have the value `1.3.0`.

#### 4.5.4 Deployment ID

As defined in the LTI Core specification [[LTI-13](#bib-lti-13)], the required
`https://purl.imsglobal.org/spec/lti/claim/deployment_id` claim
identifies the platform-tool integration governing the message.

#### 4.5.5 Data

The `https://purl.imsglobal.org/spec/lti-dl/claim/data` value must
match the value of the `data` property of the
`https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings` claim
from the `LtiDeepLinkinkingRequest` message. This claim
is required if present in LtiDeepLinkingRequest message.

#### 4.5.6 Content items

A possibly empty JSON array of selected content items all appear composed within
the `https://purl.imsglobal.org/spec/lti-dl/claim/content_items` claim.
An empty array or the absence of this claim indicates there should be no item
added as a result of this interaction. This claim is optional.

#### 4.5.7 Message

The optional `https://purl.imsglobal.org/spec/lti-dl/claim/msg` value
is a plain text string of a message the platform may show to the end user upon
return to the platform.

#### 4.5.8 Log

The optional `https://purl.imsglobal.org/spec/lti-dl/claim/log` claim
value is a plain text string of a message the platform may log when processing this message.

#### 4.5.9 Error message

The optional `https://purl.imsglobal.org/spec/lti-dl/claim/errormsg` claim
value is a plain text string of a message the platform may show to the end user
upon return to the platform. It indicates some error as occurred during the interaction.

#### 4.5.10 ErrorLog

The optional `https://purl.imsglobal.org/spec/lti-dl/claim/errorlog` claim
value is a plain text string of a message the platform may log when processing
this message. It indicates some error as occurred during the interaction.

### 4.6 Message types

This section describes how to migrate from
Deep Linking 1.0 specification [[LTI-DL-10](#bib-lti-dl-10)].

The key difference is that under Deep Linking 2.0 messages are signed
JSON payloads (JSON Web Token) [[RFC7519](#bib-rfc7519)]. In addition to the message format
itself, some changes have been made to clarify the type system and
simplify the JSON structure to be more concise and with
less nesting.

The following tables illustrate how to map LTI Deep Linking 1.0 terminology
with the one from this version of the specification:

| Deep Linking 1.0 | Deep Linking 2.0 |
|---|---|
| ContentItemSelectionRequest | LtiDeepLinkingRequest |
| ContentItemSelection | LtiDeepLinkingResponse |

#### 4.6.1 Content Item Types

| Deep Linking 1.0 media-type | Deep Linking 2.0 type |
|---|---|
| `application/vnd.ims.lti.v1.ltiResourceLink` | `ltiResourceLink` |
| `image/*` unless `copyAdvice: true` | `image` |
| `text/html` (html fragment to embed) | `html` if the item is not directly addressable with a URL.
If directly accessible, `link` with `embed` is preferred. |
| `text/html` (link to an external site) | `link` |
| any other media type, `copyAdvice: false` | `link` |
| any other media type, `copyAdvice: true` | `file` |

#### 4.6.2 Presentation target document

This specification also simplifies the possible values for the
presentation options to the technical choices: embedded code,
iframe or new window.

| Deep Linking 1.0 | Deep Linking 2.0 |
|---|---|
| embed | embed |
| frame | window, target: self |
| iframe | iframe |
| window | window |
| popup | window or iframe, depending on how the platform intends to render a popup |
| overlay | window, embed or iframe, depending on how the platform intends to render an overlay |
| none | empty array |

## A. Deep linking request example

The LTI Deep Linking launch request message JSON object follows the form in this
example.

```json
{
  "iss": "https://platform.example.org",
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
  "picture": "https://example.org/jane.jpg",
  "email": "jane@example.org",
  "locale": "en-US",
  "https://purl.imsglobal.org/spec/lti/claim/deployment_id":
    "07940580-b309-415e-a37c-914d387c1150",
  "https://purl.imsglobal.org/spec/lti/claim/message_type": "LtiDeepLinkingRequest",
  "https://purl.imsglobal.org/spec/lti/claim/version": "1.3.0",
  "https://purl.imsglobal.org/spec/lti/claim/roles": ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor",
    "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"],
  "https://purl.imsglobal.org/spec/lti/claim/context": {
    "id": "c1d887f0-a1a3-4bca-ae25-c375edcc131a",
    "label": "ECON 101",
    "title": "Economics as a Social Science",
    "type": ["CourseOffering"]
  },
  "https://purl.imsglobal.org/spec/lti/claim/tool_platform": {
    "contact_email": "support@example.org",
    "description": "An Example Tool Platform",
    "name": "Example Tool Platform",
    "url": "https://example.org",
    "product_family_code": "example.org",
    "version": "1.0"
  },
  "https://purl.imsglobal.org/spec/lti/claim/launch_presentation": {
    "document_target": "iframe",
    "height": 320,
    "width": 240
  },
  "https://purl.imsglobal.org/spec/lti/claim/custom": {
    "myCustom": "123"
  },
  "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings": {
    "deep_link_return_url": "https://platform.example/deep_links",
    "accept_types": ["link", "file", "html", "ltiResourceLink", "image"],
    "accept_media_types": "image/*,text/html",
    "accept_presentation_document_targets": ["iframe", "window", "embed"],
    "accept_multiple": true,
    "auto_create": true,
    "title": "This is the default title",
    "text": "This is the default text",
    "data": "csrftoken:c7fbba78-7b75-46e3-9201-11e6d5f36f53"
  }
}
```

*Figure 4 Example of the LTI Deep Linking launch request message JSON object*

## B. Deep linking response example

The LTI Deep Linking launch response message JSON object follows the form in this
example.

```json
{
  "iss": "962fa4d8-bcbf-49a0-94b2-2de05ad274af",
  "aud": "https://platform.example.org",
  "exp": 1510185728,
  "iat": 1510185228,
  "nonce": "fc5fdc6d-5dd6-47f4-b2c9-5d1216e9b771",
  "azp": "962fa4d8-bcbf-49a0-94b2-2de05ad274af",
  "https://purl.imsglobal.org/spec/lti/claim/deployment_id":
    "07940580-b309-415e-a37c-914d387c1150",
  "https://purl.imsglobal.org/spec/lti/claim/message_type":
    "LtiDeepLinkingResponse",
  "https://purl.imsglobal.org/spec/lti/claim/version": "1.3.0",
  "https://purl.imsglobal.org/spec/lti-dl/claim/content_items": [{
      "type": "link",
      "title": "My Home Page",
      "url": "https://something.example.com/page.html",
      "icon": {
        "url": "https://lti.example.com/image.jpg",
        "width": 100,
        "height": 100
      },
      "thumbnail": {
        "url": "https://lti.example.com/thumb.jpg",
        "width": 90,
        "height": 90
      }
    },
    {
      "type": "html",
      "html": "<h1>A Custom Title</h1>"
    },
    {
      "type": "link",
      "url": "https://www.youtube.com/watch?v=corV3-WsIro",
      "embed": {
        "html":
          "<iframe width=\"560\" height=\"315\" src=\"https://www.youtube.com/embed/corV3-WsIro\" frameborder=\"0\" allow=\"autoplay; encrypted-media\" allowfullscreen></iframe>"
      },
      "window": {
        "targetName": "youtube-corV3-WsIro",
        "windowFeatures": "height=560,width=315,menubar=no"
      },
      "iframe": {
        "width": 560,
        "height": 315,
        "src": "https://www.youtube.com/embed/corV3-WsIro"
      }
    },
    {
      "type": "image",
      "url": "https://www.example.com/image.png",
      "https://www.example.com/resourceMetadata": {
        "license": "CCBY4.0"
      }
    },
    {
      "type": "ltiResourceLink",
      "title": "A title",
      "text": "This is a link to an activity that will be graded",
      "url": "https://lti.example.com/launchMe",
      "icon": {
        "url": "https://lti.example.com/image.jpg",
        "width": 100,
        "height": 100
      },
      "thumbnail": {
        "url": "https://lti.example.com/thumb.jpg",
        "width": 90,
        "height": 90
      },
      "lineItem": {
        "scoreMaximum": 87,
        "label": "Chapter 12 quiz",
        "resourceId": "xyzpdq1234",
        "tag": "originality",
        "gradesReleased": true
      },
      "available": {
        "startDateTime": "2018-02-06T20:05:02Z",
        "endDateTime": "2018-03-07T20:05:02Z"
      },
      "submission": {
        "endDateTime": "2018-03-06T20:05:02Z"
      },
      "custom": {
        "quiz_id": "az-123",
        "duedate": "$ResourceLink.submission.endDateTime"
      },
      "window": {
        "targetName": "examplePublisherContent"
      },
      "iframe": {
        "height": 890
      }
    },
    {
      "type": "file",
      "title": "A file like a PDF that is my assignment submissions",
      "url": "https://my.example.com/assignment1.pdf",
      "mediaType": "application/pdf",
      "expiresAt": "2018-03-06T20:05:02Z"
    },
    {
      "type": "https://www.example.com/custom_type",
      "data": "somedata"
    }],
  "https://purl.imsglobal.org/spec/lti-dl/claim/data":
    "csrftoken:c7fbba78-7b75-46e3-9201-11e6d5f36f53"
}
```

*Figure 5 Example of the LTI Deep Linking launch request message JSON object*

## C. Revision history

*This section is non-normative.*

LTI Deep Linking 2.0 follows from, and replaces, the IMS LTI Content-Item Message specification released in 2016 (later rebranded as IMS LTI Deep Linking 1.0).

LTI Deep Linking 2.0 improves upon the previous LTI Deep Linking 1.0 [[LTI-DL-10](#bib-lti-dl-10)] specification by moving away from the use of OAuth 1.0a-style signing for authentication and towards the newer security model described in the IMS Security Framework specification, using signed JSON Web Tokens (JWT) and OAuth 2.0 workflows for authentication.

It also clarifies the types, and outlines the extension mechanisms available to implementers.

### C.1 Version History

| Spec Version No. | Document Version No. | Release Date | Comments |
|---|---|---|---|
| v1.0 Final | | 24 May 2016 | First release of the Deep Linking specification (formerly known as Content-Item Message). |
| v2.0 Final | | 16 April 2019 | Updates to synchronize with the IMS Security Framework and LTI v1.3 specifications. |
| v2.0 Final | | 30 July 2019 | Changes to correct minor errors and provide clearer details (see [errata](https://www.imsglobal.org/spec/lti-dl/v2p0/errata/) for specific changes). |
| v2.0 Final | 1 | 29 October 2019 | Changes to correct the case (from "LTIDeepLinkingResponse" to "LtiDeepLinkingResponse") and to make some
clarifications in the Deep Linking examples. |
| v2.0 Final | 2 | 24 January 2023 | Clarify allowable values for custom properties.
Add `accept_lineitem` to Deep Linking settings. ([docs](#deep-linking-settings))
Clarify that custom property values must be strings.
Add `gradesReleased` flag on lineItem ([docs](#lti-resource-link))
`sub` is no longer required for Deep Linking Launch for the User([docs](#user))
Clarify use of `ResourceLink.available.endDateTime` ([docs](#lti-resource-link))
Clarify use of `target_link_uri` in the LtiResourceLinkRequest payload. ([docs](#lti-resource-link))
Minor grammar corrections. |

## D. References

### D.1 Normative references

`[ISO8601]`
: [Representation of dates and times. ISO 8601:2004.](http://www.iso.org/iso/catalogue_detail?csnumber=40874). International Organization for Standardization (ISO). 2004. ISO 8601:2004. URL: <http://www.iso.org/iso/catalogue_detail?csnumber=40874>

`[LIS-20]`
: [IMS Global Learning Information Services v2.0](https://www.imsglobal.org/lis/). L. Feng; W. Lee; C. Smythe. IMS Global Learning Consortium. June 2011. URL: <https://www.imsglobal.org/lis/>

`[LTI-13]`
: [IMS Global Learning Tools Interoperability (LTI)® Core Specification v1.3](https://www.imsglobal.org/spec/lti/v1p3/). C. Vervoort; N. Mills. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/>

`[LTI-AGS-20]`
: [IMS Global Learning Tools Interoperability (LTI)® Assignment and Grade Services](https://www.imsglobal.org/spec/lti-ags/v2p0/). C. Vervoort; E. Preston; M. McKell; J. Rissler. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti-ags/v2p0/>

`[LTI-CERT-13]`
: [IMS Global Learning Tools Interoperability (LTI)® Advantage Conformance Certification Guide](https://www.imsglobal.org/spec/lti/v1p3/cert/). D. Haskins; M. McKell. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/cert/>

`[LTI-DL-10]`
: [IMS Global Learning Tools Interoperability (LTI)® Deep Linking 1.0](https://www.imsglobal.org/specs/lticiv1p0/specification). S. Vickers. IMS Global Learning Consortium. May 2016. URL: <https://www.imsglobal.org/specs/lticiv1p0/specification>

`[LTI-IMPL-13]`
: [IMS Global Learning Tools Interoperability (LTI)® Advantage Implementation Guide](https://www.imsglobal.org/spec/lti/v1p3/impl/). C. Vervoort; J. Rissler; M. McKell. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/lti/v1p3/impl/>

`[RFC2119]`
: [Key words for use in RFCs to Indicate Requirement Levels](https://www.rfc-editor.org/rfc/rfc2119). S. Bradner. IETF. March 1997. Best Current Practice. URL: <https://www.rfc-editor.org/rfc/rfc2119>

`[RFC2396]`
: [Uniform Resource Identifiers (URI): Generic Syntax](https://www.rfc-editor.org/rfc/rfc2396). T. Berners-Lee; R. Fielding; L. Masinter. IETF. August 1998. Draft Standard. URL: <https://www.rfc-editor.org/rfc/rfc2396>

`[RFC2818]`
: [HTTP Over TLS](https://httpwg.org/specs/rfc2818.html). E. Rescorla. IETF. May 2000. Informational. URL: <https://httpwg.org/specs/rfc2818.html>

`[RFC4122]`
: [A Universally Unique IDentifier (UUID) URN Namespace](https://www.rfc-editor.org/rfc/rfc4122). P. Leach; M. Mealling; R. Salz. IETF. July 2005. Proposed Standard. URL: <https://www.rfc-editor.org/rfc/rfc4122>

`[RFC7159]`
: [The JavaScript Object Notation (JSON) Data Interchange Format](https://www.rfc-editor.org/rfc/rfc7159). T. Bray, Ed.. IETF. March 2014. Proposed Standard. URL: <https://www.rfc-editor.org/rfc/rfc7159>

`[RFC7231]`
: [Hypertext Transfer Protocol (HTTP/1.1): Semantics and Content](https://httpwg.org/specs/rfc7231.html). R. Fielding, Ed.; J. Reschke, Ed.. IETF. June 2014. Proposed Standard. URL: <https://httpwg.org/specs/rfc7231.html>

`[RFC7519]`
: [JSON Web Token (JWT)](https://www.rfc-editor.org/rfc/rfc7519). M. Jones; J. Bradley; N. Sakimura. IETF. May 2015. Proposed Standard. URL: <https://www.rfc-editor.org/rfc/rfc7519>

`[SEC-10]`
: [IMS Global Security Framework v1.0](https://www.imsglobal.org/spec/security/v1p0/). C. Smythe; C. Vervoort; M. McKell; N. Mills. IMS Global Learning Consortium. April 2019. IMS Final Release. URL: <https://www.imsglobal.org/spec/security/v1p0/>

## E. List of Contributors

The following individuals contributed to the development of this document:

| Name | Organization | Role |
|---|---|---|
| Paul Gray | Learning Objects | |
| Viktor Haag | D2L | |
| Dereck Haskins | IMS Global | |
| Martin Lenord | Turnitin | |
| Karl Lloyd | Instructure | |
| Mark McKell | IMS Global | Editor |
| Nathan Mills | Instructure | |
| Bracken Mosbacker | Lumen Learning | |
| Padraig O'hiceadha | HMH | |
| Marc Phillips | Instructure | |
| Eric Preston | Blackboard | Editor |
| James Rissler | IMS Global | Editor |
| Charles Severance | University of Michigan | |
| Lior Shorshi | McGraw-Hill Education | |
| James Tse | Google | |
| Colin Smythe | IMS Global | |
| Claude Vervoort | Cengage | Editor |
