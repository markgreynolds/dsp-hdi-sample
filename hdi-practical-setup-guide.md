# SAP HANA HDI Synonyms — Practical Setup Guide

## Purpose

This guide describes how to expose an existing HANA database object through an HDI synonym, configure its target for different environments, and arrange the necessary permissions.

The example uses the existing object `NAR_QA.CUSTOMERS_GV`.

## 1\. Understand the Four Components

| Component | Purpose |
| --- | --- |
| `.hdbsynonym` | Defines the local synonym used by the application. |
| `.hdbsynonymconfig` | Configures the synonym's external target, independently of its definition. |
| `.hdbgrants` | Specifies privileges to grant using a configured grantor service. |
| User Provided Service (UPS) | Provides service credentials and connection information used by the deployment process. |

**Remember:** A synonym establishes a reference to an object; it does not automatically provide permission to access that object.

## 2\. Prescriptive Setup Steps

### Step 1 — Identify the External Object

Determine the schema and object name of the existing database object.

Example:

- Schema: `NAR_QA`
- Object: `CUSTOMERS_GV`
- Desired local synonym: `CUSTOMERS_GV`

Confirm that the object exists and that the appropriate database user can access it.

### Step 2 — Create the Synonym Definition

**File:** `db/src/CUSTOMERS_GV.hdbsynonym`

```
{
  "CUSTOMERS_GV": {}
}
```

**Purpose:** Defines the local synonym name.

**Context:** The JSON key, `CUSTOMERS_GV`, identifies the synonym. The empty object leaves its target to be supplied through synonym configuration.

### Step 3 — Configure the Synonym Target

**File:** `db/cfg/CUSTOMERS_GV.hdbsynonymconfig`

```
{
  "CUSTOMERS_GV": {
    "target": {
      "object": "CUSTOMERS_GV",
      "schema": "NAR_QA"
    }
  }
}
```

**Purpose:** Maps the local synonym to its external target.

**Context:** The `CUSTOMERS_GV` key corresponds to the synonym definition in Step 2. The target is `NAR_QA.CUSTOMERS_GV`.

Keep this file separate when you expect the target schema to vary between environments.

### Step 4 — Configure the Grantor Service

Create or verify the User Provided Service (UPS) named `synonym-grantor-service`.

**Purpose:** Provides the credentials HDI uses to perform the requested grants.

**Context:** The service must be bound or otherwise made available to the HDI deployment process under the name referenced in the grants configuration. Verify the relevant service binding and MTA configuration.

The service name does not need to match the synonym name.

### Step 5 — Configure Permissions

**File:** `db/cfg/synonym-grantor-service.hdbgrants`

The following illustrates the structure. Retain the appropriate privileges and recipients for your project.

```
{
  "synonym-grantor-service": {
    "application_user": {
      "object_privileges": [
        {
          "schema": "NAR_QA",
          "name": "CUSTOMERS_GV",
          "privileges": ["SELECT"]
        }
      ]
    },
    "object_owner": {
      "object_privileges": [
        {
          "type": "VIEW",
          "schema": "NAR_QA",
          "name": "CUSTOMERS_GV",
          "privileges": ["SELECT"],
          "privileges_with_grant_option": ["SELECT"]
        }
      ]
    }
  }
}
```

**Purpose:** Requests privileges for the specified HDI technical users.

**Context:**

- The top-level key, `synonym-grantor-service`, identifies the grantor service.
- `application_user` identifies the application's technical access user.
- `object_owner` identifies the HDI container's object-owner user.
- `schema` and `name` identify the external object.
- `privileges_with_grant_option` requests permission to grant the specified privilege onward.

**Important:** This is an illustrative template, not a guaranteed replacement for your existing grants file. The appropriate object type and grant options depend on the object and deployment requirements. Your original file also requests grant option for `application_user`; preserve that only if it is needed. The grantor's credentials must have sufficient authority for every requested grant.

### Step 6 — Verify Deployment Configuration

Before deploying, check:

- The database module has its expected `src` and `cfg` structure.
- The relevant `.hdiconfig` configuration registers the required artifact types.
- The grantor service is correctly bound and referenced.
- The target object exists in the intended schema.
- The grantor has sufficient authority to grant the requested privileges.

### Step 7 — Deploy and Validate

Deploy the database module.

Then verify:

1. Deployment completes without synonym or grant errors.
2. The local synonym `CUSTOMERS_GV` exists in the HDI container.
3. The synonym resolves to the intended external object.
4. The relevant runtime user can execute a query such as:

```
   SELECT * FROM CUSTOMERS_GV;
```

5. The application works with its actual technical user, not just an administrator account.

## 3\. Promote to Another Environment

Keep the synonym definition stable and supply the appropriate target configuration and grants for each environment.

| Setting | QA example | Production example |
| --- | --- | --- |
| Local synonym | `CUSTOMERS_GV` | `CUSTOMERS_GV` |
| Target schema | `NAR_QA` | Production schema |
| Target object | `CUSTOMERS_GV` | `CUSTOMERS_GV` |
| Grantor service | Environment-specific binding | Environment-specific binding |
| Privileges | Required permissions | Required permissions |

Replace the production schema and service names with the actual production values.

**Deployment principle:** Promote the application artifacts together with the correct environment-specific configuration. Do not assume that the QA service binding or grants automatically apply in production.

## 4\. Naming Rules to Remember

| Relationship | Rule |
| --- | --- |
| Synonym key and configuration key | Must correspond to the same synonym. |
| Local synonym and external object names | Can differ; they are separate names. |
| Synonym name and UPS name | Do not need to match. |
| Top-level `.hdbgrants` key and service binding | Must resolve to the intended grantor service. |
| Artifact filename and UPS name | Matching is not inherently required; follow HDI artifact naming conventions. |
| Target schema | Must identify the intended external schema. |

## 5\. Final Checklist

- [ ]Confirm the external schema and object.
- [ ]Create the `.hdbsynonym` under `db/src`.
- [ ]Create the `.hdbsynonymconfig` under `db/cfg`.
- [ ]Ensure the synonym keys correspond.
- [ ]Configure the grantor UPS and service binding.
- [ ]Create or verify the `.hdbgrants` file.
- [ ]Confirm the grantor has sufficient privileges.
- [ ]Deploy the HDI module.
- [ ]Test synonym access using the application's technical user.
- [ ]Prepare the corresponding target and service configuration for each deployment environment.

## The Short Version

**Synonym definition → target configuration → grantor service → privileges → deployment → validation.**

Keep these responsibilities separate. The synonym defines the local name, the configuration identifies the target, and the grants file handles authorization.

**Practical recommendation:** Keep your existing, working `.hdbgrants` file as the starting point rather than replacing it with the illustrative version in this guide. The exact grant requirements depend on how the external object and HDI users are configured.