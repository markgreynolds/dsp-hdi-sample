# HDI Synonyms and External Schemas: A Complete Guide

## What This Document Covers

When an SAP HANA HDI container needs to read data from a table or view that lives
**outside** the container — in a separate schema managed by a different team or system —
you cannot simply write a SQL query against it. HDI containers are isolated by design:
they own their own schema, deploy their own objects, and control their own privileges.
To reach across that boundary, you need three things working together: a **synonym** that
acts as a local alias for the external object, a **grantor service** that holds the
credentials of a database user with access to that external object, and a **grants file**
that instructs HDI to request the necessary privileges through that grantor.

This document explains how those pieces connect, why the naming relationships between
them are so strict, and what goes wrong — silently — when they are not aligned.

---

## The Role of a User-Provided Service (UPS)

### What it is

A **User-Provided Service (UPS)** is a Cloud Foundry construct for injecting arbitrary
credentials into an application's environment. In the context of HDI synonyms, it serves
a specific purpose: it carries the database credentials of a **grantor user** — a HANA
database user who already has `SELECT WITH GRANT OPTION` on the external object you want
to expose.

The UPS itself is not a database object. It is a CF/BTP service instance that you create
and manage through the CF CLI or BTP cockpit. When it is bound to your HDI deployer
module, CF injects its credentials into the deployer's `VCAP_SERVICES` environment
variable. The HDI deployer reads `VCAP_SERVICES` at deploy time to find the grantor
credentials, connects to the external schema using them, and executes the grants defined
in your `.hdbgrants` file.

### How to create one

```bash
cf create-user-provided-service external-sales-grantor \
  -p '{
  "host":"your-hana-host.hanacloud.ondemand.com",
  "port":"443",
  "user":"SALES_GRANTOR_USER",
  "password":"<password>",
  "schema":"SALES_DATA",
  "tags":["hana"]
}'
```

The name you give the UPS here — `external-sales-grantor` in this example — is the
anchor of the entire naming chain. Every configuration file in your HDI project that
participates in this synonym setup must reference this exact name.

### What the UPS credentials must contain

The grantor user (`SALES_GRANTOR_USER` above) must exist in the target HANA database and
must hold `SELECT WITH GRANT OPTION` on the external objects you want to expose. Without
`GRANT OPTION`, the HDI deployer can connect with those credentials but cannot issue
grants to the HDI container users — and the deployment will fail or silently produce
incomplete grants.

---

## The Naming Chain — How the UPS Name Flows Through Your Project

Everything in HDI synonym configuration is **name-based**. The UPS name you choose when
running `cf create-user-provided-service` must propagate — character for character —
through four files. A single mismatch causes silent failures: no build errors, no deploy
errors, and in some cases a synonym that appears to work while being incompletely
configured.

```
UPS name in CF/BTP  (e.g. "external-sales-grantor")
    │
    ├── mta.yaml  →  resource name: must equal the UPS name
    │                requires: entry under the HDI module must reference that resource
    │
    ├── .hdbgrants  →  top-level key must equal the UPS name
    │
    └── .hdbsynonymconfig  →  "target"."service" value must equal the UPS name
```

The `.hdbsynonym` file does not reference the UPS name — it only describes the target
object and schema. But it must be consistent with the object and schema names used in
`.hdbsynonymconfig` and `.hdbgrants`.

### File-by-file reference

| File | Field | Must equal |
|---|---|---|
| CF CLI / BTP | `cf create-user-provided-service <name>` | Your chosen grantor service name |
| `mta.yaml` | resource `name:` | The UPS name from CF |
| `mta.yaml` | `requires:` entry under the HDI deployer module | The resource name above |
| `.hdbgrants` | Top-level key (e.g. `"external-sales-grantor"`) | The UPS name |
| `.hdbsynonymconfig` | `"target"."service"` value | The UPS name |
| `.hdbsynonym` | `"target"."object"` and `"target"."schema"` | The actual DB object name and schema |

> **Rule of thumb:** Choose the UPS name before you write any configuration files, and
> use it exactly — same casing, same hyphens — everywhere. One character difference
> produces a silent failure.

---

## A Complete End-to-End Example

The following example uses consistent names throughout. The scenario: an HDI container
for a reporting application needs read access to a view `V_SALES_SUMMARY` in an external
schema `SALES_DATA`.

**Chosen names:**
- UPS / grantor service name: `external-sales-grantor`
- External schema: `SALES_DATA`
- External object: `V_SALES_SUMMARY` (a view)
- Local synonym name: `SALES_SUMMARY` (what the HDI container will call it internally)

### Step 1 — Create the UPS in CF/BTP

```bash
cf create-user-provided-service external-sales-grantor \
  -p '{"host":"your-hana-host.hanacloud.ondemand.com","port":"443","user":"SALES_GRANTOR_USER","password":"<password>","schema":"SALES_DATA","tags":["hana"]}'
```

The name `external-sales-grantor` is now registered in CF. This is the name that
appears in `VCAP_SERVICES` when the service is bound.

---

### Step 2 — Declare and bind the UPS in `mta.yaml`

The MTA descriptor does two things: it declares the UPS as a resource, and it binds that
resource to the HDI deployer module. Both references must use the UPS name exactly.

```yaml
modules:
  - name: my-reporting-app-db
    type: com.sap.cap.hdi-container
    path: db
    requires:
      - name: my-reporting-app-hdi-container
      - name: external-sales-grantor          # ← binds the UPS to this module

resources:
  - name: my-reporting-app-hdi-container
    type: com.sap.services.hana.hdi-shared

  - name: external-sales-grantor              # ← must match the CF UPS name exactly
    type: org.cloudfoundry.user-provided-service
```

When `cf deploy` processes this MTA, CF binds the `external-sales-grantor` UPS to the
deployer module. The HDI deployer can then find it in `VCAP_SERVICES` under the key
`external-sales-grantor`.

---

### Step 3 — `db/src/synonyms/SALES_SUMMARY.hdbsynonym`

The synonym file defines what local name the HDI container uses to refer to the external
object, and what that external object actually is. This file does **not** reference the
UPS — it only describes the target.

```json
{
  "SALES_SUMMARY": {
    "target": {
      "object": "V_SALES_SUMMARY",
      "schema": "SALES_DATA"
    }
  }
}
```

At runtime, any SQL in the container that references `"SALES_SUMMARY"` resolves to
`SALES_DATA.V_SALES_SUMMARY` in the external schema.

---

### Step 4 — `db/cfg/SALES_SUMMARY.hdbsynonymconfig`

The synonym config file adds the missing piece: it tells HDI which grantor service to use
when resolving the synonym's target at deploy time. The `"service"` field must equal the
UPS name.

```json
{
  "SALES_SUMMARY": {
    "target": {
      "object": "V_SALES_SUMMARY",
      "schema": "SALES_DATA",
      "service": "external-sales-grantor"
    }
  }
}
```

The synonym name (`"SALES_SUMMARY"`) must match the key used in `.hdbsynonym`. The
`"service"` value must match the UPS name and the top-level key in `.hdbgrants`.

---

### Step 5 — `db/cfg/SALES_SUMMARY.hdbgrants`

The grants file instructs the HDI deployer to use the grantor service credentials to
issue `SELECT` privileges on the external object to the HDI container's users. Two users
must be granted: the object owner (`#OO`) and the application/runtime user (`#RT`).

```json
{
  "external-sales-grantor": {
    "object_owner": {
      "object_privileges": [
        {
          "type": "VIEW",
          "name": "V_SALES_SUMMARY",
          "schema": "SALES_DATA",
          "privileges_with_grant_option": ["SELECT"],
          "privileges": ["SELECT"]
        }
      ]
    },
    "application_user": {
      "object_privileges": [
        {
          "type": "VIEW",
          "name": "V_SALES_SUMMARY",
          "schema": "SALES_DATA",
          "privileges": ["SELECT"]
        }
      ]
    }
  }
}
```

The top-level key `"external-sales-grantor"` is how the HDI deployer looks up the
correct credentials in `VCAP_SERVICES`. It must be identical to the UPS name.

> Replace `"type": "VIEW"` with `"type": "TABLE"` if the external object is a table.

---

### How It All Connects at Deploy Time

When `cf deploy` (or `hdi-deploy`) runs, the sequence is:

1. CF binds `external-sales-grantor` to the deployer module → credentials appear in
   `VCAP_SERVICES["external-sales-grantor"]`
2. The deployer reads `.hdbgrants`, finds the key `"external-sales-grantor"`, and looks
   up that name in `VCAP_SERVICES` to get the grantor user's credentials
3. Using those credentials, it connects to the external HANA schema and issues `SELECT`
   (with grant option) to the `#OO` user and plain `SELECT` to the `#RT` user
4. The deployer reads `.hdbsynonymconfig`, finds `"service": "external-sales-grantor"`,
   and uses the resolved schema/object to deploy the synonym
5. At runtime, application code accesses `"SALES_SUMMARY"` — the synonym — and the
   `#RT` user's `SELECT` privilege is what makes that work

---

## The Core Problem: Missing `application_user` Grant

### What goes wrong

The column mappings editor in SAP Business Application Studio shows **no columns**,
despite:

- The synonym resolving correctly
- The `.hdbgrants` file deploying without errors
- Being able to query the object via the synonym in a SQL console
- The build and deploy logs showing `ok` throughout

### Why it happens

The HDI deployer manages **two distinct users** for every container:

| User | Suffix | Purpose |
|---|---|---|
| Object Owner | `#OO` | Owns and deploys database objects |
| Application User | `#RT` (runtime) | Used at runtime by the application |

The column mappings UI introspects column metadata through the **application (runtime)
user**, not the object owner. If only `object_owner` is granted `SELECT`, the object
owner can see and query the object, but the application user cannot — and the UI silently
shows no columns.

### Why it is so hard to diagnose

- The build and deploy process reports **no errors or warnings**
- The synonym works — SQL queries return data
- There is **no UI message** explaining why columns are unavailable
- Nothing in the logs distinguishes "granted to object_owner only" from "fully
  configured"

---

## Symptoms Checklist

- [ ] No columns visible in the column mappings editor
- [ ] Synonym deployment succeeds with no warnings
- [ ] `.hdbgrants` deployment logs show `ok`
- [ ] SQL queries via the synonym return data correctly
- [ ] No errors anywhere in the build or deploy output

If all of the above are true, the cause is almost certainly a missing `application_user`
block in `.hdbgrants`.

---

## Privileges: `object_owner` vs `application_user`

| | `object_owner` | `application_user` |
|---|---|---|
| Needs `SELECT` | Yes | Yes |
| Needs `GRANT OPTION` / `privileges_with_grant_option` | Yes — so it can re-grant to the runtime user | No — plain `SELECT` is sufficient |
| Used for column introspection in UI | No | **Yes** |
| Used for deploy-time object creation | Yes | No |

---

## Fix

1. Add the `application_user` block to your `.hdbgrants` file (see the complete example
   above)
2. Verify the grantor service key name matches exactly across all files
3. Save the updated `.hdbgrants` file
4. **Redeploy the HDI module** — the deployer must process the updated grants
5. Reopen the column mappings editor — columns should now be visible

---

## Diagnostic Checks (if the fix does not immediately work)

1. **Verify the synonym resolves** — run in SQL console:
   ```sql
   SELECT * FROM "SALES_SUMMARY" LIMIT 1;
   ```
   If this fails, the synonym or schema mapping is wrong — not a grants issue.

2. **Check the `#OO` user has GRANT OPTION** — run as an admin:
   ```sql
   SELECT GRANTEE, PRIVILEGE, IS_GRANTABLE
   FROM SYS.OBJECT_PRIVILEGES
   WHERE OBJECT_NAME = 'V_SALES_SUMMARY'
     AND SCHEMA_NAME = 'SALES_DATA';
   ```
   The `#OO` user must appear with `IS_GRANTABLE = TRUE`. If it is `FALSE`, the grantor
   user in the UPS does not have `GRANT OPTION` on the object — fix that first.

3. **Verify the UPS is bound and its credentials are visible**:
   ```bash
   cf services
   cf env <your-deployer-app-name>
   ```
   Confirm `external-sales-grantor` appears in `VCAP_SERVICES` with a `credentials`
   block containing `host`, `user`, and `password`.

4. **Check for schema mismatch** — the `"schema"` value in `.hdbsynonymconfig` and
   `.hdbgrants` must be the actual HANA schema name, not a CF service name or an alias.
   Run `SELECT SCHEMA_NAME FROM SYS.SCHEMAS` to confirm the exact name.

5. **Force a full rebuild** — if grants still do not take effect after redeployment, do a
   full undeploy and redeploy of the HDI module. The deployer does not always reprocess
   `.hdbgrants` on an incremental deploy if it considers the file unchanged.

---

## Key Takeaway

The UPS name is the single thread connecting CF service binding, MTA resource
declaration, synonym configuration, and grant execution. It must be identical in every
file. Whenever columns are missing in the HDI column mappings editor with no other
errors, the first thing to check is whether `application_user` is granted `SELECT`
alongside `object_owner` in `.hdbgrants` — it is the single most common silent failure
in HDI synonym configurations against external schemas.
