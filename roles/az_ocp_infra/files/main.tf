terraform {
  backend "local" {}
}

provider "azurerm" {
  client_id = var.az_client_id
  subscription_id = var.az_subscription_id
  tenant_id = var.az_tenant_id
  disable_terraform_partner_id = true
  skip_provider_registration = true
}

data "azurerm_resource_group" "main" {
  name     = var.az_resource_group_name
}

data azurerm_subnet "main" {
  name = var.az_subnetwork_name
  virtual_network_name = var.az_network_name
  resource_group_name = var.az_resource_group_name
}

data "azurerm_dns_zone" "main" {
  name                = var.az_dns_zone_name
  resource_group_name = data.azurerm_resource_group.main.name
}

# Storage

resource "azurerm_storage_account" "cluster" {
  name                     = "openshift${var.ocp_cluster_name}"
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = var.az_location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "ignition" {
  name                  = "ignition"
  storage_account_name  = azurerm_storage_account.cluster.name
  container_access_type = "private"
}

# Load Balancers

resource "azurerm_network_security_group" "api-lb" {
  name = "openshift-${var.ocp_cluster_name}-api-lb"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  tags = {}
}

resource "azurerm_network_security_rule" "api-lb-api" {
    name = "openshift-${var.ocp_cluster_name}-api-lb-api"
    resource_group_name = data.azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.api-lb.name
    description = "API traffic from external"
    protocol = "Tcp"
    source_port_range = "6443"
    destination_port_range = "6443"
    source_address_prefix = "*"
    access = "Allow"
    priority = "101"
    direction = "Inbound"
}

resource "azurerm_network_security_rule" "api-lb-machine-config" {
    name = "openshift-${var.ocp_cluster_name}-api-lb-machine-config"
    resource_group_name = data.azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.api-lb.name
    description = "MachineConfig traffic from bootstrap / master"
    protocol = "Tcp"
    source_port_range = "22623"
    destination_port_range = "22623"
    source_application_security_group_ids = [
      azurerm_network_security_group.bootstrap.id,
      azurerm_network_security_group.master.id
    ]
    access = "Allow"
    priority = "102"
    direction = "Inbound"
}

resource "azurerm_lb" "api-lb" {
  name = "openshift-${var.ocp_cluster_name}-api-lb"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  frontend_ip_configuration {
    name = "openshift-${var.ocp_cluster_name}-api-lb-config"
    subnet_id = data.azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
  tags = {}
}

resource "azurerm_lb_backend_address_pool" "api-lb" {
  name = "openshift-${var.ocp_cluster_name}-api-lb"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.api-lb.id
}

resource "azurerm_lb_rule" "api-lb-https" {
  name = "openshift-${var.ocp_cluster_name}-api-lb-https"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id = azurerm_lb.api-lb.id
  frontend_ip_configuration_name = "openshift-${var.ocp_cluster_name}-api-lb-config"
  protocol = "Tcp"
  frontend_port = "6443"
  backend_port = "6443"
  backend_address_pool_id = azurerm_lb_backend_address_pool.api-lb.id
  probe_id = azurerm_lb_probe.api-lb-https.id
}

resource "azurerm_lb_probe" "api-lb-https" {
  name = "openshift-${var.ocp_cluster_name}-api-lb-https"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id = azurerm_lb.api-lb.id
  protocol = "Tcp"
  port = "6443"
}

resource "azurerm_network_security_group" "ingress-lb" {
  name = "openshift-${var.ocp_cluster_name}-ingress-lb"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  tags = {}
}

resource "azurerm_network_security_rule" "ingress-lb-http" {
    name = "openshift-${var.ocp_cluster_name}-ingress-lb-http"
    resource_group_name = data.azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.ingress-lb.name
    description = "Ingress http from external"
    protocol = "Tcp"
    source_port_range = "80"
    destination_port_range = "80"
    source_address_prefix = "*"
    access = "Allow"
    priority = "101"
    direction = "Inbound"
}

resource "azurerm_network_security_rule" "ingress-lb-https" {
    name = "openshift-${var.ocp_cluster_name}-ingress-lb-https"
    resource_group_name = data.azurerm_resource_group.main.name
    network_security_group_name = azurerm_network_security_group.ingress-lb.name
    description = "Ingress http from external"
    protocol = "Tcp"
    source_port_range = "443"
    destination_port_range = "443"
    source_address_prefix = "*"
    access = "Allow"
    priority = "102"
    direction = "Inbound"
}

resource "azurerm_lb" "ingress-lb" {
  name = "openshift-${var.ocp_cluster_name}-ingress-lb"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  frontend_ip_configuration {
    name = "openshift-${var.ocp_cluster_name}-ingress-lb-config"
    subnet_id = data.azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
  tags = {}
}

resource "azurerm_lb_backend_address_pool" "ingress-lb" {
  name = "openshift-${var.ocp_cluster_name}-ingress-lb"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.ingress-lb.id
}

resource "azurerm_lb_rule" "ingress-lb-https" {
  name = "openshift-${var.ocp_cluster_name}-ingress-lb-https"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id = azurerm_lb.ingress-lb.id
  frontend_ip_configuration_name = "openshift-${var.ocp_cluster_name}-ingress-lb-config"
  protocol = "Tcp"
  frontend_port = "443"
  backend_port = "443"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ingress-lb.id
  probe_id = azurerm_lb_probe.ingress-lb-http.id
}

resource "azurerm_lb_rule" "ingress-lb-http" {
  name = "openshift-${var.ocp_cluster_name}-ingress-lb-http"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id = azurerm_lb.ingress-lb.id
  frontend_ip_configuration_name = "openshift-${var.ocp_cluster_name}-ingress-lb-config"
  protocol = "Tcp"
  frontend_port = "80"
  backend_port = "80"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ingress-lb.id
  probe_id = azurerm_lb_probe.ingress-lb-http.id
}

resource "azurerm_lb_probe" "ingress-lb-http" {
  name = "openshift-${var.ocp_cluster_name}-ingress-lb-http"
  resource_group_name = data.azurerm_resource_group.main.name
  loadbalancer_id = azurerm_lb.ingress-lb.id
  protocol = "Tcp"
  port = "80"
}

# CoreOS Image

resource "azurerm_storage_container" "vhd" {
  name                 = "openshift-${var.ocp_cluster_name}-rhcos"
  storage_account_name = azurerm_storage_account.cluster.name
}

resource "azurerm_storage_blob" "rhcos_image" {
  name                   = "openshift-${var.ocp_cluster_name}-rhcos.vhd"
  storage_account_name   = azurerm_storage_account.cluster.name
  storage_container_name = azurerm_storage_container.vhd.name
  type                   = "block"
  source_uri             = var.az_rhcos_image_url
  metadata               = map("source_uri", var.az_rhcos_image_url)
}

resource "azurerm_image" "cluster" {
  name                = "openshift-${var.ocp_cluster_name}-rhcos"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.az_location

  os_disk {
    os_type  = "Linux"
    os_state = "Generalized"
    blob_uri = azurerm_storage_blob.rhcos_image.url
  }
}

# Bootstrap

resource "azurerm_network_security_group" "bootstrap" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  tags = {}
}

resource "azurerm_network_security_rule" "bootstrap-ssh" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-ssh"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.bootstrap.name
  description = "SSH traffic from external"
  protocol = "Tcp"
  source_port_range = "22"
  destination_port_range = "22"
  source_address_prefix = "*"
  access = "Allow"
  priority = "100"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "bootstrap-etcd" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-etcd"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.bootstrap.name
  description = "Etcd traffic from master hosts"
  protocol = "Tcp"
  source_port_range = "2379-2380"
  destination_port_range = "2379-2380"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id
  ]
  access = "Allow"
  priority = "101"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "bootstrap-api" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-api"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.bootstrap.name
  description = "Api traffic from master hosts and load balancer"
  protocol = "Tcp"
  source_port_range = "6443"
  destination_port_range = "6443"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.api-lb.id
  ]
  access = "Allow"
  priority = "102"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "bootstrap-host-services-tcp" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-host-services-tcp"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.bootstrap.name
  description = "Host services traffic from master hosts"
  protocol = "Tcp"
  source_port_range = "9000-9999"
  destination_port_range = "9000-9999"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id
  ]
  access = "Allow"
  priority = "103"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "bootstrap-kubernetes" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-kubernetes"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.bootstrap.name
  description = "Kubernetes traffic from master hosts"
  protocol = "Tcp"
  source_port_range = "10249-10259"
  destination_port_range = "10249-10259"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id
  ]
  access = "Allow"
  priority = "104"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "bootstrap-vxlan-geneve-1" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-vxlan-geneve-1"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.bootstrap.name
  description = "SDN traffic from master hosts"
  protocol = "Udp"
  source_port_range = "4789"
  destination_port_range = "4789"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id
  ]
  access = "Allow"
  priority = "105"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "bootstrap-vxlan-geneve-2" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-vxlan-geneve-2"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.bootstrap.name
  description = "SDN traffic from master hosts"
  protocol = "Udp"
  source_port_range = "6081"
  destination_port_range = "6081"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id
  ]
  access = "Allow"
  priority = "106"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "bootstrap-host-services-udp" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-host-services-udp"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.bootstrap.name
  description = "Host services traffic from master hosts"
  protocol = "Udp"
  source_port_range = "9000-9999"
  destination_port_range = "9000-9999"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id
  ]
  access = "Allow"
  priority = "107"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "bootstrap-machine-config" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-machine-config"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.bootstrap.name
  description = "MachineConfig from load balancer"
  protocol = "Tcp"
  source_port_range = "22623"
  destination_port_range = "22623"
  source_application_security_group_ids = [
    azurerm_network_security_group.api-lb.id
  ]
  access = "Allow"
  priority = "108"
  direction = "Inbound"
}

resource "azurerm_availability_set" "bootstrap" {
  name                = "openshift-${var.ocp_cluster_name}-bootstrap"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  managed = true
  tags = {}
}

data "azurerm_storage_account_sas" "ignition" {
  connection_string = azurerm_storage_account.cluster.primary_connection_string
  https_only        = true

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = timestamp()
  expiry = timeadd(timestamp(), "24h")

  permissions {
    read    = true
    list    = true
    create  = false
    add     = false
    delete  = false
    process = false
    write   = false
    update  = false
  }
}

resource "azurerm_storage_blob" "ignition" {
  name                   = "bootstrap.ign"
  source                 = file("${var.ocp_ignition_dir}/bootstrap.ign")
  storage_account_name   = azurerm_storage_account.cluster.name
  storage_container_name = azurerm_storage_container.ignition.name
  type                   = "block"
}

data "ignition_config" "bootstrap-redirect" {
  replace {
    source = "${azurerm_storage_blob.ignition.url}${data.azurerm_storage_account_sas.ignition.sas}"
  }
}

resource "azurerm_network_interface" "bootstrap" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-nic"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  network_security_group_id = azurerm_network_security_group.bootstrap.id
  ip_configuration {
    name = "openshift-${var.ocp_cluster_name}-bootstrap-nic-config"
    subnet_id = data.azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "bootstrap" {
  network_interface_id    = azurerm_network_interface.bootstrap.id
  ip_configuration_name   = "openshift-${var.ocp_cluster_name}-bootstrap-nic-config"
  backend_address_pool_id = azurerm_lb_backend_address_pool.api-lb.id
}

resource "azurerm_managed_disk" "bootstrap" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap-disk"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  storage_account_type = "Premium_LRS"
  create_option = "FromImage"
  image_reference_id = azurerm_image.cluster.id
  disk_size_gb = 100
  tags = {}
}

resource "azurerm_virtual_machine" "bootstrap" {
  name = "openshift-${var.ocp_cluster_name}-bootstrap"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  network_interface_ids = [
    azurerm_network_interface.bootstrap.id
  ]
  os_profile_linux_config {
    disable_password_authentication = true
  }
  vm_size = var.ocp_bootstrap_vm_size
  availability_set_id = azurerm_availability_set.bootstrap.id
  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true
  os_profile {
    computer_name = "openshift-${var.ocp_cluster_name}-bootstrap"
    admin_username = "core"
    admin_password = "NotActuallyApplied!"
    custom_data    = data.ignition_config.bootstrap-redirect.rendered
  }
  storage_os_disk {
    name = "openshift-${var.ocp_cluster_name}-bootstrap-disk"
    create_option = "Attach"
    caching = "ReadOnly"
    managed_disk_id = azurerm_managed_disk.bootstrap.id
  }
  tags = {}
}

# Master

resource "azurerm_network_security_group" "master" {
  name = "openshift-${var.ocp_cluster_name}-master"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  tags = {}
}

resource "azurerm_network_security_rule" "master-etcd" {
  name = "openshift-${var.ocp_cluster_name}-master-etcd"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.master.name
  description = "Etcd traffic from bootstrap/master hosts"
  protocol = "Tcp"
  source_port_range = "2379-2380"
  destination_port_range = "2379-2380"
  source_application_security_group_ids = [
    azurerm_network_security_group.bootstrap.id,
    azurerm_network_security_group.master.id
  ]
  access = "Allow"
  priority = "101"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-api" {
  name = "openshift-${var.ocp_cluster_name}-master-api"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.master.name
  description = "Api traffic from cluster hosts and load balancer"
  protocol = "Tcp"
  source_port_range = "6443"
  destination_port_range = "6443"
  source_application_security_group_ids = [
    azurerm_network_security_group.bootstrap.id,
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id,
    azurerm_network_security_group.api-lb.id
  ]
  access = "Allow"
  priority = "102"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-host-services-tcp" {
  name = "openshift-${var.ocp_cluster_name}-master-host-services-tcp"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.master.name
  description = "Host services traffic from cluster hosts"
  protocol = "Tcp"
  source_port_range = "9000-9999"
  destination_port_range = "9000-9999"
  source_application_security_group_ids = [
    azurerm_network_security_group.bootstrap.id,
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "103"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-kubernetes" {
  name = "openshift-${var.ocp_cluster_name}-master-kubernetes"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.master.name
  description = "Kubernetes traffic from cluster hosts"
  protocol = "Tcp"
  source_port_range = "10249-10259"
  destination_port_range = "10249-10259"
  source_application_security_group_ids = [
    azurerm_network_security_group.bootstrap.id,
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "104"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-vxlan-geneve-1" {
  name = "openshift-${var.ocp_cluster_name}-master-vxlan-geneve-1"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.master.name
  description = "SDN traffic from cluster hosts"
  protocol = "Udp"
  source_port_range = "4789"
  destination_port_range = "4789"
  source_application_security_group_ids = [
    azurerm_network_security_group.bootstrap.id,
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "105"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-vxlan-geneve-2" {
  name = "openshift-${var.ocp_cluster_name}-master-vxlan-geneve-2"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.master.name
  description = "SDN traffic from cluster hosts"
  protocol = "Udp"
  source_port_range = "6081"
  destination_port_range = "6081"
  source_application_security_group_ids = [
    azurerm_network_security_group.bootstrap.id,
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "106"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-host-services-udp" {
  name = "openshift-${var.ocp_cluster_name}-master-host-services-udp"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.master.name
  description = "Host services traffic from cluster hosts"
  protocol = "Udp"
  source_port_range = "9000-9999"
  destination_port_range = "9000-9999"
  source_application_security_group_ids = [
    azurerm_network_security_group.bootstrap.id,
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "107"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-node-port" {
  name = "openshift-${var.ocp_cluster_name}-master-node-port"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.master.name
  description = "NodePort traffic from cluster hosts"
  protocol = "Udp"
  source_port_range = "30000-32767"
  destination_port_range = "30000-32767"
  source_application_security_group_ids = [
    azurerm_network_security_group.bootstrap.id,
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "108"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-machine-config" {
  name = "openshift-${var.ocp_cluster_name}-master-machine-config"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.master.name
  description = "MachineConfig from load balancer"
  protocol = "Tcp"
  source_port_range = "22623"
  destination_port_range = "22623"
  source_application_security_group_ids = [
    azurerm_network_security_group.api-lb.id
  ]
  access = "Allow"
  priority = "109"
  direction = "Inbound"
}

resource "azurerm_availability_set" "master" {
  name                = "openshift-${var.ocp_cluster_name}-master"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  managed = true
  tags = {}
}

resource "azurerm_network_interface" "master" {
  count = var.ocp_master_replicas
  name = "openshift-${var.ocp_cluster_name}-master-nic-${count.index}"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  network_security_group_id = azurerm_network_security_group.master.id
  ip_configuration {
    name = "openshift-${var.ocp_cluster_name}-master-nic-config"
    subnet_id = data.azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "master" {
  count = var.ocp_master_replicas
  network_interface_id    = element(azurerm_network_interface.master.*.id, count.index)
  ip_configuration_name   = "openshift-${var.ocp_cluster_name}-master-nic-config"
  backend_address_pool_id = azurerm_lb_backend_address_pool.api-lb.id
}

resource "azurerm_managed_disk" "master" {
  count = var.ocp_master_replicas
  name = "openshift-${var.ocp_cluster_name}-master-${count.index}-disk"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  storage_account_type = "Premium_LRS"
  create_option = "FromImage"
  image_reference_id = azurerm_image.cluster.id
  disk_size_gb = 200
  tags = {}
}

resource "azurerm_virtual_machine" "master" {
  count = var.ocp_master_replicas
  name = "openshift-${var.ocp_cluster_name}-master-${count.index}"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  network_interface_ids = [
    element(azurerm_network_interface.master.*.id, count.index)
  ]
  os_profile_linux_config {
    disable_password_authentication = true
  }
  vm_size = var.ocp_master_vm_size
  availability_set_id = azurerm_availability_set.master.id
  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true
  os_profile {
    computer_name = "openshift-${var.ocp_cluster_name}-master-${count.index}"
    admin_username = "core"
    admin_password = "NotActuallyApplied!"
    custom_data    = file("${var.ocp_ignition_dir}/master.ign")
  }
  storage_os_disk {
    name = "openshift-${var.ocp_cluster_name}-master-${count.index}-disk"
    create_option = "Attach"
    caching = "ReadOnly"
    managed_disk_id = element(azurerm_managed_disk.master.*.id, count.index)
  }
  tags = {}
}

# Worker

resource "azurerm_network_security_group" "worker" {
  name = "openshift-${var.ocp_cluster_name}-worker"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  tags = {}
}

resource "azurerm_network_security_rule" "worker-host-services-tcp" {
  name = "openshift-${var.ocp_cluster_name}-worker-host-services-tcp"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.worker.name
  description = "Host services traffic from cluster hosts"
  protocol = "Tcp"
  source_port_range = "9000-9999"
  destination_port_range = "9000-9999"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "101"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "worker-kubernetes" {
  name = "openshift-${var.ocp_cluster_name}-worker-kubernetes"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.worker.name
  description = "Kubernetes traffic from cluster hosts"
  protocol = "Tcp"
  source_port_range = "10249-10259"
  destination_port_range = "10249-10259"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "102"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "worker-vxlan-geneve-1" {
  name = "openshift-${var.ocp_cluster_name}-worker-vxlan-geneve-1"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.worker.name
  description = "SDN traffic from cluster hosts"
  protocol = "Udp"
  source_port_range = "4789"
  destination_port_range = "4789"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "103"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "worker-vxlan-geneve-2" {
  name = "openshift-${var.ocp_cluster_name}-worker-vxlan-geneve-2"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.worker.name
  description = "SDN traffic from cluster hosts"
  protocol = "Udp"
  source_port_range = "6081"
  destination_port_range = "6081"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "104"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "worker-host-services-udp" {
  name = "openshift-${var.ocp_cluster_name}-worker-host-services-udp"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.worker.name
  description = "Host services traffic from cluster hosts"
  protocol = "Udp"
  source_port_range = "9000-9999"
  destination_port_range = "9000-9999"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "105"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "worker-node-port" {
  name = "openshift-${var.ocp_cluster_name}-worker-node-port"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.worker.name
  description = "NodePort traffic from cluster hosts"
  protocol = "Udp"
  source_port_range = "30000-32767"
  destination_port_range = "30000-32767"
  source_application_security_group_ids = [
    azurerm_network_security_group.master.id,
    azurerm_network_security_group.worker.id
  ]
  access = "Allow"
  priority = "106"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-ingress-http" {
  name = "openshift-${var.ocp_cluster_name}-master-ingress-http"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.worker.name
  description = "Ingress http from load balancer"
  protocol = "Tcp"
  source_port_range = "80"
  destination_port_range = "80"
  source_application_security_group_ids = [
    azurerm_network_security_group.ingress-lb.id
  ]
  access = "Allow"
  priority = "107"
  direction = "Inbound"
}

resource "azurerm_network_security_rule" "master-ingress-https" {
  name = "openshift-${var.ocp_cluster_name}-master-ingress-https"
  resource_group_name = data.azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.worker.name
  description = "Ingress http from load balancer"
  protocol = "Tcp"
  source_port_range = "443"
  destination_port_range = "443"
  source_application_security_group_ids = [
    azurerm_network_security_group.ingress-lb.id
  ]
  access = "Allow"
  priority = "108"
  direction = "Inbound"
}

resource "azurerm_availability_set" "worker" {
  name                = "openshift-${var.ocp_cluster_name}-worker"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  managed = true
  tags = {}
}

resource "azurerm_network_interface" "worker" {
  count = var.ocp_worker_replicas
  name = "openshift-${var.ocp_cluster_name}-worker-nic-${count.index}"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  network_security_group_id = azurerm_network_security_group.worker.id
  ip_configuration {
    name = "openshift-${var.ocp_cluster_name}-worker-nic-config"
    subnet_id = data.azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_managed_disk" "worker" {
  count = var.ocp_worker_replicas
  name = "openshift-${var.ocp_cluster_name}-worker-${count.index}-disk"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  storage_account_type = "Premium_LRS"
  create_option = "FromImage"
  image_reference_id = azurerm_image.cluster.id
  disk_size_gb = 200
  tags = {}
}

resource "azurerm_virtual_machine" "worker" {
  count = var.ocp_worker_replicas
  name = "openshift-${var.ocp_cluster_name}-worker-${count.index}"
  resource_group_name = data.azurerm_resource_group.main.name
  location = var.az_location
  network_interface_ids = [
    element(azurerm_network_interface.worker.*.id, count.index)
  ]
  os_profile_linux_config {
    disable_password_authentication = true
  }
  vm_size = var.ocp_worker_vm_size
  availability_set_id = azurerm_availability_set.worker.id
  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true
  os_profile {
    computer_name = "openshift-${var.ocp_cluster_name}-worker-${count.index}"
    admin_username = "core"
    admin_password = "NotActuallyApplied!"
    custom_data    = file("${var.ocp_ignition_dir}/worker.ign")
  }
  storage_os_disk {
    name = "openshift-${var.ocp_cluster_name}-worker-${count.index}-disk"
    create_option = "Attach"
    caching = "ReadOnly"
    managed_disk_id = element(azurerm_managed_disk.worker.*.id, count.index)
  }

  tags = {}
}

# DNS Entries

resource "azurerm_dns_a_record" "api-public" {
  name = "api.${var.ocp_cluster_name}"
  resource_group_name = var.az_resource_group_name
  zone_name = data.azurerm_dns_zone.main.name
  ttl = 300
  records = [
    azurerm_lb.api-lb.private_ip_address
  ]
  tags = {}
}

resource "azurerm_dns_a_record" "api-private" {
  name = "api-int.${var.ocp_cluster_name}"
  resource_group_name = var.az_resource_group_name
  zone_name = data.azurerm_dns_zone.main.name
  ttl = 300
  records = [
    azurerm_lb.api-lb.private_ip_address
  ]
  tags = {}
}

resource "azurerm_dns_a_record" "ingress" {
  name = "*.apps.${var.ocp_cluster_name}"
  resource_group_name = var.az_resource_group_name
  zone_name = data.azurerm_dns_zone.main.name
  ttl = 300
  records = [
    azurerm_lb.ingress-lb.private_ip_address
  ]
  tags = {}
}
