# SAP HANA HDI Synonyms — FAQ and Practical Reference

## Purpose

This document explains how HDI synonyms, synonym configurations, grantor services, and grants work together. It is intended as a practical reference for development and deployment across QA, production, and other environments.

The running example is an external database object:

`NAR_QA.CUSTOMERS_GV`

The desired local synonym is:

`CUSTOMERS_GV`

---

## 1\. Fundamental Concepts

### Q1. What is an HDI synonym?

A synonym is a database object that provides a local name for another database object.

Instead of directly referencing:

```
SELECT * FROM "NAR_QA"."CUSTOMERS_GV";
```

your application can reference the synonym:

```
SELECT * FROM "CUSTOMERS_GV";
```

The synonym points to the external object. It does not copy the data or automatically provide access privileges.

### Q2. Why are there both `.hdbsynonym` and `.hdbsynonymconfig` files?

They separate the synonym's identity from its target configuration.

| File | Responsibility |
| --- | --- |
| `.hdbsynonym` | Declares the local synonym. |
| `.hdbsynonymconfig` | Supplies or overrides the target configuration. |

The configuration is optional. Target information can also be included directly in the `.hdbsynonym` file.

SAP documentation: [Synonyms —](<https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-database-deployment-infrastructure-hdi-reference/synonyms-hdbsynonym-and-hdbsynonymconfig>)[`.hdbsynonym`](<https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-database-deployment-infrastructure-hdi-reference/synonyms-hdbsynonym-and-hdbsynonymconfig>)[and](<https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-database-deployment-infrastructure-hdi-reference/synonyms-hdbsynonym-and-hdbsynonymconfig>)[`.hdbsynonymconfig`](<https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-database-deployment-infrastructure-hdi-reference/synonyms-hdbsynonym-and-hdbsynonymconfig>).

### Q3. Why does `.hdbsynonymconfig` seem to be a mapping file?

That is a good way to understand it.

It maps a synonym name to the external database object it should reference. It does not create a second synonym with the same name.

For example:

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

This maps the local synonym `CUSTOMERS_GV` to `NAR_QA.CUSTOMERS_GV`.

### Q4. Can I put the target configuration directly in `.hdbsynonym`?

Yes. For a fixed target, the two files can be consolidated.

`db/src/CUSTOMERS_GV.hdbsynonym`

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

This defines the synonym and its target in one file.

However, keeping the target in `.hdbsynonymconfig` is useful when deployment environments need different target schemas or when target properties are resolved from bound services.

### Q5. Why keep the files separate if consolidation is possible?

Separation supports environment-specific configuration.

For example, the synonym definition can remain unchanged while the configuration varies:

| Environment | Target |
| --- | --- |
| QA | `NAR_QA.CUSTOMERS_GV` |
| Production | `NAR_PROD.CUSTOMERS_GV` |

The production schema here is illustrative; use the actual schema configured in that environment.

---

## 2\. Names and File Relationships

### Q6. Which names must match?

The important distinction is between names that identify the same synonym and names that identify different resources.

| Relationship | Requirement |
| --- | --- |
| `.hdbsynonym` JSON key and corresponding `.hdbsynonymconfig` JSON key | Must identify the same synonym. |
| Local synonym name and external object name | May differ. |
| Synonym name and UPS name | Do not need to match. |
| Top-level `.hdbgrants` key and grantor service | Must resolve to the intended bound service, subject to service replacements. |
| Filename and UPS name | No inherent requirement to match. |

For example, the following names can all be different:

- Local synonym: `CUSTOMERS_GV`
- External schema: `NAR_QA`
- External object: `CUSTOMERS_GV`
- Grantor service: `synonym-grantor-service`

The configuration connects these separate names.

### Q7. How does a synonym find its configuration file?

The deployer discovers and processes supported design-time artifacts and configuration files. The configuration entry identifies the synonym through its JSON key.

For example:

`db/src/customer-synonyms.hdbsynonym`

```
{
  "CUSTOMERS_GV": {},
  "ORDERS_GV": {}
}
```

`db/cfg/external-targets.hdbsynonymconfig`

```
{
  "CUSTOMERS_GV": {
    "target": {
      "object": "CUSTOMERS_GV",
      "schema": "NAR_QA"
    }
  },
  "ORDERS_GV": {
    "target": {
      "object": "ORDERS_GV",
      "schema": "NAR_QA"
    }
  }
}
```

The filenames do not need to match each other. The JSON keys establish the logical association.

### Q8. Can I define hundreds of synonyms in one file?

Yes. Multiple synonym definitions can be stored in one `.hdbsynonym` file, with corresponding configurations grouped in one or more `.hdbsynonymconfig` files.

The number of files is primarily an organizational choice.

Common approaches include:

- One large pair of files.
- Separate files for individual synonyms.
- Groups organized by source system, schema, or business domain.

Choose the structure that makes the project easiest to maintain.

### Q9. What happens if multiple configuration files define the same synonym?

Avoid duplicate or conflicting definitions. Do not rely on file order or filenames to determine which target wins.

For example, two configurations that map `CUSTOMERS_GV` to different schemas create an ambiguous deployment design.

Use one authoritative configuration for each synonym in a deployment, and verify the exact behavior against the HDI version if duplicates already exist.

### Q10. Does the configuration filename have to match the synonym name?

No inherent filename-to-synonym naming relationship should be assumed. For example, a file named `external-targets.hdbsynonymconfig` can contain several synonym entries.

Use clear filenames for maintainability, and ensure the JSON entries are correct.

---

## 3\. The `src` and `cfg` Directories

### Q11. Why are `db/src` and `db/cfg` separate?

They serve different roles in the standard HDI deployment structure.

| Directory | Typical contents |
| --- | --- |
| `db/src/` | Design-time database artifacts, such as synonym definitions, tables, and views. |
| `db/cfg/` | Deployment configuration files, including synonym configurations and grant files. |

The deployer follows defined discovery and processing rules; it does not simply search arbitrary project folders for anything that looks relevant.

SAP documents recursive scanning of `cfg/` for files with a `.*config` suffix when applying the configuration-template mechanism. This includes files such as `.hdbsynonymconfig` and `.hdbvirtualtableconfig`.

Reference: [Templates for HDI Configuration Files](<https://help.sap.com/docs/SAP_HANA_PLATFORM/3823b0f33420468ba5f1cf7f59bd6bd9/7ef53fb04ecc49a3ae647c21a0736994.html>).

### Q12. Can `.hdbsynonymconfig` be placed in `db/src`?

SAP examples demonstrate that synonym configurations can be represented as design-time artifacts, while `db/cfg` is the conventional location for deployment-specific configuration and template processing.

For a project that uses environment-specific configuration, keep the `.hdbsynonymconfig` in `db/cfg` unless you have a specific, verified reason to use a different arrangement.

### Q13. Are `src` and `cfg` hardcoded into the deployer?

They are prescribed directory conventions in the standard HDI deployment workflow, not arbitrary names chosen for each artifact.

The exact behavior depends on the deployer and its configuration mechanisms. Follow the standard project layout rather than renaming these directories without verifying support.

### Q14. Does a file in `cfg` become a database object?

Not merely because it exists in `cfg`.

A `.hdbsynonymconfig` supplies deployment configuration for a synonym. The runtime database object is the deployed synonym, not a second catalog object representing the JSON configuration.

Some configuration processing creates transient files during deployment. Do not confuse those intermediate files with persistent database objects.

### Q15. What does `.hdiconfig` do?

`.hdiconfig` maps artifact file suffixes to HDI build plug-ins.

For example, the relevant mappings include:

```
{
  "file_suffixes": {
    "hdbsynonym": {
      "plugin_name": "com.sap.hana.di.synonym"
    },
    "hdbsynonymconfig": {
      "plugin_name": "com.sap.hana.di.synonym.config"
    }
  }
}
```

Use the complete, appropriate configuration for your HDI environment; this snippet illustrates only the relevant entries.

Reference: [HDI Artifact Types and Build Plug-ins](<https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-database-deployment-infrastructure-hdi-reference/sap-hdi-artifact-types-and-build-plug-ins-reference>).

---

## 4\. User Provided Services and Service Bindings

### Q16. What is a UPS in this workflow?

A User Provided Service supplies connection details and credentials for an externally managed resource.

In this context, the important question is what role the service plays. A service can provide credentials used by the deployer to issue grants, or its properties can be used to resolve a synonym's target configuration.

These roles are related but distinct.

### Q17. Why is `synonym-grantor-service` in `.hdbgrants` but not in my `.hdbsynonymconfig`?

Your current synonym configuration contains a literal schema:

```
"schema": "NAR_QA"
```

It does not need a service reference to determine that schema.

Your grants file, however, starts with:

```
{
  "synonym-grantor-service": {
    ...
  }
}
```

That key identifies the service used as the grantor.

The service is involved in granting privileges, even though your synonym configuration does not use it to determine the target schema.

### Q18. Can a synonym configuration obtain its schema from a service?

Yes. HDI supports service-based configuration using properties such as `schema.configure`.

For example:

```
{
  "CUSTOMERS_GV": {
    "target": {
      "object": "CUSTOMERS_GV",
      "schema.configure": "logical-external-service/schema"
    }
  }
}
```

At deployment time, the configuration mechanism resolves the schema property from the referenced bound service.

This is useful when the actual schema name is determined by the environment rather than hardcoded in the source.

Reference: [Templates for HDI Configuration Files](<https://help.sap.com/docs/SAP_HANA_PLATFORM/3823b0f33420468ba5f1cf7f59bd6bd9/7ef53fb04ecc49a3ae647c21a0736994.html>).

### Q19. Does the logical service name have to equal the actual service name?

Not necessarily. Service replacements can map an actual bound service name to a logical name used in configuration files.

The name in the configuration must resolve to the intended service through the configured binding and replacement mechanism.

---

## 5\. Understanding `.hdbgrants`

### Q20. What does `.hdbgrants` do?

It instructs the HDI deployer to grant specified database privileges to designated recipients using a configured grantor service.

It does not define the synonym's target.

### Q21. What does the first JSON key mean?

In this file:

```
{
  "synonym-grantor-service": {
    "application_user": {},
    "object_owner": {}
  }
}
```

The first key identifies the grantor service.

HDI resolves the service, connects using its credentials, and attempts to grant the specified privileges.

### Q22. What do `object_owner` and `application_user` mean?

They identify different privilege recipients.

- `object_owner`: the HDI container's object-owner user.
- `application_user`: the application user or users associated with the application module's service binding.

The object owner may need privileges with grant option to support dependent objects deployed within the container. The application user needs the privileges required for runtime access.

Reference: [Permissions for Objects in HDI Containers](<https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-database-developer-guide-for-cloud-foundry-multitarget-applications-sap-business-app-studio/permissions-for-objects-in-hdi-containers>).

### Q23. What does `privileges_with_grant_option` mean?

It requests a privilege that the recipient can grant onward, subject to HANA's authorization rules.

For example, `SELECT` with grant option gives the recipient permission to read the object and authority to grant `SELECT` to another user.

It does **not** give the grantor additional authority. The grantor must already be authorized to issue the grant.

### Q24. What happens when the grantor lacks sufficient authority?

HANA rejects the grant operation, and deployment reports an authorization or grant-related error.

For an ordinary object-level `SELECT` grant, the grantor generally needs to own the object or have `SELECT` with grant option, subject to the applicable HANA privilege rules.

For example, a grantor who can query `NAR_QA.CUSTOMERS_GV` but lacks grant option may be able to read the object but unable to grant that access to an HDI user.

### Q25. Does the `.hdbgrants` filename have to match the service name?

The filename is not the primary linkage. The top-level JSON key identifies the grantor service.

Using the service name as the filename is a useful convention, but the contents and service binding determine the actual relationship.

### Q26. Does `.hdbgrants` become a database object?

No. It is a deployment instruction processed by the HDI deployer, not a synonym or other ordinary catalog object.

### Q27. If I remove a privilege from `.hdbgrants`, is it automatically revoked?

Do not assume so. Removing a grant request is not equivalent to explicitly revoking an already granted privilege. HDI supports `.hdbrevokes` for revocation workflows.

---

## 6\. Deployment and Environment Promotion

### Q28. What happens during deployment?

At a high level:

1. The deployer discovers the design-time artifacts and configuration.
2. The synonym definition and its target configuration are processed.
3. The synonym is deployed into the HDI container.
4. The grant configuration is processed using the bound grantor service.
5. HANA validates the requested grant operations.
6. The deployed objects and their permissions are validated through testing.

The exact execution sequence can vary by artifact dependencies and deployment behavior.

### Q29. How should the project be promoted from QA to production?

Keep the synonym definition stable where possible. Supply the correct target configuration, service bindings, and grants for each environment.

For example:

| Setting | QA | Production |
| --- | --- | --- |
| Local synonym | `CUSTOMERS_GV` | `CUSTOMERS_GV` |
| Target schema | `NAR_QA` | Production schema |
| Target object | `CUSTOMERS_GV` | `CUSTOMERS_GV` |
| Grantor service | QA service binding | Production service binding |
| Privileges | Required QA permissions | Required production permissions |

The production schema is illustrative. Replace it with the actual production schema.

### Q30. Can the same synonym configuration work in every environment?

Yes, if the target is resolved through an appropriate environment-specific service or if the external object uses the same schema and name in every environment.

If the target is hardcoded as `"schema": "NAR_QA"`, it remains a reference to `NAR_QA` unless the deployed configuration is changed or overridden.

### Q31. Do I need to change `.hdbgrants` when promoting to production?

Possibly. Verify that the production grantor service exists, resolves correctly, and has sufficient authority. Also verify the target object, recipient users, and required privileges.

A working QA grants file does not guarantee that the corresponding production grants will succeed.

---

## 7\. Troubleshooting

### Q32. The synonym deploys, but a query fails with an authorization error. What should I check?

Check these items in order:

1. Does the external object exist?
2. Does the synonym target the intended schema and object?
3. Does the grantor service resolve correctly?
4. Did the required grants succeed?
5. Does the actual application technical user have the necessary access?
6. Does the external object require additional privileges beyond `SELECT`?

A synonym can exist even when a user cannot successfully query its target.

### Q33. The deployer cannot find the synonym configuration. What should I check?

- Confirm the file extension is exactly `.hdbsynonymconfig`.
- Confirm the file is in the intended location, typically `db/cfg` for deployment-specific configuration.
- Verify the relevant plug-in mapping in `.hdiconfig`.
- Check that the JSON is valid.
- Verify that the configuration key identifies the intended synonym.
- Review the deployer logs for discovery, parsing, or deployment errors.

### Q34. The grant operation fails. What should I check?

- Is the top-level grantor key correct?
- Does the corresponding bound service exist?
- Are service replacements configured correctly?
- Are the credentials valid?
- Does the external object exist?
- Does the grantor have sufficient authority?
- Are the requested object type and privilege combinations valid?
- Are the intended recipient users available in the deployment setup?

### Q35. Can I create a synonym with the same name as a system object?

Avoid doing so without checking SAP's guidance. SAP specifically warns against creating local synonyms that conflict with existing system tables that already have public synonyms, because this can cause locks and affect deployments or other database operations.

---

## 8\. Recommended Workflow for This Project

For the `CUSTOMERS_GV` synonym, use the following checklist.

- [ ]Confirm that `NAR_QA.CUSTOMERS_GV` exists.
- [ ]Define the local synonym in `db/src/CUSTOMERS_GV.hdbsynonym`.
- [ ]Configure the target in `db/cfg/CUSTOMERS_GV.hdbsynonymconfig`.
- [ ]Ensure the synonym and configuration keys correspond.
- [ ]Verify the `synonym-grantor-service` binding.
- [ ]Review the existing `.hdbgrants` file rather than replacing it with a generic template.
- [ ]Confirm that the grantor can grant the requested privileges.
- [ ]Deploy the HDI module.
- [ ]Test `SELECT * FROM CUSTOMERS_GV` using the application's actual technical user.
- [ ]Prepare the appropriate target configuration and grantor service for production.

## 9\. Final Mental Model

Keep the following responsibilities separate:

| Question | Relevant component |
| --- | --- |
| What local name should the application use? | `.hdbsynonym` |
| Which external object does it reference? | `.hdbsynonymconfig` or embedded target configuration |
| Where do service-supplied schema or connection properties come from? | Bound service and configuration mechanism |
| Which service executes the grants? | Top-level key in `.hdbgrants` |
| Who receives the privileges? | `object_owner` and `application_user` |
| Who enforces authorization? | HANA |

**The short version:** define the synonym, configure its target, arrange the required grants, bind the correct services, deploy, and validate access.

You do not need to understand every HDI feature to maintain this pattern. Learn the responsibilities of these components, keep the configuration consistent, and investigate additional mechanisms only when your deployment requires them.