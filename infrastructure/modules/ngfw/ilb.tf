# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb
resource "azurerm_lb" "egress" {
  location            = var.azure-region
  resource_group_name = data.azurerm_resource_group.transitRG.name
  name                = "egress-lb"
  sku                 = "Standard"

  frontend_ip_configuration {
    name      = "LoadBalancerIP"
    subnet_id = data.azurerm_subnet.private.id
  }

  depends_on = [data.azurerm_virtual_network.transit]

  tags = merge(var.default-tags)
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_probe
resource "azurerm_lb_probe" "egress_https" {
  name                = "https"
  loadbalancer_id     = azurerm_lb.egress.id
  port                = 443
  protocol            = "Https"
  request_path        = "/php/login.php"
  interval_in_seconds = 5
  number_of_probes    = 2

}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_backend_address_pool
resource "azurerm_lb_backend_address_pool" "ngfw-private" {
  name            = "ngfw-private"
  loadbalancer_id = azurerm_lb.egress.id

  depends_on = [azurerm_linux_virtual_machine.vmseries]
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/lb_rule
resource "azurerm_lb_rule" "allports" {
  name                           = "all-ports"
  loadbalancer_id                = azurerm_lb.egress.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "LoadBalancerIP"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ngfw-private.id]
  probe_id                       = azurerm_lb_probe.egress_https.id
  enable_floating_ip             = true
  load_distribution              = "SourceIPProtocol"

  depends_on = [azurerm_network_interface.ngfw-private]
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_backend_address_pool_association
resource "azurerm_network_interface_backend_address_pool_association" "ngfw-private" {
  for_each                = var.vmseries
  network_interface_id    = azurerm_network_interface.ngfw-private[each.key].id
  ip_configuration_name   = "ngfw-private-ipconfig1-${each.key}"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ngfw-private.id

  depends_on = [azurerm_network_interface.ngfw-private]
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table
resource "azurerm_route_table" "private" {
  name                          = "private-route-table"
  location                      = var.azure-region
  resource_group_name           = data.azurerm_resource_group.transitRG.name
  disable_bgp_route_propagation = false

  tags = merge(var.default-tags)
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route
resource "azurerm_route" "example" {
  name                   = "default"
  resource_group_name    = data.azurerm_resource_group.transitRG.name
  route_table_name       = azurerm_route_table.private.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_lb.egress.private_ip_address #Egress load balancer IP

  depends_on = [azurerm_lb.egress]
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association
resource "azurerm_subnet_route_table_association" "private" {
  subnet_id      = data.azurerm_subnet.private.id
  route_table_id = azurerm_route_table.private.id
}