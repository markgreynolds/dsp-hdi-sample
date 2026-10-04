 # HDI Artifact Promotion and Environment-Specific Credentials

 ## A Solution Discussion for HDI-Only Projects

 ### Abstract

 SAP HANA HDI projects frequently combine database artifacts, external-schema synonyms, grants, and environment-specific credentials. The resulting deployment model can be confusing because several mechanisms—HDI deployer configuration, Cloud Foundry User-Provided Services (UPS), `default-services.json`, service bindings, and MTA descriptors—can participate in deployment, but they serve different purposes.

 This paper describes a deployment architecture for an **HDI-only project**, particularly one in which end users access the resulting database through SQL-based tools rather than through a Cloud Foundry application.

 The central design principle is:

 > **Promote the HDI artifacts unchanged across environments while allowing each environment to supply its own credentials and external-system endpoints.**

 This separates application/database content from environment infrastructure and credentials.

---

 # 1\. Problem Statement

 Consider an HDI project containing:

 - tables, views, procedures, and other database artifacts;
- synonyms pointing to objects outside the HDI container;
- `.hdbsynonymconfig` files describing how those synonyms resolve;
- `.hdbgrants` files defining the privileges required to access external objects;
- a grantor database user whose credentials must be available during deployment.

 The project may ultimately be promoted through:

```
Development → Test → Production
```

 The desirable lifecycle properties are:

 1. The same database artifacts should be promoted between environments.
2. Credentials must not be committed to Git.
3. Development, Test, and Production must be able to use different external HANA systems.
4. Developers should not have to modify the project for each environment.
5. CI/CD should not need to contain application-specific credential logic if the environment is already configured appropriately.
6. Environment-specific infrastructure should be established separately from the application artifact.
7. Credential rotation should not require changing the database artifacts.

 The challenge is determining how the credentials required by `.hdbgrants` reach the HDI deployer.

---

 # 2\. HDI Artifact Configuration Versus Deployment Infrastructure

 An important distinction is that HDI artifacts do not inherently depend on MTA.

 For example:

```
db/
├── package.json
├── src/
│   ├── .hdiconfig
│   ├── tables/
│   ├── views/
│   └── ...
└── cfg/
    ├── .hdiconfig
    ├── *.hdbgrants
    └── *.hdbsynonymconfig
```

 The `.hdb*` artifacts are interpreted by the HDI deployment infrastructure.

 An `mta.yaml`, by contrast, is deployment orchestration metadata. It can describe:

 - services to create;
- service dependencies;
- service bindings;
- CF application modules;
- content deployers;
- sequencing and deployment relationships.

 Therefore:

 > `mta.yaml` is not an HDI artifact configuration file.

 In an HDI-only project that is deployed directly through BAS tooling or `@sap/hdi-deploy`, an MTA descriptor may be unnecessary unless the project is deliberately using MTA/Cloud Foundry deployment orchestration.

---

 # 3\. The `cfg` Directory and `.hdiconfig`

 A common project layout is:

```
db/
├── src/
│   └── .hdiconfig
└── cfg/
    ├── .hdiconfig
    ├── SALES.hdbgrants
    └── SALES.hdbsynonymconfig
```

 Here `src` and `cfg` are siblings.

 This matters because HDI deploy configuration is resolved relative to the deployment source roots. If both directories are configured as separate deployment roots, a `.hdiconfig` in `src` does not automatically serve as the configuration for `cfg`.

 Consequently, the separate configuration files can be intentional:

```
db/
├── src/
│   └── .hdiconfig
│
└── cfg/
    └── .hdiconfig
```

 The exact deployment behavior should be confirmed against the project's `package.json` and the version of `@sap/hdi-deploy` being used.

---

 # 4\. External Schemas and the Three-Part Relationship

 External-schema access introduces three important pieces of configuration.

 For example:

```
external-sales-grantor
```

 might be the logical service name.

 That name can participate in a chain such as:

```
.hdbgrants
       │
       │ grantor/service name
       ▼
external-sales-grantor
       ▲
       │
.hdbsynonymconfig
       │
       │ service
       ▼
external-sales-grantor
       │
       ▼
environment-provided credentials
       │
       ▼
external HANA database
```

 The important point is that the project does **not** need to encode the actual Production password in `.hdbgrants`.

 The project expresses a dependency on a logical service.

 The deployment environment supplies the actual credentials associated with that service.

---

 # 5\. What `.hdbgrants` Describes

 A simplified example might look like:

```
{
  "external-sales-grantor": {
    "object_owner": {
      "object_privileges": [
        {
          "name": "SALES_DATA.V_SALES_SUMMARY",
          "type": "VIEW",
          "privileges": [
            "SELECT"
          ]
        }
      ]
    }
  }
}
```

 The significant value is:

```
external-sales-grantor
```

 This identifies the grantor/service dependency.

 The `.hdbgrants` file describes **what privileges must be granted**.

 It does not need to contain:

 - the external database password;
- the Production database host;
- a developer's password;
- a Test-specific username.

 Those belong to the deployment environment.

---

 # 6\. What `.hdbsynonymconfig` Describes

 A corresponding synonym configuration might identify the same logical service:

```
{
  "SYNONYM_FOR_SALES": {
    "target": {
      "object": "V_SALES_SUMMARY"
    },
    "schema": {
      "schema": "SALES_DATA"
    },
    "service": "external-sales-grantor"
  }
}
```

 The service name is therefore a logical identifier:

```
external-sales-grantor
```

 It does not inherently mean:

```
DEV database
TEST database
PROD database
```

 Instead, each environment can provide a service with that logical name.

---

 # 7\. What a User-Provided Service Does

 A Cloud Foundry User-Provided Service is fundamentally a way of making externally supplied connection credentials available through the Cloud Foundry service model.

 For example, an environment might contain:

```
external-sales-grantor
```

 with credentials such as:

```
host     = external-hana.example.com
port     = 443
user     = SALES_GRANTOR
password = ********
```

 The important conceptual distinction is:

 > A UPS is not the database object being accessed.

 It is a **credential/service representation** that allows a deployment process or application to obtain the information needed to connect to that external system.

 In a CF-based deployment, a service binding can make those credentials available to the consuming process through the Cloud Foundry environment.

---

 # 8\. Service Injection

 The phrase "service injection" is useful because the application or deployer does not necessarily have to contain the credentials itself.

 Conceptually:

```
             CF Service
                 │
                 │ binding
                 ▼
          Deployment process
                 │
                 │ credentials
                 ▼
           HDI deployer
                 │
                 ▼
        External HANA database
```

 The deployment artifact says:

```
"I require external-sales-grantor."
```

 The environment says:

```
"Here is external-sales-grantor for this environment."
```

 This is the foundation of environment-neutral artifact promotion.

---

 # 9\. The Earlier MTA/CF Deployer Model

 In an MTA-based deployment, the HDI deployer can be represented as a CF application/content deployer.

 Conceptually:

```
mta.yaml
   │
   ├── HDI container service
   │
   ├── external UPS
   │
   └── content deployer
             │
             ▼
       @sap/hdi-deploy
```

 The MTA deployment machinery can:

 1. create or locate services;
2. establish bindings;
3. start the deployment process;
4. make service credentials available;
5. run the HDI deployment.

 This is why a CF/MTA deployment often makes service injection appear automatic.

---

 # 10\. Why That Model Does Not Automatically Apply to an HDI-Only Project

 An HDI-only project may have:

 - no application runtime;
- no `cf push`;
- no long-running CF application;
- users accessing the database through Database Explorer, DBeaver, HANA Studio, or other SQL clients;
- direct invocation of the HDI deployer through BAS tooling or another deployment mechanism.

 In that architecture, there may be no CF application whose binding can be used to inject the UPS.

 Therefore, statements such as:

 > "The deployer gets the UPS through its application binding"

 must be understood as referring specifically to the CF/MTA deployment model.

 They should not automatically be applied to direct HDI deployment.

---

 # 11\. `default-services.json`

 One alternative discussed for direct/local HDI deployment is:

```
db/
├── default-services.json
├── package.json
├── src/
└── cfg/
```

 The file can represent the service credentials needed by the deployment process.

 A conceptual example is:

```
{
  "external-sales-grantor": {
    "host": "your-hana-host.example.com",
    "port": "443",
    "user": "SALES_GRANTOR_USER",
    "password": "secret",
    "encrypt": true,
    "sslValidateCertificate": true
  }
}
```

 The critical relationship is:

```
default-services.json
        │
        │ key
        ▼
external-sales-grantor
        ▲
        │
        ├── .hdbgrants
        │
        └── .hdbsynonymconfig
```

 The file therefore provides the concrete implementation of the logical service name.

---

 # 12\. The Problem With `default-services.json`

 The drawback is not that the file is inherently wrong.

 The drawback is lifecycle management.

 A persistent file creates questions such as:

 - Who creates it?
- Who maintains it?
- Where does the Production password come from?
- How does Test receive its version?
- Is it accidentally committed?
- How is it replaced when credentials rotate?
- How does CI/CD obtain it?
- Does every developer need one?

 At minimum, it should not be committed to Git if it contains plaintext credentials:

```
db/default-services.json
```

 This produces a clean Git repository, but the deployment still needs a way to create or supply the file.

---

 # 13\. Persistent Versus Ephemeral Credential Supply

 The important realization is that:

 > **The deployer needs credentials at deployment time; it does not necessarily follow that a credential file must permanently exist.**

 There are several possible models.

 ## 13.1 Persistent UPS

```
BTP environment
└── external-sales-grantor
        │
        └── credentials
```

 The service is pre-created and maintained as environment infrastructure.

 ## 13.2 Persistent `default-services.json`

```
db/
└── default-services.json
```

 The file exists on the machine performing the deployment.

 ## 13.3 Ephemeral Generated File

 A deployment process can conceptually:

```
Secret store
     │
     ▼
deployment script
     │
     ├── create temporary default-services.json
     │
     ├── execute deployment
     │
     └── delete file
```

 This avoids Git exposure and can minimize the lifetime of the credential-bearing file.

 ## 13.4 Native Ephemeral Injection

 A deployment system may instead obtain secrets dynamically and expose them directly to the deployment process.

 The exact mechanism depends on the deployment technology and what `@sap/hdi-deploy` recognizes as its service/credential input.

 One should not assume that arbitrary environment variables such as:

```
GRANTOR_PASSWORD=...
```

 are automatically equivalent to a named HDI service.

 The service-resolution mechanism must still be satisfied.

---

 # 14\. Credential Sources

 A secure deployment environment can obtain credentials from a variety of systems, including:

 - CI/CD secret stores;
- SAP credential-management services;
- Cloud Foundry service bindings;
- HashiCorp Vault;
- Azure Key Vault;
- AWS Secrets Manager;
- Google Secret Manager;
- enterprise secrets-management systems such as CyberArk;
- other organization-approved secret stores.

 The important architecture is:

```
Secure secret store
        │
        ▼
Deployment environment
        │
        ▼
HDI deployer
```

 rather than:

```
Git repository
        │
        ▼
plaintext password
```

---

 # 15\. Development, Test, and Production

 For an artifact-promotion lifecycle, the strongest conceptual separation is:

```
                  SAME ARTIFACT
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
         DEV          TEST         PROD
          │            │            │
       Dev UPS      Test UPS      Prod UPS
          │            │            │
       Dev HANA     Test HANA     Prod HANA
```

 The Git-controlled artifacts remain unchanged.

 For example, all three environments can use:

```
external-sales-grantor
```

 while the actual credentials differ.

 Development:

```
external-sales-grantor
    → DEV grantor credentials
    → DEV external HANA
```

 Test:

```
external-sales-grantor
    → TEST grantor credentials
    → TEST external HANA
```

 Production:

```
external-sales-grantor
    → PROD grantor credentials
    → PROD external HANA
```

 This is the fundamental benefit of environment-specific service configuration.

---

 # 16\. Why a Pre-Existing UPS Is Attractive

 For an organization already using Cloud Foundry/BTP service infrastructure, a pre-existing UPS has an appealing property:

 > **The environment knows how to satisfy the application's service dependency before deployment starts.**

 The application artifact does not have to carry credentials.

 The developer does not have to edit a file.

 The CI/CD pipeline does not necessarily need to know the Production password.

 Instead:

```
                  Git
                   │
                   ▼
          HDI deployment artifact
                   │
                   ▼
              environment
                   │
                   ▼
       external-sales-grantor
                   │
                   ▼
        environment credentials
```

 This makes the environment responsible for its own infrastructure.

---

 # 17\. Pre-Created UPS by Environment

 A possible operational model is:

```
Development CF space
└── external-sales-grantor
    └── DEV external HANA credentials

Test CF space
└── external-sales-grantor
    └── TEST external HANA credentials

Production CF space
└── external-sales-grantor
    └── PROD external HANA credentials
```

 The HDI artifact can remain identical.

 The environment supplies the appropriate service instance.

 This also means credential rotation can be performed at the environment level without modifying the HDI artifacts.

---

 # 18\. Git Promotion

 The Git repository contains the deployable database definition:

```
db/
├── package.json
├── src/
│   ├── .hdiconfig
│   ├── tables/
│   ├── views/
│   └── ...
└── cfg/
    ├── .hdiconfig
    ├── SALES.hdbgrants
    └── SALES.hdbsynonymconfig
```

 It should not contain:

```
db/default-services.json
```

 if that file contains credentials.

 A promotion then looks like:

```
Git commit
    │
    ▼
Development
    │
    │ same commit
    ▼
Test
    │
    │ same commit
    ▼
Production
```

 The environment-specific credential configuration is outside the artifact being promoted.

---

 # 19\. Artifact Versus Environment

 This can be summarized as:

 | Concern | Application artifact | Environment |
| --- | --- | --- |
| Tables | Git | — |
| Views | Git | — |
| Procedures | Git | — |
| Synonyms | Git | — |
| Grant definitions | Git | — |
| Service name | Git | — |
| HDI configuration | Git | — |
| External HANA host | — | Environment |
| Grantor username | — | Environment |
| Grantor password | — | Environment |
| Credential rotation | — | Environment |
| Dev/Test/Prod endpoint | — | Environment |

This separation is the core architectural objective.

---

 # 20\. Deployment Choices

 There are several legitimate deployment architectures.

 ## Choice A — MTA/CF Deployment With UPS

```
mta.yaml
   │
   ├── service definitions
   ├── bindings
   └── content deployer
             │
             ▼
       @sap/hdi-deploy
```

 ### Characteristics

 - Strong integration with CF service bindings.
- UPS can be pre-created.
- Environment can provide credentials.
- MTA handles deployment orchestration.
- Appropriate when the organization already uses MTA/CF deployment.

 ### Trade-off

 For a genuinely HDI-only project, this may introduce CF/MTA machinery that the database itself does not require.

---

 # 21\. Choice B — Direct HDI Deployment With `default-services.json`

```
Git artifact
     │
     ▼
default-services.json
     │
     ▼
@sap/hdi-deploy
```

 ### Characteristics

 - Straightforward local/direct deployment model.
- No UPS required.
- Credentials can be supplied locally.
- Useful when direct deployment is the chosen operating model.

 ### Trade-off

 The credentials file must be created and managed outside Git.

---

 # 22\. Choice C — Ephemeral `default-services.json`

```
Secret store
     │
     ▼
deployment script
     │
     ▼
temporary default-services.json
     │
     ▼
@sap/hdi-deploy
     │
     ▼
delete temporary file
```

 ### Characteristics

 - No credentials in Git.
- No long-lived credentials file.
- Can work well with CI/CD.
- Separates secret storage from artifact storage.

 ### Trade-off

 The deployment mechanism must reliably generate the service configuration expected by the HDI deployer.

---

 # 23\. Choice D — Environment-Managed UPS

```
Environment
    │
    └── pre-created UPS
             │
             ▼
       service binding
             │
             ▼
        HDI deployer
```

 ### Characteristics

 - Credentials belong to the environment.
- Artifact remains environment-neutral.
- Developer and pipeline do not need to construct credentials.
- Credential rotation can be managed independently.
- Particularly attractive when CF/BTP infrastructure is already established.

 ### Trade-off

 The deployment mechanism must actually provide the UPS credentials to the HDI deployment process.

---

 # 24\. Recommended Conceptual Model

 For an HDI-only application with established BTP/CF environments, a clean architecture is:

```
                       SOURCE CONTROL
                            │
                            │
                     immutable artifacts
                            │
                            ▼
                 ┌────────────────────┐
                 │      HDI Project    │
                 │                    │
                 │ .hdbgrants         │
                 │ .hdbsynonymconfig  │
                 │ .hdbsynonym        │
                 │ .hdiconfig          │
                 └─────────┬──────────┘
                           │
                promoted unchanged
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
        DEV              TEST             PROD
          │                │                │
     pre-existing     pre-existing     pre-existing
         UPS              UPS              UPS
          │                │                │
       DEV creds        TEST creds       PROD creds
          │                │                │
          ▼                ▼                ▼
      external          external          external
       HANA              HANA              HANA
```

 The logical dependency is stable:

```
external-sales-grantor
```

 The physical implementation changes with the environment.

---

 # 25\. Operational Responsibilities

 This architecture also provides a useful division of responsibility.

 ### Development/application team

 Maintains:

 - `.hdbgrants`;
- `.hdbsynonymconfig`;
- synonyms;
- database artifacts;
- service-name references.

 ### Platform/infrastructure team

 Maintains:

 - UPS instances;
- external connection information;
- grantor credentials;
- credential rotation;
- environment-level access controls.

 ### Deployment system

 Responsible for:

 - obtaining the correct Git revision;
- deploying it into the intended environment;
- ensuring the environment's required services are available.

 This prevents database developers from becoming responsible for Production secrets.

---

 # 26\. Credential Rotation

 A significant benefit of this separation appears when credentials change.

 Suppose Production's grantor password changes.

 With environment-managed credentials:

```
Update Production credential
            │
            ▼
Production UPS
            │
            ▼
next deployment
```

 There is no requirement to modify:

```
.hdbgrants
.hdbsynonymconfig
.hdbsynonym
```

 and no requirement to create a new Git commit merely because a password changed.

 This is one of the strongest reasons to keep credentials outside the artifact.

---

 # 27\. What Must Exist at Deployment Time?

 The fundamental requirement is not:

 > "A `default-services.json` file must exist."

 Nor is it universally:

 > "A UPS must exist."

 The actual requirement is:

 > **The HDI deployment process must have access to the credentials corresponding to the logical grantor service referenced by the HDI artifacts.**

 Those credentials may be supplied through different mechanisms depending on the deployment architecture.

 Conceptually:

```
.hdbgrants
     │
     ▼
logical service name
     │
     ▼
deployment-time service resolution
     │
     ▼
grantor credentials
     │
     ▼
external HANA
```

 The mechanism implementing "deployment-time service resolution" is what varies.

---

 # 28\. The Meaning of "Supply"

 The word "supply" should therefore be interpreted broadly.

 It means:

 > Make the required service credentials available to the HDI deployer at deployment time.

 It does **not** inherently mean:

 - check a credentials file into Git;
- manually copy a file between environments;
- have every developer maintain a password file;
- embed the password in `.hdbgrants`.

 Possible implementations include:

```
UPS
default-services.json
ephemeral generated file
service binding
secure secret store
deployment environment
```

 The correct choice depends on how the HDI deployer is being invoked.

---

 # 29\. A Critical Boundary

 There is an important distinction between the **logical service model** and the **credential transport mechanism**.

 The HDI artifact may require:

```
external-sales-grantor
```

 That does not dictate whether the credentials arrive through:

```
CF binding
default-services.json
another supported local configuration
```

 The deployment infrastructure maps the logical dependency to actual credentials.

 This allows the artifact itself to remain portable.

---

 # 30\. Design Principle: Promote Artifacts, Configure Environments

 The resulting principle can be stated simply:

 > **Promote artifacts; configure environments.**

 Artifacts should describe:

```
WHAT
```

 For example:

```
Create this synonym.
Grant this privilege.
Use the service named external-sales-grantor.
```

 The environment should describe:

```
WHERE and WITH WHAT CREDENTIALS
```

 For example:

```
external-sales-grantor
    → Test HANA
    → Test grantor user
    → Test credentials
```

 This produces a clean boundary between development content and operational infrastructure.

---

 # 31\. Practical Decision Framework

 For an HDI-only project, consider the following questions.

 ### Question 1 — Is the deployment CF/MTA based?

 If yes, a pre-existing UPS and service binding can provide a natural credential-delivery mechanism.

 If no, investigate the direct `@sap/hdi-deploy` credential mechanisms available in the specific tooling/version being used.

 ### Question 2 — Is there already an environment-management team?

 If yes, environment-managed services/credentials can keep application deployment simple.

 ### Question 3 — Does CI/CD need to understand database passwords?

 Ideally no.

 The deployment pipeline should select the environment and invoke the deployment rather than carrying the credentials as application configuration.

 ### Question 4 — Does the artifact change between environments?

 Ideally no.

 The same Git artifact should be deployable to Dev, Test, and Production.

 ### Question 5 — Where are secrets stored?

 They should be maintained in an approved secret-management mechanism rather than in Git.

---

 # 32\. Conclusion

 An HDI project containing external synonyms and grants has two fundamentally different kinds of information.

 The first is **database deployment intent**:

```
.hdbgrants
.hdbsynonymconfig
.hdbsynonym
.hdiconfig
```

 The second is **environment-specific connectivity**:

```
host
port
username
password
credentials
```

 The first belongs with the application artifact and should be promoted through Git.

 The second belongs to the deployment environment.

 A User-Provided Service is one way of representing and supplying the second category. `default-services.json` is another mechanism that can be used in appropriate direct/local deployment scenarios. An ephemeral deployment mechanism can also prevent credentials from becoming persistent project files.

 For an organization with established BTP/Cloud Foundry environments, a particularly clean model is to pre-create the required UPS in each environment using the same logical service name:

```
DEV:
    external-sales-grantor → Dev credentials

TEST:
    external-sales-grantor → Test credentials

PROD:
    external-sales-grantor → Production credentials
```

 The Git artifact then remains identical:

```
external-sales-grantor
```

 while the environment determines what that service actually means.

 The resulting lifecycle is:

```
                  Git
                   │
                   │
             HDI artifacts
                   │
                   ▼
             Development
                   │
             same artifact
                   ▼
                 Test
                   │
             same artifact
                   ▼
               Production

       Environment-specific services
       remain outside the artifact
```

 This provides a clean separation of concerns:

 > **The application artifact declares its dependencies. The environment satisfies them.**

 That is the essential architecture for reliable HDI artifact promotion without embedding environment-specific credentials in the application source.