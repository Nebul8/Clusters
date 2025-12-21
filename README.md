# Clusters

A GitOps-managed infrastructure repository that defines Kubernetes cluster configurations and deployments for UDL's global game server infrastructure.

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Overview

The Clusters repository serves as the central source of truth for deploying and managing UDL's game server infrastructure across multiple geographic regions. It leverages GitOps principles with Flux CD for automated deployment and configuration management of Kubernetes clusters.

This repository contains cluster-specific configurations, Helm releases, and namespace definitions that orchestrate the deployment of game server controllers (update-controller, restart-controller) and related services. By maintaining infrastructure as code, it enables version-controlled, reproducible deployments across all UDL clusters while ensuring consistency and reliability.

The repository follows a structured hierarchy based on geographic regions and cluster identifiers, making it easy to scale infrastructure globally while maintaining clear separation of concerns between different environments and regions.

### Key Responsibilities

- **Cluster Configuration**: Define and manage Kubernetes cluster configurations across multiple geographic regions using standardized naming conventions
- **GitOps Deployment**: Automate deployment of controllers and services through Flux CD-managed Helm releases
- **Namespace Management**: Organize and isolate services within appropriate Kubernetes namespaces
- **Infrastructure as Code**: Maintain all infrastructure definitions in version-controlled YAML manifests for auditability and reproducibility

## Architecture

```mermaid
graph TB
    subgraph "Git Repository"
        Repo[Clusters Repository]
        Repo --> Cluster1[cluster/eu-de-01]
    end
    
    subgraph "Cluster: eu-de-01.udl.tf"
        FluxCD[Flux CD]
        
        subgraph "Helm Releases"
            UC_Helm[update-controller-helm.yaml]
            RC_Helm[restart-controller-helm.yaml]
        end
        
        subgraph "Namespace: udl"
            NS[namespace.yaml]
            UC[Update Controller]
            RC[Restart Controller]
            Servers[Game Servers]
        end
    end
    
    Repo -->|Monitors| FluxCD
    FluxCD -->|Deploys| UC_Helm
    FluxCD -->|Deploys| RC_Helm
    UC_Helm -->|Creates| UC
    RC_Helm -->|Creates| RC
    NS -->|Defines| Servers
    UC -->|Manages Updates| Servers
    RC -->|Manages Restarts| Servers
    
    style Repo fill:#1a4d6d
    style FluxCD fill:#6d1a1a
    style NS fill:#1a6d1a
```

## How It Works

### GitOps Deployment Flow

```mermaid
sequenceDiagram
    autonumber
    participant Dev as Developer
    participant Git as Git Repository
    participant Flux as Flux CD
    participant K8s as Kubernetes Cluster
    participant Helm as Helm Controller
    participant App as Applications
    
    Dev->>Git: Push configuration changes
    Git->>Git: Commit to main branch
    Flux->>Git: Poll for changes (interval)
    Git-->>Flux: New commit detected
    Flux->>Flux: Reconcile HelmRelease
    Flux->>Helm: Apply HelmRelease spec
    Helm->>K8s: Deploy/Update resources
    K8s->>App: Create/Update pods
    App-->>K8s: Report status
    K8s-->>Flux: Reconciliation complete
    Flux->>Git: Update status (if configured)
```

### Cluster Lifecycle State Machine

```mermaid
stateDiagram-v2
    [*] --> Defined: Create cluster config
    Defined --> Deploying: Flux detects changes
    Deploying --> Reconciling: Apply manifests
    Reconciling --> Healthy: All resources ready
    Reconciling --> Degraded: Some resources fail
    Healthy --> Reconciling: Configuration change
    Healthy --> Updating: Update detected
    Degraded --> Reconciling: Auto-retry
    Degraded --> Failed: Max retries exceeded
    Updating --> Reconciling: Apply updates
    Failed --> Reconciling: Manual intervention
    Healthy --> [*]: Cluster decommissioned
```

## Features

- **Geographic Distribution**: Support for multi-region deployments using ISO 3166-1 Alpha-2 country codes for consistent global infrastructure
- **Flux CD Integration**: Automated GitOps-based deployments with HelmRelease CRDs for declarative infrastructure management
- **Standardized Naming**: Hierarchical naming convention `[region]-[country_code]-[cluster_id].udl.tf` for clear cluster identification
- **Controller Orchestration**: Centralized deployment of update-controller and restart-controller for game server lifecycle management
- **Namespace Isolation**: Logical separation of services within dedicated namespaces (e.g., `udl` namespace)
- **Helm Values Customization**: Per-cluster Helm value overrides for environment-specific configurations
- **Version Control**: Full audit trail of infrastructure changes through Git history
- **Declarative Configuration**: All infrastructure defined in YAML manifests for reproducibility and consistency
- **Scalable Structure**: Easy addition of new clusters and regions following established patterns
- **Kebab-case Convention**: Consistent folder and file naming using kebab-case for service definitions

## Prerequisites

- Kubernetes cluster (v1.25+) with appropriate RBAC permissions
- Flux CD v2 installed and configured on target clusters
- Access to UDL's OCI registry for Helm charts
- Git access to the Clusters repository
- `kubectl` CLI tool for manual operations (optional)

## Installation

### Setting Up a New Cluster

1. **Create cluster directory structure**:
   ```bash
   mkdir -p cluster/[region]-[country_code]-[cluster_id]/{helm,udl}
   ```

2. **Define the namespace**:
   ```bash
   cat > cluster/[region]-[country_code]-[cluster_id]/udl/namespace.yaml <<EOF
   apiVersion: v1
   kind: Namespace
   metadata:
     name: udl
   EOF
   ```

3. **Add Helm releases**:
   - Create Helm repository definitions in `helm/` directory
   - Create service-specific Helm value overrides in `udl/[service-name]/helm-values.yaml`

4. **Bootstrap Flux CD** (on the cluster):
   ```bash
   flux bootstrap github \
     --owner=UDL-TF \
     --repository=Clusters \
     --branch=main \
     --path=cluster/[region]-[country_code]-[cluster_id]
   ```

5. **Commit and push**:
   ```bash
   git add cluster/[region]-[country_code]-[cluster_id]
   git commit -m "Add [region]-[country_code]-[cluster_id] cluster"
   git push origin main
   ```

Flux CD will automatically detect the changes and deploy the defined resources to the cluster.

## Configuration

### Cluster Naming Convention

**Top-level cluster DNS**:
```
[region]-[country_code]-[cluster_id].udl.tf
```

**Node-level DNS** (for reference):
```
n[node_id].[region]-[country_code]-[cluster_id].udl.tf
```

Where:
- `region`: Geographic region (e.g., `eu`, `us`, `ap`)
- `country_code`: [ISO 3166-1 Alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1) country code (e.g., `de`, `us`, `jp`)
- `cluster_id`: Two-digit cluster identifier (e.g., `01`, `02`)
- `node_id`: Node number within the cluster

**Example**: `eu-de-01.udl.tf` (Europe, Germany, Cluster 01)

### Directory Structure Conventions

- **Folders**: Use `kebab-case` - each folder defines a service
- **Files**: Follow hierarchical structure with number ordering when needed
- **Services**: Each service gets its own directory under the cluster's namespace directory

## Development

### Project Structure

```
Clusters/
├── cluster/                       # Cluster configurations
│   └── eu-de-01/                 # Example cluster (Europe, Germany, #01)
│       ├── helm/                 # Helm repository definitions
│       │   ├── restart-controller-helm.yaml
│       │   └── update-controller-helm.yaml
│       └── udl/                  # UDL namespace resources
│           ├── namespace.yaml    # Namespace definition
│           ├── restart-controller/
│           │   └── helm-values.yaml
│           └── update-controller/
│               └── helm-values.yaml
├── LICENSE                        # MIT License
└── README.md                      # This file
```

### Adding a New Service

1. Create a new directory under `cluster/[cluster-name]/udl/[service-name]/`
2. Add `helm-values.yaml` with service-specific configuration
3. Create corresponding Helm repository reference in `cluster/[cluster-name]/helm/`
4. Commit and push - Flux will handle deployment

### Adding a New Cluster

1. Follow the directory structure pattern from existing clusters
2. Use proper naming convention: `[region]-[country_code]-[cluster_id]`
3. Copy and adapt configurations from existing clusters
4. Bootstrap Flux CD on the new cluster pointing to the new path

## License

See [LICENSE](LICENSE) file for details.

## Dependencies

- [Flux CD v2](https://fluxcd.io/) - GitOps toolkit for Kubernetes
- [Helm](https://helm.sh/) - Kubernetes package manager
- [update-controller](https://github.com/UDL-TF) - Controller for managing game server updates
- [restart-controller](https://github.com/UDL-TF) - Controller for managing game server restarts