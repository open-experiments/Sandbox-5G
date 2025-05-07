# 5G Core with Radio Access Network Simulator

This repository provides a complete 5g sandbox with Open5GS-based 5G Core Network + containerized UERANSIM. <br>
It implements Cloud-Native Network Functions (CNFs) with comprehensive monitoring, logging, and tracing capabilities.

![Architecture](https://raw.githubusercontent.com/open-experiments/sandbox-5g/refs/heads/main/images/arch.png)

## Features

- **Fully containerized 5G Core Network Functions** based on Open5GS v2.7.5
- **Simulated RAN environment** with UERANSIM v3.2.6
- **Comprehensive monitoring stack** with Prometheus, Grafana, Jaeger, ELK
- **Service Mesh integration** with OpenShift Service Mesh 3 (Istio Upstream)
- **Optimized HTTP configuration** using HTTP/1.1 for SBI communications
- **Automated deployment scripts** for easy installation and configuration
- **Custom metrics and dashboards** for 5G Core performance monitoring

## Architecture Components

### 5G Core Network Functions

| Component | Description |
|-----------|-------------|
| **AMF** | Access and Mobility Management Function - handles registration and connection management |
| **SMF** | Session Management Function - manages PDU sessions and IP address allocation |
| **UPF** | User Plane Function - handles user data packet forwarding and QoS enforcement |
| **NRF** | Network Repository Function - service registry for 5G service discovery |
| **UDM** | Unified Data Management - subscriber data management |
| **UDR** | Unified Data Repository - subscriber data storage |
| **AUSF** | Authentication Server Function - handles authentication procedures |
| **PCF** | Policy Control Function - manages network policies |
| **NSSF** | Network Slice Selection Function - handles network slice selection |
| **WebUI** | Web interface for subscriber management |
| **MongoDB** | Database for storing subscriber data |

### RAN Simulation (UERANSIM Single POD with 3 Containers)

| Component | Description |
|-----------|-------------|
| **gNB** | Simulated 5G base station |
| **UE** | Simulated 5G user equipment/device |
| **UE Binder** | Helper container for network configuration |

### Monitoring Stack

| Component | Description |
|-----------|-------------|
| **Prometheus** | Metrics collection and storage |
| **Grafana** | Metrics visualization with custom 5G dashboards |
| **Jaeger** | Distributed tracing for 5G service interactions |
| **Elasticsearch** | Log storage and indexing |
| **Kibana** | Log visualization and analysis |
| **Fluent Bit** | Log collection and forwarding |

## Prerequisites

- OpenShift Container Platform 4.18+ (tested on 4.18.9)
- Red Hat build of OpenTelemetry
- OSSM3-v3.0.0
- Cluster administrator access
- SCTP protocol support enabled on worker nodes
- Sufficient cluster resources (at least 3 worker nodes recommended)
- OpenShift CLI (`oc`) installed and configured
- The following additional operators installed:
  - Kiali Operator
  - OpenTelemetry Operator
  - Tempo Operator

## Installation

### 1. Prepare the Cluster

First, clone this repository and run the preparation script to install required operators and configure the service mesh:

```bash
git clone https://github.com/open-experiments/sandbox-5g.git
cd sandbox-5g
./prepstep.sh
```

This script (To Be Run ONLY ONCE!) will:
- Install required operators via subscription
- Enable Gateway API support
- Set up Minio for Tempo tracing
- Install OpenTelemetry Collector
- Configure OpenShift Service Mesh 3
- Set up Kiali for visualization
- Enable SCTP protocol on worker nodes (requires node reboot)

### 2. Deploy the 5G Core

Deploy the Open5GS 5G Core network functions:

```bash
./install-open5gcore.sh
```

This will:
- Create a dedicated namespace for the 5G Core
- Add the namespace to the service mesh
- Deploy all core network functions in the correct order
- Configure network policies for Service-Based Interface (SBI)
- Create a default subscriber profile
- Apply istio gateway configuration

### 3. Deploy Monitoring Stack

Set up the monitoring infrastructure:

```bash
./deploy-monitoring.sh
```

This creates:
- Prometheus instance with ServiceMonitor for 5G Core metrics
- Grafana with pre-configured dashboards for 5G Core monitoring
- Jaeger for distributed tracing
- ELK stack (Elasticsearch, Fluent Bit, Kibana) for log management

### 4. Deploy UERANSIM

Deploy the simulated Radio Access Network components:

```bash
./ran/deploy-ueransim.sh
```

This script automatically:
- Discovers the AMF IP address
- Creates appropriate ConfigMaps
- Deploys gNB and UE components
- Configures the UE Binder for network connectivity

## Accessing the Components

After deployment, you can access the following interfaces:

| Component | Access Method | Default Credentials |
|-----------|---------------|---------------------|
| **5G Core WebUI** | `https://$(oc get route open5gs-webui -n open5gcore -o jsonpath='{.spec.host}')` | admin / 1423 |
| **Grafana** | `https://$(oc get route grafana -n open5gs-monitoring -o jsonpath='{.spec.host}')` | admin / admin |
| **Prometheus** | `https://$(oc get route prometheus -n open5gs-monitoring -o jsonpath='{.spec.host}')` | N/A |
| **Jaeger** | `https://$(oc get route jaeger -n open5gs-monitoring -o jsonpath='{.spec.host}')` | N/A |
| **Kibana** | `https://$(oc get route kibana -n open5gs-monitoring -o jsonpath='{.spec.host}')` | N/A |
| **Kiali** | `https://$(oc get route kiali -n istio-system -o jsonpath='{.spec.host}')` | N/A |

## Configuration

### Default Network Settings

The deployment uses these default settings:

- **MCC**: 999 (Test Network)
- **MNC**: 70
- **TAC**: 7
- **SST/SD**: 1/000001
- **Default UE**: IMSI 999700000000001

### Customizing the Deployment

You can customize the deployment by editing the following files:

- **Core settings**: Modify `deploy-open5gcore.sh` to change MCC, MNC, and other core parameters
- **UE settings**: Modify `5gran-ue-configmap.yaml` to change UE parameters
- **gNB settings**: The gNB config is dynamically generated in `deploy-ueransim.sh`
- **Monitoring settings**: Modify dashboard definitions in `deploy-monitoring.sh`

## Testing the Deployment

### Verifying Core Connectivity

Check if all pods are running:

```bash
oc get pods -n open5gcore
```

Verify that the gNB can connect to the AMF:

```bash
oc logs deployment/5gran -c gnb -n open5gcore
```

### Testing Data Connectivity

Check if the UE has successfully connected and received an IP address:

```bash
oc logs deployment/5gran -c ue -n open5gcore
```

Verify data connectivity through the UE binder:

```bash
oc logs deployment/5gran -c uebinder -n open5gcore
```

## Troubleshooting

### Common Issues

1. **gNB cannot connect to AMF**:
   - Verify that SCTP is enabled on nodes
   - Check AMF pod logs for connection issues
   - Ensure network policies allow connections

2. **UE cannot register**:
   - Check that the subscriber exists in MongoDB -> Go to the WebUI (admin/1423) to check the record.
   - Verify AMF and UDM logs for authentication issues
   - Ensure the UE configuration matches core settings

3. **HTTP/2 errors in component logs**:
   - This deployment uses HTTP/1.1 to avoid HTTP/2 errors
   - Check if any component has `http2: true` in its configuration

### Accessing Logs

Check component logs using:

```bash
oc logs deployment/<component-name> -n open5gcore
```

For more detailed analysis, use Kibana to query logs across all components.

## Cleanup

### Remove UERANSIM

```bash
./ran/delete-ueransim.sh
```

### Remove 5G Core

```bash
./delete-open5gcore.sh
```

This will:
- Delete all deployments, services, and routes
- Remove ConfigMaps
- Provide an option to delete persistent volume claims for MongoDB

## Performance Considerations

- The default resource limits are set for a development environment
- For production use, increase CPU/memory limits in deployment templates
- MongoDB performance is critical - consider using a dedicated storage class

## Security Considerations

- This deployment uses privileged containers for UPF and UE
- Custom SCCs are applied to the namespace
- TLS termination is handled at the OpenShift routes
- For production, implement additional network policies and use external identity providers

## License

This project is based on:
- [Open5GS](https://open5gs.org/) - AGPL-3.0
- [UERANSIM](https://github.com/aligungr/UERANSIM) - GPL-3.0

## Acknowledgments

- Gradiant 5G Charts (https://github.com/Gradiant/5g-charts)
- Open5GS Community
- UERANSIM Project

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
