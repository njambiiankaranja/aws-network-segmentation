# AWS Network Segmentation with Terraform

A custom AWS network built as code, split into public, private and isolated tiers so that each resource is reachable only from where it should be. The design is then tested: a table of real connection attempts shows which ones are allowed, which are blocked, and what the network's own logs recorded.

---

## The Problem It Solves

A common beginner setup puts every server in one public network and relies on a password or a single firewall rule to keep attackers out. If one server is compromised, everything beside it is exposed, and a database that can be reached from the internet is one mistake away from a breach.

Network segmentation fixes this by design. Servers are placed in separate zones, and traffic between zones is allowed only where it is needed. The internet can reach the web tier, the web tier can reach the app tier, and the app tier can reach the database. Nothing else can. A compromised web server still cannot talk to the database, and a database cannot send data out.

This is the kind of design a company expects before it moves a real application to AWS.

---

## What It Builds

```text
                      Internet
                         |
                  Internet Gateway
                         |
 +-----------------------+------------------------------+
 | VPC 10.0.0.0/16                                      |
 |                                                      |
 |  PUBLIC tier   (route to the internet)               |
 |    web server                                        |
 |         |  app port only                             |
 |         v                                            |
 |  PRIVATE APP tier   (no inbound from the internet)   |
 |    app server                                        |
 |         |  database port only                        |
 |         v                                            |
 |  ISOLATED DATA tier   (no route to the internet)     |
 |    database stand-in                                 |
 |                                                      |
 |  S3 gateway endpoint (free)                          |
 |  Session Manager endpoints (shell access, no SSH)    |
 |  VPC Flow Logs to CloudWatch                         |
 |  Optional NAT Gateway (app tier outbound only)       |
 +------------------------------------------------------+
```

Each tier has subnets in two availability zones, so the loss of one zone does not take a tier down. One small test server per tier is deployed so the rules can be tried for real.

| Tier | Subnets | Route to the internet | Who can reach it |
|---|---|---|---|
| Public | `10.0.0.0/24`, `10.0.1.0/24` | Yes, through the internet gateway | The internet, on port 80 |
| Private app | `10.0.10.0/24`, `10.0.11.0/24` | Only if NAT is enabled, outbound only | The web tier, on the app port |
| Isolated data | `10.0.20.0/24`, `10.0.21.0/24` | None | The app tier, on the database port |

---

## How the Isolation Works

Four mechanisms work together. Each one covers a different kind of mistake.

### 1. Route tables decide where traffic can go

A subnet is "public" for one reason only: its route table sends `0.0.0.0/0` to the internet gateway. The app tier route table has no such route unless NAT is enabled, and the data tier route table never has one. Without a route, a packet has nowhere to go, no matter what any firewall says.

### 2. Security groups decide who may talk to whom

Security groups are stateful: if a request is allowed in, the reply is allowed back automatically. They are chained by reference instead of by IP address:

- The web group accepts port 80 from the internet.
- The app group accepts the app port only from the web group.
- The data group accepts the database port only from the app group, and has no outbound rules at all.

Because the groups refer to each other, the rules keep working when servers are replaced and their IP addresses change.

### 3. A network ACL guards the data subnets

A network ACL filters at the edge of a whole subnet and is stateless, so it checks each direction separately and replies must be allowed explicitly. On the data tier it allows only the database port in from the app subnets, and only the replies out. Anything else is denied. A security group and a network ACL do different jobs, and having both means one misconfiguration does not open the vault.

| | Security group | Network ACL |
|---|---|---|
| Applies to | A server | A whole subnet |
| Stateful | Yes | No |
| Rules | Allow only | Allow and deny, in numbered order |
| Refers to other groups | Yes | No, only IP ranges |

### 4. Endpoints give private access to AWS services

A free S3 gateway endpoint lets private and isolated subnets reach S3 through AWS's own network, without an internet gateway or NAT. The route to it exists in the app and data route tables, but a route only says where traffic may go. The data security group has no outbound rules, so the data tier is still refused when it tries to reach S3. To allow it, an outbound rule for the S3 prefix list would be added.

Interface endpoints for Session Manager let the app server, which has no internet, open a shell session without SSH.

---

## Design Decisions

| Choice | Why |
|---|---|
| Three tiers | Separates what faces the internet, what runs the logic, and what holds the data |
| Two availability zones per tier | Survives the loss of a zone |
| Security groups chained by reference | Rules follow the servers, not their IP addresses |
| No outbound rules on the data group | A database never needs to start a connection, so it is not allowed to |
| Network ACL on the data tier only | A second layer where the data lives, without making the rest harder to manage |
| NAT Gateway off by default | It bills every hour. Without it, the app tier has no internet, which is a safe default |
| Session Manager instead of SSH | No inbound port is ever opened for administration |
| No shell on the data server | Nobody needs to log in to the vault. It only answers on its port |
| Flow Logs on the whole VPC | The network's own record of what was accepted and refused |
| Remote Terraform state in S3 | State is not tied to one computer |

---

## Proof: Who Can Reach What

The design was tested against the deployed network. The test servers each run a tiny listener on their tier's port. The web and app tests were run from Session Manager shells in the browser, and each blocked attempt used `curl -m 5`, so a drop shows as a 5 second timeout.

| From | To | Expected | Result |
|---|---|---|---|
| Internet | Web server, port 80 | Allowed | Allowed. Returned the web tier response |
| Internet | Web server, port 8080 | Blocked | Blocked. Timed out after 5 seconds |
| Web tier | App server, app port | Allowed | Allowed. Returned the app tier response |
| Web tier | Database port | Blocked | Blocked. Timed out, and a Flow Log `REJECT` was recorded |
| App tier | Database port | Allowed | Allowed. Returned the data tier response |
| Data tier | Internet | Blocked | Blocked. No `0.0.0.0/0` route, and outbound attempts were rejected in the Flow Logs |

The app and data servers have no public IP address at all, so they cannot be reached from the internet in the first place.

### What the Flow Logs recorded

Each Flow Log record lists: version, account, network interface, source address, destination address, source port, destination port, protocol, packets, bytes, start, end, action and status. Protocol `6` is TCP and `17` is UDP.

**The web server trying the database port:**

```text
2 <account-id> eni-04d5... 10.0.0.200 10.0.20.165 60910 5432 6 3 180 ... REJECT OK
```

The source is the web server, the destination is the data server on port 5432, and the action is `REJECT`. Three packets are `curl` retrying until it gave up. This is the network refusing the connection, and not the connection failing for some unrelated reason.

**The data server trying to leave:** shortly after boot, the data server tried to reach Amazon S3 addresses on port 443, probably to check its package repositories. Those outbound connections show as `REJECT`, because the data group has no outbound rules.

**Strangers on the internet:** within minutes of the web server getting a public IP, records appeared of unknown addresses probing it on unusual ports such as 5060, 8089 and 8094. They were all refused, because only port 80 is open. A public address gets scanned almost immediately, which is the reason to open only what is needed.

---

## NAT Gateway: What It Adds and Costs

By default the app tier cannot reach the internet. Setting `enable_nat = true` creates a NAT Gateway in the public subnet and adds a route from the app tier to it. Private servers can then start outbound connections, for example to download updates, while the internet still cannot start connections to them.

The cost is the reason it is optional: a NAT Gateway is billed for every hour it exists, plus the data it processes. Turn it on to see the difference, then turn it off again.

---

## Project Structure

```text
aws-network-segmentation/
├── .github/workflows/terraform-ci.yml   # Runs fmt and validate on every pull request
├── terraform/
│   ├── providers.tf           # Provider versions and S3 backend
│   ├── variables.tf           # Inputs and defaults
│   ├── network.tf             # VPC, subnets, route tables, optional NAT
│   ├── security.tf            # Chained security groups
│   ├── nacl.tf                # Network ACL for the data tier
│   ├── endpoints.tf           # S3 gateway endpoint
│   ├── compute.tf             # One test server per tier
│   ├── ssm.tf                 # Session Manager role and interface endpoints
│   ├── flowlogs.tf            # VPC Flow Logs to CloudWatch
│   ├── tier_server.sh.tftpl   # Start-up script for the test listeners
│   └── outputs.tf             # IPs, subnet IDs and session commands
├── .gitignore
└── README.md
```

### Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | Region to deploy into |
| `project_name` | `netseg` | Prefix for resource names and the `Project` tag |
| `vpc_cidr` | `10.0.0.0/16` | CIDR block for the whole VPC |
| `public_subnet_cidrs` | two `/24` blocks | Public tier subnets |
| `app_subnet_cidrs` | two `/24` blocks | Private app tier subnets |
| `data_subnet_cidrs` | two `/24` blocks | Isolated data tier subnets |
| `app_port` | `8080` | Port the app tier listens on |
| `db_port` | `5432` | Port the database tier listens on |
| `instance_type` | `t3.micro` | Size of the three test servers |
| `enable_nat` | `false` | Create a NAT Gateway for the app tier |

---

## Deployment

Prerequisites: an AWS account with the AWS CLI configured, Terraform `>= 1.0.0`, and an S3 bucket for remote state (set in `providers.tf`).

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Wait two to three minutes after the apply so the servers can start and register with Session Manager. The outputs show each server's address and the commands to open a session.

### Running the tests

From your own computer, using the `web_public_ip` output:

```bash
curl -m 5 http://<web_public_ip>          # expect the web tier response
curl -m 5 http://<web_public_ip>:8080     # expect a timeout
```

From the AWS console, open EC2, select the web server and choose Connect, then Session Manager:

```bash
curl -m 5 http://<app_private_ip>:8080    # expect the app tier response
curl -m 5 http://<data_private_ip>:5432   # expect a timeout
```

Open a session on the app server and run:

```bash
curl -m 5 http://<data_private_ip>:5432   # expect the data tier response
```

Check the data tier route table has no route to the internet:

```bash
aws ec2 describe-route-tables --filters Name=tag:Name,Values=netseg-data-rt --query 'RouteTables[].Routes'
```

Then search the `/vpc/netseg-flow-logs` log group in CloudWatch for `REJECT`. Flow Logs can take a few minutes to appear.

To see the effect of NAT:

```bash
terraform apply -var="enable_nat=true"
terraform apply -var="enable_nat=false"
```

### Tear down

```bash
terraform destroy
```

---

## Debugging a Connection That Does Not Work

When "it cannot connect", check the layers in order:

1. **Route.** Does the source subnet have a route to the destination?
2. **Network ACL.** Does the subnet allow the traffic in both directions, including the replies?
3. **Security group.** Does the destination's group allow the source's group on that port?
4. **The service.** Is anything actually listening on that port?

Flow Logs speed this up, because a `REJECT` record shows that the network blocked it, and no record at all points to a routing problem.

---

## Things to Know

- **The network is free, the test setup is not.** Subnets, route tables, security groups and the S3 endpoint cost nothing. The three Session Manager interface endpoints, the three servers and the flow log storage bill while they exist, so destroy the stack when the tests are done.
- **No inbound SSH.** Servers are reached through AWS Systems Manager Session Manager, so no port 22 is ever opened.
- **The data server has no shell.** That is deliberate. It has no outbound access and no Session Manager role, so it can only be tested from other tiers.
- **The data tier cannot update itself.** With no outbound access, servers there cannot download patches. Use patched images, or add outbound rules for specific AWS services.
- **The database is a stand-in.** The data server runs a simple listener on the database port. The network only cares about the port, so a real database would behave the same way.
- **One NAT Gateway.** The optional NAT sits in one zone. A production setup would use one per zone so a zone failure does not cut off the app tier.
- **Plain HTTP on the public tier.** This project is about the network layout. HTTPS and certificates are a separate layer.

---

## Ideas for Extending It

- A load balancer in the public tier in front of the app tier
- A real database in the data tier, such as RDS PostgreSQL in a subnet group
- An outbound rule for the S3 prefix list, so the data tier can reach S3 and nothing else
- AWS Network Firewall or rules driven by a variable
- A second environment (staging) using the same code with different CIDR ranges
- Extend the CI pipeline to run `terraform plan` using GitHub Actions OIDC