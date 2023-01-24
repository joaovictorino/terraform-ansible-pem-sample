resource "azurerm_public_ip" "publicip" {
  name                = "publicip"
  resource_group_name = azurerm_resource_group.aulainfra.name
  location            = azurerm_resource_group.aulainfra.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "aula-nic" {
  name                = "aula-nic"
  location            = azurerm_resource_group.aulainfra.location
  resource_group_name = azurerm_resource_group.aulainfra.name

  ip_configuration {
    name                            = "internal"
    subnet_id                       = azurerm_subnet.subnet.id
    private_ip_address_allocation   = "Dynamic"
    public_ip_address_id            = azurerm_public_ip.publicip.id
  }
}

resource "azurerm_network_interface_security_group_association" "ng-nic-assoc" {
  network_interface_id      = azurerm_network_interface.aula-nic.id
  network_security_group_id = azurerm_network_security_group.infra-ng.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm"
  resource_group_name = azurerm_resource_group.aulainfra.name
  location            = azurerm_resource_group.aulainfra.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.aula-nic.id
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.private-key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  depends_on = [
    local_file.private_key
  ]
}